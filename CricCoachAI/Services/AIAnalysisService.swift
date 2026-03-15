import Foundation
import UIKit

/// Service for AI-powered coaching feedback via Claude Vision API
class AIAnalysisService {
    
    private let apiTimeout = AppConstants.apiTimeout
    
    // MARK: - Main Analysis
    
    /// Send analysis data to backend and get AI coaching feedback.
    /// Respects the `ai_coaching_enabled` feature flag — returns fallback if disabled.
    func analyzeSession(
        analysisType: AnalysisType,
        keyFrameImages: [PosePhase: UIImage],
        poseSequence: PoseSequence,
        detectedPhases: [DetectedPhase],
        techniqueScores: [TechniqueScore],
        userProfile: UserProfile?,
        previousScores: [String: Int]?
    ) async throws -> AICoachingResponse {
        
        // Check feature flag — AI coaching can be disabled server-side
        let flagsEnabled = await MainActor.run { FeatureFlagService.shared.isAICoachingEnabled }
        guard flagsEnabled else {
            return generateFallbackFeedback(
                techniqueScores: techniqueScores,
                analysisType: analysisType
            )
        }
        
        AnalyticsService.track(.aiAnalysisStarted, properties: [
            "analysis_type": analysisType.rawValue,
            "key_frame_count": keyFrameImages.count
        ])
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Build the request payload
        let payload = try buildPayload(
            analysisType: analysisType,
            keyFrameImages: keyFrameImages,
            poseSequence: poseSequence,
            detectedPhases: detectedPhases,
            techniqueScores: techniqueScores,
            userProfile: userProfile,
            previousScores: previousScores
        )
        
        // Send to backend
        do {
            let rawResponse = try await sendToBackend(payload: payload)
            
            // Validate AI claims against actual pose data (P1-2: AI Validation Layer)
            let validationResult = AIResponseValidator.validate(
                response: rawResponse,
                against: payload,
                techniqueScores: techniqueScores
            )
            
            if validationResult.wasModified {
                print("[AIAnalysis] Validator modified response: \(validationResult.flaggedIssues.count) flags")
                for flag in validationResult.flaggedIssues {
                    print("  - \(flag.field): claimed=\(flag.claimedValue), actual=\(flag.actualValue), deviation=\(String(format: "%.1f", flag.deviationPercent))%, action=\(flag.action.rawValue)")
                }
            }
            
            // If all issues were removed, fall back to rule-based feedback
            let response: AICoachingResponse
            if validationResult.cleanedResponse.issues.isEmpty && !rawResponse.issues.isEmpty {
                print("[AIAnalysis] All AI issues removed by validator — falling back to rule-based feedback")
                response = generateFallbackFeedback(
                    techniqueScores: techniqueScores,
                    analysisType: analysisType
                )
            } else {
                response = validationResult.cleanedResponse
            }
            
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            AnalyticsService.track(.aiAnalysisCompleted, properties: [
                "latency_ms": latencyMs,
                "overall_score": response.overallScore,
                "issue_count": response.issues.count,
                "analysis_type": analysisType.rawValue,
                "validation_flags": validationResult.flaggedIssues.count,
                "validation_modified": validationResult.wasModified
            ])
            
            return response
        } catch {
            AnalyticsService.track(.aiAnalysisFailed, properties: [
                "error_type": String(describing: type(of: error)),
                "error_message": error.localizedDescription,
                "analysis_type": analysisType.rawValue
            ])
            AnalyticsService.captureError(error, context: [
                "service": "AIAnalysisService",
                "analysis_type": analysisType.rawValue
            ])
            throw error
        }
    }
    
    // MARK: - Payload Construction
    
    private func buildPayload(
        analysisType: AnalysisType,
        keyFrameImages: [PosePhase: UIImage],
        poseSequence: PoseSequence,
        detectedPhases: [DetectedPhase],
        techniqueScores: [TechniqueScore],
        userProfile: UserProfile?,
        previousScores: [String: Int]?
    ) throws -> AnalysisPayload {
        
        var keyFrames: [KeyFramePayload] = []
        
        for phase in detectedPhases {
            guard let image = keyFrameImages[phase.phase],
                  let frameData = poseSequence.frame(atIndex: phase.keyFrame) else { continue }
            
            // Encode image as base64
            guard let imageData = image.jpegData(compressionQuality: 0.7) else { continue }
            let base64Image = imageData.base64EncodedString()
            
            // Get angles for this frame
            let angles = AngleCalculator.allAngles(in: frameData)
            
            keyFrames.append(KeyFramePayload(
                phase: phase.phase.rawValue,
                imageBase64: base64Image,
                poseLandmarks: frameData.landmarks.mapValues { ["x": $0.x, "y": $0.y] },
                measuredAngles: angles.mapValues { Float($0) }
            ))
        }
        
        // Build rule scores
        var ruleScores: [String: PhaseScorePayload] = [:]
        for score in techniqueScores {
            ruleScores[score.phase.rawValue] = PhaseScorePayload(
                overall: score.overallScore,
                checkpoints: score.checkpoints.map { cp in
                    CheckpointPayload(
                        name: cp.name,
                        score: cp.score,
                        measured: cp.measuredValueDescription,
                        ideal: cp.idealRange
                    )
                }
            )
        }
        
        // Build user context
        let userContext = UserContextPayload(
            heightCm: userProfile?.heightCm,
            playingRole: userProfile?.playingRole,
            bowlingStyle: userProfile?.bowlingStyle,
            experienceLevel: userProfile?.experienceLevel ?? "beginner",
            knownIssues: userProfile?.knownIssuesList ?? [],
            previousSessionScores: previousScores
        )
        
        return AnalysisPayload(
            analysisType: analysisType.rawValue,
            keyFrames: keyFrames,
            ruleScores: ruleScores,
            userContext: userContext
        )
    }
    
    // MARK: - Network
    
    private func sendToBackend(payload: AnalysisPayload) async throws -> AICoachingResponse {
        let url = URL(string: AppConstants.apiBaseURL + AppConstants.analyzeEndpoint)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConstants.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "X-API-Version")
        request.timeoutInterval = apiTimeout
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw AIAnalysisError.rateLimited
            }
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIAnalysisError.serverError(httpResponse.statusCode, body)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            return try decoder.decode(AICoachingResponse.self, from: data)
        } catch {
            // Retry once if JSON parsing fails
            throw AIAnalysisError.invalidJSON(String(data: data, encoding: .utf8) ?? "")
        }
    }
    
    // MARK: - Fallback (when API is unavailable)
    
    /// Generate basic coaching feedback from rule scores only (no AI)
    func generateFallbackFeedback(
        techniqueScores: [TechniqueScore],
        analysisType: AnalysisType
    ) -> AICoachingResponse {
        
        let overallScore = techniqueScores.isEmpty ? 0 :
            techniqueScores.reduce(0) { $0 + $1.overallScore } / techniqueScores.count
        
        // Find positives (score >= 80)
        let positives = techniqueScores.flatMap { score in
            score.checkpoints.filter { $0.score >= 80 }
        }.prefix(2).map { cp in
            PositiveFeedback(
                title: cp.name,
                description: cp.shortFeedback
            )
        }
        
        // Find issues (worst scores first)
        let allCheckpoints = techniqueScores.flatMap { score in
            score.checkpoints.map { ($0, score.phase) }
        }.sorted { $0.0.score < $1.0.score }
        
        let issues = allCheckpoints.prefix(3).enumerated().map { (index, item) in
            let (cp, phase) = item
            return IssueFeedback(
                rank: index + 1,
                title: cp.name,
                severity: cp.severity.rawValue,
                description: cp.shortFeedback,
                measuredValue: cp.measuredValueDescription,
                idealValue: cp.idealRange,
                phase: phase.rawValue,
                whyItMatters: "This affects your overall technique quality.",
                drill: DrillRecommendation(
                    name: "Practice Drill",
                    description: "Focus on \(cp.name.lowercased()) during your next net session. Use shadow practice to build muscle memory.",
                    reps: "20 repetitions",
                    frequency: "Every practice session"
                ),
                target: "Improve \(cp.name) score to 80+ within 2 weeks"
            )
        }
        
        return AICoachingResponse(
            overallAssessment: "Based on rule-based analysis, your overall technique scores \(overallScore)/100. AI coaching feedback is currently unavailable — showing basic analysis.",
            overallScore: overallScore,
            positives: Array(positives),
            issues: Array(issues),
            progressNote: nil,
            nextSessionFocus: issues.first.map { "Focus on \($0.title) in your next session." }
        )
    }
    
    // MARK: - Session Comparison
    
    /// Get AI comparison between two sessions
    func compareSessions(
        session1Scores: [TechniqueScore],
        session2Scores: [TechniqueScore],
        analysisType: AnalysisType
    ) async throws -> String {
        // Build a simple comparison prompt
        var comparison = "Session comparison:\n"
        
        let phases = analysisType == .batting ? PosePhase.battingPhases : PosePhase.bowlingPhases
        for phase in phases {
            let score1 = session1Scores.first { $0.phase == phase }?.overallScore ?? 0
            let score2 = session2Scores.first { $0.phase == phase }?.overallScore ?? 0
            let diff = score2 - score1
            let arrow = diff > 0 ? "↑" : diff < 0 ? "↓" : "→"
            comparison += "\(phase.displayName): \(score1) → \(score2) \(arrow)\(abs(diff))\n"
        }
        
        return comparison
    }
}

// MARK: - Payload Types

struct AnalysisPayload: Codable {
    let analysisType: String
    let keyFrames: [KeyFramePayload]
    let ruleScores: [String: PhaseScorePayload]
    let userContext: UserContextPayload
}

struct KeyFramePayload: Codable {
    let phase: String
    let imageBase64: String
    let poseLandmarks: [String: [String: Float]]
    let measuredAngles: [String: Float]
}

struct PhaseScorePayload: Codable {
    let overall: Int
    let checkpoints: [CheckpointPayload]
}

struct CheckpointPayload: Codable {
    let name: String
    let score: Int
    let measured: String
    let ideal: String
}

struct UserContextPayload: Codable {
    let heightCm: Int?
    let playingRole: String?
    let bowlingStyle: String?
    let experienceLevel: String
    let knownIssues: [String]
    let previousSessionScores: [String: Int]?
}

// MARK: - Errors

enum AIAnalysisError: LocalizedError {
    case invalidResponse
    case rateLimited
    case serverError(Int, String)
    case invalidJSON(String)
    case timeout
    case unavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .rateLimited: return "You've reached your analysis limit. Upgrade to Pro for unlimited."
        case .serverError(let code, let body): return "Server error (\(code)): \(body)"
        case .invalidJSON: return "Could not parse AI response"
        case .timeout: return "AI analysis timed out. Try again."
        case .unavailable: return "AI coaching is temporarily unavailable. Showing basic analysis."
        }
    }
}

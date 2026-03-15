import Foundation
import SwiftData
import UIKit

// MARK: - Analysis Session (SwiftData Model)

@Model
final class AnalysisSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var analysisType: String  // "batting" or "bowling"
    var videoLocalPath: String
    var overallScore: Int
    var aiResponseJSON: String?  // Full AI response JSON
    var phaseScoresJSON: String?  // Encoded [TechniqueScore]
    var detectedPhasesJSON: String?  // Encoded [DetectedPhase]
    var poseSequenceJSON: String?  // Encoded PoseSequence (can be large)
    var userNotes: String?
    var durationSeconds: Double
    var isProcessing: Bool
    var isAIAnalysisComplete: Bool
    var userFeedback: Bool?  // nil = not submitted, true = helpful, false = not helpful
    
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        analysisType: String,
        videoLocalPath: String,
        overallScore: Int = 0,
        durationSeconds: Double = 0
    ) {
        self.id = id
        self.date = date
        self.analysisType = analysisType
        self.videoLocalPath = videoLocalPath
        self.overallScore = overallScore
        self.durationSeconds = durationSeconds
        self.isProcessing = true
        self.isAIAnalysisComplete = false
    }
    
    // MARK: - Computed Properties
    
    var type: AnalysisType {
        AnalysisType(rawValue: analysisType) ?? .batting
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    // MARK: - Decoded Data
    
    var techniqueScores: [TechniqueScore] {
        get {
            guard let json = phaseScoresJSON,
                  let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TechniqueScore].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                phaseScoresJSON = String(data: data, encoding: .utf8)
            }
        }
    }
    
    var detectedPhases: [DetectedPhase] {
        get {
            guard let json = detectedPhasesJSON,
                  let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([DetectedPhase].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                detectedPhasesJSON = String(data: data, encoding: .utf8)
            }
        }
    }
    
    var poseSequence: PoseSequence? {
        get {
            guard let json = poseSequenceJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(PoseSequence.self, from: data)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                poseSequenceJSON = String(data: data, encoding: .utf8)
            }
        }
    }
    
    var aiCoachingResponse: AICoachingResponse? {
        get {
            guard let json = aiResponseJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(AICoachingResponse.self, from: data)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                aiResponseJSON = String(data: data, encoding: .utf8)
            }
        }
    }
    
    /// Video URL from local path
    var videoURL: URL? {
        let url = URL(fileURLWithPath: videoLocalPath)
        return FileManager.default.fileExists(atPath: videoLocalPath) ? url : nil
    }
    
    /// Score for a specific phase
    func score(for phase: PosePhase) -> TechniqueScore? {
        techniqueScores.first { $0.phase == phase }
    }
    
    /// Average score across all phases
    var averagePhaseScore: Int {
        let scores = techniqueScores
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0) { $0 + $1.overallScore } / scores.count
    }
}

// MARK: - AI Coaching Response

struct AICoachingResponse: Codable {
    let overallAssessment: String
    let overallScore: Int
    let positives: [PositiveFeedback]
    let issues: [IssueFeedback]
    let progressNote: String?
    let nextSessionFocus: String?
    
    enum CodingKeys: String, CodingKey {
        case overallAssessment = "overall_assessment"
        case overallScore = "overall_score"
        case positives
        case issues
        case progressNote = "progress_note"
        case nextSessionFocus = "next_session_focus"
    }
}

struct PositiveFeedback: Codable, Identifiable {
    var id: String { title }
    let title: String
    let description: String
}

struct IssueFeedback: Codable, Identifiable {
    var id: Int { rank }
    let rank: Int
    let title: String
    let severity: String
    let description: String
    let measuredValue: String
    let idealValue: String
    let phase: String
    let whyItMatters: String
    let drill: DrillRecommendation
    let target: String
    
    enum CodingKeys: String, CodingKey {
        case rank, title, severity, description
        case measuredValue = "measured_value"
        case idealValue = "ideal_value"
        case phase
        case whyItMatters = "why_it_matters"
        case drill, target
    }
    
    var severityLevel: Severity {
        switch severity.lowercased() {
        case "critical": return .critical
        case "moderate": return .moderate
        case "minor": return .minor
        default: return .moderate
        }
    }
}

struct DrillRecommendation: Codable {
    let name: String
    let description: String
    let reps: String
    let frequency: String
}

// MARK: - User Profile

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var heightCm: Int?
    var experienceLevel: String  // beginner, intermediate, advanced
    var playingRole: String?
    var bowlingStyle: String?
    var knownIssues: String?  // Comma-separated
    var subscriptionTier: String  // free, pro
    var analysesThisMonth: Int
    var monthResetDate: Date
    var hasCompletedOnboarding: Bool
    var prefersBatting: Bool
    var prefersBowling: Bool
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        heightCm: Int? = nil,
        experienceLevel: String = "beginner",
        playingRole: String? = nil,
        bowlingStyle: String? = nil,
        subscriptionTier: String = "free",
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = id
        self.heightCm = heightCm
        self.experienceLevel = experienceLevel
        self.playingRole = playingRole
        self.bowlingStyle = bowlingStyle
        self.subscriptionTier = subscriptionTier
        self.analysesThisMonth = 0
        self.monthResetDate = Date()
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.prefersBatting = true
        self.prefersBowling = false
        self.createdAt = Date()
    }
    
    var knownIssuesList: [String] {
        get {
            knownIssues?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        }
        set {
            knownIssues = newValue.joined(separator: ", ")
        }
    }
    
    var isPro: Bool {
        subscriptionTier == "pro"
    }
    
    var canAnalyze: Bool {
        isPro || analysesThisMonth < 3
    }
    
    var remainingFreeAnalyses: Int {
        max(0, 3 - analysesThisMonth)
    }
    
    /// Check and reset monthly counter if needed
    func checkMonthlyReset() {
        let calendar = Calendar.current
        if !calendar.isDate(monthResetDate, equalTo: Date(), toGranularity: .month) {
            analysesThisMonth = 0
            monthResetDate = Date()
        }
    }
}

// MARK: - Experience Level

enum ExperienceLevel: String, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
    
    var description: String {
        switch self {
        case .beginner: return "New to cricket or casual player"
        case .intermediate: return "Play regularly in club/league cricket"
        case .advanced: return "Competitive player with years of experience"
        }
    }
}

// MARK: - Playing Role

enum PlayingRole: String, CaseIterable, Identifiable {
    case topOrderBatsman = "top_order_batsman"
    case middleOrderBatsman = "middle_order_batsman"
    case lowerOrderBatsman = "lower_order_batsman"
    case allRounder = "all_rounder"
    case wicketKeeper = "wicket_keeper"
    case paceBowler = "pace_bowler"
    case spinBowler = "spin_bowler"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .topOrderBatsman: return "Top Order Batsman"
        case .middleOrderBatsman: return "Middle Order Batsman"
        case .lowerOrderBatsman: return "Lower Order Batsman"
        case .allRounder: return "All Rounder"
        case .wicketKeeper: return "Wicket Keeper"
        case .paceBowler: return "Pace Bowler"
        case .spinBowler: return "Spin Bowler"
        }
    }
}

// MARK: - Bowling Style

enum BowlingStyle: String, CaseIterable, Identifiable {
    case rightArmFast = "right_arm_fast"
    case leftArmFast = "left_arm_fast"
    case rightArmMedium = "right_arm_medium"
    case leftArmMedium = "left_arm_medium"
    case rightArmOffSpin = "right_arm_off_spin"
    case rightArmLegSpin = "right_arm_leg_spin"
    case leftArmOrthodox = "left_arm_orthodox"
    case leftArmUnorthodox = "left_arm_unorthodox"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .rightArmFast: return "Right Arm Fast"
        case .leftArmFast: return "Left Arm Fast"
        case .rightArmMedium: return "Right Arm Medium"
        case .leftArmMedium: return "Left Arm Medium"
        case .rightArmOffSpin: return "Right Arm Off Spin"
        case .rightArmLegSpin: return "Right Arm Leg Spin"
        case .leftArmOrthodox: return "Left Arm Orthodox"
        case .leftArmUnorthodox: return "Left Arm Unorthodox"
        }
    }
}

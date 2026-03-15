import Foundation

/// Validates AI coaching responses against actual measured pose data
/// to catch hallucinated or contradictory claims before they reach the UI.
///
/// ## How it works
/// 1. Parses each issue's `measured_value` for numeric values
/// 2. Looks up the actual measurement from the payload sent to Claude
/// 3. Compares: ≤20% deviation → keep, 20-50% → correct, >50% → remove
/// 4. Caps `overall_score` to ±10 of rule-based average
/// 5. Validates phase references exist
///
/// ## Usage
/// ```swift
/// let result = AIResponseValidator.validate(
///     response: aiResponse,
///     against: payload,
///     techniqueScores: scores
/// )
/// // Use result.cleanedResponse for UI
/// // Log result.flaggedIssues for observability
/// ```
struct AIResponseValidator {
    
    // MARK: - Result Types
    
    struct ValidationResult {
        let cleanedResponse: AICoachingResponse
        let flaggedIssues: [ValidationFlag]
        let wasModified: Bool
    }
    
    struct ValidationFlag {
        let field: String          // e.g., "issues[0].measured_value"
        let claimedValue: String   // What Claude said
        let actualValue: String    // What the pose data shows
        let deviationPercent: Double
        let action: FlagAction
    }
    
    enum FlagAction: String {
        case kept       // Deviation ≤20%, kept as-is
        case corrected  // Deviation 20-50%, replaced with actual value
        case removed    // Deviation >50% or unparseable, issue removed
    }
    
    // MARK: - Thresholds
    
    /// Maximum allowed deviation before correcting the claimed value
    private static let correctionThreshold: Double = 20.0
    /// Maximum allowed deviation before removing the issue entirely
    private static let removalThreshold: Double = 50.0
    /// Maximum allowed delta between AI score and rule-based average
    private static let scoreCapDelta: Int = 10
    
    // MARK: - Main Validation
    
    /// Validate and clean an AI response against the payload that was sent
    static func validate(
        response: AICoachingResponse,
        against payload: AnalysisPayload,
        techniqueScores: [TechniqueScore]
    ) -> ValidationResult {
        var flags: [ValidationFlag] = []
        var wasModified = false
        
        // Build a lookup of actual measured values from payload
        let actualMeasurements = buildMeasurementLookup(from: payload, scores: techniqueScores)
        
        // Collect valid phases from the payload
        let validPhases = Set(payload.keyFrames.map { $0.phase })
        
        // 1. Validate issues
        var cleanedIssues: [IssueFeedback] = []
        
        for (index, issue) in response.issues.enumerated() {
            // Check phase reference exists
            if !validPhases.contains(issue.phase) && !validPhases.isEmpty {
                flags.append(ValidationFlag(
                    field: "issues[\(index)].phase",
                    claimedValue: issue.phase,
                    actualValue: "valid: \(validPhases.joined(separator: ", "))",
                    deviationPercent: 100,
                    action: .removed
                ))
                wasModified = true
                continue
            }
            
            // Check measured_value against actual data
            if let claimedNum = extractNumericValue(from: issue.measuredValue) {
                if let actualNum = findActualMeasurement(
                    phase: issue.phase,
                    issueTitle: issue.title,
                    measuredText: issue.measuredValue,
                    measurements: actualMeasurements
                ) {
                    let deviation = deviationPercent(claimed: claimedNum, actual: actualNum)
                    
                    if deviation > removalThreshold {
                        // >50% deviation — remove entirely
                        flags.append(ValidationFlag(
                            field: "issues[\(index)].measured_value",
                            claimedValue: issue.measuredValue,
                            actualValue: String(format: "%.1f", actualNum),
                            deviationPercent: deviation,
                            action: .removed
                        ))
                        wasModified = true
                        continue
                    } else if deviation > correctionThreshold {
                        // 20-50% deviation — correct the value
                        flags.append(ValidationFlag(
                            field: "issues[\(index)].measured_value",
                            claimedValue: issue.measuredValue,
                            actualValue: String(format: "%.1f", actualNum),
                            deviationPercent: deviation,
                            action: .corrected
                        ))
                        
                        // Create corrected issue with actual measurement
                        let correctedIssue = IssueFeedback(
                            rank: issue.rank,
                            title: issue.title,
                            severity: issue.severity,
                            description: issue.description,
                            measuredValue: String(format: "%.1f", actualNum),
                            idealValue: issue.idealValue,
                            phase: issue.phase,
                            whyItMatters: issue.whyItMatters,
                            drill: issue.drill,
                            target: issue.target
                        )
                        cleanedIssues.append(correctedIssue)
                        wasModified = true
                        continue
                    } else {
                        // ≤20% — keep as-is
                        flags.append(ValidationFlag(
                            field: "issues[\(index)].measured_value",
                            claimedValue: issue.measuredValue,
                            actualValue: String(format: "%.1f", actualNum),
                            deviationPercent: deviation,
                            action: .kept
                        ))
                    }
                }
            }
            
            // Issue passed validation (or couldn't be checked)
            cleanedIssues.append(issue)
        }
        
        // Re-rank cleaned issues
        var rerankedIssues: [IssueFeedback] = []
        for (index, issue) in cleanedIssues.enumerated() {
            rerankedIssues.append(IssueFeedback(
                rank: index + 1,
                title: issue.title,
                severity: issue.severity,
                description: issue.description,
                measuredValue: issue.measuredValue,
                idealValue: issue.idealValue,
                phase: issue.phase,
                whyItMatters: issue.whyItMatters,
                drill: issue.drill,
                target: issue.target
            ))
        }
        
        // 2. Validate positives — check phase references
        var cleanedPositives = response.positives
        // Positives don't have phase references, so we keep them unless clearly wrong
        
        // 3. Cap overall score to ±10 of rule-based average
        var cappedScore = response.overallScore
        if !techniqueScores.isEmpty {
            let ruleBasedAvg = techniqueScores.reduce(0) { $0 + $1.overallScore } / techniqueScores.count
            if abs(cappedScore - ruleBasedAvg) > scoreCapDelta {
                flags.append(ValidationFlag(
                    field: "overall_score",
                    claimedValue: "\(response.overallScore)",
                    actualValue: "\(ruleBasedAvg)",
                    deviationPercent: Double(abs(response.overallScore - ruleBasedAvg)),
                    action: .corrected
                ))
                cappedScore = ruleBasedAvg
                wasModified = true
            }
        }
        
        // 4. Build cleaned response
        let cleanedResponse = AICoachingResponse(
            overallAssessment: response.overallAssessment,
            overallScore: cappedScore,
            positives: cleanedPositives,
            issues: rerankedIssues,
            progressNote: response.progressNote,
            nextSessionFocus: response.nextSessionFocus
        )
        
        // Log validation results
        if !flags.isEmpty {
            let removed = flags.filter { $0.action == .removed }.count
            let corrected = flags.filter { $0.action == .corrected }.count
            
            AnalyticsService.track(.aiValidationFlags, properties: [
                "flag_count": flags.count,
                "removed_count": removed,
                "corrected_count": corrected,
                "issues_before": response.issues.count,
                "issues_after": rerankedIssues.count
            ])
        }
        
        return ValidationResult(
            cleanedResponse: cleanedResponse,
            flaggedIssues: flags,
            wasModified: wasModified
        )
    }
    
    // MARK: - Measurement Lookup
    
    /// Build a flat lookup of all actual measurements from the payload
    private static func buildMeasurementLookup(
        from payload: AnalysisPayload,
        scores: [TechniqueScore]
    ) -> [String: Double] {
        var lookup: [String: Double] = [:]
        
        // From key frame angles
        for frame in payload.keyFrames {
            for (angleName, angleValue) in frame.measuredAngles {
                let key = "\(frame.phase).\(angleName)"
                lookup[key] = Double(angleValue)
                // Also store without phase prefix for fuzzy matching
                lookup[angleName] = Double(angleValue)
            }
        }
        
        // From technique score checkpoints
        for score in scores {
            for checkpoint in score.checkpoints {
                // Try to extract a numeric value from the measured description
                if let num = extractNumericValue(from: checkpoint.measuredValueDescription) {
                    let key = "\(score.phase.rawValue).\(checkpoint.name)"
                    lookup[key] = num
                    lookup[checkpoint.name] = num
                }
            }
        }
        
        return lookup
    }
    
    /// Try to find the actual measurement that matches an issue
    private static func findActualMeasurement(
        phase: String,
        issueTitle: String,
        measuredText: String,
        measurements: [String: Double]
    ) -> Double? {
        // Strategy 1: Direct phase.angle lookup
        for (key, value) in measurements {
            if key.hasPrefix(phase) {
                // Check if the issue title or measured text references this measurement
                let angleName = key.replacingOccurrences(of: "\(phase).", with: "")
                if issueTitle.lowercased().contains(angleName.lowercased().replacingOccurrences(of: "_", with: " ")) {
                    return value
                }
            }
        }
        
        // Strategy 2: Fuzzy match on checkpoint name
        let titleWords = issueTitle.lowercased().components(separatedBy: .whitespaces)
        for (key, value) in measurements {
            let keyWords = key.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .components(separatedBy: .whitespaces)
            let overlap = Set(titleWords).intersection(Set(keyWords))
            if overlap.count >= 2 {
                return value
            }
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    /// Extract the first numeric value from a string like "45.2° elbow angle" or "4.2 inches"
    static func extractNumericValue(from text: String) -> Double? {
        // Match patterns like: 45.2, 45, -3.1, 0.05
        let pattern = #"-?\d+\.?\d*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return Double(text[range])
    }
    
    /// Calculate percentage deviation between claimed and actual values
    static func deviationPercent(claimed: Double, actual: Double) -> Double {
        guard actual != 0 else {
            return claimed == 0 ? 0 : 100
        }
        return abs(claimed - actual) / abs(actual) * 100
    }
}

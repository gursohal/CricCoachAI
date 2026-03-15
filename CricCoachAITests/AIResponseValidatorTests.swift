import XCTest
@testable import CricCoachAI

/// Unit tests for AIResponseValidator — verifies hallucination detection
/// and correction logic across all validation rules.
final class AIResponseValidatorTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makePayload(
        phases: [String] = ["stance", "backlift", "contact"],
        angles: [String: [String: Float]] = [
            "stance": ["knee_bend": 165, "feet_width": 1.1],
            "backlift": ["wrist_height": 95],
            "contact": ["front_elbow": 160, "head_stability": 1.5]
        ]
    ) -> AnalysisPayload {
        let keyFrames = phases.map { phase in
            KeyFramePayload(
                phase: phase,
                imageBase64: "",
                poseLandmarks: [:],
                measuredAngles: angles[phase] ?? [:]
            )
        }
        return AnalysisPayload(
            analysisType: "batting",
            keyFrames: keyFrames,
            ruleScores: [:],
            userContext: UserContextPayload(
                heightCm: nil, playingRole: nil, bowlingStyle: nil,
                experienceLevel: "beginner", knownIssues: [],
                previousSessionScores: nil
            )
        )
    }
    
    private func makeResponse(
        score: Int = 75,
        issues: [IssueFeedback] = [],
        positives: [PositiveFeedback] = []
    ) -> AICoachingResponse {
        AICoachingResponse(
            overallAssessment: "Test assessment",
            overallScore: score,
            positives: positives,
            issues: issues,
            progressNote: nil,
            nextSessionFocus: nil
        )
    }
    
    private func makeIssue(
        rank: Int = 1,
        title: String = "Knee Bend",
        measuredValue: String = "165°",
        idealValue: String = "160-175°",
        phase: String = "stance",
        severity: String = "moderate"
    ) -> IssueFeedback {
        IssueFeedback(
            rank: rank,
            title: title,
            severity: severity,
            description: "Test description",
            measuredValue: measuredValue,
            idealValue: idealValue,
            phase: phase,
            whyItMatters: "Test reason",
            drill: DrillRecommendation(
                name: "Test Drill",
                description: "Do this drill",
                reps: "10",
                frequency: "Daily"
            ),
            target: "Improve to 80+"
        )
    }
    
    private func makeScores(overallScores: [Int] = [75, 80, 70]) -> [TechniqueScore] {
        let phases: [PosePhase] = [.stance, .backlift, .contact]
        return zip(phases, overallScores).map { phase, score in
            TechniqueScore(
                phase: phase,
                overallScore: score,
                checkpoints: [
                    CheckpointScore(
                        name: "Knee Bend",
                        score: score,
                        measuredValue: 165,
                        measuredValueDescription: "165°",
                        idealRange: "160-175°",
                        shortFeedback: "Good"
                    )
                ],
                keyFrameIndex: 0,
                keyFrameTimestamp: 0
            )
        }
    }
    
    // MARK: - extractNumericValue Tests
    
    func testExtractNumericValue_degrees() {
        XCTAssertEqual(AIResponseValidator.extractNumericValue(from: "45.2° elbow angle"), 45.2)
    }
    
    func testExtractNumericValue_percentage() {
        XCTAssertEqual(AIResponseValidator.extractNumericValue(from: "1.5% deviation"), 1.5)
    }
    
    func testExtractNumericValue_integer() {
        XCTAssertEqual(AIResponseValidator.extractNumericValue(from: "165 degrees"), 165)
    }
    
    func testExtractNumericValue_negative() {
        XCTAssertEqual(AIResponseValidator.extractNumericValue(from: "-3.1 inches"), -3.1)
    }
    
    func testExtractNumericValue_noNumber() {
        XCTAssertNil(AIResponseValidator.extractNumericValue(from: "no numbers here"))
    }
    
    func testExtractNumericValue_multipleNumbers_takesFirst() {
        XCTAssertEqual(AIResponseValidator.extractNumericValue(from: "45° to 60°"), 45)
    }
    
    // MARK: - deviationPercent Tests
    
    func testDeviationPercent_exact() {
        XCTAssertEqual(AIResponseValidator.deviationPercent(claimed: 100, actual: 100), 0)
    }
    
    func testDeviationPercent_within20() {
        let dev = AIResponseValidator.deviationPercent(claimed: 170, actual: 165)
        XCTAssertLessThanOrEqual(dev, 20, "170 vs 165 should be ≤20% deviation")
    }
    
    func testDeviationPercent_over50() {
        let dev = AIResponseValidator.deviationPercent(claimed: 45, actual: 120)
        XCTAssertGreaterThan(dev, 50, "45 vs 120 should be >50% deviation")
    }
    
    func testDeviationPercent_zeroActual() {
        XCTAssertEqual(AIResponseValidator.deviationPercent(claimed: 0, actual: 0), 0)
        XCTAssertEqual(AIResponseValidator.deviationPercent(claimed: 5, actual: 0), 100)
    }
    
    // MARK: - Validation: Issue Kept (≤20% deviation)
    
    func testValidation_issueKept_withinThreshold() {
        let issue = makeIssue(
            title: "Knee Bend",
            measuredValue: "163°",  // Claimed 163, actual is 165 → ~1.2% deviation
            phase: "stance"
        )
        let response = makeResponse(score: 75, issues: [issue])
        let payload = makePayload()
        let scores = makeScores()
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        // Issue should be kept
        XCTAssertEqual(result.cleanedResponse.issues.count, 1)
        XCTAssertEqual(result.cleanedResponse.issues.first?.title, "Knee Bend")
    }
    
    // MARK: - Validation: Issue with Invalid Phase Removed
    
    func testValidation_issueWithInvalidPhase_removed() {
        let issue = makeIssue(
            title: "Fake Phase Issue",
            measuredValue: "100°",
            phase: "nonexistent_phase"
        )
        let response = makeResponse(score: 75, issues: [issue])
        let payload = makePayload()
        let scores = makeScores()
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        XCTAssertTrue(result.wasModified)
        XCTAssertEqual(result.cleanedResponse.issues.count, 0)
        XCTAssertTrue(result.flaggedIssues.contains { $0.action == .removed })
    }
    
    // MARK: - Validation: Overall Score Capped
    
    func testValidation_overallScoreCapped_whenTooHigh() {
        // Rule-based average = (75 + 80 + 70) / 3 = 75
        // AI claims 95 → deviation = 20 > 10 → should be capped to 75
        let response = makeResponse(score: 95, issues: [])
        let payload = makePayload()
        let scores = makeScores(overallScores: [75, 80, 70])
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        XCTAssertTrue(result.wasModified)
        XCTAssertEqual(result.cleanedResponse.overallScore, 75)
    }
    
    func testValidation_overallScoreKept_whenWithinRange() {
        // Rule-based average = 75, AI claims 80 → deviation = 5 ≤ 10 → keep
        let response = makeResponse(score: 80, issues: [])
        let payload = makePayload()
        let scores = makeScores(overallScores: [75, 80, 70])
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        XCTAssertEqual(result.cleanedResponse.overallScore, 80)
    }
    
    func testValidation_overallScoreCapped_whenTooLow() {
        // Rule-based average = 75, AI claims 50 → deviation = 25 > 10 → cap to 75
        let response = makeResponse(score: 50, issues: [])
        let payload = makePayload()
        let scores = makeScores(overallScores: [75, 80, 70])
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        XCTAssertTrue(result.wasModified)
        XCTAssertEqual(result.cleanedResponse.overallScore, 75)
    }
    
    // MARK: - Validation: Issues Re-ranked After Removal
    
    func testValidation_issuesReranked_afterRemoval() {
        let issue1 = makeIssue(rank: 1, title: "Bad Phase", phase: "nonexistent")
        let issue2 = makeIssue(rank: 2, title: "Knee Bend", phase: "stance")
        let issue3 = makeIssue(rank: 3, title: "Front Elbow", measuredValue: "160°", phase: "contact")
        
        let response = makeResponse(score: 75, issues: [issue1, issue2, issue3])
        let payload = makePayload()
        let scores = makeScores()
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        // issue1 removed (bad phase), remaining re-ranked 1, 2
        XCTAssertEqual(result.cleanedResponse.issues.count, 2)
        XCTAssertEqual(result.cleanedResponse.issues[0].rank, 1)
        XCTAssertEqual(result.cleanedResponse.issues[1].rank, 2)
    }
    
    // MARK: - Validation: Empty Response Preserved
    
    func testValidation_emptyIssues_preserved() {
        let response = makeResponse(score: 75, issues: [])
        let payload = makePayload()
        let scores = makeScores()
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        XCTAssertFalse(result.wasModified)
        XCTAssertEqual(result.cleanedResponse.issues.count, 0)
    }
    
    // MARK: - Validation: Positives Preserved
    
    func testValidation_positivesPreserved() {
        let positives = [
            PositiveFeedback(title: "Good stance", description: "Well balanced"),
            PositiveFeedback(title: "Head still", description: "Great head stability")
        ]
        let response = makeResponse(score: 75, issues: [], positives: positives)
        let payload = makePayload()
        let scores = makeScores()
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        XCTAssertEqual(result.cleanedResponse.positives.count, 2)
    }
    
    // MARK: - Validation: No Scores → No Score Cap
    
    func testValidation_noTechniqueScores_scoreNotCapped() {
        let response = makeResponse(score: 95, issues: [])
        let payload = makePayload()
        let scores: [TechniqueScore] = []  // No scores → can't cap
        
        let result = AIResponseValidator.validate(
            response: response,
            against: payload,
            techniqueScores: scores
        )
        
        XCTAssertEqual(result.cleanedResponse.overallScore, 95)
    }
}

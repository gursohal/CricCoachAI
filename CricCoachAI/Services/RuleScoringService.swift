import Foundation
import CoreGraphics

/// Rule-based biomechanical scoring service
/// Scores each phase against ideal benchmarks.
/// Accepts an optional `ScoringConfig` for server-overridable thresholds (P2-8).
class RuleScoringService {
    
    /// Scoring thresholds — defaults match `IdealValues` in Constants.swift.
    /// Pass a server-fetched config to override thresholds without an app update.
    let config: ScoringConfig
    
    init(config: ScoringConfig = .default) {
        self.config = config
    }
    
    // MARK: - Main Scoring
    
    /// Score all detected phases
    func scoreAllPhases(
        phases: [DetectedPhase],
        poseSequence: PoseSequence,
        analysisType: AnalysisType
    ) -> [TechniqueScore] {
        return phases.compactMap { phase in
            scorePhase(phase, poseSequence: poseSequence, analysisType: analysisType)
        }
    }
    
    /// Score a single phase
    func scorePhase(
        _ detectedPhase: DetectedPhase,
        poseSequence: PoseSequence,
        analysisType: AnalysisType
    ) -> TechniqueScore? {
        guard let keyFrame = poseSequence.frame(atIndex: detectedPhase.keyFrame) else {
            return nil
        }
        
        let checkpoints: [CheckpointScore]
        
        switch detectedPhase.phase {
        // Batting phases
        case .stance:
            checkpoints = scoreStance(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .backlift:
            checkpoints = scoreBacklift(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .stride:
            checkpoints = scoreStride(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .downswing:
            checkpoints = scoreDownswing(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .contact:
            checkpoints = scoreContact(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .battingFollowThrough:
            checkpoints = scoreBattingFollowThrough(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
            
        // Bowling phases
        case .runUp:
            checkpoints = scoreRunUp(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .gather:
            checkpoints = scoreGather(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .backFootContact:
            checkpoints = scoreBackFootContact(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .frontFootContact:
            checkpoints = scoreFrontFootContact(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .release:
            checkpoints = scoreRelease(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        case .bowlingFollowThrough:
            checkpoints = scoreBowlingFollowThrough(keyFrame: keyFrame, sequence: poseSequence, phase: detectedPhase)
        }
        
        guard !checkpoints.isEmpty else { return nil }
        
        let overallScore = checkpoints.reduce(0) { $0 + $1.score } / checkpoints.count
        
        return TechniqueScore(
            phase: detectedPhase.phase,
            overallScore: overallScore,
            checkpoints: checkpoints,
            keyFrameIndex: detectedPhase.keyFrame,
            keyFrameTimestamp: detectedPhase.keyFrameTimestamp
        )
    }
    
    // MARK: - Batting Stance Scoring
    
    private func scoreStance(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Feet Width
        if let feetWidth = AngleCalculator.feetWidthNormalized(in: keyFrame) {
            let range = IdealValues.BattingStance.feetWidthRange
            let score = scoreInRange(value: feetWidth, idealRange: range, penaltyPerUnit: 100, unitSize: 0.1)
            checkpoints.append(CheckpointScore(
                name: "Feet Width",
                score: score,
                measuredValue: feetWidth,
                measuredValueDescription: String(format: "%.1fx shoulder width", feetWidth),
                idealRange: "\(range.lowerBound)-\(range.upperBound)x shoulder width",
                shortFeedback: score >= 80 ? "Good stance width" : "Adjust feet width to \(range.lowerBound)-\(range.upperBound)x shoulder width",
                landmark: BodyLandmark.leftAnkle.rawValue
            ))
        }
        
        // Knee Bend
        if let leftKnee = AngleCalculator.leftKneeAngle(in: keyFrame),
           let rightKnee = AngleCalculator.rightKneeAngle(in: keyFrame) {
            let avgKnee = (leftKnee + rightKnee) / 2
            let range = IdealValues.BattingStance.kneeBendRange
            let score = scoreInRange(value: avgKnee, idealRange: range, penaltyPerUnit: 15, unitSize: 5)
            checkpoints.append(CheckpointScore(
                name: "Knee Bend",
                score: score,
                measuredValue: avgKnee,
                measuredValueDescription: String(format: "%.0f°", avgKnee),
                idealRange: "\(Int(range.lowerBound))-\(Int(range.upperBound))°",
                shortFeedback: score >= 80 ? "Good knee flex" : avgKnee > range.upperBound ? "Knees too straight — add slight bend" : "Knees too bent — stand a bit taller",
                landmark: BodyLandmark.leftKnee.rawValue
            ))
        }
        
        // Head Position
        if let headDev = AngleCalculator.headOverBaseDeviation(in: keyFrame) {
            let threshold = IdealValues.BattingStance.headAlignmentThreshold
            let deviationPct = headDev * 100
            let score = headDev <= threshold ? 100 : max(0, 100 - Int((headDev - threshold) / 0.02) * 10)
            checkpoints.append(CheckpointScore(
                name: "Head Position",
                score: score,
                measuredValue: deviationPct,
                measuredValueDescription: String(format: "%.1f%% deviation", deviationPct),
                idealRange: "< \(Int(threshold * 100))% of stance width",
                shortFeedback: score >= 80 ? "Head well centered" : "Head drifting \(String(format: "%.1f%%", deviationPct)) off center",
                landmark: BodyLandmark.nose.rawValue
            ))
        }
        
        // Weight Distribution
        if let weight = AngleCalculator.weightDistribution(in: keyFrame) {
            let range = IdealValues.BattingStance.weightDistributionRange
            let score = range.contains(weight) ? 100 : max(0, 100 - Int(abs(weight - (range.lowerBound + range.upperBound) / 2) * 200))
            checkpoints.append(CheckpointScore(
                name: "Weight Distribution",
                score: score,
                measuredValue: weight,
                measuredValueDescription: weight < -0.1 ? "Back foot heavy" : weight > 0.1 ? "Front foot heavy" : "Centered",
                idealRange: "Centered or slightly back",
                shortFeedback: score >= 80 ? "Good weight distribution" : weight > 0.1 ? "Too much weight on front foot" : "Too much weight on back foot"
            ))
        }
        
        return checkpoints
    }
    
    // MARK: - Batting Backlift Scoring
    
    private func scoreBacklift(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Backlift Height
        if let wristHeight = AngleCalculator.wristHeightRelativeToShoulder(
            in: keyFrame, wrist: .rightWrist, shoulder: .rightShoulder
        ) {
            let threshold = IdealValues.BattingBacklift.wristAboveShoulderThreshold
            let score = wristHeight >= threshold ? 100 : max(0, 100 - Int((threshold - wristHeight) * 150))
            checkpoints.append(CheckpointScore(
                name: "Backlift Height",
                score: score,
                measuredValue: wristHeight,
                measuredValueDescription: String(format: "%.0f%% of shoulder height", wristHeight * 100),
                idealRange: "At or above shoulder height",
                shortFeedback: score >= 80 ? "Good backlift height" : "Lift the bat higher — wrists should be at shoulder height",
                landmark: BodyLandmark.rightWrist.rawValue
            ))
        }
        
        // Head Stability (compared to stance)
        if let stanceFrame = sequence.frame(atIndex: phase.startFrame) {
            if let headMovement = PoseNormalizer.headStability(from: stanceFrame, to: keyFrame) {
                let threshold = IdealValues.BattingBacklift.headMovementThreshold
                let score = headMovement <= threshold ? 100 : max(0, 100 - Int((headMovement - threshold) * 10))
                checkpoints.append(CheckpointScore(
                    name: "Head Stability",
                    score: score,
                    measuredValue: headMovement,
                    measuredValueDescription: String(format: "%.1f%% movement", headMovement),
                    idealRange: "< \(Int(threshold))% of body height",
                    shortFeedback: score >= 80 ? "Head stays still during backlift" : "Head moves \(String(format: "%.1f%%", headMovement)) — keep it still",
                    landmark: BodyLandmark.nose.rawValue
                ))
            }
        }
        
        // Front Shoulder Alignment
        if let shoulderTilt = AngleCalculator.shoulderTilt(in: keyFrame) {
            let maxOpen = IdealValues.BattingBacklift.shoulderAlignmentMax
            let openness = abs(shoulderTilt)
            let score = openness <= maxOpen ? 100 : max(0, 100 - Int((openness - maxOpen) * 3))
            checkpoints.append(CheckpointScore(
                name: "Front Shoulder",
                score: score,
                measuredValue: openness,
                measuredValueDescription: String(format: "%.0f° open", openness),
                idealRange: "< \(Int(maxOpen))° open",
                shortFeedback: score >= 80 ? "Shoulder well aligned" : "Front shoulder opening too early — stay side-on longer",
                landmark: BodyLandmark.leftShoulder.rawValue
            ))
        }
        
        return checkpoints
    }
    
    // MARK: - Batting Stride Scoring
    
    private func scoreStride(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Stride Length
        if let strideLength = AngleCalculator.strideLengthNormalized(in: keyFrame) {
            let range = IdealValues.BattingStride.strideLengthRange
            let score = scoreInRange(value: strideLength, idealRange: range, penaltyPerUnit: 50, unitSize: 0.2)
            checkpoints.append(CheckpointScore(
                name: "Stride Length",
                score: score,
                measuredValue: strideLength,
                measuredValueDescription: String(format: "%.1fx shoulder width", strideLength),
                idealRange: "\(range.lowerBound)-\(range.upperBound)x shoulder width",
                shortFeedback: score >= 80 ? "Good stride length" : strideLength < range.lowerBound ? "Stride too short — get to the pitch of the ball" : "Over-striding — reduces balance",
                landmark: BodyLandmark.leftAnkle.rawValue
            ))
        }
        
        // Front Knee Angle
        if let leftKnee = AngleCalculator.leftKneeAngle(in: keyFrame) {
            let range = IdealValues.BattingStride.frontKneeRange
            let score = scoreInRange(value: leftKnee, idealRange: range, penaltyPerUnit: 15, unitSize: 5)
            checkpoints.append(CheckpointScore(
                name: "Front Knee",
                score: score,
                measuredValue: leftKnee,
                measuredValueDescription: String(format: "%.0f°", leftKnee),
                idealRange: "\(Int(range.lowerBound))-\(Int(range.upperBound))°",
                shortFeedback: score >= 80 ? "Good front knee position" : leftKnee < range.lowerBound ? "Front knee too bent" : "Front knee too straight — add some flex",
                landmark: BodyLandmark.leftKnee.rawValue
            ))
        }
        
        // Head Position (should be over or ahead of front knee)
        if let headPos = AngleCalculator.headRelativeToFrontFoot(in: keyFrame, frontFoot: .leftAnkle) {
            let score = headPos >= -0.1 ? 100 : max(0, 100 - Int(abs(headPos + 0.1) * 200))
            checkpoints.append(CheckpointScore(
                name: "Head Position",
                score: score,
                measuredValue: headPos,
                measuredValueDescription: headPos >= 0 ? "Ahead of front foot" : "Behind front foot",
                idealRange: "Over or ahead of front knee",
                shortFeedback: score >= 80 ? "Head well positioned" : "Get your head over the ball — lead with your head",
                landmark: BodyLandmark.nose.rawValue
            ))
        }
        
        return checkpoints
    }
    
    // MARK: - Batting Downswing Scoring
    
    private func scoreDownswing(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Bat path (elbow angles during downswing)
        if let rightElbow = AngleCalculator.rightElbowAngle(in: keyFrame) {
            let score = rightElbow >= 90 ? 100 : max(0, 100 - Int((90 - rightElbow) * 2))
            checkpoints.append(CheckpointScore(
                name: "Bat Path",
                score: score,
                measuredValue: rightElbow,
                measuredValueDescription: String(format: "%.0f° right elbow", rightElbow),
                idealRange: "> 90° (not cramped)",
                shortFeedback: score >= 80 ? "Good bat swing path" : "Elbow too closed — create more room",
                landmark: BodyLandmark.rightElbow.rawValue
            ))
        }
        
        return checkpoints
    }
    
    // MARK: - Batting Contact Scoring
    
    private func scoreContact(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Head Stability
        if let stanceFrame = sequence.frames.first {
            if let headMovement = PoseNormalizer.headStability(from: stanceFrame, to: keyFrame) {
                let threshold = IdealValues.BattingContact.headStabilityThreshold
                let score = headMovement <= threshold ? 100 : max(0, 100 - Int((headMovement - threshold) * 15))
                checkpoints.append(CheckpointScore(
                    name: "Head Stability",
                    score: score,
                    measuredValue: headMovement,
                    measuredValueDescription: String(format: "%.1f%% lateral movement", headMovement),
                    idealRange: "< \(Int(threshold))% of body height",
                    shortFeedback: score >= 80 ? "Eyes level at contact — great!" : "Head moving \(String(format: "%.1f%%", headMovement)) — keep eyes level on the ball",
                    landmark: BodyLandmark.nose.rawValue
                ))
            }
        }
        
        // Head Over Ball
        if let headPos = AngleCalculator.headRelativeToFrontFoot(in: keyFrame, frontFoot: .leftAnkle) {
            let threshold = IdealValues.BattingContact.headOverFootThreshold
            let score = abs(headPos) <= threshold * 3 ? 100 : max(0, 100 - Int(abs(headPos) * 100))
            checkpoints.append(CheckpointScore(
                name: "Head Over Ball",
                score: score,
                measuredValue: headPos,
                measuredValueDescription: headPos > 0 ? "Ahead of front foot" : "Behind front foot",
                idealRange: "Directly over or slightly ahead of front foot",
                shortFeedback: score >= 80 ? "Head nicely over the ball" : "Get your head closer to the line of the ball"
            ))
        }
        
        // Front Elbow
        if let frontElbow = AngleCalculator.leftElbowAngle(in: keyFrame) {
            let range = IdealValues.BattingContact.frontElbowRange
            let score = scoreInRange(value: frontElbow, idealRange: range, penaltyPerUnit: 15, unitSize: 5)
            checkpoints.append(CheckpointScore(
                name: "Front Elbow",
                score: score,
                measuredValue: frontElbow,
                measuredValueDescription: String(format: "%.0f°", frontElbow),
                idealRange: "\(Int(range.lowerBound))-\(Int(range.upperBound))°",
                shortFeedback: score >= 80 ? "Front arm well extended" : "Extend the front arm more at contact — don't collapse the elbow",
                landmark: BodyLandmark.leftElbow.rawValue
            ))
        }
        
        // Weight Transfer
        if let weight = AngleCalculator.weightDistribution(in: keyFrame) {
            let score = weight > 0 ? 100 : max(0, 100 - Int(abs(weight) * 150))
            checkpoints.append(CheckpointScore(
                name: "Weight Transfer",
                score: score,
                measuredValue: weight,
                measuredValueDescription: weight > 0 ? "Forward" : "Back",
                idealRange: "Weight shifted to front foot",
                shortFeedback: score >= 80 ? "Good weight transfer" : "Transfer weight into the shot — drive through the ball"
            ))
        }
        
        return checkpoints
    }
    
    // MARK: - Batting Follow Through Scoring
    
    private func scoreBattingFollowThrough(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Wrist Height (should finish high)
        if let wristHeight = AngleCalculator.wristHeightRelativeToShoulder(
            in: keyFrame, wrist: .rightWrist, shoulder: .rightShoulder
        ) {
            let score = wristHeight >= 0.8 ? 100 : max(0, Int(wristHeight * 125))
            checkpoints.append(CheckpointScore(
                name: "Bat Swing Completion",
                score: score,
                measuredValue: wristHeight,
                measuredValueDescription: wristHeight >= 1.0 ? "Above shoulder" : "Below shoulder",
                idealRange: "Wrists finish above shoulder",
                shortFeedback: score >= 80 ? "Great follow through" : "Complete the swing — finish high",
                landmark: BodyLandmark.rightWrist.rawValue
            ))
        }
        
        // Balance
        if let headDev = AngleCalculator.headOverBaseDeviation(in: keyFrame) {
            let score = headDev < 0.15 ? 100 : max(0, 100 - Int(headDev * 200))
            checkpoints.append(CheckpointScore(
                name: "Balance",
                score: score,
                measuredValue: headDev,
                measuredValueDescription: String(format: "%.1f%% deviation", headDev * 100),
                idealRange: "Stable base, both feet on ground",
                shortFeedback: score >= 80 ? "Good balance maintained" : "Falling over — stay balanced through the shot"
            ))
        }
        
        return checkpoints
    }
    
    // MARK: - Bowling Phase Scoring
    
    private func scoreRunUp(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Head stability during run-up
        if let startFrame = sequence.frame(atIndex: phase.startFrame) {
            if let headMovement = PoseNormalizer.headStability(from: startFrame, to: keyFrame) {
                let score = headMovement < 5 ? 100 : max(0, 100 - Int(headMovement * 5))
                checkpoints.append(CheckpointScore(
                    name: "Head Stability",
                    score: score,
                    measuredValue: headMovement,
                    measuredValueDescription: String(format: "%.1f%% movement", headMovement),
                    idealRange: "Minimal head bounce",
                    shortFeedback: score >= 80 ? "Smooth run-up" : "Too much head movement in run-up — stay smooth"
                ))
            }
        }
        
        return checkpoints
    }
    
    private func scoreGather(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        // Gather phase scoring
        var checkpoints: [CheckpointScore] = []
        
        if let hipShoulderSep = AngleCalculator.hipShoulderSeparation(in: keyFrame) {
            let score = hipShoulderSep >= 20 ? 100 : max(0, Int(hipShoulderSep * 5))
            checkpoints.append(CheckpointScore(
                name: "Body Coil",
                score: score,
                measuredValue: hipShoulderSep,
                measuredValueDescription: String(format: "%.0f° separation", hipShoulderSep),
                idealRange: "20-40° hip-shoulder separation",
                shortFeedback: score >= 80 ? "Good body coil" : "More hip-shoulder separation needed in the gather"
            ))
        }
        
        return checkpoints
    }
    
    private func scoreBackFootContact(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Hip-Shoulder Separation
        if let separation = AngleCalculator.hipShoulderSeparation(in: keyFrame) {
            let range = IdealValues.BowlingRelease.hipShoulderSeparationRange
            let score = scoreInRange(value: separation, idealRange: range, penaltyPerUnit: 10, unitSize: 5)
            checkpoints.append(CheckpointScore(
                name: "Hip-Shoulder Separation",
                score: score,
                measuredValue: separation,
                measuredValueDescription: String(format: "%.0f°", separation),
                idealRange: "\(Int(range.lowerBound))-\(Int(range.upperBound))°",
                shortFeedback: score >= 80 ? "Good hip-shoulder separation" : "Need more rotation — drive with your hips"
            ))
        }
        
        // Bowling Action Type (side-on vs chest-on vs mixed)
        let actionType = AngleCalculator.bowlingActionType(in: keyFrame)
        let actionScore = actionType == .mixed ? 50 : 100
        checkpoints.append(CheckpointScore(
            name: "Body Alignment",
            score: actionScore,
            measuredValue: Double(actionScore),
            measuredValueDescription: actionType.rawValue,
            idealRange: "Consistent side-on or chest-on",
            shortFeedback: actionType == .mixed ? "⚠️ MIXED ACTION — Injury risk! See a coach." : "Consistent \(actionType.rawValue) action"
        ))
        
        return checkpoints
    }
    
    private func scoreFrontFootContact(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Front Leg Brace
        if let frontKnee = AngleCalculator.leftKneeAngle(in: keyFrame) {
            let range = IdealValues.BowlingRelease.frontLegBraceRange
            let score = scoreInRange(value: frontKnee, idealRange: range, penaltyPerUnit: 10, unitSize: 5)
            checkpoints.append(CheckpointScore(
                name: "Front Leg Brace",
                score: score,
                measuredValue: frontKnee,
                measuredValueDescription: String(format: "%.0f°", frontKnee),
                idealRange: "\(Int(range.lowerBound))-\(Int(range.upperBound))°",
                shortFeedback: score >= 80 ? "Good front leg brace" : "Brace front leg more — plant and drive",
                landmark: BodyLandmark.leftKnee.rawValue
            ))
        }
        
        return checkpoints
    }
    
    private func scoreRelease(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Arm Height at Release
        if let armAngle = AngleCalculator.bowlingArmAngleFromVertical(
            in: keyFrame,
            bowlingArm: .rightShoulder,
            bowlingElbow: .rightElbow,
            bowlingWrist: .rightWrist
        ) {
            let maxAngle = IdealValues.BowlingRelease.armAngleFromVerticalMax
            let score = armAngle <= maxAngle ? 100 : max(0, 100 - Int((armAngle - maxAngle) * 2))
            checkpoints.append(CheckpointScore(
                name: "Arm Height",
                score: score,
                measuredValue: armAngle,
                measuredValueDescription: String(format: "%.0f° from vertical", armAngle),
                idealRange: "Within \(Int(maxAngle))° of vertical",
                shortFeedback: score >= 80 ? "High arm action — great!" : "Get your arm higher at release — \(String(format: "%.0f°", armAngle)) off vertical",
                landmark: BodyLandmark.rightWrist.rawValue
            ))
        }
        
        // Front Leg Brace at Release
        if let frontKnee = AngleCalculator.leftKneeAngle(in: keyFrame) {
            let range = IdealValues.BowlingRelease.frontLegBraceRange
            let score = scoreInRange(value: frontKnee, idealRange: range, penaltyPerUnit: 10, unitSize: 5)
            checkpoints.append(CheckpointScore(
                name: "Front Leg Brace",
                score: score,
                measuredValue: frontKnee,
                measuredValueDescription: String(format: "%.0f°", frontKnee),
                idealRange: "\(Int(range.lowerBound))-\(Int(range.upperBound))°",
                shortFeedback: score >= 80 ? "Front leg braced well" : "Front leg collapsing — brace harder for more pace",
                landmark: BodyLandmark.leftKnee.rawValue
            ))
        }
        
        // Head Position
        if let headDev = AngleCalculator.headOverBaseDeviation(in: keyFrame) {
            let score = headDev < 0.1 ? 100 : max(0, 100 - Int(headDev * 200))
            checkpoints.append(CheckpointScore(
                name: "Head Position",
                score: score,
                measuredValue: headDev * 100,
                measuredValueDescription: String(format: "%.1f%% deviation", headDev * 100),
                idealRange: "Head upright, looking at target",
                shortFeedback: score >= 80 ? "Head stable at release" : "Head falling away — stay tall at release",
                landmark: BodyLandmark.nose.rawValue
            ))
        }
        
        return checkpoints
    }
    
    private func scoreBowlingFollowThrough(keyFrame: PoseFrame, sequence: PoseSequence, phase: DetectedPhase) -> [CheckpointScore] {
        var checkpoints: [CheckpointScore] = []
        
        // Balance
        if let headDev = AngleCalculator.headOverBaseDeviation(in: keyFrame) {
            let score = headDev < 0.2 ? 100 : max(0, 100 - Int(headDev * 150))
            checkpoints.append(CheckpointScore(
                name: "Balance",
                score: score,
                measuredValue: headDev,
                measuredValueDescription: String(format: "%.1f%% deviation", headDev * 100),
                idealRange: "Balanced finish",
                shortFeedback: score >= 80 ? "Good follow through balance" : "Falling over in follow through — stay balanced"
            ))
        }
        
        return checkpoints
    }
    
    // MARK: - Scoring Utility
    
    /// Score a value against an ideal range
    /// Returns 0-100 score
    private func scoreInRange(
        value: Double,
        idealRange: ClosedRange<Double>,
        penaltyPerUnit: Int,
        unitSize: Double
    ) -> Int {
        if idealRange.contains(value) {
            return 100
        }
        
        let deviation: Double
        if value < idealRange.lowerBound {
            deviation = idealRange.lowerBound - value
        } else {
            deviation = value - idealRange.upperBound
        }
        
        let units = deviation / unitSize
        let penalty = Int(units) * penaltyPerUnit
        return max(0, 100 - penalty)
    }
}

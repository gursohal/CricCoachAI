import Foundation
import CoreGraphics

/// Service for detecting cricket batting/bowling phases from pose sequences
/// Uses a rule-based state machine with landmark velocity analysis
class PhaseDetectionService {
    
    private let smoothingWindow = AppConstants.smoothingWindowSize
    
    // MARK: - Main Detection
    
    /// Detect all phases from a pose sequence
    func detectPhases(
        in sequence: PoseSequence,
        analysisType: AnalysisType
    ) -> [DetectedPhase] {
        guard sequence.frames.count > 10 else { return [] }
        
        switch analysisType {
        case .batting:
            return detectBattingPhases(in: sequence)
        case .bowling:
            return detectBowlingPhases(in: sequence)
        }
    }
    
    // MARK: - Batting Phase Detection
    
    private func detectBattingPhases(in sequence: PoseSequence) -> [DetectedPhase] {
        var phases: [DetectedPhase] = []
        let frames = sequence.frames
        guard frames.count > 20 else { return [] }
        
        // Calculate wrist velocities for phase transition detection
        let wristVelocities = calculateSmoothedVelocities(
            for: .rightWrist, in: sequence
        )
        let leftWristVelocities = calculateSmoothedVelocities(
            for: .leftWrist, in: sequence
        )
        
        // Calculate ankle separation changes for stride detection
        let ankleSeparations = frames.compactMap { frame -> (Int, Double)? in
            guard let sep = AngleCalculator.strideLengthNormalized(in: frame) else { return nil }
            return (frame.frameIndex, sep)
        }
        
        // Calculate wrist heights for backlift/contact detection
        let wristHeights = frames.compactMap { frame -> (Int, Double)? in
            guard let rw = frame.position(for: .rightWrist),
                  let rs = frame.position(for: .rightShoulder) else { return nil }
            return (frame.frameIndex, Double(rw.y - rs.y))
        }
        
        // Find key transition points
        let stanceEnd = findStanceEnd(wristVelocities: wristVelocities, frames: frames)
        let backliftPeak = findBackliftPeak(wristHeights: wristHeights, after: stanceEnd)
        let strideEnd = findStrideEnd(ankleSeparations: ankleSeparations, after: backliftPeak)
        let contactPoint = findContactPoint(wristHeights: wristHeights, after: strideEnd)
        
        // Build phases from transition points
        let stanceStart = 0
        let lastFrame = frames.count - 1
        
        // STANCE
        if stanceEnd > stanceStart {
            let keyFrame = (stanceStart + stanceEnd) / 2
            phases.append(DetectedPhase(
                phase: .stance,
                startFrame: stanceStart,
                endFrame: stanceEnd,
                keyFrame: keyFrame,
                keyFrameTimestamp: frames[safe: keyFrame]?.timestamp ?? 0,
                confidence: 0.85
            ))
        }
        
        // BACKLIFT
        if let peak = backliftPeak, peak > stanceEnd {
            let backliftStart = stanceEnd + 1
            phases.append(DetectedPhase(
                phase: .backlift,
                startFrame: backliftStart,
                endFrame: peak,
                keyFrame: peak,
                keyFrameTimestamp: frames[safe: peak]?.timestamp ?? 0,
                confidence: 0.8
            ))
        }
        
        // STRIDE
        let strideStart = (backliftPeak ?? stanceEnd) + 1
        if let strEnd = strideEnd, strEnd > strideStart {
            phases.append(DetectedPhase(
                phase: .stride,
                startFrame: strideStart,
                endFrame: strEnd,
                keyFrame: strEnd,
                keyFrameTimestamp: frames[safe: strEnd]?.timestamp ?? 0,
                confidence: 0.75
            ))
        }
        
        // DOWNSWING
        let downswingStart = (strideEnd ?? strideStart) + 1
        if let contact = contactPoint, contact > downswingStart {
            let downswingEnd = contact - 1
            let downswingMid = (downswingStart + downswingEnd) / 2
            if downswingEnd > downswingStart {
                phases.append(DetectedPhase(
                    phase: .downswing,
                    startFrame: downswingStart,
                    endFrame: downswingEnd,
                    keyFrame: downswingMid,
                    keyFrameTimestamp: frames[safe: downswingMid]?.timestamp ?? 0,
                    confidence: 0.7
                ))
            }
        }
        
        // CONTACT
        if let contact = contactPoint {
            let contactEnd = min(contact + 3, lastFrame)
            phases.append(DetectedPhase(
                phase: .contact,
                startFrame: max(contact - 2, 0),
                endFrame: contactEnd,
                keyFrame: contact,
                keyFrameTimestamp: frames[safe: contact]?.timestamp ?? 0,
                confidence: 0.8
            ))
        }
        
        // FOLLOW THROUGH
        let followStart = (contactPoint ?? (lastFrame - 10)) + 3
        if followStart < lastFrame {
            let followKeyFrame = min(followStart + 5, lastFrame)
            phases.append(DetectedPhase(
                phase: .battingFollowThrough,
                startFrame: followStart,
                endFrame: lastFrame,
                keyFrame: followKeyFrame,
                keyFrameTimestamp: frames[safe: followKeyFrame]?.timestamp ?? 0,
                confidence: 0.75
            ))
        }
        
        return phases
    }
    
    // MARK: - Bowling Phase Detection
    
    private func detectBowlingPhases(in sequence: PoseSequence) -> [DetectedPhase] {
        var phases: [DetectedPhase] = []
        let frames = sequence.frames
        guard frames.count > 20 else { return [] }
        
        let lastFrame = frames.count - 1
        
        // Calculate body horizontal velocity for run-up detection
        let bodyVelocities = calculateBodyHorizontalVelocities(in: sequence)
        
        // Calculate ankle heights for foot contact detection
        let leftAnkleHeights = frames.compactMap { f -> (Int, Double)? in
            guard let a = f.position(for: .leftAnkle) else { return nil }
            return (f.frameIndex, Double(a.y))
        }
        let rightAnkleHeights = frames.compactMap { f -> (Int, Double)? in
            guard let a = f.position(for: .rightAnkle) else { return nil }
            return (f.frameIndex, Double(a.y))
        }
        
        // Calculate bowling arm (right wrist) height
        let bowlingArmHeights = frames.compactMap { f -> (Int, Double)? in
            guard let w = f.position(for: .rightWrist) else { return nil }
            return (f.frameIndex, Double(w.y))
        }
        
        // Find key transitions
        let gatherStart = findGatherStart(bodyVelocities: bodyVelocities, frames: frames)
        let backFootLand = findFootContact(
            ankleHeights: rightAnkleHeights,
            after: gatherStart ?? 0,
            lookingForDrop: true
        )
        let frontFootLand = findFootContact(
            ankleHeights: leftAnkleHeights,
            after: backFootLand ?? (gatherStart ?? 0),
            lookingForDrop: true
        )
        let releasePoint = findReleasePoint(
            bowlingArmHeights: bowlingArmHeights,
            after: frontFootLand ?? (backFootLand ?? 0)
        )
        
        // RUN-UP
        let runUpEnd = max((gatherStart ?? 10) - 1, 0)
        if runUpEnd > 5 {
            let keyFrame = max(runUpEnd - 5, 0)
            phases.append(DetectedPhase(
                phase: .runUp,
                startFrame: 0,
                endFrame: runUpEnd,
                keyFrame: keyFrame,
                keyFrameTimestamp: frames[safe: keyFrame]?.timestamp ?? 0,
                confidence: 0.8
            ))
        }
        
        // GATHER/BOUND
        if let gs = gatherStart {
            let gatherEnd = (backFootLand ?? (gs + 10)) - 1
            let gatherKey = (gs + min(gatherEnd, frames.count - 1)) / 2
            phases.append(DetectedPhase(
                phase: .gather,
                startFrame: gs,
                endFrame: min(gatherEnd, lastFrame),
                keyFrame: min(gatherKey, lastFrame),
                keyFrameTimestamp: frames[safe: min(gatherKey, lastFrame)]?.timestamp ?? 0,
                confidence: 0.7
            ))
        }
        
        // BACK FOOT CONTACT
        if let bfc = backFootLand {
            let bfcEnd = (frontFootLand ?? (bfc + 5)) - 1
            phases.append(DetectedPhase(
                phase: .backFootContact,
                startFrame: bfc,
                endFrame: min(bfcEnd, lastFrame),
                keyFrame: bfc,
                keyFrameTimestamp: frames[safe: bfc]?.timestamp ?? 0,
                confidence: 0.75
            ))
        }
        
        // FRONT FOOT CONTACT
        if let ffc = frontFootLand {
            let ffcEnd = (releasePoint ?? (ffc + 5)) - 1
            phases.append(DetectedPhase(
                phase: .frontFootContact,
                startFrame: ffc,
                endFrame: min(ffcEnd, lastFrame),
                keyFrame: ffc,
                keyFrameTimestamp: frames[safe: ffc]?.timestamp ?? 0,
                confidence: 0.8
            ))
        }
        
        // RELEASE
        if let rp = releasePoint {
            let releaseEnd = min(rp + 3, lastFrame)
            phases.append(DetectedPhase(
                phase: .release,
                startFrame: max(rp - 2, 0),
                endFrame: releaseEnd,
                keyFrame: rp,
                keyFrameTimestamp: frames[safe: rp]?.timestamp ?? 0,
                confidence: 0.8
            ))
        }
        
        // FOLLOW THROUGH
        let followStart = (releasePoint ?? (lastFrame - 10)) + 3
        if followStart < lastFrame {
            let followKey = min(followStart + 5, lastFrame)
            phases.append(DetectedPhase(
                phase: .bowlingFollowThrough,
                startFrame: min(followStart, lastFrame),
                endFrame: lastFrame,
                keyFrame: followKey,
                keyFrameTimestamp: frames[safe: followKey]?.timestamp ?? 0,
                confidence: 0.7
            ))
        }
        
        return phases
    }
    
    // MARK: - Batting Transition Detectors
    
    /// Find the frame where stance ends (first significant wrist movement upward)
    private func findStanceEnd(wristVelocities: [(Int, CGPoint)], frames: [PoseFrame]) -> Int {
        let threshold: CGFloat = 0.02  // velocity threshold
        
        // Look for first sustained upward wrist movement
        for (index, velocity) in wristVelocities {
            if velocity.y > threshold {
                // Verify it's sustained (next few frames also show movement)
                let nextVelocities = wristVelocities.filter { $0.0 > index && $0.0 <= index + 3 }
                let sustainedMovement = nextVelocities.allSatisfy { $0.1.y > threshold * 0.5 }
                if sustainedMovement || nextVelocities.isEmpty {
                    return max(index - 1, 0)
                }
            }
        }
        
        // Default: first 20% of frames
        return frames.count / 5
    }
    
    /// Find the peak of the backlift (highest wrist position)
    private func findBackliftPeak(wristHeights: [(Int, Double)], after startFrame: Int) -> Int? {
        let relevantHeights = wristHeights.filter { $0.0 > startFrame }
        guard !relevantHeights.isEmpty else { return nil }
        
        // Find first local maximum in wrist height (above shoulder)
        var maxHeight: Double = -1
        var maxFrame: Int?
        
        for (frame, height) in relevantHeights {
            if height > maxHeight && height > 0 {  // above shoulder
                maxHeight = height
                maxFrame = frame
            } else if maxFrame != nil && height < maxHeight * 0.8 {
                // Started descending significantly
                break
            }
        }
        
        return maxFrame
    }
    
    /// Find stride end (maximum ankle separation after backlift)
    private func findStrideEnd(ankleSeparations: [(Int, Double)], after startFrame: Int?) -> Int? {
        guard let start = startFrame else { return nil }
        let relevantSeps = ankleSeparations.filter { $0.0 > start }
        guard !relevantSeps.isEmpty else { return nil }
        
        // Find maximum ankle separation
        return relevantSeps.max(by: { $0.1 < $1.1 })?.0
    }
    
    /// Find contact point (lowest wrist position during downswing)
    private func findContactPoint(wristHeights: [(Int, Double)], after startFrame: Int?) -> Int? {
        guard let start = startFrame else { return nil }
        let relevantHeights = wristHeights.filter { $0.0 > start }
        guard !relevantHeights.isEmpty else { return nil }
        
        // Find the minimum wrist height after stride (contact point)
        var minHeight = Double.infinity
        var minFrame: Int?
        
        for (frame, height) in relevantHeights {
            if height < minHeight {
                minHeight = height
                minFrame = frame
            } else if minFrame != nil && height > minHeight + 0.05 {
                // Wrist rising again (follow through)
                break
            }
        }
        
        return minFrame
    }
    
    // MARK: - Bowling Transition Detectors
    
    /// Find where the gather/bound starts (deceleration before delivery)
    private func findGatherStart(bodyVelocities: [(Int, Double)], frames: [PoseFrame]) -> Int? {
        guard bodyVelocities.count > 10 else { return nil }
        
        // Look for sudden change in horizontal velocity (deceleration for gather)
        // The gather typically happens in the last 40% of the delivery
        let startLookingFrom = bodyVelocities.count * 3 / 5
        
        for i in startLookingFrom..<bodyVelocities.count - 5 {
            let currentVel = bodyVelocities[i].1
            if i + 3 < bodyVelocities.count {
                let futureVel = bodyVelocities[i + 3].1
                // Significant deceleration
                if currentVel > 0.01 && futureVel < currentVel * 0.5 {
                    return bodyVelocities[i].0
                }
            }
        }
        
        // Default: 60% through the video
        return frames.count * 3 / 5
    }
    
    /// Find foot contact (ankle drops to ground level)
    private func findFootContact(
        ankleHeights: [(Int, Double)],
        after startFrame: Int,
        lookingForDrop: Bool
    ) -> Int? {
        let relevantHeights = ankleHeights.filter { $0.0 > startFrame }
        guard relevantHeights.count > 3 else { return nil }
        
        // Find minimum ankle height (foot on ground)
        // Look for the first significant drop after the start frame
        let baselineHeight = relevantHeights.prefix(3).map { $0.1 }.reduce(0, +) / 3.0
        
        for (frame, height) in relevantHeights {
            if height < baselineHeight * 0.7 {
                return frame
            }
        }
        
        // Fall back to minimum height
        return relevantHeights.min(by: { $0.1 < $1.1 })?.0
    }
    
    /// Find the release point (bowling arm at highest point)
    private func findReleasePoint(
        bowlingArmHeights: [(Int, Double)],
        after startFrame: Int
    ) -> Int? {
        let relevantHeights = bowlingArmHeights.filter { $0.0 > startFrame }
        guard !relevantHeights.isEmpty else { return nil }
        
        // Find maximum arm height (release point)
        return relevantHeights.max(by: { $0.1 < $1.1 })?.0
    }
    
    // MARK: - Velocity Calculations
    
    /// Calculate smoothed velocity of a landmark across frames
    private func calculateSmoothedVelocities(
        for landmark: BodyLandmark,
        in sequence: PoseSequence
    ) -> [(Int, CGPoint)] {
        let frames = sequence.frames
        guard frames.count > smoothingWindow else { return [] }
        
        var velocities: [(Int, CGPoint)] = []
        
        for i in smoothingWindow..<frames.count {
            let current = i
            let previous = i - smoothingWindow
            
            if let vel = sequence.landmarkVelocity(landmark, fromFrame: previous, toFrame: current) {
                velocities.append((i, vel))
            }
        }
        
        return velocities
    }
    
    /// Calculate horizontal body velocity (for run-up detection)
    private func calculateBodyHorizontalVelocities(in sequence: PoseSequence) -> [(Int, Double)] {
        let frames = sequence.frames
        guard frames.count > 3 else { return [] }
        
        var velocities: [(Int, Double)] = []
        
        for i in 3..<frames.count {
            let f1 = frames[i - 3]
            let f2 = frames[i]
            
            if let hip1 = f1.midpoint(between: .leftHip, and: .rightHip),
               let hip2 = f2.midpoint(between: .leftHip, and: .rightHip) {
                let dt = f2.timestamp - f1.timestamp
                guard dt > 0 else { continue }
                let velocity = Double(abs(hip2.x - hip1.x) / CGFloat(dt))
                velocities.append((i, velocity))
            }
        }
        
        return velocities
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

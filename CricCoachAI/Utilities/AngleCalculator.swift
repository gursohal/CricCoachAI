import Foundation
import CoreGraphics

/// Utility for calculating angles between body landmarks
struct AngleCalculator {
    
    /// Calculate the angle at point B formed by rays BA and BC
    /// Returns angle in degrees (0-180)
    static func angleBetween(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        let baX = Double(a.x - b.x)
        let baY = Double(a.y - b.y)
        let bcX = Double(c.x - b.x)
        let bcY = Double(c.y - b.y)
        
        let dotProduct = baX * bcX + baY * bcY
        let magnitudeBA = sqrt(baX * baX + baY * baY)
        let magnitudeBC = sqrt(bcX * bcX + bcY * bcY)
        
        guard magnitudeBA > 0 && magnitudeBC > 0 else { return 0 }
        
        let cosAngle = max(-1.0, min(1.0, dotProduct / (magnitudeBA * magnitudeBC)))
        return acos(cosAngle) * 180.0 / Double.pi
    }
    
    /// Calculate the angle at a joint given three body landmarks
    static func jointAngle(
        in frame: PoseFrame,
        proximal: BodyLandmark,
        joint: BodyLandmark,
        distal: BodyLandmark
    ) -> Double? {
        guard let a = frame.position(for: proximal),
              let b = frame.position(for: joint),
              let c = frame.position(for: distal) else { return nil }
        return angleBetween(a: a, b: b, c: c)
    }
    
    // MARK: - Common Cricket Angles
    
    /// Left elbow angle (shoulder-elbow-wrist)
    static func leftElbowAngle(in frame: PoseFrame) -> Double? {
        jointAngle(in: frame, proximal: .leftShoulder, joint: .leftElbow, distal: .leftWrist)
    }
    
    /// Right elbow angle (shoulder-elbow-wrist)
    static func rightElbowAngle(in frame: PoseFrame) -> Double? {
        jointAngle(in: frame, proximal: .rightShoulder, joint: .rightElbow, distal: .rightWrist)
    }
    
    /// Left knee angle (hip-knee-ankle)
    static func leftKneeAngle(in frame: PoseFrame) -> Double? {
        jointAngle(in: frame, proximal: .leftHip, joint: .leftKnee, distal: .leftAnkle)
    }
    
    /// Right knee angle (hip-knee-ankle)
    static func rightKneeAngle(in frame: PoseFrame) -> Double? {
        jointAngle(in: frame, proximal: .rightHip, joint: .rightKnee, distal: .rightAnkle)
    }
    
    /// Left shoulder angle (elbow-shoulder-hip)
    static func leftShoulderAngle(in frame: PoseFrame) -> Double? {
        jointAngle(in: frame, proximal: .leftElbow, joint: .leftShoulder, distal: .leftHip)
    }
    
    /// Right shoulder angle (elbow-shoulder-hip)
    static func rightShoulderAngle(in frame: PoseFrame) -> Double? {
        jointAngle(in: frame, proximal: .rightElbow, joint: .rightShoulder, distal: .rightHip)
    }
    
    /// Left hip angle (shoulder-hip-knee)
    static func leftHipAngle(in frame: PoseFrame) -> Double? {
        jointAngle(in: frame, proximal: .leftShoulder, joint: .leftHip, distal: .leftKnee)
    }
    
    /// Right hip angle (shoulder-hip-knee)
    static func rightHipAngle(in frame: PoseFrame) -> Double? {
        jointAngle(in: frame, proximal: .rightShoulder, joint: .rightHip, distal: .rightKnee)
    }
    
    // MARK: - Shoulder-Hip Alignment
    
    /// Angle of the shoulder line relative to horizontal
    /// 0° = perfectly horizontal, positive = left shoulder higher
    static func shoulderTilt(in frame: PoseFrame) -> Double? {
        guard let ls = frame.position(for: .leftShoulder),
              let rs = frame.position(for: .rightShoulder) else { return nil }
        let dx = rs.x - ls.x
        let dy = rs.y - ls.y
        return atan2(Double(dy), Double(dx)) * 180.0 / Double.pi
    }
    
    /// Angle of the hip line relative to horizontal
    static func hipTilt(in frame: PoseFrame) -> Double? {
        guard let lh = frame.position(for: .leftHip),
              let rh = frame.position(for: .rightHip) else { return nil }
        let dx = rh.x - lh.x
        let dy = rh.y - lh.y
        return atan2(Double(dy), Double(dx)) * 180.0 / Double.pi
    }
    
    /// Hip-shoulder separation angle (important for bowling)
    /// Measures the rotational difference between shoulder line and hip line
    static func hipShoulderSeparation(in frame: PoseFrame) -> Double? {
        guard let shoulderAngle = shoulderTilt(in: frame),
              let hipAngle = hipTilt(in: frame) else { return nil }
        return abs(shoulderAngle - hipAngle)
    }
    
    // MARK: - Body Alignment
    
    /// Vertical alignment of head over base
    /// Returns horizontal deviation as a fraction of shoulder width
    static func headOverBaseDeviation(in frame: PoseFrame) -> Double? {
        guard let nose = frame.position(for: .nose),
              let la = frame.position(for: .leftAnkle),
              let ra = frame.position(for: .rightAnkle),
              let sw = frame.shoulderWidth else { return nil }
        guard sw > 0 else { return nil }
        
        let baseMidX = (la.x + ra.x) / 2
        return Double(abs(nose.x - baseMidX) / sw)
    }
    
    /// Head position relative to front foot
    /// Positive = head ahead of front foot (toward bowler)
    static func headRelativeToFrontFoot(
        in frame: PoseFrame,
        frontFoot: BodyLandmark
    ) -> Double? {
        guard let nose = frame.position(for: .nose),
              let foot = frame.position(for: frontFoot),
              let sw = frame.shoulderWidth else { return nil }
        guard sw > 0 else { return nil }
        
        return Double((nose.x - foot.x) / sw)
    }
    
    // MARK: - Bowling Specific
    
    /// Bowling arm angle relative to vertical at release
    static func bowlingArmAngleFromVertical(
        in frame: PoseFrame,
        bowlingArm: BodyLandmark,  // shoulder
        bowlingElbow: BodyLandmark,
        bowlingWrist: BodyLandmark
    ) -> Double? {
        guard let shoulder = frame.position(for: bowlingArm),
              let wrist = frame.position(for: bowlingWrist) else { return nil }
        
        // Create a vertical reference point directly above the shoulder
        let verticalPoint = CGPoint(x: shoulder.x, y: shoulder.y - 1)
        return angleBetween(a: verticalPoint, b: shoulder, c: wrist)
    }
    
    /// Detect if bowling action is side-on, chest-on, or mixed
    /// Based on shoulder alignment relative to the bowling direction
    static func bowlingActionType(in frame: PoseFrame) -> BowlingActionType {
        guard let shoulderAngle = shoulderTilt(in: frame) else { return .unknown }
        
        let absAngle = abs(shoulderAngle)
        
        // Side-on: shoulders roughly perpendicular to crease (close to 90° or -90°)
        // Chest-on: shoulders roughly parallel to crease (close to 0°)
        if absAngle > 60 {
            return .sideOn
        } else if absAngle < 30 {
            return .chestOn
        } else {
            return .mixed  // This is an injury risk!
        }
    }
    
    // MARK: - Distance Measurements
    
    /// Stride length as a multiple of shoulder width
    static func strideLengthNormalized(in frame: PoseFrame) -> Double? {
        guard let la = frame.position(for: .leftAnkle),
              let ra = frame.position(for: .rightAnkle),
              let sw = frame.shoulderWidth else { return nil }
        guard sw > 0 else { return nil }
        
        let dx = ra.x - la.x
        let dy = ra.y - la.y
        let strideLength = sqrt(dx * dx + dy * dy)
        return Double(strideLength / sw)
    }
    
    /// Feet width as a multiple of shoulder width
    static func feetWidthNormalized(in frame: PoseFrame) -> Double? {
        strideLengthNormalized(in: frame)
    }
    
    /// Wrist height relative to shoulder height (1.0 = at shoulder, >1 = above)
    static func wristHeightRelativeToShoulder(
        in frame: PoseFrame,
        wrist: BodyLandmark,
        shoulder: BodyLandmark
    ) -> Double? {
        guard let w = frame.position(for: wrist),
              let s = frame.position(for: shoulder),
              let hip = frame.position(for: shoulder == .leftShoulder ? .leftHip : .rightHip) else { return nil }
        
        // In Vision coordinates, y increases upward (0 at bottom, 1 at top)
        let torsoHeight = abs(s.y - hip.y)
        guard torsoHeight > 0 else { return nil }
        
        let wristRelative = (w.y - hip.y) / torsoHeight
        let shoulderRelative = (s.y - hip.y) / torsoHeight
        
        guard shoulderRelative > 0 else { return nil }
        return Double(wristRelative / shoulderRelative)
    }
    
    // MARK: - Center of Mass Estimation
    
    /// Rough center of mass estimation (midpoint of hips)
    static func centerOfMass(in frame: PoseFrame) -> CGPoint? {
        frame.midpoint(between: .leftHip, and: .rightHip)
    }
    
    /// Weight distribution: how far the center of mass is from center of stance
    /// Returns -1 to 1: negative = back foot, 0 = centered, positive = front foot
    static func weightDistribution(in frame: PoseFrame) -> Double? {
        guard let com = centerOfMass(in: frame),
              let la = frame.position(for: .leftAnkle),
              let ra = frame.position(for: .rightAnkle) else { return nil }
        
        let stanceMid = CGPoint(x: (la.x + ra.x) / 2, y: (la.y + ra.y) / 2)
        let stanceWidth = abs(ra.x - la.x)
        guard stanceWidth > 0 else { return nil }
        
        return Double((com.x - stanceMid.x) / (stanceWidth / 2))
    }
    
    // MARK: - All Angles for a Frame
    
    /// Calculate all relevant angles for display
    static func allAngles(in frame: PoseFrame) -> [String: Double] {
        var angles: [String: Double] = [:]
        
        if let v = leftElbowAngle(in: frame) { angles["Left Elbow"] = v }
        if let v = rightElbowAngle(in: frame) { angles["Right Elbow"] = v }
        if let v = leftKneeAngle(in: frame) { angles["Left Knee"] = v }
        if let v = rightKneeAngle(in: frame) { angles["Right Knee"] = v }
        if let v = leftShoulderAngle(in: frame) { angles["Left Shoulder"] = v }
        if let v = rightShoulderAngle(in: frame) { angles["Right Shoulder"] = v }
        if let v = leftHipAngle(in: frame) { angles["Left Hip"] = v }
        if let v = rightHipAngle(in: frame) { angles["Right Hip"] = v }
        if let v = shoulderTilt(in: frame) { angles["Shoulder Tilt"] = v }
        if let v = hipTilt(in: frame) { angles["Hip Tilt"] = v }
        if let v = hipShoulderSeparation(in: frame) { angles["Hip-Shoulder Separation"] = v }
        
        return angles
    }
}

// MARK: - Bowling Action Type

enum BowlingActionType: String {
    case sideOn = "Side-On"
    case chestOn = "Chest-On"
    case mixed = "Mixed (Injury Risk!)"
    case unknown = "Unknown"
}

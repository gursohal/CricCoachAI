import Foundation
import CoreGraphics

// MARK: - Landmark Names

/// Standard body landmark identifiers matching Apple Vision's VNHumanBodyPoseObservation
enum BodyLandmark: String, CaseIterable, Codable {
    // Head
    case nose
    case leftEye = "left_eye"
    case rightEye = "right_eye"
    case leftEar = "left_ear"
    case rightEar = "right_ear"
    
    // Torso
    case neck
    case leftShoulder = "left_shoulder"
    case rightShoulder = "right_shoulder"
    case leftHip = "left_hip"
    case rightHip = "right_hip"
    case root  // center of hips
    
    // Arms
    case leftElbow = "left_elbow"
    case rightElbow = "right_elbow"
    case leftWrist = "left_wrist"
    case rightWrist = "right_wrist"
    
    // Legs
    case leftKnee = "left_knee"
    case rightKnee = "right_knee"
    case leftAnkle = "left_ankle"
    case rightAnkle = "right_ankle"
    
    var displayName: String {
        switch self {
        case .nose: return "Nose"
        case .leftEye: return "Left Eye"
        case .rightEye: return "Right Eye"
        case .leftEar: return "Left Ear"
        case .rightEar: return "Right Ear"
        case .neck: return "Neck"
        case .leftShoulder: return "Left Shoulder"
        case .rightShoulder: return "Right Shoulder"
        case .leftHip: return "Left Hip"
        case .rightHip: return "Right Hip"
        case .root: return "Root"
        case .leftElbow: return "Left Elbow"
        case .rightElbow: return "Right Elbow"
        case .leftWrist: return "Left Wrist"
        case .rightWrist: return "Right Wrist"
        case .leftKnee: return "Left Knee"
        case .rightKnee: return "Right Knee"
        case .leftAnkle: return "Left Ankle"
        case .rightAnkle: return "Right Ankle"
        }
    }
    
    /// Body part group for color coding
    var bodyGroup: BodyGroup {
        switch self {
        case .nose, .leftEye, .rightEye, .leftEar, .rightEar:
            return .head
        case .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .root:
            return .torso
        case .leftElbow, .rightElbow, .leftWrist, .rightWrist:
            return .arms
        case .leftKnee, .rightKnee, .leftAnkle, .rightAnkle:
            return .legs
        }
    }
    
    enum BodyGroup: String, CaseIterable {
        case head
        case torso
        case arms
        case legs
    }
}

// MARK: - Skeleton Connections

/// Defines which landmarks connect to form the skeleton
struct SkeletonConnection: Identifiable {
    let id = UUID()
    let from: BodyLandmark
    let to: BodyLandmark
    
    static let allConnections: [SkeletonConnection] = [
        // Head
        SkeletonConnection(from: .nose, to: .neck),
        SkeletonConnection(from: .nose, to: .leftEye),
        SkeletonConnection(from: .nose, to: .rightEye),
        SkeletonConnection(from: .leftEye, to: .leftEar),
        SkeletonConnection(from: .rightEye, to: .rightEar),
        
        // Torso
        SkeletonConnection(from: .neck, to: .leftShoulder),
        SkeletonConnection(from: .neck, to: .rightShoulder),
        SkeletonConnection(from: .leftShoulder, to: .leftHip),
        SkeletonConnection(from: .rightShoulder, to: .rightHip),
        SkeletonConnection(from: .leftHip, to: .rightHip),
        SkeletonConnection(from: .leftShoulder, to: .rightShoulder),
        
        // Left arm
        SkeletonConnection(from: .leftShoulder, to: .leftElbow),
        SkeletonConnection(from: .leftElbow, to: .leftWrist),
        
        // Right arm
        SkeletonConnection(from: .rightShoulder, to: .rightElbow),
        SkeletonConnection(from: .rightElbow, to: .rightWrist),
        
        // Left leg
        SkeletonConnection(from: .leftHip, to: .leftKnee),
        SkeletonConnection(from: .leftKnee, to: .leftAnkle),
        
        // Right leg
        SkeletonConnection(from: .rightHip, to: .rightKnee),
        SkeletonConnection(from: .rightKnee, to: .rightAnkle),
    ]
}

// MARK: - Pose Frame

/// Represents body pose data for a single video frame
struct PoseFrame: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let frameIndex: Int
    let landmarks: [String: NormalizedPoint]
    let confidence: [String: Float]
    
    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        frameIndex: Int,
        landmarks: [String: NormalizedPoint],
        confidence: [String: Float]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.landmarks = landmarks
        self.confidence = confidence
    }
    
    /// Get the position of a specific landmark
    func position(for landmark: BodyLandmark) -> CGPoint? {
        guard let point = landmarks[landmark.rawValue] else { return nil }
        return CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
    }
    
    /// Get the confidence of a specific landmark
    func confidenceFor(_ landmark: BodyLandmark) -> Float {
        confidence[landmark.rawValue] ?? 0.0
    }
    
    /// Check if key landmarks have sufficient confidence
    /// Requires at least 3 of 6 key landmarks with confidence > 0.1
    var hasValidKeyLandmarks: Bool {
        let keyLandmarks: [BodyLandmark] = [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftWrist, .rightWrist
        ]
        let validCount = keyLandmarks.filter { confidenceFor($0) > 0.1 }.count
        return validCount >= 3
    }
    
    /// Midpoint between two landmarks
    func midpoint(between a: BodyLandmark, and b: BodyLandmark) -> CGPoint? {
        guard let pa = position(for: a), let pb = position(for: b) else { return nil }
        return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    }
    
    /// Distance between two landmarks (in normalized coordinates)
    func distance(from a: BodyLandmark, to b: BodyLandmark) -> CGFloat? {
        guard let pa = position(for: a), let pb = position(for: b) else { return nil }
        let dx = pb.x - pa.x
        let dy = pb.y - pa.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Shoulder width (useful for normalizing distances)
    var shoulderWidth: CGFloat? {
        distance(from: .leftShoulder, to: .rightShoulder)
    }
}

// MARK: - Normalized Point

/// A 2D point with coordinates normalized to 0-1 range
struct NormalizedPoint: Codable, Equatable {
    let x: Float
    let y: Float
    
    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
    
    init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
    
    init(cgPoint: CGPoint) {
        self.x = Float(cgPoint.x)
        self.y = Float(cgPoint.y)
    }
}

// MARK: - Pose Sequence

/// A collection of pose frames for an entire video
struct PoseSequence: Codable {
    let frames: [PoseFrame]
    let fps: Double
    let totalDuration: TimeInterval
    let videoWidth: Int
    let videoHeight: Int
    
    var frameCount: Int { frames.count }
    
    /// Get the pose frame at or nearest to a specific timestamp
    func frame(at timestamp: TimeInterval) -> PoseFrame? {
        frames.min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) })
    }
    
    /// Get the pose frame at a specific index
    func frame(atIndex index: Int) -> PoseFrame? {
        guard index >= 0 && index < frames.count else { return nil }
        return frames[index]
    }
    
    /// Get velocity of a landmark between two frames (normalized units per second)
    func landmarkVelocity(_ landmark: BodyLandmark, fromFrame: Int, toFrame: Int) -> CGPoint? {
        guard let f1 = frame(atIndex: fromFrame),
              let f2 = frame(atIndex: toFrame),
              let p1 = f1.position(for: landmark),
              let p2 = f2.position(for: landmark) else { return nil }
        
        let dt = f2.timestamp - f1.timestamp
        guard dt > 0 else { return nil }
        
        return CGPoint(
            x: (p2.x - p1.x) / CGFloat(dt),
            y: (p2.y - p1.y) / CGFloat(dt)
        )
    }
    
    /// Get smoothed position using rolling average
    func smoothedPosition(for landmark: BodyLandmark, at frameIndex: Int, windowSize: Int = 5) -> CGPoint? {
        let halfWindow = windowSize / 2
        let startIdx = max(0, frameIndex - halfWindow)
        let endIdx = min(frames.count - 1, frameIndex + halfWindow)
        
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var count: CGFloat = 0
        
        for i in startIdx...endIdx {
            if let pos = frames[i].position(for: landmark) {
                sumX += pos.x
                sumY += pos.y
                count += 1
            }
        }
        
        guard count > 0 else { return nil }
        return CGPoint(x: sumX / count, y: sumY / count)
    }
}

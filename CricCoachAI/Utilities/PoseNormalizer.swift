import Foundation
import CoreGraphics

/// Normalizes pose data for consistent comparison across different body sizes,
/// camera distances, and video resolutions
struct PoseNormalizer {
    
    // MARK: - Normalization
    
    /// Normalize a pose frame so that measurements are relative to the person's body proportions
    /// Uses shoulder width as the reference unit
    static func normalize(_ frame: PoseFrame) -> PoseFrame {
        guard let shoulderWidth = frame.shoulderWidth, shoulderWidth > 0 else {
            return frame
        }
        
        // Find the center of the body (midpoint of hips)
        guard let hipCenter = frame.midpoint(between: .leftHip, and: .rightHip) else {
            return frame
        }
        
        // Normalize all landmarks relative to hip center, scaled by shoulder width
        var normalizedLandmarks: [String: NormalizedPoint] = [:]
        
        for (key, point) in frame.landmarks {
            let normalizedX = (CGFloat(point.x) - hipCenter.x) / shoulderWidth
            let normalizedY = (CGFloat(point.y) - hipCenter.y) / shoulderWidth
            normalizedLandmarks[key] = NormalizedPoint(x: Float(normalizedX), y: Float(normalizedY))
        }
        
        return PoseFrame(
            id: frame.id,
            timestamp: frame.timestamp,
            frameIndex: frame.frameIndex,
            landmarks: normalizedLandmarks,
            confidence: frame.confidence
        )
    }
    
    /// Normalize an entire sequence of pose frames
    static func normalize(_ sequence: PoseSequence) -> PoseSequence {
        let normalizedFrames = sequence.frames.map { normalize($0) }
        return PoseSequence(
            frames: normalizedFrames,
            fps: sequence.fps,
            totalDuration: sequence.totalDuration,
            videoWidth: sequence.videoWidth,
            videoHeight: sequence.videoHeight
        )
    }
    
    // MARK: - Body Proportions
    
    /// Estimate body height from visible landmarks (in normalized coordinates)
    static func estimatedBodyHeight(in frame: PoseFrame) -> CGFloat? {
        guard let head = frame.position(for: .nose),
              let leftAnkle = frame.position(for: .leftAnkle),
              let rightAnkle = frame.position(for: .rightAnkle) else { return nil }
        
        let ankleY = min(leftAnkle.y, rightAnkle.y)  // lowest point
        return abs(head.y - ankleY)
    }
    
    /// Calculate torso length (neck to hip center)
    static func torsoLength(in frame: PoseFrame) -> CGFloat? {
        guard let neck = frame.position(for: .neck),
              let hipCenter = frame.midpoint(between: .leftHip, and: .rightHip) else { return nil }
        
        let dx = neck.x - hipCenter.x
        let dy = neck.y - hipCenter.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Calculate upper arm length (shoulder to elbow)
    static func upperArmLength(in frame: PoseFrame, side: Side) -> CGFloat? {
        let shoulder: BodyLandmark = side == .left ? .leftShoulder : .rightShoulder
        let elbow: BodyLandmark = side == .left ? .leftElbow : .rightElbow
        return frame.distance(from: shoulder, to: elbow)
    }
    
    /// Calculate lower arm length (elbow to wrist)
    static func lowerArmLength(in frame: PoseFrame, side: Side) -> CGFloat? {
        let elbow: BodyLandmark = side == .left ? .leftElbow : .rightElbow
        let wrist: BodyLandmark = side == .left ? .leftWrist : .rightWrist
        return frame.distance(from: elbow, to: wrist)
    }
    
    /// Calculate upper leg length (hip to knee)
    static func upperLegLength(in frame: PoseFrame, side: Side) -> CGFloat? {
        let hip: BodyLandmark = side == .left ? .leftHip : .rightHip
        let knee: BodyLandmark = side == .left ? .leftKnee : .rightKnee
        return frame.distance(from: hip, to: knee)
    }
    
    /// Calculate lower leg length (knee to ankle)
    static func lowerLegLength(in frame: PoseFrame, side: Side) -> CGFloat? {
        let knee: BodyLandmark = side == .left ? .leftKnee : .rightKnee
        let ankle: BodyLandmark = side == .left ? .leftAnkle : .rightAnkle
        return frame.distance(from: knee, to: ankle)
    }
    
    // MARK: - Movement Tracking
    
    /// Calculate the displacement of a landmark between two frames
    /// Returns displacement as a fraction of body height
    static func landmarkDisplacement(
        _ landmark: BodyLandmark,
        from frame1: PoseFrame,
        to frame2: PoseFrame
    ) -> CGFloat? {
        guard let p1 = frame1.position(for: landmark),
              let p2 = frame2.position(for: landmark),
              let bodyHeight = estimatedBodyHeight(in: frame1),
              bodyHeight > 0 else { return nil }
        
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let displacement = sqrt(dx * dx + dy * dy)
        return displacement / bodyHeight
    }
    
    /// Track head stability between two frames (percentage of body height that head moved)
    static func headStability(from frame1: PoseFrame, to frame2: PoseFrame) -> Double? {
        guard let displacement = landmarkDisplacement(.nose, from: frame1, to: frame2) else { return nil }
        return Double(displacement * 100)  // as percentage
    }
    
    /// Calculate the overall movement of the body between frames
    static func overallMovement(from frame1: PoseFrame, to frame2: PoseFrame) -> CGFloat? {
        let trackingLandmarks: [BodyLandmark] = [
            .nose, .leftShoulder, .rightShoulder,
            .leftHip, .rightHip, .leftAnkle, .rightAnkle
        ]
        
        var totalDisplacement: CGFloat = 0
        var count: CGFloat = 0
        
        for landmark in trackingLandmarks {
            if let d = landmarkDisplacement(landmark, from: frame1, to: frame2) {
                totalDisplacement += d
                count += 1
            }
        }
        
        guard count > 0 else { return nil }
        return totalDisplacement / count
    }
    
    // MARK: - Coordinate Transformation
    
    /// Convert normalized Vision coordinates to screen coordinates for rendering
    static func toScreenCoordinates(
        point: CGPoint,
        viewSize: CGSize,
        videoSize: CGSize
    ) -> CGPoint {
        // Vision framework uses bottom-left origin with y going up
        // UIKit/SwiftUI uses top-left origin with y going down
        let aspectRatio = videoSize.width / videoSize.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        var scale: CGFloat
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        
        if aspectRatio > viewAspectRatio {
            // Video is wider - fit to width, letterbox top/bottom
            scale = viewSize.width / videoSize.width
            offsetY = (viewSize.height - videoSize.height * scale) / 2
        } else {
            // Video is taller - fit to height, pillarbox sides
            scale = viewSize.height / videoSize.height
            offsetX = (viewSize.width - videoSize.width * scale) / 2
        }
        
        let screenX = point.x * videoSize.width * scale + offsetX
        let screenY = (1 - point.y) * videoSize.height * scale + offsetY  // Flip Y
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    /// Convert a full pose frame to screen coordinates
    static func toScreenCoordinates(
        frame: PoseFrame,
        viewSize: CGSize,
        videoSize: CGSize
    ) -> [BodyLandmark: CGPoint] {
        var screenPoints: [BodyLandmark: CGPoint] = [:]
        
        for landmark in BodyLandmark.allCases {
            if let point = frame.position(for: landmark) {
                screenPoints[landmark] = toScreenCoordinates(
                    point: point,
                    viewSize: viewSize,
                    videoSize: videoSize
                )
            }
        }
        
        return screenPoints
    }
    
    enum Side {
        case left, right
    }
}

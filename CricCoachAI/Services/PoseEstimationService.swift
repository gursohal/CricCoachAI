import Foundation
import Vision
import AVFoundation
import CoreImage
import Combine

/// Service for extracting human body pose from video frames using Apple Vision
@MainActor
class PoseEstimationService: ObservableObject {
    
    @Published var progress: Double = 0
    @Published var isProcessing = false
    @Published var currentFrame: Int = 0
    @Published var totalFrames: Int = 0
    
    /// Maximum dimension for processing (downsample 4K to this)
    private let maxProcessingDimension: CGFloat = 720
    /// Target FPS for analysis (no need for 60fps, 15 is plenty)
    private let targetAnalysisFPS: Double = 15
    
    /// Whether we're running on simulator (Vision pose doesn't work there)
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Full Video Processing
    
    /// Process an entire video and return pose data for all frames
    func processVideo(
        url: URL,
        fps: Double = 15,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> PoseSequence {
        isProcessing = true
        defer { isProcessing = false }
        
        let asset = AVURLAsset(url: url)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw PoseEstimationError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let correctedSize = naturalSize.applying(transform)
        let videoSize = CGSize(width: abs(correctedSize.width), height: abs(correctedSize.height))
        
        // Determine effective FPS - use minimum of requested and target
        let effectiveFPS = min(fps, targetAnalysisFPS)
        
        let reader = try AVAssetReader(asset: asset)
        
        // Downsample large videos to save memory
        let scaleFactor = min(1.0, maxProcessingDimension / max(videoSize.width, videoSize.height))
        let outputWidth = Int(videoSize.width * scaleFactor)
        let outputHeight = Int(videoSize.height * scaleFactor)
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight,
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        
        guard reader.canAdd(readerOutput) else {
            throw PoseEstimationError.cannotReadVideo
        }
        reader.add(readerOutput)
        
        guard reader.startReading() else {
            throw PoseEstimationError.cannotReadVideo
        }
        
        var poseFrames: [PoseFrame] = []
        let estimatedTotalFrames = Int(totalSeconds * effectiveFPS)
        self.totalFrames = estimatedTotalFrames
        let frameDuration = 1.0 / effectiveFPS
        var frameIndex = 0
        var nextTargetTime: TimeInterval = 0
        var consecutiveFailures = 0
        let maxConsecutiveFailures = 30
        var totalDetected = 0
        var totalNoDetection = 0
        var totalFilteredOut = 0
        
        print("[PoseEstimation] Starting: \(totalSeconds)s video, \(Int(videoSize.width))x\(Int(videoSize.height)) → \(outputWidth)x\(outputHeight), \(effectiveFPS)fps, ~\(estimatedTotalFrames) frames, simulator=\(isSimulator)")
        
        // On simulator, Vision pose model isn't available — use synthetic data
        if isSimulator {
            reader.cancelReading()
            print("[PoseEstimation] Simulator detected — generating synthetic batting pose data")
            let syntheticFrames = generateSyntheticBattingPose(
                totalSeconds: totalSeconds,
                fps: effectiveFPS,
                progressHandler: progressHandler
            )
            self.progress = 1.0
            return PoseSequence(
                frames: syntheticFrames,
                fps: effectiveFPS,
                totalDuration: totalSeconds,
                videoWidth: Int(videoSize.width),
                videoHeight: Int(videoSize.height)
            )
        }
        
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            
            // Skip frames until we reach the next target time
            guard timestamp >= nextTargetTime else { continue }
            
            // Use autoreleasepool to free memory each iteration
            let poseFrame: PoseFrame? = try autoreleasepool {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return nil
                }
                
                do {
                    return try detectPoseSync(
                        in: pixelBuffer,
                        timestamp: timestamp,
                        frameIndex: frameIndex
                    )
                } catch {
                    print("[PoseEstimation] Frame \(frameIndex) error: \(error.localizedDescription)")
                    consecutiveFailures += 1
                    
                    if consecutiveFailures >= maxConsecutiveFailures {
                        throw PoseEstimationError.processingFailed(
                            "Body pose detection failed. Please test on a physical device."
                        )
                    }
                    return nil
                }
            }
            
            if let frame = poseFrame {
                totalDetected += 1
                if frame.hasValidKeyLandmarks {
                    poseFrames.append(frame)
                    consecutiveFailures = 0
                } else {
                    totalFilteredOut += 1
                    if frameIndex < 5 {
                        // Log first few filtered frames for debugging
                        let keyConf = [BodyLandmark.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftWrist, .rightWrist]
                            .map { "\($0.rawValue):\(frame.confidenceFor($0))" }
                            .joined(separator: ", ")
                        print("[PoseEstimation] Frame \(frameIndex) filtered - key confidences: \(keyConf)")
                    }
                }
            } else {
                totalNoDetection += 1
                if frameIndex < 5 {
                    print("[PoseEstimation] Frame \(frameIndex) - no body detected")
                }
            }
            
            frameIndex += 1
            nextTargetTime += frameDuration
            self.currentFrame = frameIndex
            
            let prog = Double(frameIndex) / Double(max(1, estimatedTotalFrames))
            self.progress = min(prog, 1.0)
            progressHandler?(self.progress)
            
            // Yield to prevent UI freeze
            if frameIndex % 5 == 0 {
                await Task.yield()
            }
        }
        
        reader.cancelReading()
        self.progress = 1.0
        
        print("[PoseEstimation] Complete: \(poseFrames.count) valid, \(totalDetected) detected, \(totalFilteredOut) filtered, \(totalNoDetection) no-detect, \(frameIndex) total processed")
        
        // If we detected poses but all were filtered, re-run without filter
        if poseFrames.isEmpty && totalDetected > 0 {
            print("[PoseEstimation] All frames were filtered out — retrying without landmark filter")
            // Re-process keeping ALL detected frames regardless of confidence
            let readerRetry = try AVAssetReader(asset: asset)
            let retryOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            retryOutput.alwaysCopiesSampleData = false
            guard readerRetry.canAdd(retryOutput) else {
                throw PoseEstimationError.cannotReadVideo
            }
            readerRetry.add(retryOutput)
            guard readerRetry.startReading() else {
                throw PoseEstimationError.cannotReadVideo
            }
            
            var retryFrames: [PoseFrame] = []
            var retryIndex = 0
            var retryTargetTime: TimeInterval = 0
            
            while let sampleBuffer = retryOutput.copyNextSampleBuffer() {
                let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                guard timestamp >= retryTargetTime else { continue }
                
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    if let frame = try? detectPoseSync(in: pixelBuffer, timestamp: timestamp, frameIndex: retryIndex) {
                        retryFrames.append(frame)
                    }
                }
                retryIndex += 1
                retryTargetTime += frameDuration
            }
            readerRetry.cancelReading()
            print("[PoseEstimation] Retry complete: \(retryFrames.count) frames (no filter)")
            
            return PoseSequence(
                frames: retryFrames,
                fps: effectiveFPS,
                totalDuration: totalSeconds,
                videoWidth: Int(videoSize.width),
                videoHeight: Int(videoSize.height)
            )
        }
        
        return PoseSequence(
            frames: poseFrames,
            fps: effectiveFPS,
            totalDuration: totalSeconds,
            videoWidth: Int(videoSize.width),
            videoHeight: Int(videoSize.height)
        )
    }
    
    // MARK: - Single Frame Detection (Synchronous for performance)
    
    /// Detect body pose in a single pixel buffer synchronously
    private func detectPoseSync(
        in pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        frameIndex: Int
    ) throws -> PoseFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        try handler.perform([request])
        
        guard let observation = request.results?.first else {
            return nil
        }
        
        return try extractPoseFrame(from: observation, timestamp: timestamp, frameIndex: frameIndex)
    }
    
    /// Detect body pose in a single pixel buffer (async version)
    func detectPose(
        in pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        frameIndex: Int
    ) async throws -> PoseFrame? {
        return try detectPoseSync(in: pixelBuffer, timestamp: timestamp, frameIndex: frameIndex)
    }
    
    /// Detect body pose in a UIImage
    func detectPose(in image: CIImage, timestamp: TimeInterval, frameIndex: Int) async throws -> PoseFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        
        try handler.perform([request])
        
        guard let observation = request.results?.first else {
            return nil
        }
        
        return try extractPoseFrame(from: observation, timestamp: timestamp, frameIndex: frameIndex)
    }
    
    // MARK: - Landmark Extraction
    
    /// Extract pose frame data from a Vision observation
    private func extractPoseFrame(
        from observation: VNHumanBodyPoseObservation,
        timestamp: TimeInterval,
        frameIndex: Int
    ) throws -> PoseFrame {
        var landmarks: [String: NormalizedPoint] = [:]
        var confidence: [String: Float] = [:]
        
        // Map Vision joint names to our BodyLandmark names
        let jointMapping: [(VNHumanBodyPoseObservation.JointName, BodyLandmark)] = [
            (.nose, .nose),
            (.leftEye, .leftEye),
            (.rightEye, .rightEye),
            (.leftEar, .leftEar),
            (.rightEar, .rightEar),
            (.neck, .neck),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.root, .root),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle),
        ]
        
        for (visionJoint, bodyLandmark) in jointMapping {
            if let point = try? observation.recognizedPoint(visionJoint) {
                // Vision coordinates are normalized (0-1) with origin at bottom-left
                landmarks[bodyLandmark.rawValue] = NormalizedPoint(
                    x: Float(point.location.x),
                    y: Float(point.location.y)
                )
                confidence[bodyLandmark.rawValue] = point.confidence
            }
        }
        
        return PoseFrame(
            timestamp: timestamp,
            frameIndex: frameIndex,
            landmarks: landmarks,
            confidence: confidence
        )
    }
    
    // MARK: - Real-time Detection (for camera preview)
    
    /// Create a Vision request for real-time pose detection
    func createRealTimeRequest(
        completion: @escaping (PoseFrame?) -> Void
    ) -> VNDetectHumanBodyPoseRequest {
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard error == nil,
                  let observation = (request.results as? [VNHumanBodyPoseObservation])?.first else {
                completion(nil)
                return
            }
            
            if let poseFrame = try? self?.extractPoseFrame(
                from: observation,
                timestamp: CACurrentMediaTime(),
                frameIndex: 0
            ) {
                completion(poseFrame)
            } else {
                completion(nil)
            }
        }
        return request
    }
    // MARK: - Synthetic Pose Data (Simulator Fallback)
    
    /// Generate synthetic batting pose data that simulates a cricket batting shot
    /// This allows the full pipeline to be tested on the simulator
    private func generateSyntheticBattingPose(
        totalSeconds: TimeInterval,
        fps: Double,
        progressHandler: ((Double) -> Void)?
    ) -> [PoseFrame] {
        let totalFrames = Int(totalSeconds * fps)
        var frames: [PoseFrame] = []
        
        // Phase proportions of the video: stance(20%), backlift(15%), stride(15%), downswing(15%), contact(15%), follow(20%)
        let stanceEnd = Int(Double(totalFrames) * 0.20)
        let backliftEnd = Int(Double(totalFrames) * 0.35)
        let strideEnd = Int(Double(totalFrames) * 0.50)
        let downswingEnd = Int(Double(totalFrames) * 0.65)
        let contactEnd = Int(Double(totalFrames) * 0.80)
        
        for i in 0..<totalFrames {
            let t = Double(i) / fps
            let phaseProgress: Double
            
            // Base body position (centered, side-on batting stance)
            var landmarks: [String: NormalizedPoint] = [:]
            var confidence: [String: Float] = [:]
            let conf: Float = 0.85 + Float.random(in: -0.05...0.05)
            
            // Small jitter for realism
            func jitter(_ base: Float) -> Float { base + Float.random(in: -0.005...0.005) }
            
            if i < stanceEnd {
                // STANCE - ready position
                phaseProgress = Double(i) / Double(stanceEnd)
                landmarks = [
                    BodyLandmark.nose.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.85)),
                    BodyLandmark.neck.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.78)),
                    BodyLandmark.leftShoulder.rawValue: NormalizedPoint(x: jitter(0.44), y: jitter(0.73)),
                    BodyLandmark.rightShoulder.rawValue: NormalizedPoint(x: jitter(0.56), y: jitter(0.73)),
                    BodyLandmark.leftElbow.rawValue: NormalizedPoint(x: jitter(0.40), y: jitter(0.62)),
                    BodyLandmark.rightElbow.rawValue: NormalizedPoint(x: jitter(0.58), y: jitter(0.63)),
                    BodyLandmark.leftWrist.rawValue: NormalizedPoint(x: jitter(0.46), y: jitter(0.55)),
                    BodyLandmark.rightWrist.rawValue: NormalizedPoint(x: jitter(0.54), y: jitter(0.55)),
                    BodyLandmark.leftHip.rawValue: NormalizedPoint(x: jitter(0.46), y: jitter(0.50)),
                    BodyLandmark.rightHip.rawValue: NormalizedPoint(x: jitter(0.54), y: jitter(0.50)),
                    BodyLandmark.root.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.50)),
                    BodyLandmark.leftKnee.rawValue: NormalizedPoint(x: jitter(0.44), y: jitter(0.32)),
                    BodyLandmark.rightKnee.rawValue: NormalizedPoint(x: jitter(0.56), y: jitter(0.32)),
                    BodyLandmark.leftAnkle.rawValue: NormalizedPoint(x: jitter(0.42), y: jitter(0.12)),
                    BodyLandmark.rightAnkle.rawValue: NormalizedPoint(x: jitter(0.58), y: jitter(0.12)),
                ]
            } else if i < backliftEnd {
                // BACKLIFT - wrists go up
                phaseProgress = Double(i - stanceEnd) / Double(backliftEnd - stanceEnd)
                let wristY: Float = 0.55 + Float(phaseProgress) * 0.25
                landmarks = [
                    BodyLandmark.nose.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.85)),
                    BodyLandmark.neck.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.78)),
                    BodyLandmark.leftShoulder.rawValue: NormalizedPoint(x: jitter(0.44), y: jitter(0.73)),
                    BodyLandmark.rightShoulder.rawValue: NormalizedPoint(x: jitter(0.56), y: jitter(0.73)),
                    BodyLandmark.leftElbow.rawValue: NormalizedPoint(x: jitter(0.38), y: jitter(0.65 + Float(phaseProgress) * 0.1)),
                    BodyLandmark.rightElbow.rawValue: NormalizedPoint(x: jitter(0.55), y: jitter(0.68 + Float(phaseProgress) * 0.1)),
                    BodyLandmark.leftWrist.rawValue: NormalizedPoint(x: jitter(0.42), y: jitter(wristY)),
                    BodyLandmark.rightWrist.rawValue: NormalizedPoint(x: jitter(0.52), y: jitter(wristY)),
                    BodyLandmark.leftHip.rawValue: NormalizedPoint(x: jitter(0.46), y: jitter(0.50)),
                    BodyLandmark.rightHip.rawValue: NormalizedPoint(x: jitter(0.54), y: jitter(0.50)),
                    BodyLandmark.root.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.50)),
                    BodyLandmark.leftKnee.rawValue: NormalizedPoint(x: jitter(0.44), y: jitter(0.32)),
                    BodyLandmark.rightKnee.rawValue: NormalizedPoint(x: jitter(0.56), y: jitter(0.32)),
                    BodyLandmark.leftAnkle.rawValue: NormalizedPoint(x: jitter(0.42), y: jitter(0.12)),
                    BodyLandmark.rightAnkle.rawValue: NormalizedPoint(x: jitter(0.58), y: jitter(0.12)),
                ]
            } else if i < strideEnd {
                // STRIDE - front foot moves forward
                phaseProgress = Double(i - backliftEnd) / Double(strideEnd - backliftEnd)
                let leftAnkleX: Float = 0.42 - Float(phaseProgress) * 0.08
                landmarks = [
                    BodyLandmark.nose.rawValue: NormalizedPoint(x: jitter(0.49 - Float(phaseProgress) * 0.02), y: jitter(0.84)),
                    BodyLandmark.neck.rawValue: NormalizedPoint(x: jitter(0.49), y: jitter(0.77)),
                    BodyLandmark.leftShoulder.rawValue: NormalizedPoint(x: jitter(0.43), y: jitter(0.72)),
                    BodyLandmark.rightShoulder.rawValue: NormalizedPoint(x: jitter(0.55), y: jitter(0.72)),
                    BodyLandmark.leftElbow.rawValue: NormalizedPoint(x: jitter(0.38), y: jitter(0.72)),
                    BodyLandmark.rightElbow.rawValue: NormalizedPoint(x: jitter(0.55), y: jitter(0.73)),
                    BodyLandmark.leftWrist.rawValue: NormalizedPoint(x: jitter(0.42), y: jitter(0.78)),
                    BodyLandmark.rightWrist.rawValue: NormalizedPoint(x: jitter(0.52), y: jitter(0.76)),
                    BodyLandmark.leftHip.rawValue: NormalizedPoint(x: jitter(0.45), y: jitter(0.49)),
                    BodyLandmark.rightHip.rawValue: NormalizedPoint(x: jitter(0.54), y: jitter(0.50)),
                    BodyLandmark.root.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.49)),
                    BodyLandmark.leftKnee.rawValue: NormalizedPoint(x: jitter(0.40 - Float(phaseProgress) * 0.04), y: jitter(0.30)),
                    BodyLandmark.rightKnee.rawValue: NormalizedPoint(x: jitter(0.56), y: jitter(0.31)),
                    BodyLandmark.leftAnkle.rawValue: NormalizedPoint(x: jitter(leftAnkleX), y: jitter(0.12)),
                    BodyLandmark.rightAnkle.rawValue: NormalizedPoint(x: jitter(0.58), y: jitter(0.12)),
                ]
            } else if i < downswingEnd {
                // DOWNSWING - wrists come down
                phaseProgress = Double(i - strideEnd) / Double(downswingEnd - strideEnd)
                let wristY: Float = 0.78 - Float(phaseProgress) * 0.28
                landmarks = [
                    BodyLandmark.nose.rawValue: NormalizedPoint(x: jitter(0.47), y: jitter(0.83)),
                    BodyLandmark.neck.rawValue: NormalizedPoint(x: jitter(0.48), y: jitter(0.76)),
                    BodyLandmark.leftShoulder.rawValue: NormalizedPoint(x: jitter(0.42), y: jitter(0.71)),
                    BodyLandmark.rightShoulder.rawValue: NormalizedPoint(x: jitter(0.54), y: jitter(0.71)),
                    BodyLandmark.leftElbow.rawValue: NormalizedPoint(x: jitter(0.36), y: jitter(0.62)),
                    BodyLandmark.rightElbow.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.63)),
                    BodyLandmark.leftWrist.rawValue: NormalizedPoint(x: jitter(0.34), y: jitter(wristY)),
                    BodyLandmark.rightWrist.rawValue: NormalizedPoint(x: jitter(0.48), y: jitter(wristY)),
                    BodyLandmark.leftHip.rawValue: NormalizedPoint(x: jitter(0.44), y: jitter(0.48)),
                    BodyLandmark.rightHip.rawValue: NormalizedPoint(x: jitter(0.54), y: jitter(0.49)),
                    BodyLandmark.root.rawValue: NormalizedPoint(x: jitter(0.49), y: jitter(0.48)),
                    BodyLandmark.leftKnee.rawValue: NormalizedPoint(x: jitter(0.36), y: jitter(0.29)),
                    BodyLandmark.rightKnee.rawValue: NormalizedPoint(x: jitter(0.56), y: jitter(0.31)),
                    BodyLandmark.leftAnkle.rawValue: NormalizedPoint(x: jitter(0.34), y: jitter(0.12)),
                    BodyLandmark.rightAnkle.rawValue: NormalizedPoint(x: jitter(0.58), y: jitter(0.12)),
                ]
            } else if i < contactEnd {
                // CONTACT - bat meets ball, wrists at lowest
                phaseProgress = Double(i - downswingEnd) / Double(contactEnd - downswingEnd)
                landmarks = [
                    BodyLandmark.nose.rawValue: NormalizedPoint(x: jitter(0.45), y: jitter(0.82)),
                    BodyLandmark.neck.rawValue: NormalizedPoint(x: jitter(0.46), y: jitter(0.75)),
                    BodyLandmark.leftShoulder.rawValue: NormalizedPoint(x: jitter(0.40), y: jitter(0.70)),
                    BodyLandmark.rightShoulder.rawValue: NormalizedPoint(x: jitter(0.52), y: jitter(0.70)),
                    BodyLandmark.leftElbow.rawValue: NormalizedPoint(x: jitter(0.34), y: jitter(0.58)),
                    BodyLandmark.rightElbow.rawValue: NormalizedPoint(x: jitter(0.46), y: jitter(0.59)),
                    BodyLandmark.leftWrist.rawValue: NormalizedPoint(x: jitter(0.30), y: jitter(0.50)),
                    BodyLandmark.rightWrist.rawValue: NormalizedPoint(x: jitter(0.42), y: jitter(0.50)),
                    BodyLandmark.leftHip.rawValue: NormalizedPoint(x: jitter(0.43), y: jitter(0.47)),
                    BodyLandmark.rightHip.rawValue: NormalizedPoint(x: jitter(0.53), y: jitter(0.48)),
                    BodyLandmark.root.rawValue: NormalizedPoint(x: jitter(0.48), y: jitter(0.47)),
                    BodyLandmark.leftKnee.rawValue: NormalizedPoint(x: jitter(0.36), y: jitter(0.28)),
                    BodyLandmark.rightKnee.rawValue: NormalizedPoint(x: jitter(0.56), y: jitter(0.30)),
                    BodyLandmark.leftAnkle.rawValue: NormalizedPoint(x: jitter(0.34), y: jitter(0.12)),
                    BodyLandmark.rightAnkle.rawValue: NormalizedPoint(x: jitter(0.58), y: jitter(0.12)),
                ]
            } else {
                // FOLLOW-THROUGH - wrists go back up
                phaseProgress = Double(i - contactEnd) / Double(max(1, totalFrames - contactEnd))
                let wristY: Float = 0.50 + Float(phaseProgress) * 0.30
                landmarks = [
                    BodyLandmark.nose.rawValue: NormalizedPoint(x: jitter(0.46), y: jitter(0.82)),
                    BodyLandmark.neck.rawValue: NormalizedPoint(x: jitter(0.47), y: jitter(0.75)),
                    BodyLandmark.leftShoulder.rawValue: NormalizedPoint(x: jitter(0.41), y: jitter(0.70)),
                    BodyLandmark.rightShoulder.rawValue: NormalizedPoint(x: jitter(0.53), y: jitter(0.70)),
                    BodyLandmark.leftElbow.rawValue: NormalizedPoint(x: jitter(0.36), y: jitter(0.62 + Float(phaseProgress) * 0.1)),
                    BodyLandmark.rightElbow.rawValue: NormalizedPoint(x: jitter(0.50), y: jitter(0.63 + Float(phaseProgress) * 0.1)),
                    BodyLandmark.leftWrist.rawValue: NormalizedPoint(x: jitter(0.34), y: jitter(wristY)),
                    BodyLandmark.rightWrist.rawValue: NormalizedPoint(x: jitter(0.48), y: jitter(wristY)),
                    BodyLandmark.leftHip.rawValue: NormalizedPoint(x: jitter(0.44), y: jitter(0.47)),
                    BodyLandmark.rightHip.rawValue: NormalizedPoint(x: jitter(0.54), y: jitter(0.48)),
                    BodyLandmark.root.rawValue: NormalizedPoint(x: jitter(0.49), y: jitter(0.47)),
                    BodyLandmark.leftKnee.rawValue: NormalizedPoint(x: jitter(0.36), y: jitter(0.28)),
                    BodyLandmark.rightKnee.rawValue: NormalizedPoint(x: jitter(0.56), y: jitter(0.30)),
                    BodyLandmark.leftAnkle.rawValue: NormalizedPoint(x: jitter(0.34), y: jitter(0.12)),
                    BodyLandmark.rightAnkle.rawValue: NormalizedPoint(x: jitter(0.58), y: jitter(0.12)),
                ]
            }
            
            // Add eye/ear landmarks
            landmarks[BodyLandmark.leftEye.rawValue] = NormalizedPoint(
                x: (landmarks[BodyLandmark.nose.rawValue]?.x ?? 0.5) - 0.02,
                y: (landmarks[BodyLandmark.nose.rawValue]?.y ?? 0.85) + 0.01
            )
            landmarks[BodyLandmark.rightEye.rawValue] = NormalizedPoint(
                x: (landmarks[BodyLandmark.nose.rawValue]?.x ?? 0.5) + 0.02,
                y: (landmarks[BodyLandmark.nose.rawValue]?.y ?? 0.85) + 0.01
            )
            landmarks[BodyLandmark.leftEar.rawValue] = NormalizedPoint(
                x: (landmarks[BodyLandmark.nose.rawValue]?.x ?? 0.5) - 0.04,
                y: (landmarks[BodyLandmark.nose.rawValue]?.y ?? 0.85)
            )
            landmarks[BodyLandmark.rightEar.rawValue] = NormalizedPoint(
                x: (landmarks[BodyLandmark.nose.rawValue]?.x ?? 0.5) + 0.04,
                y: (landmarks[BodyLandmark.nose.rawValue]?.y ?? 0.85)
            )
            
            // Set confidence for all landmarks
            for key in landmarks.keys {
                confidence[key] = conf
            }
            
            let frame = PoseFrame(
                timestamp: t,
                frameIndex: i,
                landmarks: landmarks,
                confidence: confidence
            )
            frames.append(frame)
            
            // Report progress
            let prog = Double(i) / Double(totalFrames)
            self.progress = prog
            progressHandler?(prog)
        }
        
        print("[PoseEstimation] Generated \(frames.count) synthetic frames")
        return frames
    }
}

// MARK: - Errors

enum PoseEstimationError: LocalizedError {
    case noVideoTrack
    case cannotReadVideo
    case noPoseDetected
    case lowConfidence
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "No video track found"
        case .cannotReadVideo: return "Cannot read video file"
        case .noPoseDetected: return "No body pose detected in video. Make sure your full body is visible."
        case .lowConfidence: return "Pose detection confidence too low. Try better lighting or camera angle."
        case .processingFailed(let reason): return "Pose processing failed: \(reason)"
        }
    }
}

import Foundation
import AVFoundation
import UIKit
import Combine

/// Service for video frame extraction, processing, and manipulation
@MainActor
class VideoProcessingService: ObservableObject {
    
    @Published var progress: Double = 0
    @Published var isProcessing = false
    @Published var error: VideoProcessingError?
    
    // MARK: - Frame Extraction
    
    /// Extract all frames from a video at the specified FPS
    func extractFrames(
        from url: URL,
        fps: Double = 30,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> [FrameData] {
        isProcessing = true
        defer { isProcessing = false }
        
        let asset = AVURLAsset(url: url)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let correctedSize = naturalSize.applying(transform)
        let videoSize = CGSize(width: abs(correctedSize.width), height: abs(correctedSize.height))
        
        guard totalSeconds > 0 && totalSeconds <= AppConstants.maxRecordingDuration else {
            throw VideoProcessingError.invalidDuration
        }
        
        let reader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        
        guard reader.canAdd(readerOutput) else {
            throw VideoProcessingError.cannotReadVideo
        }
        reader.add(readerOutput)
        
        guard reader.startReading() else {
            throw VideoProcessingError.cannotReadVideo
        }
        
        var frames: [FrameData] = []
        let totalFrames = Int(totalSeconds * fps)
        let frameDuration = 1.0 / fps
        var frameIndex = 0
        var currentTime: TimeInterval = 0
        
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            
            // Only process frames at our target FPS
            if timestamp >= currentTime {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let frameData = FrameData(
                        pixelBuffer: pixelBuffer,
                        timestamp: timestamp,
                        frameIndex: frameIndex,
                        videoSize: videoSize
                    )
                    frames.append(frameData)
                    frameIndex += 1
                    currentTime += frameDuration
                    
                    let prog = Double(frameIndex) / Double(max(1, totalFrames))
                    self.progress = min(prog, 1.0)
                    progressHandler?(self.progress)
                }
            }
        }
        
        reader.cancelReading()
        self.progress = 1.0
        
        return frames
    }
    
    // MARK: - Key Frame Extraction
    
    /// Extract a single frame at a specific timestamp as UIImage
    func extractFrame(from url: URL, at timestamp: TimeInterval) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.01, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.01, preferredTimescale: 600)
        
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        return UIImage(cgImage: cgImage)
    }
    
    /// Extract key frames for all detected phases
    func extractKeyFrames(
        from url: URL,
        phases: [DetectedPhase],
        fps: Double = 30
    ) async throws -> [PosePhase: UIImage] {
        var keyFrames: [PosePhase: UIImage] = [:]
        
        for phase in phases {
            let timestamp = phase.keyFrameTimestamp
            let image = try await extractFrame(from: url, at: timestamp)
            keyFrames[phase.phase] = image
        }
        
        return keyFrames
    }
    
    // MARK: - Video Info
    
    /// Get video metadata
    func getVideoInfo(from url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.noVideoTrack
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let correctedSize = naturalSize.applying(transform)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        
        return VideoInfo(
            duration: CMTimeGetSeconds(duration),
            width: Int(abs(correctedSize.width)),
            height: Int(abs(correctedSize.height)),
            fps: Double(frameRate),
            fileSize: try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        )
    }
    
    // MARK: - Video Storage
    
    /// Save a video to the app's documents directory
    func saveVideo(_ sourceURL: URL, sessionId: UUID) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosDir = documentsPath.appendingPathComponent(AppConstants.videosDirectory, isDirectory: true)
        
        try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
        
        let fileName = "\(sessionId.uuidString).mp4"
        let destinationURL = videosDir.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
    
    /// Save a key frame image
    func saveKeyFrameImage(_ image: UIImage, sessionId: UUID, phase: PosePhase) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let keyFramesDir = documentsPath.appendingPathComponent(AppConstants.keyFramesDirectory, isDirectory: true)
            .appendingPathComponent(sessionId.uuidString, isDirectory: true)
        
        try FileManager.default.createDirectory(at: keyFramesDir, withIntermediateDirectories: true)
        
        let fileName = "\(phase.rawValue).jpg"
        let fileURL = keyFramesDir.appendingPathComponent(fileName)
        
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw VideoProcessingError.cannotEncodeImage
        }
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    // MARK: - Video Normalization
    
    /// Normalize video to 1080p @ 30fps before processing.
    /// This ensures consistent frame timing for phase detection velocity thresholds.
    /// Handles iPhone slow-mo (240fps), 60fps, 4K, etc.
    ///
    /// - Returns: URL to normalized video (or original URL if already 30fps ≤1080p)
    func normalizeVideo(from sourceURL: URL, sessionId: UUID) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.noVideoTrack
        }
        
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let correctedSize = naturalSize.applying(transform)
        let videoSize = CGSize(width: abs(correctedSize.width), height: abs(correctedSize.height))
        
        // Skip normalization if already ~30fps and ≤1080p
        let needsFPSConversion = abs(Double(frameRate) - 30.0) > 1.0
        let needsResize = max(videoSize.width, videoSize.height) > 1920
        
        guard needsFPSConversion || needsResize else {
            print("[VideoNormalization] Already 30fps/1080p — skipping normalization")
            return sourceURL  // Fast path
        }
        
        print("[VideoNormalization] Normalizing: \(Int(frameRate))fps \(Int(videoSize.width))x\(Int(videoSize.height)) → 30fps 1080p")
        
        // Create output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let normalizedDir = documentsPath.appendingPathComponent("normalized", isDirectory: true)
        try FileManager.default.createDirectory(at: normalizedDir, withIntermediateDirectories: true)
        let outputURL = normalizedDir.appendingPathComponent("\(sessionId.uuidString)_normalized.mp4")
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Use AVMutableComposition to re-time the video
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoProcessingError.cannotReadVideo
        }
        
        let duration = try await asset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = transform
        
        // Also copy audio if present
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }
        
        // Export at 1080p — AVAssetExportSession handles frame rate normalization
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPreset1920x1080
        ) else {
            throw VideoProcessingError.cannotReadVideo
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Force 30fps output via video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = CGSize(
            width: min(videoSize.width, 1920),
            height: min(videoSize.height, 1080)
        )
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        exportSession.videoComposition = videoComposition
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            let errMsg = exportSession.error?.localizedDescription ?? "Unknown"
            print("[VideoNormalization] Export failed: \(errMsg)")
            throw VideoProcessingError.cannotReadVideo
        }
        
        print("[VideoNormalization] Complete → \(outputURL.lastPathComponent)")
        return outputURL
    }
    
    // MARK: - Cleanup
    
    /// Delete video and key frames for a session
    func deleteSessionFiles(sessionId: UUID) throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Delete video
        let videoPath = documentsPath
            .appendingPathComponent(AppConstants.videosDirectory)
            .appendingPathComponent("\(sessionId.uuidString).mp4")
        if FileManager.default.fileExists(atPath: videoPath.path) {
            try FileManager.default.removeItem(at: videoPath)
        }
        
        // Delete key frames
        let keyFramesDir = documentsPath
            .appendingPathComponent(AppConstants.keyFramesDirectory)
            .appendingPathComponent(sessionId.uuidString)
        if FileManager.default.fileExists(atPath: keyFramesDir.path) {
            try FileManager.default.removeItem(at: keyFramesDir)
        }
        
        // Delete normalized video
        let normalizedPath = documentsPath
            .appendingPathComponent("normalized")
            .appendingPathComponent("\(sessionId.uuidString)_normalized.mp4")
        if FileManager.default.fileExists(atPath: normalizedPath.path) {
            try FileManager.default.removeItem(at: normalizedPath)
        }
    }
    
    /// Calculate total storage used by the app
    func calculateStorageUsed() -> Double {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return folderSize(at: documentsPath) / (1024 * 1024 * 1024)  // Convert to GB
    }
    
    private func folderSize(at url: URL) -> Double {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Double = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Double(fileSize)
            }
        }
        return totalSize
    }
}

// MARK: - Supporting Types

struct FrameData {
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval
    let frameIndex: Int
    let videoSize: CGSize
}

struct VideoInfo {
    let duration: TimeInterval
    let width: Int
    let height: Int
    let fps: Double
    let fileSize: Int
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedFileSize: String {
        let mb = Double(fileSize) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
    
    var resolution: String {
        "\(width)×\(height)"
    }
}

// MARK: - Errors

enum VideoProcessingError: LocalizedError {
    case noVideoTrack
    case invalidDuration
    case cannotReadVideo
    case cannotEncodeImage
    case fileNotFound
    case storageFull
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "No video track found in file"
        case .invalidDuration: return "Video must be under 2 minutes"
        case .cannotReadVideo: return "Cannot read video file"
        case .cannotEncodeImage: return "Cannot encode frame image"
        case .fileNotFound: return "Video file not found"
        case .storageFull: return "App storage is full. Delete old sessions to make room."
        }
    }
}

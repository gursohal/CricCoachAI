import SwiftUI
import AVKit

struct SkeletonOverlayView: View {
    let videoURL: URL
    let poseSequence: PoseSequence
    let detectedPhases: [DetectedPhase]
    var onPhaseSelected: ((PosePhase) -> Void)?
    
    @State private var player: AVPlayer?
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var isPlaying = false
    @State private var playbackRate: Float = 1.0
    @State private var currentPoseFrame: PoseFrame?
    @State private var showAngles = true
    @State private var videoSize: CGSize = CGSize(width: 1920, height: 1080)
    
    private let playbackRates: [Float] = [0.25, 0.5, 1.0]
    private let timer = Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player
                if let player = player {
                    VideoPlayer(player: player)
                        .disabled(true)  // Disable default controls
                        .overlay(
                            // Skeleton overlay
                            Canvas { context, size in
                                drawSkeleton(context: context, size: size)
                            }
                            .allowsHitTesting(false)
                        )
                }
                
                // Controls overlay
                VStack {
                    // Top - angle badges
                    if showAngles, let frame = currentPoseFrame {
                        angleBadges(frame: frame, viewSize: geometry.size)
                    }
                    
                    Spacer()
                    
                    // Bottom controls
                    VStack(spacing: 8) {
                        // Phase timeline
                        PhaseTimelineView(
                            phases: detectedPhases,
                            currentTime: currentTime,
                            duration: duration,
                            onSeek: { time in seekTo(time) },
                            onPhaseSelected: onPhaseSelected
                        )
                        
                        // Scrubber
                        Slider(value: $currentTime, in: 0...max(duration, 0.1)) { editing in
                            if !editing { seekTo(currentTime) }
                        }
                        .tint(DesignSystem.Colors.cricketGreenLight)
                        
                        // Playback controls
                        HStack(spacing: 20) {
                            // Frame back
                            Button(action: frameBack) {
                                Image(systemName: "backward.frame.fill")
                                    .font(.title3)
                            }
                            
                            // Play/Pause
                            Button(action: togglePlayback) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2)
                            }
                            
                            // Frame forward
                            Button(action: frameForward) {
                                Image(systemName: "forward.frame.fill")
                                    .font(.title3)
                            }
                            
                            Spacer()
                            
                            // Speed toggle
                            Button(action: cycleSpeed) {
                                Text("\(playbackRate == 1.0 ? "1" : String(format: "%.2g", playbackRate))×")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.white.opacity(0.2)))
                            }
                            
                            // Angles toggle
                            Button(action: { showAngles.toggle() }) {
                                Image(systemName: showAngles ? "angle" : "angle")
                                    .font(.caption)
                                    .padding(6)
                                    .background(Circle().fill(showAngles ? DesignSystem.Colors.cricketGreenLight.opacity(0.5) : .white.opacity(0.2)))
                            }
                            
                            // Time
                            Text(formatTime(currentTime))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.white)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { player?.pause() }
        .onReceive(timer) { _ in updateCurrentTime() }
    }
    
    // MARK: - Skeleton Drawing
    
    private func drawSkeleton(context: GraphicsContext, size: CGSize) {
        guard let frame = currentPoseFrame else { return }
        
        let screenPoints = PoseNormalizer.toScreenCoordinates(
            frame: frame,
            viewSize: size,
            videoSize: videoSize
        )
        
        // Draw connections (lines)
        for connection in SkeletonConnection.allConnections {
            guard let from = screenPoints[connection.from],
                  let to = screenPoints[connection.to] else { continue }
            
            let color = DesignSystem.Colors.skeletonColor(for: connection.from.bodyGroup)
            
            // Glow effect
            var glowPath = Path()
            glowPath.move(to: from)
            glowPath.addLine(to: to)
            context.stroke(
                glowPath,
                with: .color(color.opacity(0.4)),
                lineWidth: DesignSystem.Layout.skeletonLineWidth + DesignSystem.Layout.skeletonGlowRadius
            )
            
            // Main line
            var linePath = Path()
            linePath.move(to: from)
            linePath.addLine(to: to)
            context.stroke(
                linePath,
                with: .color(color),
                lineWidth: DesignSystem.Layout.skeletonLineWidth
            )
        }
        
        // Draw landmark points
        for (landmark, point) in screenPoints {
            let color = DesignSystem.Colors.skeletonColor(for: landmark.bodyGroup)
            let radius = DesignSystem.Layout.skeletonPointRadius
            
            // Glow
            let glowRect = CGRect(
                x: point.x - radius - 2,
                y: point.y - radius - 2,
                width: (radius + 2) * 2,
                height: (radius + 2) * 2
            )
            context.fill(
                Path(ellipseIn: glowRect),
                with: .color(color.opacity(0.3))
            )
            
            // Point
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1)
        }
    }
    
    // MARK: - Angle Badges
    
    @ViewBuilder
    private func angleBadges(frame: PoseFrame, viewSize: CGSize) -> some View {
        let screenPoints = PoseNormalizer.toScreenCoordinates(
            frame: frame, viewSize: viewSize, videoSize: videoSize
        )
        
        ZStack {
            // Left elbow
            if let angle = AngleCalculator.leftElbowAngle(in: frame),
               let point = screenPoints[.leftElbow] {
                AngleBadgeView(angle: angle, label: "L Elbow")
                    .position(x: point.x - 40, y: point.y - 20)
            }
            
            // Right elbow
            if let angle = AngleCalculator.rightElbowAngle(in: frame),
               let point = screenPoints[.rightElbow] {
                AngleBadgeView(angle: angle, label: "R Elbow")
                    .position(x: point.x + 40, y: point.y - 20)
            }
            
            // Front knee
            if let angle = AngleCalculator.leftKneeAngle(in: frame),
               let point = screenPoints[.leftKnee] {
                AngleBadgeView(angle: angle, label: "L Knee")
                    .position(x: point.x - 40, y: point.y)
            }
        }
    }
    
    // MARK: - Player Controls
    
    private func setupPlayer() {
        let p = AVPlayer(url: videoURL)
        player = p
        
        Task {
            if let d = try? await AVURLAsset(url: videoURL).load(.duration) {
                duration = CMTimeGetSeconds(d)
            }
            if let track = try? await AVURLAsset(url: videoURL).loadTracks(withMediaType: .video).first {
                let size = try? await track.load(.naturalSize)
                let transform = try? await track.load(.preferredTransform)
                if let s = size, let t = transform {
                    let cs = s.applying(t)
                    videoSize = CGSize(width: abs(cs.width), height: abs(cs.height))
                }
            }
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.rate = playbackRate
        }
        isPlaying.toggle()
    }
    
    private func seekTo(_ time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        updatePoseFrame(at: time)
    }
    
    private func frameForward() {
        let frameTime = 1.0 / poseSequence.fps
        let newTime = min(currentTime + frameTime, duration)
        seekTo(newTime)
        currentTime = newTime
    }
    
    private func frameBack() {
        let frameTime = 1.0 / poseSequence.fps
        let newTime = max(currentTime - frameTime, 0)
        seekTo(newTime)
        currentTime = newTime
    }
    
    private func cycleSpeed() {
        guard let currentIndex = playbackRates.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            return
        }
        let nextIndex = (currentIndex + 1) % playbackRates.count
        playbackRate = playbackRates[nextIndex]
        if isPlaying { player?.rate = playbackRate }
    }
    
    private func updateCurrentTime() {
        guard let player = player else { return }
        let time = CMTimeGetSeconds(player.currentTime())
        if time.isFinite && time >= 0 {
            currentTime = time
            updatePoseFrame(at: time)
        }
    }
    
    private func updatePoseFrame(at time: TimeInterval) {
        currentPoseFrame = poseSequence.frame(at: time)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}

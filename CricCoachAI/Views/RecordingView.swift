import SwiftUI
import AVFoundation

struct RecordingView: View {
    let analysisType: AnalysisType
    let onVideoRecorded: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager()
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
            // Overlay
            VStack {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    
                    Spacer()
                    
                    // Timer
                    if isRecording {
                        Text(formatTime(recordingTime))
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(.red.opacity(0.8))
                            )
                    }
                    
                    Spacer()
                    
                    // Analysis type badge
                    Text(analysisType.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.5)))
                }
                .padding()
                
                Spacer()
                
                // Max duration warning
                if recordingTime > AppConstants.maxRecordingDuration - 10 && isRecording {
                    Text("Recording will stop in \(Int(AppConstants.maxRecordingDuration - recordingTime))s")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Capsule().fill(.red.opacity(0.7)))
                }
                
                // Record button
                HStack {
                    Spacer()
                    
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            
                            if isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.red)
                                    .frame(width: 28, height: 28)
                            } else {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 60, height: 60)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            cameraManager.configure()
        }
        .onDisappear {
            timer?.invalidate()
            cameraManager.stop()
        }
        .onChange(of: cameraManager.recordedVideoURL) { _, url in
            if let url = url {
                onVideoRecorded(url)
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        cameraManager.startRecording()
        isRecording = true
        recordingTime = 0
        
        AnalyticsService.track(.recordingStarted, properties: [
            "analysis_type": analysisType.rawValue
        ])
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
            if recordingTime >= AppConstants.maxRecordingDuration {
                stopRecording()
            }
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        cameraManager.stopRecording()
        
        AnalyticsService.track(.recordingCompleted, properties: [
            "duration_seconds": recordingTime,
            "analysis_type": analysisType.rawValue
        ])
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    
    @Published var recordedVideoURL: URL?
    @Published var isConfigured = false
    @Published var error: String?
    
    func configure() {
        guard !isConfigured else { return }
        
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        
        // Camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            error = "Cannot access camera"
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Audio input
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        
        // Movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            movieOutput.maxRecordedDuration = CMTime(seconds: AppConstants.maxRecordingDuration, preferredTimescale: 600)
        }
        
        session.commitConfiguration()
        isConfigured = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    func startRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }
    
    func stopRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if error == nil {
                self?.recordedVideoURL = outputFileURL
            } else {
                self?.error = error?.localizedDescription
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

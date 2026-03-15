import SwiftUI
import PhotosUI
import AVFoundation

struct VideoImportView: View {
    let onVideoSelected: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isProcessing {
                    ProgressView("Processing video...")
                        .padding()
                } else if let error = error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { self.error = nil }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 16) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 56))
                                .foregroundColor(DesignSystem.Colors.cricketGreenLight)
                            Text("Select a Video")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Choose a video under 2 minutes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Import Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedItem) { _, newValue in
                guard let item = newValue else { return }
                processSelectedItem(item)
            }
        }
    }
    
    private func processSelectedItem(_ item: PhotosPickerItem) {
        isProcessing = true
        
        Task {
            do {
                guard let videoData = try await item.loadTransferable(type: VideoTransferable.self) else {
                    error = "Could not load video"
                    isProcessing = false
                    return
                }
                
                // Check duration
                let asset = AVURLAsset(url: videoData.url)
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                
                guard seconds <= AppConstants.maxImportDuration else {
                    error = "Video must be under 2 minutes (yours is \(Int(seconds))s)"
                    isProcessing = false
                    return
                }
                
                // Track import analytics
                let importAsset = AVURLAsset(url: videoData.url)
                var importFPS: Double = 30
                var importResolution = "unknown"
                if let track = try? await importAsset.loadTracks(withMediaType: .video).first {
                    importFPS = Double(try await track.load(.nominalFrameRate))
                    let size = try await track.load(.naturalSize)
                    importResolution = "\(Int(size.width))x\(Int(size.height))"
                }
                
                AnalyticsService.track(.videoImported, properties: [
                    "duration_seconds": seconds,
                    "source_fps": importFPS,
                    "resolution": importResolution
                ])
                
                await MainActor.run {
                    isProcessing = false
                    onVideoSelected(videoData.url)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "\(UUID().uuidString).mp4"
            let destination = tempDir.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

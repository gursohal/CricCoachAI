import SwiftUI
import PhotosUI

struct SetupGuideView: View {
    let analysisType: AnalysisType
    let onVideoReady: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var showingRecording = false
    @State private var showingImport = false
    
    private let tips: [(String, String, String)] = [
        ("video.badge.checkmark", "Any Video Works", "Import any cricket video — from your camera roll, match footage, or net practice. We'll detect the batsman or bowler automatically."),
        ("figure.cricket", "Full Body Visible", "For best results, the player should be mostly visible in the frame. Any camera angle works — side-on, front, behind the stumps."),
        ("sparkles", "Tips for Best Analysis", "Side-on view gives the most detailed angle measurements. But don't worry — our AI adapts to whatever angle you have!"),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<tips.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? DesignSystem.Colors.cricketGreenLight : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top)
            
            // Content
            TabView(selection: $currentPage) {
                ForEach(0..<tips.count, id: \.self) { index in
                    VStack(spacing: 24) {
                        Spacer()
                        
                        Image(systemName: tips[index].0)
                            .font(.system(size: 72))
                            .foregroundColor(DesignSystem.Colors.cricketGreenLight)
                        
                        Text(tips[index].1)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(tips[index].2)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        // Analysis-specific tip
                        if index == 1 {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text(analysisType == .batting ?
                                     "Tip: Side-on view gives the most accurate angle data" :
                                     "Tip: Side-on view is best for bowling action analysis"
                                )
                                .font(.caption)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.1))
                            )
                            .padding(.horizontal)
                        }
                        
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: { showingImport = true }) {
                    Label("Import Any Cricket Video", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.cricketGreenLight)
                        .foregroundColor(.white)
                        .cornerRadius(DesignSystem.Layout.cornerRadius)
                }
                
                Button(action: { showingRecording = true }) {
                    Label("Record New Video", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(DesignSystem.Layout.cornerRadius)
                }
            }
            .padding()
        }
        .navigationTitle("\(analysisType.displayName) Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showingRecording) {
            RecordingView(
                analysisType: analysisType,
                onVideoRecorded: { url in
                    showingRecording = false
                    onVideoReady(url)
                }
            )
        }
        .sheet(isPresented: $showingImport) {
            VideoImportView(
                onVideoSelected: { url in
                    showingImport = false
                    onVideoReady(url)
                }
            )
        }
    }
}

#Preview {
    NavigationStack {
        SetupGuideView(analysisType: .batting) { _ in }
    }
}

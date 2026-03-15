import SwiftUI
import UIKit

/// Service for generating shareable analysis cards
class SharingService {
    
    /// Generate a shareable image card for an analysis session
    @MainActor
    static func generateShareCard(session: AnalysisSession) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(session: session))
        renderer.scale = 3.0  // 3x for high quality
        return renderer.uiImage
    }
    
    /// Share an analysis session via the system share sheet
    @MainActor
    static func shareSession(_ session: AnalysisSession, from viewController: UIViewController? = nil) {
        guard let image = generateShareCard(session: session) else { return }
        
        let text = "Just analyzed my \(session.type.displayName.lowercased()) technique with CricCoach AI! Score: \(session.overallScore)/100 🏏"
        
        let activityVC = UIActivityViewController(
            activityItems: [image, text],
            applicationActivities: nil
        )
        
        if let vc = viewController ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController {
            vc.present(activityVC, animated: true)
        }
    }
}

// MARK: - Share Card View

struct ShareCardView: View {
    let session: AnalysisSession
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CricCoach AI")
                        .font(.headline)
                        .foregroundColor(DesignSystem.Colors.cricketGreenLight)
                    Text(session.type.displayName + " Analysis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(session.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Score
            HStack {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(session.overallScore) / 100)
                        .stroke(DesignSystem.Colors.scoreColor(for: session.overallScore), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(session.overallScore)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.scoreColor(for: session.overallScore))
                        Text("/100")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)
                
                Spacer()
                
                // Phase scores
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.techniqueScores.prefix(4), id: \.id) { score in
                        HStack(spacing: 8) {
                            Text(score.phase.shortName)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 28, alignment: .leading)
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.2))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(DesignSystem.Colors.scoreColor(for: score.overallScore))
                                        .frame(width: geo.size.width * CGFloat(score.overallScore) / 100)
                                }
                            }
                            .frame(height: 8)
                            
                            Text("\(score.overallScore)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.scoreColor(for: score.overallScore))
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                }
            }
            
            // Footer
            HStack {
                Image(systemName: "cricket.ball")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.cricketGreenLight)
                Text("criccoach.ai")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Record. Analyze. Improve.")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.gold)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 8)
    }
}

// MARK: - Share Button Modifier

struct ShareButton: ViewModifier {
    let session: AnalysisSession
    
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { SharingService.shareSession(session) }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
    }
}

extension View {
    func shareButton(session: AnalysisSession) -> some View {
        modifier(ShareButton(session: session))
    }
}

import SwiftUI

struct ScoreCardView: View {
    let title: String
    let score: Int
    let subtitle: String?
    let icon: String?
    
    init(title: String, score: Int, subtitle: String? = nil, icon: String? = nil) {
        self.title = title
        self.score = score
        self.subtitle = subtitle
        self.icon = icon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack(alignment: .bottom, spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.scoreColor(for: score))
                
                Text("/100")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }
            
            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DesignSystem.Colors.scoreColor(for: score))
                        .frame(width: geo.size.width * CGFloat(score) / 100, height: 6)
                }
            }
            .frame(height: 6)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.smallCornerRadius)
                .fill(Color(UIColor.tertiarySystemBackground))
        )
    }
}

struct CheckpointRowView: View {
    let checkpoint: CheckpointScore
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                Image(systemName: checkpoint.severity.icon)
                    .foregroundColor(checkpoint.severity.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(checkpoint.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(checkpoint.shortFeedback)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(checkpoint.score)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.scoreColor(for: checkpoint.score))
                    Text(checkpoint.idealRange)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.smallCornerRadius)
                    .fill(Color(UIColor.tertiarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        ScoreCardView(title: "Overall Score", score: 72, subtitle: "Good technique with room for improvement")
        ScoreCardView(title: "Head Stability", score: 45, subtitle: "Critical - needs work")
    }
    .padding()
    .preferredColorScheme(.dark)
}

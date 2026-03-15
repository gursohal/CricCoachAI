import SwiftUI

struct PhaseDetailView: View {
    let techniqueScore: TechniqueScore
    let session: AnalysisSession
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Layout.padding) {
                // Phase header with score
                VStack(spacing: 8) {
                    HStack {
                        Circle().fill(techniqueScore.phase.color).frame(width: 12, height: 12)
                        Text(techniqueScore.phase.displayName)
                            .font(.title2).fontWeight(.bold)
                    }
                    Text("\(techniqueScore.overallScore)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.scoreColor(for: techniqueScore.overallScore))
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                    .fill(Color(UIColor.secondarySystemBackground)))
                
                // Checkpoints
                VStack(alignment: .leading, spacing: 12) {
                    Text("Checkpoints")
                        .font(.headline)
                    
                    ForEach(techniqueScore.checkpoints) { checkpoint in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: checkpoint.severity.icon)
                                    .foregroundColor(checkpoint.severity.color)
                                Text(checkpoint.name)
                                    .font(.subheadline).fontWeight(.medium)
                                Spacer()
                                Text("\(checkpoint.score)/100")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.scoreColor(for: checkpoint.score))
                            }
                            
                            // Score bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(height: 4)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(DesignSystem.Colors.scoreColor(for: checkpoint.score))
                                        .frame(width: geo.size.width * CGFloat(checkpoint.score) / 100, height: 4)
                                }
                            }.frame(height: 4)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Measured").font(.caption2).foregroundColor(.secondary)
                                    Text(checkpoint.measuredValueDescription).font(.caption).fontWeight(.medium)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Ideal").font(.caption2).foregroundColor(.secondary)
                                    Text(checkpoint.idealRange).font(.caption).fontWeight(.medium).foregroundColor(.green)
                                }
                            }
                            
                            Text(checkpoint.shortFeedback)
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.tertiarySystemBackground)))
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(techniqueScore.phase.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

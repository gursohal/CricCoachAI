import SwiftUI

struct PhaseTimelineView: View {
    let phases: [DetectedPhase]
    let currentTime: TimeInterval
    let duration: TimeInterval
    var onSeek: ((TimeInterval) -> Void)?
    var onPhaseSelected: ((PosePhase) -> Void)?
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 24)
                
                // Phase segments
                ForEach(phases) { phase in
                    let startX = (phase.keyFrameTimestamp - Double(phase.keyFrame - phase.startFrame) / 30.0) / max(duration, 0.01) * geo.size.width
                    let endX = (phase.keyFrameTimestamp + Double(phase.endFrame - phase.keyFrame) / 30.0) / max(duration, 0.01) * geo.size.width
                    let width = max(endX - startX, 2)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(phase.phase.color.opacity(0.6))
                        .frame(width: width, height: 24)
                        .offset(x: startX)
                        .onTapGesture {
                            onSeek?(phase.keyFrameTimestamp)
                            onPhaseSelected?(phase.phase)
                        }
                }
                
                // Phase labels
                ForEach(phases) { phase in
                    let xPos = phase.keyFrameTimestamp / max(duration, 0.01) * geo.size.width
                    Text(phase.phase.shortName)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: xPos - 10)
                        .offset(y: -14)
                }
                
                // Current position indicator
                let position = currentTime / max(duration, 0.01) * geo.size.width
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: 30)
                    .offset(x: min(max(position, 0), geo.size.width))
            }
        }
        .frame(height: 30)
    }
}

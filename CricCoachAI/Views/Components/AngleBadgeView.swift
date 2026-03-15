import SwiftUI

struct AngleBadgeView: View {
    let angle: Double
    let label: String
    
    var body: some View {
        VStack(spacing: 1) {
            Text(String(format: "%.0f°", angle))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 7))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.black.opacity(0.7))
        )
    }
}

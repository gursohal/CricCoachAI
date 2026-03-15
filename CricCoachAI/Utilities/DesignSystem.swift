import SwiftUI

/// Centralized design system for CricCoach AI
/// Note: UI extensions for model types (PosePhase.color, Severity.color, etc.)
/// are defined in their respective model files to avoid redeclaration.
enum DesignSystem {
    
    // MARK: - Colors
    
    enum Colors {
        static let cricketGreen = Color(red: 0.106, green: 0.369, blue: 0.125)       // #1B5E20
        static let cricketGreenLight = Color(red: 0.180, green: 0.545, blue: 0.200)   // #2E8B32
        static let gold = Color(red: 1.0, green: 0.839, blue: 0.0)                     // #FFD600
        static let goldDark = Color(red: 0.8, green: 0.671, blue: 0.0)
        
        static let scoreRed = Color(red: 0.9, green: 0.2, blue: 0.2)
        static let scoreOrange = Color(red: 0.95, green: 0.55, blue: 0.1)
        static let scoreYellow = Color(red: 0.95, green: 0.85, blue: 0.1)
        static let scoreGreen = Color(red: 0.2, green: 0.8, blue: 0.3)
        
        static let skeletonHead = Color.red
        static let skeletonArms = Color.blue
        static let skeletonTorso = Color.cyan
        static let skeletonLegs = Color.green
        
        /// Score color based on value (0-100)
        static func scoreColor(for score: Int) -> Color {
            switch score {
            case ..<50: return scoreRed
            case 50..<65: return scoreOrange
            case 65..<80: return scoreYellow
            default: return scoreGreen
            }
        }
        
        /// Skeleton color based on body group
        static func skeletonColor(for group: BodyLandmark.BodyGroup) -> Color {
            switch group {
            case .head: return skeletonHead
            case .torso: return skeletonTorso
            case .arms: return skeletonArms
            case .legs: return skeletonLegs
            }
        }
    }
    
    // MARK: - Layout
    
    enum Layout {
        static let padding: CGFloat = 16
        static let smallPadding: CGFloat = 8
        static let largePadding: CGFloat = 24
        static let cornerRadius: CGFloat = 16
        static let smallCornerRadius: CGFloat = 8
        static let skeletonLineWidth: CGFloat = 3
        static let skeletonPointRadius: CGFloat = 5
        static let skeletonGlowRadius: CGFloat = 4
        static let scoreCardHeight: CGFloat = 120
        static let phaseTimelineHeight: CGFloat = 60
    }
    
    // MARK: - Animation
    
    enum Animation {
        static let standard: SwiftUI.Animation = .easeInOut(duration: 0.3)
        static let spring: SwiftUI.Animation = .spring(response: 0.4, dampingFraction: 0.8)
        static let slow: SwiftUI.Animation = .easeInOut(duration: 0.6)
    }
}

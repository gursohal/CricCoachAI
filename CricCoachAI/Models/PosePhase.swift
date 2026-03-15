import Foundation
import SwiftUI

// MARK: - Analysis Type

enum AnalysisType: String, Codable, CaseIterable, Identifiable {
    case batting
    case bowling
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .batting: return "Batting"
        case .bowling: return "Bowling"
        }
    }
    
    var icon: String {
        switch self {
        case .batting: return "figure.cricket"
        case .bowling: return "figure.bowling"
        }
    }
    
    var phases: [PosePhase] {
        switch self {
        case .batting: return PosePhase.battingPhases
        case .bowling: return PosePhase.bowlingPhases
        }
    }
}

// MARK: - Pose Phase

enum PosePhase: String, Codable, CaseIterable, Identifiable {
    // Batting phases
    case stance
    case backlift
    case stride
    case downswing
    case contact
    case battingFollowThrough = "batting_follow_through"
    
    // Bowling phases
    case runUp = "run_up"
    case gather
    case backFootContact = "back_foot_contact"
    case frontFootContact = "front_foot_contact"
    case release
    case bowlingFollowThrough = "bowling_follow_through"
    
    var id: String { rawValue }
    
    static var battingPhases: [PosePhase] {
        [.stance, .backlift, .stride, .downswing, .contact, .battingFollowThrough]
    }
    
    static var bowlingPhases: [PosePhase] {
        [.runUp, .gather, .backFootContact, .frontFootContact, .release, .bowlingFollowThrough]
    }
    
    var displayName: String {
        switch self {
        case .stance: return "Stance"
        case .backlift: return "Backlift"
        case .stride: return "Stride"
        case .downswing: return "Downswing"
        case .contact: return "Contact"
        case .battingFollowThrough: return "Follow Through"
        case .runUp: return "Run-Up"
        case .gather: return "Gather/Bound"
        case .backFootContact: return "Back Foot Contact"
        case .frontFootContact: return "Front Foot Contact"
        case .release: return "Release"
        case .bowlingFollowThrough: return "Follow Through"
        }
    }
    
    var shortName: String {
        switch self {
        case .stance: return "STA"
        case .backlift: return "BKL"
        case .stride: return "STR"
        case .downswing: return "DWN"
        case .contact: return "CON"
        case .battingFollowThrough: return "FTH"
        case .runUp: return "RUN"
        case .gather: return "GTH"
        case .backFootContact: return "BFC"
        case .frontFootContact: return "FFC"
        case .release: return "REL"
        case .bowlingFollowThrough: return "FTH"
        }
    }
    
    var color: Color {
        switch self {
        case .stance: return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .backlift: return Color(red: 0.3, green: 0.8, blue: 0.4)
        case .stride: return Color(red: 0.9, green: 0.7, blue: 0.2)
        case .downswing: return Color(red: 0.9, green: 0.5, blue: 0.2)
        case .contact: return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .battingFollowThrough: return Color(red: 0.7, green: 0.3, blue: 0.9)
        case .runUp: return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .gather: return Color(red: 0.3, green: 0.8, blue: 0.4)
        case .backFootContact: return Color(red: 0.9, green: 0.7, blue: 0.2)
        case .frontFootContact: return Color(red: 0.9, green: 0.5, blue: 0.2)
        case .release: return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .bowlingFollowThrough: return Color(red: 0.7, green: 0.3, blue: 0.9)
        }
    }
    
    var description: String {
        switch self {
        case .stance:
            return "The ready position before the ball is bowled"
        case .backlift:
            return "Bat is lifted in preparation for the shot"
        case .stride:
            return "Front foot moves toward the ball"
        case .downswing:
            return "Bat comes down toward the ball"
        case .contact:
            return "Bat meets the ball"
        case .battingFollowThrough:
            return "Bat continues after contact"
        case .runUp:
            return "Bowler approaching the crease"
        case .gather:
            return "Bowler jumps before delivery stride"
        case .backFootContact:
            return "Back foot lands in delivery stride"
        case .frontFootContact:
            return "Front foot lands in delivery stride"
        case .release:
            return "Ball leaves the hand"
        case .bowlingFollowThrough:
            return "Continued motion after release"
        }
    }
    
    var analysisType: AnalysisType {
        switch self {
        case .stance, .backlift, .stride, .downswing, .contact, .battingFollowThrough:
            return .batting
        case .runUp, .gather, .backFootContact, .frontFootContact, .release, .bowlingFollowThrough:
            return .bowling
        }
    }
    
    var orderIndex: Int {
        switch self {
        case .stance: return 0
        case .backlift: return 1
        case .stride: return 2
        case .downswing: return 3
        case .contact: return 4
        case .battingFollowThrough: return 5
        case .runUp: return 0
        case .gather: return 1
        case .backFootContact: return 2
        case .frontFootContact: return 3
        case .release: return 4
        case .bowlingFollowThrough: return 5
        }
    }
}

// MARK: - Detected Phase

struct DetectedPhase: Codable, Identifiable {
    let id: UUID
    let phase: PosePhase
    let startFrame: Int
    let endFrame: Int
    let keyFrame: Int
    let keyFrameTimestamp: TimeInterval
    let confidence: Float
    
    init(
        id: UUID = UUID(),
        phase: PosePhase,
        startFrame: Int,
        endFrame: Int,
        keyFrame: Int,
        keyFrameTimestamp: TimeInterval,
        confidence: Float
    ) {
        self.id = id
        self.phase = phase
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.keyFrame = keyFrame
        self.keyFrameTimestamp = keyFrameTimestamp
        self.confidence = confidence
    }
    
    var frameRange: ClosedRange<Int> {
        startFrame...endFrame
    }
    
    var durationFrames: Int {
        endFrame - startFrame + 1
    }
}

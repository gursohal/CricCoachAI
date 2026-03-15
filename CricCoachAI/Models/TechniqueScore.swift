import Foundation
import SwiftUI

// MARK: - Severity

enum Severity: String, Codable, CaseIterable {
    case critical   // score < 50
    case moderate   // score 50-74
    case minor      // score 75-89
    case good       // score 90-100
    
    init(score: Int) {
        switch score {
        case ..<50: self = .critical
        case 50..<75: self = .moderate
        case 75..<90: self = .minor
        default: self = .good
        }
    }
    
    var displayName: String {
        switch self {
        case .critical: return "Critical"
        case .moderate: return "Needs Work"
        case .minor: return "Minor Issue"
        case .good: return "Good"
        }
    }
    
    var color: Color {
        switch self {
        case .critical: return .red
        case .moderate: return .orange
        case .minor: return .yellow
        case .good: return .green
        }
    }
    
    var icon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .minor: return "info.circle.fill"
        case .good: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Checkpoint Score

struct CheckpointScore: Codable, Identifiable {
    let id: UUID
    let name: String
    let score: Int
    let measuredValue: Double
    let measuredValueDescription: String
    let idealRange: String
    let severity: Severity
    let shortFeedback: String
    let landmark: String?  // associated body landmark for highlighting
    
    init(
        id: UUID = UUID(),
        name: String,
        score: Int,
        measuredValue: Double,
        measuredValueDescription: String,
        idealRange: String,
        shortFeedback: String,
        landmark: String? = nil
    ) {
        self.id = id
        self.name = name
        self.score = max(0, min(100, score))
        self.measuredValue = measuredValue
        self.measuredValueDescription = measuredValueDescription
        self.idealRange = idealRange
        self.severity = Severity(score: score)
        self.shortFeedback = shortFeedback
        self.landmark = landmark
    }
}

// MARK: - Technique Score

struct TechniqueScore: Codable, Identifiable {
    let id: UUID
    let phase: PosePhase
    let overallScore: Int
    let checkpoints: [CheckpointScore]
    let keyFrameIndex: Int
    let keyFrameTimestamp: TimeInterval
    
    init(
        id: UUID = UUID(),
        phase: PosePhase,
        overallScore: Int,
        checkpoints: [CheckpointScore],
        keyFrameIndex: Int,
        keyFrameTimestamp: TimeInterval
    ) {
        self.id = id
        self.phase = phase
        self.overallScore = max(0, min(100, overallScore))
        self.checkpoints = checkpoints
        self.keyFrameIndex = keyFrameIndex
        self.keyFrameTimestamp = keyFrameTimestamp
    }
    
    var severity: Severity {
        Severity(score: overallScore)
    }
    
    var criticalCheckpoints: [CheckpointScore] {
        checkpoints.filter { $0.severity == .critical }
    }
    
    var moderateCheckpoints: [CheckpointScore] {
        checkpoints.filter { $0.severity == .moderate }
    }
    
    var goodCheckpoints: [CheckpointScore] {
        checkpoints.filter { $0.severity == .good }
    }
    
    /// Sorted checkpoints by severity (worst first)
    var sortedCheckpoints: [CheckpointScore] {
        checkpoints.sorted { $0.score < $1.score }
    }
}

// MARK: - Score Color Helper

extension Int {
    /// Color based on technique score value
    var scoreColor: Color {
        switch self {
        case ..<50: return .red
        case 50..<65: return .orange
        case 65..<80: return .yellow
        case 80...: return .green
        default: return .gray
        }
    }
    
    /// Grade letter based on score
    var scoreGrade: String {
        switch self {
        case 90...: return "A+"
        case 85..<90: return "A"
        case 80..<85: return "A-"
        case 75..<80: return "B+"
        case 70..<75: return "B"
        case 65..<70: return "B-"
        case 60..<65: return "C+"
        case 55..<60: return "C"
        case 50..<55: return "C-"
        case 40..<50: return "D"
        default: return "F"
        }
    }
}

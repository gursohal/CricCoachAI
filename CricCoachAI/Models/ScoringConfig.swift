import Foundation

/// Server-overridable scoring thresholds.
///
/// Default values match the current `IdealValues` enum in `Constants.swift`.
/// Architecture enables fetching from Supabase in a future iteration.
///
/// ## Usage
/// ```swift
/// let config = ScoringConfig.default  // Uses hardcoded defaults
/// let score = ruleScoringService.scorePhase(using: config)
/// ```
///
/// ## Future: Server-side fetch
/// ```swift
/// let config = await ScoringConfigService.shared.currentConfig
/// ```
struct ScoringConfig: Codable {
    
    // MARK: - Batting Stance
    
    struct BattingStance: Codable {
        var feetWidthMin: Double = 1.0
        var feetWidthMax: Double = 1.3
        var feetWidthPenaltyPer01x: Int = 10
        var kneeBendMin: Double = 160
        var kneeBendMax: Double = 175
        var kneeBendPenaltyPer5deg: Int = 15
        var headAlignmentThreshold: Double = 0.05
        var headAlignmentPenaltyPer2pct: Int = 10
        var weightDistributionMin: Double = -0.2
        var weightDistributionMax: Double = 0.1
        var weightDistributionPenalty: Int = 20
    }
    
    // MARK: - Batting Backlift
    
    struct BattingBacklift: Codable {
        var wristAboveShoulderThreshold: Double = 1.0
        var wristHeightPenaltyPer10pct: Int = 15
        var headMovementThreshold: Double = 3.0
        var headMovementPenaltyPer1pct: Int = 10
        var directionAngleMin: Double = 0
        var directionAngleMax: Double = 15
        var directionPenalty: Int = 20
        var shoulderAlignmentMax: Double = 20
    }
    
    // MARK: - Batting Stride
    
    struct BattingStride: Codable {
        var strideLengthMin: Double = 1.5
        var strideLengthMax: Double = 2.2
        var strideLengthPenaltyPer02x: Int = 10
        var strideDirectionMax: Double = 10
        var strideDirectionPenaltyPer5deg: Int = 15
        var frontKneeMin: Double = 140
        var frontKneeMax: Double = 165
    }
    
    // MARK: - Batting Contact
    
    struct BattingContact: Codable {
        var headStabilityThreshold: Double = 2.0
        var headStabilityPenaltyPer1pct: Int = 15
        var frontElbowMin: Double = 150
        var frontElbowMax: Double = 180
        var headOverFootThreshold: Double = 0.1
    }
    
    // MARK: - Batting Follow Through
    
    struct BattingFollowThrough: Codable {
        var wristAboveShoulderRequired: Bool = true
        var balanceRequired: Bool = true
    }
    
    // MARK: - Bowling Release
    
    struct BowlingRelease: Codable {
        var armAngleFromVerticalMax: Double = 15
        var armAnglePenaltyPer5deg: Int = 10
        var frontLegBraceMin: Double = 160
        var frontLegBraceMax: Double = 180
        var hipShoulderSeparationMin: Double = 30
        var hipShoulderSeparationMax: Double = 50
    }
    
    // MARK: - General
    
    struct General: Codable {
        var headStabilityMinScore: Int = 50
        var minimumPhaseConfidence: Float = 0.6
        var velocityThreshold: Double = 0.01
    }
    
    // MARK: - All Sub-Configs
    
    var battingStance: BattingStance = .init()
    var battingBacklift: BattingBacklift = .init()
    var battingStride: BattingStride = .init()
    var battingContact: BattingContact = .init()
    var battingFollowThrough: BattingFollowThrough = .init()
    var bowlingRelease: BowlingRelease = .init()
    var general: General = .init()
    
    /// Version tag for cache invalidation
    var version: String = "1.0"
    
    // MARK: - Default Instance
    
    /// The default config matching current `IdealValues` in Constants.swift
    static let `default` = ScoringConfig()
}

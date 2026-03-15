import Foundation
import SwiftUI

/// App-wide constants and configuration
enum AppConstants {
    
    // MARK: - App Info
    static let appName = "CricCoach AI"
    static let tagline = "Your AI cricket coach. Record. Analyze. Improve."
    static let bundleId = "com.criccoach.ai"
    
    // MARK: - Video Recording
    static let maxRecordingDuration: TimeInterval = 120  // 2 minutes
    static let recordingFPS: Double = 30
    static let recordingResolution = "1080p"
    static let maxImportDuration: TimeInterval = 120  // 2 minutes
    
    // MARK: - Pose Estimation
    static let minimumConfidence: Float = 0.5
    static let smoothingWindowSize = 5  // frames for rolling average
    
    // MARK: - Subscription
    static let freeAnalysesPerMonth = 3
    static let proMonthlyPrice = "$7.99"
    static let proYearlyPrice = "$49.99"
    static let proMonthlyProductId = "com.criccoach.ai.pro.monthly"
    static let proYearlyProductId = "com.criccoach.ai.pro.yearly"
    
    // MARK: - API
    static let apiBaseURL = "https://your-supabase-project.supabase.co"
    static let supabaseAnonKey = "your-anon-key-here"
    static let analyzeEndpoint = "/functions/v1/analyze"
    static let apiTimeout: TimeInterval = 30
    
    // MARK: - Storage
    static let videosDirectory = "recordings"
    static let keyFramesDirectory = "keyframes"
    static let maxStorageGB: Double = 2.0
}

// MARK: - Ideal Biomechanical Values

/// Ideal angle ranges and thresholds for scoring
enum IdealValues {
    
    // MARK: - Batting Stance
    enum BattingStance {
        static let feetWidthRange: ClosedRange<Double> = 1.0...1.3  // x shoulder width
        static let feetWidthPenaltyPer01x: Int = 10
        
        static let kneeBendRange: ClosedRange<Double> = 160...175  // degrees
        static let kneeBendPenaltyPer5deg: Int = 15
        
        static let headAlignmentThreshold: Double = 0.05  // 5% of stance width
        static let headAlignmentPenaltyPer2pct: Int = 10
        
        static let weightDistributionRange: ClosedRange<Double> = -0.2...0.1  // centered to slightly back
        static let weightDistributionPenalty: Int = 20
    }
    
    // MARK: - Batting Backlift
    enum BattingBacklift {
        static let wristAboveShoulderThreshold: Double = 1.0  // relative to shoulder height
        static let wristHeightPenaltyPer10pct: Int = 15
        
        static let headMovementThreshold: Double = 3.0  // % of body height
        static let headMovementPenaltyPer1pct: Int = 10
        
        static let directionAngleRange: ClosedRange<Double> = 0...15  // degrees off-side
        static let directionPenalty: Int = 20
        
        static let shoulderAlignmentMax: Double = 20  // degrees
    }
    
    // MARK: - Batting Stride
    enum BattingStride {
        static let strideLengthRange: ClosedRange<Double> = 1.5...2.2  // x shoulder width
        static let strideLengthPenaltyPer02x: Int = 10
        
        static let strideDirectionMax: Double = 10  // degrees from straight
        static let strideDirectionPenaltyPer5deg: Int = 15
        
        static let frontKneeRange: ClosedRange<Double> = 140...165  // degrees
    }
    
    // MARK: - Batting Contact
    enum BattingContact {
        static let headStabilityThreshold: Double = 2.0  // % of body height
        static let headStabilityPenaltyPer1pct: Int = 15
        
        static let frontElbowRange: ClosedRange<Double> = 150...180  // degrees
        
        static let headOverFootThreshold: Double = 0.1  // normalized
    }
    
    // MARK: - Batting Follow Through
    enum BattingFollowThrough {
        static let wristAboveShoulderRequired = true
        static let balanceRequired = true
    }
    
    // MARK: - Bowling Release
    enum BowlingRelease {
        static let armAngleFromVerticalMax: Double = 15  // degrees
        static let armAnglePenaltyPer5deg: Int = 10
        
        static let frontLegBraceRange: ClosedRange<Double> = 160...180  // degrees for pace
        
        static let hipShoulderSeparationRange: ClosedRange<Double> = 30...50  // degrees
    }
    
    // MARK: - Bowling Front Foot
    enum BowlingFrontFoot {
        /// No-ball detection threshold
        static let noBallWarning = true
    }
    
    // MARK: - General Thresholds
    enum General {
        static let headStabilityMinScore = 50  // below this is critical
        static let minimumPhaseConfidence: Float = 0.6
        static let velocityThreshold: CGFloat = 0.01  // minimum landmark velocity to count as movement
    }
}

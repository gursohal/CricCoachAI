import Foundation
import SwiftData
import UIKit

/// Service for local persistence (SwiftData) and future cloud sync
@MainActor
class StorageService: ObservableObject {
    
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    
    init() {
        let schema = Schema([AnalysisSession.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = modelContainer.mainContext
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    // MARK: - User Profile
    
    /// Get or create the user profile
    func getOrCreateProfile() -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        
        let profile = UserProfile()
        modelContext.insert(profile)
        try? modelContext.save()
        return profile
    }
    
    /// Update user profile
    func updateProfile(_ update: (UserProfile) -> Void) {
        let profile = getOrCreateProfile()
        update(profile)
        try? modelContext.save()
    }
    
    // MARK: - Analysis Sessions
    
    /// Create a new analysis session
    func createSession(
        analysisType: AnalysisType,
        videoLocalPath: String,
        durationSeconds: Double
    ) -> AnalysisSession {
        let session = AnalysisSession(
            analysisType: analysisType.rawValue,
            videoLocalPath: videoLocalPath,
            durationSeconds: durationSeconds
        )
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }
    
    /// Save/update a session
    func saveSession(_ session: AnalysisSession) {
        try? modelContext.save()
    }
    
    /// Get all sessions, ordered by date (newest first)
    func getAllSessions() -> [AnalysisSession] {
        let descriptor = FetchDescriptor<AnalysisSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get sessions filtered by type
    func getSessions(type: AnalysisType) -> [AnalysisSession] {
        let typeStr = type.rawValue
        let descriptor = FetchDescriptor<AnalysisSession>(
            predicate: #Predicate { $0.analysisType == typeStr },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get recent sessions (last N)
    func getRecentSessions(limit: Int = 10) -> [AnalysisSession] {
        var descriptor = FetchDescriptor<AnalysisSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get a specific session by ID
    func getSession(id: UUID) -> AnalysisSession? {
        var descriptor = FetchDescriptor<AnalysisSession>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Delete a session
    func deleteSession(_ session: AnalysisSession) {
        // Delete associated files
        let videoService = VideoProcessingService()
        try? videoService.deleteSessionFiles(sessionId: session.id)
        
        modelContext.delete(session)
        try? modelContext.save()
    }
    
    // MARK: - Progress Data
    
    /// Get score trend for a specific checkpoint across sessions
    func getScoreTrend(
        checkpointName: String,
        analysisType: AnalysisType,
        limit: Int = 10
    ) -> [(Date, Int)] {
        let sessions = getSessions(type: analysisType).prefix(limit)
        
        var trend: [(Date, Int)] = []
        for session in sessions {
            for score in session.techniqueScores {
                if let checkpoint = score.checkpoints.first(where: { $0.name == checkpointName }) {
                    trend.append((session.date, checkpoint.score))
                }
            }
        }
        
        return trend.reversed()  // chronological order
    }
    
    /// Get overall score trend
    func getOverallScoreTrend(
        analysisType: AnalysisType,
        limit: Int = 10
    ) -> [(Date, Int)] {
        let sessions = getSessions(type: analysisType).prefix(limit)
        return sessions.map { ($0.date, $0.overallScore) }.reversed()
    }
    
    /// Get the latest scores for each checkpoint (for previous session comparison)
    func getLatestCheckpointScores(analysisType: AnalysisType) -> [String: Int] {
        guard let latestSession = getSessions(type: analysisType).first else { return [:] }
        
        var scores: [String: Int] = [:]
        for techniqueScore in latestSession.techniqueScores {
            for checkpoint in techniqueScore.checkpoints {
                scores[checkpoint.name] = checkpoint.score
            }
        }
        return scores
    }
    
    /// Calculate streak (consecutive weeks with at least one session)
    func calculateStreak() -> Int {
        let sessions = getAllSessions()
        guard !sessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var streak = 1
        let currentWeek = calendar.component(.weekOfYear, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        
        // Check if there's a session this week
        let hasSessionThisWeek = sessions.contains { session in
            calendar.component(.weekOfYear, from: session.date) == currentWeek &&
            calendar.component(.year, from: session.date) == currentYear
        }
        
        guard hasSessionThisWeek else { return 0 }
        
        // Count consecutive previous weeks
        for weekOffset in 1...52 {
            let targetWeek = currentWeek - weekOffset
            let adjustedWeek = targetWeek > 0 ? targetWeek : targetWeek + 52
            let adjustedYear = targetWeek > 0 ? currentYear : currentYear - 1
            
            let hasSession = sessions.contains { session in
                calendar.component(.weekOfYear, from: session.date) == adjustedWeek &&
                calendar.component(.year, from: session.date) == adjustedYear
            }
            
            if hasSession {
                streak += 1
            } else {
                break
            }
        }
        
        return streak
    }
    
    /// Get biggest improvement across checkpoints
    func getBiggestImprovement(analysisType: AnalysisType) -> (String, Int)? {
        let sessions = getSessions(type: analysisType)
        guard sessions.count >= 2 else { return nil }
        
        let latestScores = getLatestCheckpointScores(analysisType: analysisType)
        
        // Get scores from ~4 sessions ago (or earliest)
        let comparisonIndex = min(3, sessions.count - 1)
        let comparisonSession = sessions[comparisonIndex]
        
        var comparisonScores: [String: Int] = [:]
        for score in comparisonSession.techniqueScores {
            for cp in score.checkpoints {
                comparisonScores[cp.name] = cp.score
            }
        }
        
        var biggestImprovement: (String, Int) = ("", 0)
        for (name, currentScore) in latestScores {
            if let previousScore = comparisonScores[name] {
                let improvement = currentScore - previousScore
                if improvement > biggestImprovement.1 {
                    biggestImprovement = (name, improvement)
                }
            }
        }
        
        return biggestImprovement.1 > 0 ? biggestImprovement : nil
    }
    
    // MARK: - Subscription Tracking
    
    /// Increment analysis count for the month
    func incrementAnalysisCount() {
        let profile = getOrCreateProfile()
        profile.checkMonthlyReset()
        profile.analysesThisMonth += 1
        try? modelContext.save()
    }
    
    /// Check if user can perform analysis
    func canPerformAnalysis() -> Bool {
        let profile = getOrCreateProfile()
        profile.checkMonthlyReset()
        return profile.canAnalyze
    }
}

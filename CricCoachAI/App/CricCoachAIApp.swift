import SwiftUI
import SwiftData

@main
struct CricCoachAIApp: App {
    
    @StateObject private var storageService = StorageService()
    @StateObject private var featureFlags = FeatureFlagService.shared
    
    init() {
        AnalyticsService.initialize()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageService)
                .environmentObject(featureFlags)
                .modelContainer(storageService.modelContainer)
                .preferredColorScheme(.dark)
                .task {
                    AnalyticsService.track(.appLaunched)
                    await featureFlags.fetchFlags()
                }
        }
    }
}

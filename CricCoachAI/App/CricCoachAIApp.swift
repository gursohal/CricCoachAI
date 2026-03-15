import SwiftUI
import SwiftData

@main
struct CricCoachAIApp: App {
    
    @StateObject private var storageService = StorageService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageService)
                .modelContainer(storageService.modelContainer)
                .preferredColorScheme(.dark)
        }
    }
}

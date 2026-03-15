import SwiftUI

struct ContentView: View {
    @EnvironmentObject var storageService: StorageService
    @State private var hasCompletedOnboarding = false
    
    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(hasCompleted: $hasCompletedOnboarding)
            }
        }
        .onAppear {
            let profile = storageService.getOrCreateProfile()
            hasCompletedOnboarding = profile.hasCompletedOnboarding
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(0)
            
            NavigationStack {
                SessionProgressView()
            }
            .tabItem {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(1)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .tint(DesignSystem.Colors.cricketGreenLight)
    }
}

// MARK: - Settings View (placeholder)

struct SettingsView: View {
    @EnvironmentObject var storageService: StorageService
    @State private var profile: UserProfile?
    
    var body: some View {
        List {
            Section("Profile") {
                if let profile = profile {
                    HStack {
                        Text("Experience")
                        Spacer()
                        Text(profile.experienceLevel.capitalized)
                            .foregroundColor(.secondary)
                    }
                    if let role = profile.playingRole {
                        HStack {
                            Text("Role")
                            Spacer()
                            Text(PlayingRole(rawValue: role)?.displayName ?? role)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let height = profile.heightCm {
                        HStack {
                            Text("Height")
                            Spacer()
                            Text("\(height) cm")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section("Subscription") {
                if let profile = profile {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(profile.isPro ? "Pro ✨" : "Free")
                            .foregroundColor(profile.isPro ? DesignSystem.Colors.gold : .secondary)
                    }
                    if !profile.isPro {
                        HStack {
                            Text("Analyses remaining")
                            Spacer()
                            Text("\(profile.remainingFreeAnalyses)/3 this month")
                                .foregroundColor(.secondary)
                        }
                        NavigationLink("Upgrade to Pro") {
                            PaywallView()
                        }
                        .foregroundColor(DesignSystem.Colors.cricketGreenLight)
                    }
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                Link("Privacy Policy", destination: URL(string: "https://criccoach.ai/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://criccoach.ai/terms")!)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            profile = storageService.getOrCreateProfile()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(StorageService())
}

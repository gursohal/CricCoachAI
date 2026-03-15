import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompleted: Bool
    @EnvironmentObject var storageService: StorageService
    @State private var currentPage = 0
    @State private var selectedSkill: AnalysisType?
    @State private var height: String = ""
    @State private var experience: ExperienceLevel = .beginner
    @State private var role: PlayingRole = .topOrderBatsman
    
    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Welcome
            welcomePage.tag(0)
            
            // Page 2: What to improve
            skillSelectionPage.tag(1)
            
            // Page 3: Basic info
            profilePage.tag(2)
            
            // Page 4: Camera setup tutorial
            cameraSetupPage.tag(3)
            
            // Page 5: Get started
            getStartedPage.tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
    
    // MARK: - Pages
    
    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "cricket.ball")
                .font(.system(size: 80))
                .foregroundColor(DesignSystem.Colors.cricketGreenLight)
            
            VStack(spacing: 8) {
                Text("CricCoach AI")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Your AI Cricket Coach")
                    .font(.title3).foregroundColor(.secondary)
            }
            
            Text("Record. Analyze. Improve.")
                .font(.headline)
                .foregroundColor(DesignSystem.Colors.gold)
            
            Spacer()
            
            Button("Get Started") { withAnimation { currentPage = 1 } }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.cricketGreenLight)
                .controlSize(.large)
            
            Spacer().frame(height: 60)
        }
    }
    
    private var skillSelectionPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("I want to improve my...")
                .font(.title2).fontWeight(.bold)
            
            ForEach(AnalysisType.allCases) { type in
                Button(action: { selectedSkill = type }) {
                    HStack {
                        Image(systemName: type.icon).font(.title2)
                        Text(type.displayName).fontWeight(.semibold)
                        Spacer()
                        if selectedSkill == type {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(selectedSkill == type ? DesignSystem.Colors.cricketGreen.opacity(0.2) : Color(UIColor.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedSkill == type ? DesignSystem.Colors.cricketGreenLight : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            
            Button("Both") { selectedSkill = .batting }
                .font(.subheadline).foregroundColor(DesignSystem.Colors.cricketGreenLight)
            
            Spacer()
            
            Button("Next") { withAnimation { currentPage = 2 } }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.cricketGreenLight)
                .disabled(selectedSkill == nil)
            
            Spacer().frame(height: 60)
        }
        .padding(.horizontal)
    }
    
    private var profilePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("About You").font(.title2).fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height (cm)").font(.subheadline).foregroundColor(.secondary)
                    TextField("e.g. 178", text: $height)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Experience Level").font(.subheadline).foregroundColor(.secondary)
                    Picker("Experience", selection: $experience) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playing Role").font(.subheadline).foregroundColor(.secondary)
                    Picker("Role", selection: $role) {
                        ForEach(PlayingRole.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
            
            Spacer()
            
            Button("Next") { withAnimation { currentPage = 3 } }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.cricketGreenLight)
            
            Spacer().frame(height: 60)
        }
        .padding(.horizontal)
    }
    
    private var cameraSetupPage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(DesignSystem.Colors.cricketGreenLight)
            
            Text("Camera Setup Tips").font(.title2).fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                tipRow(icon: "iphone.gen3", text: "Place phone on a tripod or lean it against something stable")
                tipRow(icon: "ruler", text: "Position 3-4 meters away at waist height")
                tipRow(icon: "figure.stand", text: "Make sure your full body is visible in frame")
                tipRow(icon: "sun.max", text: "Good lighting helps — outdoor or bright indoor nets")
            }
            .padding()
            
            Spacer()
            
            Button("Next") { withAnimation { currentPage = 4 } }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.cricketGreenLight)
            
            Spacer().frame(height: 60)
        }
        .padding(.horizontal)
    }
    
    private var getStartedPage: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)
            
            Text("You're All Set!").font(.title).fontWeight(.bold)
            Text("Record your first session and get AI coaching feedback.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            
            Spacer()
            
            Button("Record Your First Session!") { completeOnboarding() }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.cricketGreenLight)
                .controlSize(.large)
            
            Spacer().frame(height: 60)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helpers
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(DesignSystem.Colors.cricketGreenLight)
                .frame(width: 32)
            Text(text).font(.subheadline)
        }
    }
    
    private func completeOnboarding() {
        storageService.updateProfile { profile in
            profile.hasCompletedOnboarding = true
            profile.experienceLevel = experience.rawValue
            profile.playingRole = role.rawValue
            if let h = Int(height), h > 0 { profile.heightCm = h }
        }
        hasCompleted = true
    }
}

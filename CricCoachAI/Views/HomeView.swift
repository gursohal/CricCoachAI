import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var storageService: StorageService
    @State private var sessions: [AnalysisSession] = []
    @State private var showingNewAnalysis = false
    @State private var selectedAnalysisType: AnalysisType = .batting
    @State private var streak = 0
    @State private var showingSetupGuide = false
    
    // Processing state
    @State private var isProcessing = false
    @State private var processingStep = ""
    @State private var processingProgress: Double = 0
    @State private var processingError: String?
    @State private var completedSession: AnalysisSession?
    @State private var showingAnalysis = false
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: DesignSystem.Layout.padding) {
                    // New Analysis Button
                    newAnalysisSection
                    
                    // Quick Stats
                    if let latestSession = sessions.first {
                        quickStatsCard(session: latestSession)
                    }
                    
                    // Streak
                    if streak > 0 {
                        streakCard
                    }
                    
                    // Session History
                    if sessions.isEmpty {
                        emptyStateCard
                    } else {
                        sessionHistorySection
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("CricCoach AI")
            
            // Processing overlay
            if isProcessing {
                processingOverlay
            }
        }
        .onAppear { loadData() }
        .sheet(isPresented: $showingNewAnalysis) {
            NavigationStack {
                newAnalysisTypeSelection
            }
        }
        .fullScreenCover(isPresented: $showingSetupGuide) {
            NavigationStack {
                SetupGuideView(
                    analysisType: selectedAnalysisType,
                    onVideoReady: { url in
                        showingSetupGuide = false
                        startAnalysisPipeline(videoURL: url)
                    }
                )
            }
        }
        .navigationDestination(isPresented: $showingAnalysis) {
            if let session = completedSession {
                AnalysisView(session: session)
            }
        }
        .alert("Analysis Error", isPresented: .init(
            get: { processingError != nil },
            set: { if !$0 { processingError = nil } }
        )) {
            Button("OK") { processingError = nil }
        } message: {
            Text(processingError ?? "")
        }
    }
    
    // MARK: - Processing Overlay
    
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Animated cricket ball
                Image(systemName: "cricket.ball")
                    .font(.system(size: 48))
                    .foregroundColor(DesignSystem.Colors.cricketGreenLight)
                    .rotationEffect(.degrees(processingProgress * 360))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: processingProgress)
                
                Text("Analyzing Your Technique")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(processingStep)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                
                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: processingProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.Colors.cricketGreenLight))
                        .frame(width: 200)
                    
                    Text("\(Int(processingProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                // Step indicators
                VStack(alignment: .leading, spacing: 8) {
                    pipelineStep("Extracting poses", progress: processingProgress, threshold: 0.0)
                    pipelineStep("Detecting phases", progress: processingProgress, threshold: 0.5)
                    pipelineStep("Scoring technique", progress: processingProgress, threshold: 0.75)
                    pipelineStep("Generating results", progress: processingProgress, threshold: 0.9)
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(UIColor.systemBackground).opacity(0.95))
                    .shadow(radius: 20)
            )
            .padding(.horizontal, 32)
        }
    }
    
    private func pipelineStep(_ title: String, progress: Double, threshold: Double) -> some View {
        HStack(spacing: 8) {
            if progress > threshold + 0.15 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if progress >= threshold {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            }
            Text(title)
                .font(.caption)
                .foregroundColor(progress >= threshold ? .primary : .secondary)
        }
    }
    
    // MARK: - Analysis Pipeline
    
    private func startAnalysisPipeline(videoURL: URL) {
        isProcessing = true
        processingProgress = 0
        processingStep = "Preparing video..."
        processingError = nil
        
        Task {
            do {
                // 1. Save video and create session
                let videoService = VideoProcessingService()
                let sessionId = UUID()
                let savedURL = try videoService.saveVideo(videoURL, sessionId: sessionId)
                let videoInfo = try await videoService.getVideoInfo(from: savedURL)
                
                let session = await MainActor.run {
                    storageService.createSession(
                        analysisType: selectedAnalysisType,
                        videoLocalPath: savedURL.path,
                        durationSeconds: videoInfo.duration
                    )
                }
                
                // 2. Pose Estimation (~50% of work)
                await MainActor.run {
                    processingStep = "Extracting body poses from video..."
                    processingProgress = 0.05
                }
                
                let poseService = PoseEstimationService()
                let poseSequence = try await poseService.processVideo(url: savedURL) { progress in
                    Task { @MainActor in
                        processingProgress = 0.05 + progress * 0.45
                    }
                }
                
                await MainActor.run {
                    processingProgress = 0.5
                    processingStep = "Detecting technique phases..."
                }
                
                guard !poseSequence.frames.isEmpty else {
                    throw AnalysisPipelineError.noPoseDetected
                }
                
                // 3. Phase Detection
                let phaseService = PhaseDetectionService()
                let detectedPhases = phaseService.detectPhases(
                    in: poseSequence,
                    analysisType: selectedAnalysisType
                )
                
                await MainActor.run {
                    processingProgress = 0.75
                    processingStep = "Scoring biomechanics..."
                }
                
                guard !detectedPhases.isEmpty else {
                    throw AnalysisPipelineError.noPhasesDetected
                }
                
                // 4. Rule-Based Scoring
                let scoringService = RuleScoringService()
                let techniqueScores = scoringService.scoreAllPhases(
                    phases: detectedPhases,
                    poseSequence: poseSequence,
                    analysisType: selectedAnalysisType
                )
                
                let overallScore = techniqueScores.isEmpty ? 0 :
                    techniqueScores.reduce(0) { $0 + $1.overallScore } / techniqueScores.count
                
                await MainActor.run {
                    processingProgress = 0.9
                    processingStep = "Generating results..."
                }
                
                // 5. Save results to session
                await MainActor.run {
                    session.poseSequence = poseSequence
                    session.detectedPhases = detectedPhases
                    session.techniqueScores = techniqueScores
                    session.overallScore = overallScore
                    session.isProcessing = false
                    
                    // Generate fallback AI feedback (no API call for now)
                    let aiService = AIAnalysisService()
                    let fallback = aiService.generateFallbackFeedback(
                        techniqueScores: techniqueScores,
                        analysisType: selectedAnalysisType
                    )
                    session.aiCoachingResponse = fallback
                    
                    storageService.saveSession(session)
                    storageService.incrementAnalysisCount()
                    
                    processingProgress = 1.0
                    processingStep = "Done!"
                }
                
                // Brief pause so user sees 100%
                try await Task.sleep(nanoseconds: 500_000_000)
                
                await MainActor.run {
                    isProcessing = false
                    completedSession = session
                    showingAnalysis = true
                    loadData()
                }
                
            } catch {
                await MainActor.run {
                    isProcessing = false
                }
                // Delay showing alert to avoid presentation conflict
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    processingError = "Analysis failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - New Analysis Section
    
    private var newAnalysisSection: some View {
        Button(action: { showingNewAnalysis = true }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Analysis")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Record or import a video")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(DesignSystem.Colors.cricketGreenLight)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                    .stroke(DesignSystem.Colors.cricketGreenLight.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Type Selection
    
    private var newAnalysisTypeSelection: some View {
        VStack(spacing: 24) {
            Text("What are you analyzing?")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(AnalysisType.allCases) { type in
                Button(action: {
                    selectedAnalysisType = type
                    showingNewAnalysis = false
                    showingSetupGuide = true
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: type.icon)
                            .font(.system(size: 36))
                            .foregroundColor(DesignSystem.Colors.cricketGreenLight)
                            .frame(width: 60)
                        
                        VStack(alignment: .leading) {
                            Text(type.displayName)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text(type == .batting ? "Analyze your batting technique" : "Analyze your bowling action")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("New Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showingNewAnalysis = false }
            }
        }
    }
    
    // MARK: - Quick Stats
    
    private func quickStatsCard(session: AnalysisSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Score")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(alignment: .bottom, spacing: 16) {
                Text("\(session.overallScore)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.scoreColor(for: session.overallScore))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.overallScore.scoreGrade)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.scoreColor(for: session.overallScore))
                    
                    if sessions.count > 1 {
                        let previousScore = sessions[1].overallScore
                        let diff = session.overallScore - previousScore
                        HStack(spacing: 2) {
                            Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption)
                            Text("\(abs(diff)) pts")
                                .font(.caption)
                        }
                        .foregroundColor(diff >= 0 ? .green : .red)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: session.type.icon)
                    Text(session.type.displayName)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DesignSystem.Colors.cricketGreen.opacity(0.3)))
            }
            
            if let response = session.aiCoachingResponse, let topIssue = response.issues.first {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Focus: \(topIssue.title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    // MARK: - Streak Card
    
    private var streakCard: some View {
        HStack {
            Text("🔥")
                .font(.title)
            Text("\(streak) week streak — keep it up!")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.2), .red.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.cricketGreenLight.opacity(0.6))
            
            Text("No sessions yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Record or import a video of your batting or bowling to get AI-powered coaching feedback.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Start Your First Analysis") {
                showingNewAnalysis = true
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.cricketGreenLight)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    // MARK: - Session History
    
    private var sessionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session History")
                .font(.headline)
            
            ForEach(sessions) { session in
                NavigationLink(destination: AnalysisView(session: session)) {
                    SessionRowView(session: session)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadData() {
        sessions = storageService.getAllSessions()
        streak = storageService.calculateStreak()
    }
}

// MARK: - Analysis Pipeline Error

enum AnalysisPipelineError: LocalizedError {
    case noPoseDetected
    case noPhasesDetected
    case videoNotFound
    
    var errorDescription: String? {
        switch self {
        case .noPoseDetected:
            return "No body pose was detected in the video. Make sure your full body is visible and well lit."
        case .noPhasesDetected:
            return "Could not detect batting/bowling phases. Make sure the video shows a complete shot or delivery."
        case .videoNotFound:
            return "Video file not found."
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: AnalysisSession
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(
                        DesignSystem.Colors.scoreColor(for: session.overallScore).opacity(0.3),
                        lineWidth: 3
                    )
                Circle()
                    .trim(from: 0, to: CGFloat(session.overallScore) / 100)
                    .stroke(
                        DesignSystem.Colors.scoreColor(for: session.overallScore),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                Text("\(session.overallScore)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.scoreColor(for: session.overallScore))
            }
            .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: session.type.icon)
                        .font(.caption)
                    Text(session.type.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if session.isProcessing {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.smallCornerRadius)
                .fill(Color(UIColor.tertiarySystemBackground))
        )
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environmentObject(StorageService())
}

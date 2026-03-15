import SwiftUI

struct AnalysisView: View {
    let session: AnalysisSession
    @EnvironmentObject var storageService: StorageService
    @State private var selectedPhase: PosePhase?
    @State private var showingVideo = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Layout.padding) {
                // Overall Score
                overallScoreSection
                
                // Video Player (if available)
                if let _ = session.videoURL, let _ = session.poseSequence {
                    Button(action: { showingVideo = true }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                            Text("View Video with Skeleton Overlay")
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                            .fill(Color(UIColor.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
                
                // AI Coaching (if available)
                if let ai = session.aiCoachingResponse {
                    aiCoachingSection(ai)
                }
                
                // Phase-by-Phase Scores
                phaseScoresSection
                
                // Next Session Focus
                if let focus = session.aiCoachingResponse?.nextSessionFocus {
                    nextSessionCard(focus)
                }
                
                // User Feedback
                feedbackSection
            }
            .padding(.horizontal)
        }
        .navigationTitle("\(session.type.displayName) Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingVideo) {
            if let url = session.videoURL, let seq = session.poseSequence {
                NavigationStack {
                    SkeletonOverlayView(
                        videoURL: url,
                        poseSequence: seq,
                        detectedPhases: session.detectedPhases,
                        onPhaseSelected: { phase in
                            selectedPhase = phase
                        }
                    )
                    .navigationTitle("Video Analysis")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingVideo = false }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Overall Score
    
    private var overallScoreSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: CGFloat(session.overallScore) / 100)
                    .stroke(DesignSystem.Colors.scoreColor(for: session.overallScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(session.overallScore)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.scoreColor(for: session.overallScore))
                    Text(session.overallScore.scoreGrade)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let assessment = session.aiCoachingResponse?.overallAssessment {
                Text(assessment)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
            .fill(Color(UIColor.secondarySystemBackground)))
    }
    
    // MARK: - AI Coaching
    
    private func aiCoachingSection(_ ai: AICoachingResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Positives
            if !ai.positives.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What You're Doing Well", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    ForEach(ai.positives) { positive in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(positive.title).font(.subheadline).fontWeight(.medium)
                                Text(positive.description).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
                    }
                }
            }
            
            // Issues
            if !ai.issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Top Issues to Fix", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    ForEach(ai.issues) { issue in
                        IssueCardView(issue: issue)
                    }
                }
            }
            
            // Progress Note
            if let note = ai.progressNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.blue)
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
            }
        }
    }
    
    // MARK: - Phase Scores
    
    private var phaseScoresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phase-by-Phase")
                .font(.headline)
            
            ForEach(session.techniqueScores, id: \.id) { score in
                NavigationLink(destination: PhaseDetailView(techniqueScore: score, session: session)) {
                    HStack {
                        Circle().fill(score.phase.color).frame(width: 12, height: 12)
                        Text(score.phase.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(score.overallScore)")
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.scoreColor(for: score.overallScore))
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.tertiarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - User Feedback
    
    @ViewBuilder
    private var feedbackSection: some View {
        if session.userFeedback == nil {
            // Show feedback prompt
            VStack(spacing: 12) {
                Text("Was this analysis helpful?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 24) {
                    Button(action: { submitFeedback(helpful: true) }) {
                        Label("Helpful", systemImage: "hand.thumbsup")
                            .font(.subheadline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { submitFeedback(helpful: false) }) {
                        Label("Not Helpful", systemImage: "hand.thumbsdown")
                            .font(.subheadline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                .fill(Color(UIColor.secondarySystemBackground)))
        } else if let feedback = session.userFeedback {
            // Show thank-you
            HStack {
                Image(systemName: feedback ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .foregroundColor(feedback ? .green : .orange)
                Text(feedback ? "Thanks! Glad it helped." : "Thanks — we'll improve.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
                .fill(Color(UIColor.secondarySystemBackground)))
        }
    }
    
    private func submitFeedback(helpful: Bool) {
        session.userFeedback = helpful
        
        AnalyticsService.track(.feedbackSubmitted, properties: [
            "helpful": helpful,
            "session_id": session.id.uuidString,
            "overall_score": session.overallScore,
            "analysis_type": session.analysisType
        ])
    }
    
    // MARK: - Next Session Card
    
    private func nextSessionCard(_ focus: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Next Session Focus", systemImage: "target")
                .font(.headline)
                .foregroundColor(DesignSystem.Colors.cricketGreenLight)
            Text(focus)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
            .fill(DesignSystem.Colors.cricketGreen.opacity(0.15)))
    }
}

// MARK: - Issue Card

struct IssueCardView: View {
    let issue: IssueFeedback
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text("#\(issue.rank)")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(issue.severityLevel.color))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title).font(.subheadline).fontWeight(.semibold)
                        Text(issue.description).font(.caption).foregroundColor(.secondary).lineLimit(isExpanded ? nil : 2)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Measurement
                    HStack {
                        Text("Measured:").font(.caption).foregroundColor(.secondary)
                        Text(issue.measuredValue).font(.caption).fontWeight(.medium)
                        Spacer()
                        Text("Ideal:").font(.caption).foregroundColor(.secondary)
                        Text(issue.idealValue).font(.caption).fontWeight(.medium).foregroundColor(.green)
                    }
                    
                    // Why it matters
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why it matters").font(.caption).fontWeight(.bold)
                        Text(issue.whyItMatters).font(.caption).foregroundColor(.secondary)
                    }
                    
                    // Drill
                    VStack(alignment: .leading, spacing: 4) {
                        Label(issue.drill.name, systemImage: "figure.walk")
                            .font(.caption).fontWeight(.bold).foregroundColor(DesignSystem.Colors.cricketGreenLight)
                        Text(issue.drill.description).font(.caption).foregroundColor(.secondary)
                        HStack {
                            Label(issue.drill.reps, systemImage: "repeat").font(.caption2)
                            Spacer()
                            Label(issue.drill.frequency, systemImage: "calendar").font(.caption2)
                        }.foregroundColor(.secondary)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(DesignSystem.Colors.cricketGreen.opacity(0.1)))
                    
                    // Target
                    HStack {
                        Image(systemName: "target").foregroundColor(.orange)
                        Text(issue.target).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: DesignSystem.Layout.smallCornerRadius)
            .fill(Color(UIColor.tertiarySystemBackground)))
    }
}

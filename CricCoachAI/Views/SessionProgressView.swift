import SwiftUI
import Charts

struct SessionProgressView: View {
    @EnvironmentObject var storageService: StorageService
    @State private var selectedType: AnalysisType = .batting
    @State private var scoreTrend: [(Date, Int)] = []
    @State private var biggestImprovement: (String, Int)?
    @State private var sessions: [AnalysisSession] = []
    @State private var showingComparison = false
    @State private var session1: AnalysisSession?
    @State private var session2: AnalysisSession?
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Layout.padding) {
                // Type picker
                Picker("Type", selection: $selectedType) {
                    ForEach(AnalysisType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                if sessions.isEmpty {
                    emptyState
                } else {
                    // Overall trend chart
                    if !scoreTrend.isEmpty {
                        trendChart
                    }
                    
                    // Biggest improvement
                    if let (name, points) = biggestImprovement {
                        HStack {
                            Text("🎉")
                            Text("\(name): +\(points) points!")
                                .font(.subheadline).fontWeight(.medium)
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.15)))
                    }
                    
                    // Compare sessions
                    if sessions.count >= 2 {
                        Button(action: { showingComparison = true }) {
                            Label("Compare Sessions", systemImage: "arrow.left.and.right")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Session list
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sessions").font(.headline)
                        ForEach(sessions) { session in
                            NavigationLink(destination: AnalysisView(session: session)) {
                                SessionRowView(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Progress")
        .onChange(of: selectedType) { _, _ in loadData() }
        .onAppear { loadData() }
        .sheet(isPresented: $showingComparison) {
            ComparisonPickerView(sessions: sessions) { s1, s2 in
                session1 = s1
                session2 = s2
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No \(selectedType.displayName.lowercased()) sessions yet")
                .font(.title3).fontWeight(.semibold)
            Text("Complete your first analysis to start tracking progress.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score Trend").font(.headline)
            Chart {
                ForEach(scoreTrend.indices, id: \.self) { i in
                    LineMark(
                        x: .value("Session", i + 1),
                        y: .value("Score", scoreTrend[i].1)
                    )
                    .foregroundStyle(DesignSystem.Colors.cricketGreenLight)
                    
                    PointMark(
                        x: .value("Session", i + 1),
                        y: .value("Score", scoreTrend[i].1)
                    )
                    .foregroundStyle(DesignSystem.Colors.cricketGreenLight)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100])
            }
            .frame(height: 200)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }
    
    private func loadData() {
        sessions = storageService.getSessions(type: selectedType)
        scoreTrend = storageService.getOverallScoreTrend(analysisType: selectedType)
        biggestImprovement = storageService.getBiggestImprovement(analysisType: selectedType)
    }
}

// MARK: - Comparison Picker

struct ComparisonPickerView: View {
    let sessions: [AnalysisSession]
    let onSelect: (AnalysisSession, AnalysisSession) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected1: AnalysisSession?
    @State private var selected2: AnalysisSession?
    
    var body: some View {
        NavigationStack {
            List {
                Section("Select two sessions to compare") {
                    ForEach(sessions) { session in
                        Button(action: { toggleSelection(session) }) {
                            HStack {
                                if selected1?.id == session.id || selected2?.id == session.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                } else {
                                    Image(systemName: "circle").foregroundColor(.secondary)
                                }
                                Text(session.formattedDate)
                                Spacer()
                                Text("\(session.overallScore)")
                                    .foregroundColor(DesignSystem.Colors.scoreColor(for: session.overallScore))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Compare")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Compare") {
                        if let s1 = selected1, let s2 = selected2 {
                            onSelect(s1, s2)
                            dismiss()
                        }
                    }
                    .disabled(selected1 == nil || selected2 == nil)
                }
            }
        }
    }
    
    private func toggleSelection(_ session: AnalysisSession) {
        if selected1?.id == session.id { selected1 = nil }
        else if selected2?.id == session.id { selected2 = nil }
        else if selected1 == nil { selected1 = session }
        else if selected2 == nil { selected2 = session }
        else { selected1 = session; selected2 = nil }
    }
}

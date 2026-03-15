import Foundation

/// Service for loading scoring thresholds — local defaults now, server-fetchable later.
///
/// ## Current behavior
/// Returns `ScoringConfig.default` (matching hardcoded `IdealValues`).
///
/// ## Future behavior (post-Iteration 4)
/// Will fetch from Supabase `scoring_config` table on app launch, with local defaults as fallback.
///
/// ## Usage
/// ```swift
/// let config = await ScoringConfigService.shared.currentConfig
/// let service = RuleScoringService(config: config)  // dependency injection
/// ```
@MainActor
class ScoringConfigService: ObservableObject {
    
    static let shared = ScoringConfigService()
    
    @Published private(set) var currentConfig: ScoringConfig = .default
    @Published private(set) var isLoaded = false
    
    private init() {}
    
    // MARK: - Fetch (Future)
    
    /// Fetch scoring config from Supabase.
    /// Currently returns local defaults. Will add server fetch in a future iteration.
    func fetchConfig() async {
        // TODO: Fetch from Supabase scoring_config table
        // For now, use defaults
        self.currentConfig = .default
        self.isLoaded = true
        
        // Future implementation:
        // let urlString = "\(AppConstants.apiBaseURL)/rest/v1/scoring_config?select=*&order=version.desc&limit=1"
        // guard let url = URL(string: urlString) else { return }
        // var request = URLRequest(url: url)
        // request.setValue("Bearer \(AppConstants.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        // request.setValue(AppConstants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        // request.timeoutInterval = 5
        //
        // do {
        //     let (data, _) = try await URLSession.shared.data(for: request)
        //     let configs = try JSONDecoder().decode([ScoringConfig].self, from: data)
        //     if let latest = configs.first {
        //         self.currentConfig = latest
        //     }
        // } catch {
        //     // Use defaults on failure
        //     print("[ScoringConfig] Fetch failed, using defaults: \(error.localizedDescription)")
        // }
        // self.isLoaded = true
    }
}

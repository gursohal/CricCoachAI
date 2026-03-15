import Foundation

/// Service for fetching and caching feature flags from Supabase.
///
/// Flags are fetched on app launch (non-blocking, ≤5s timeout).
/// If the fetch fails, hardcoded defaults are used so the app works offline.
///
/// ## Usage
/// ```swift
/// // Check a flag:
/// if FeatureFlagService.shared.isAICoachingEnabled { ... }
///
/// // Fetch on launch:
/// await FeatureFlagService.shared.fetchFlags()
/// ```
@MainActor
class FeatureFlagService: ObservableObject {
    
    static let shared = FeatureFlagService()
    
    @Published private(set) var flags: [String: Any] = [:]
    @Published private(set) var isLoaded = false
    @Published private(set) var lastFetchError: String?
    
    /// Hardcoded defaults — used until server responds (or if fetch fails)
    private let defaults: [String: Any] = [
        "ai_coaching_enabled": true,
        "prompt_version": "v1",
        "free_tier_limit": 3,
        "min_app_version": "1.0.0",
        "maintenance_mode": false
    ]
    
    private init() {
        // Start with defaults
        self.flags = defaults
    }
    
    // MARK: - Fetch
    
    /// Fetch feature flags from Supabase. Non-blocking, ≤5s timeout.
    /// Falls back to defaults on any error.
    func fetchFlags() async {
        let urlString = "\(AppConstants.apiBaseURL)/rest/v1/feature_flags?select=key,value"
        guard let url = URL(string: urlString) else {
            self.isLoaded = true
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(AppConstants.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConstants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 5  // Don't block app launch
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw FeatureFlagError.serverError
            }
            
            // Parse the response: [{ "key": "...", "value": ... }, ...]
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw FeatureFlagError.invalidResponse
            }
            
            var parsed: [String: Any] = defaults
            for row in rows {
                if let key = row["key"] as? String {
                    let value = row["value"]
                    // JSONB values come as their native types from Supabase REST API
                    if let val = value {
                        parsed[key] = val
                    }
                }
            }
            
            self.flags = parsed
            self.lastFetchError = nil
            
            AnalyticsService.track(.featureFlagsFetched, properties: [
                "flag_count": parsed.count,
                "ai_coaching_enabled": isAICoachingEnabled,
                "maintenance_mode": isMaintenanceMode,
                "free_tier_limit": freeTierLimit
            ])
            
        } catch {
            // Use defaults on failure — app must work offline
            self.flags = defaults
            self.lastFetchError = error.localizedDescription
            
            AnalyticsService.track(.featureFlagsFailed, properties: [
                "error": error.localizedDescription
            ])
            
            print("[FeatureFlags] Fetch failed, using defaults: \(error.localizedDescription)")
        }
        
        self.isLoaded = true
    }
    
    // MARK: - Typed Accessors
    
    /// Kill switch for AI coaching feature
    var isAICoachingEnabled: Bool {
        boolFlag("ai_coaching_enabled") ?? true
    }
    
    /// Active prompt version for Claude API
    var promptVersion: String {
        stringFlag("prompt_version") ?? "v1"
    }
    
    /// Number of free analyses per month (server-tunable)
    var freeTierLimit: Int {
        intFlag("free_tier_limit") ?? 3
    }
    
    /// Minimum supported app version
    var minimumAppVersion: String {
        stringFlag("min_app_version") ?? "1.0.0"
    }
    
    /// Whether the app is in maintenance mode
    var isMaintenanceMode: Bool {
        boolFlag("maintenance_mode") ?? false
    }
    
    // MARK: - Generic Accessors
    
    /// Get a boolean flag value
    func boolFlag(_ key: String) -> Bool? {
        if let val = flags[key] as? Bool { return val }
        // JSONB booleans may come as Int (0/1) from some REST clients
        if let val = flags[key] as? Int { return val != 0 }
        // Or as String "true"/"false"
        if let val = flags[key] as? String { return val.lowercased() == "true" }
        return nil
    }
    
    /// Get a string flag value
    func stringFlag(_ key: String) -> String? {
        flags[key] as? String
    }
    
    /// Get an integer flag value
    func intFlag(_ key: String) -> Int? {
        if let val = flags[key] as? Int { return val }
        if let val = flags[key] as? Double { return Int(val) }
        if let val = flags[key] as? String, let num = Int(val) { return num }
        return nil
    }
    
    // MARK: - Version Check
    
    /// Check if the current app version meets the minimum required version
    var isAppVersionSupported: Bool {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return true
        }
        return currentVersion.compare(minimumAppVersion, options: .numeric) != .orderedAscending
    }
}

// MARK: - Errors

enum FeatureFlagError: LocalizedError {
    case serverError
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .serverError: return "Feature flags server error"
        case .invalidResponse: return "Invalid feature flags response"
        }
    }
}

import Foundation

// MARK: - Analytics Events

/// All tracked analytics events in the app
enum AnalyticsEvent: String {
    // Recording
    case recordingStarted = "recording_started"
    case recordingCompleted = "recording_completed"
    case videoImported = "video_imported"
    
    // Pose Estimation
    case poseEstimationStarted = "pose_estimation_started"
    case poseEstimationCompleted = "pose_estimation_completed"
    case poseEstimationFailed = "pose_estimation_failed"
    
    // Phase Detection
    case phaseDetectionCompleted = "phase_detection_completed"
    
    // Scoring
    case scoringCompleted = "scoring_completed"
    
    // AI Analysis
    case aiAnalysisStarted = "ai_analysis_started"
    case aiAnalysisCompleted = "ai_analysis_completed"
    case aiAnalysisFailed = "ai_analysis_failed"
    case aiValidationFlags = "ai_validation_flags"
    
    // Subscription
    case paywallViewed = "subscription_paywall_viewed"
    case subscriptionStarted = "subscription_started"
    
    // Sharing
    case sessionShared = "session_shared"
    
    // Feedback
    case feedbackSubmitted = "feedback_submitted"
    
    // Feature Flags
    case featureFlagsFetched = "feature_flags_fetched"
    case featureFlagsFailed = "feature_flags_failed"
    
    // App Lifecycle
    case appLaunched = "app_launched"
    case analysisSessionViewed = "analysis_session_viewed"
}

// MARK: - Analytics Service

/// Unified analytics wrapper — single point of control for all tracking.
///
/// Wraps Sentry (crash/error reporting) and PostHog (product analytics).
/// All analytics calls go through this service so we can:
/// - Swap providers without touching feature code
/// - Disable tracking in tests/previews
/// - Ensure consistent event naming
///
/// ## Setup
/// Call `AnalyticsService.initialize()` once in the app's `init()`.
/// Then use `AnalyticsService.track(...)` and `AnalyticsService.captureError(...)` everywhere.
enum AnalyticsService {
    
    /// Whether analytics is enabled (disabled in tests and previews)
    private static var isEnabled: Bool {
        #if DEBUG
        // Disable in unit tests
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        // Disable in SwiftUI previews
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }
        #endif
        return true
    }
    
    // MARK: - Initialization
    
    /// Initialize Sentry and PostHog SDKs. Call once at app launch.
    static func initialize() {
        guard isEnabled else {
            print("[Analytics] Disabled (test/preview environment)")
            return
        }
        
        // --- Sentry ---
        // TODO: Uncomment when Sentry SPM package is resolved
        // import Sentry
        //
        // SentrySDK.start { options in
        //     options.dsn = AppConstants.sentryDSN
        //     options.tracesSampleRate = 0.2
        //     options.profilesSampleRate = 0.1
        //     options.environment = AppConstants.isProduction ? "production" : "development"
        //     options.enableAutoSessionTracking = true
        //     options.attachScreenshot = true
        //     options.enableMetricKit = true
        // }
        
        // --- PostHog ---
        // TODO: Uncomment when PostHog SPM package is resolved
        // import PostHog
        //
        // let config = PostHogConfig(apiKey: AppConstants.postHogAPIKey)
        // config.host = "https://app.posthog.com"
        // PostHogSDK.shared.setup(config)
        
        print("[Analytics] Initialized (Sentry + PostHog)")
    }
    
    // MARK: - Event Tracking
    
    /// Track a product analytics event with optional properties
    static func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        guard isEnabled else { return }
        
        // PostHog capture
        // PostHogSDK.shared.capture(event.rawValue, properties: properties)
        
        #if DEBUG
        let propsStr = properties.isEmpty ? "" : " \(properties)"
        print("[Analytics] \(event.rawValue)\(propsStr)")
        #endif
    }
    
    // MARK: - Error Tracking
    
    /// Capture an error in Sentry with optional context
    static func captureError(_ error: Error, context: [String: Any] = [:]) {
        guard isEnabled else { return }
        
        // SentrySDK.capture(error: error) { scope in
        //     for (key, value) in context {
        //         scope.setExtra(value: value, key: key)
        //     }
        // }
        
        #if DEBUG
        print("[Analytics] ERROR: \(error.localizedDescription) context=\(context)")
        #endif
    }
    
    /// Capture a non-fatal message in Sentry
    static func captureMessage(_ message: String, level: SentryLevel = .warning, context: [String: Any] = [:]) {
        guard isEnabled else { return }
        
        // SentrySDK.capture(message: message) { scope in
        //     scope.setLevel(level.sentryLevel)
        //     for (key, value) in context {
        //         scope.setExtra(value: value, key: key)
        //     }
        // }
        
        #if DEBUG
        print("[Analytics] MESSAGE [\(level.rawValue)]: \(message)")
        #endif
    }
    
    // MARK: - Performance Tracing
    
    /// Start a performance transaction (returns an opaque token to finish later)
    static func startTransaction(name: String, operation: String) -> PerformanceTransaction {
        let start = CFAbsoluteTimeGetCurrent()
        
        // let span = SentrySDK.startTransaction(name: name, operation: operation)
        
        return PerformanceTransaction(name: name, operation: operation, startTime: start)
    }
    
    /// Finish a performance transaction
    static func finishTransaction(_ transaction: PerformanceTransaction, status: TransactionStatus = .ok) {
        guard isEnabled else { return }
        
        let duration = CFAbsoluteTimeGetCurrent() - transaction.startTime
        
        // transaction.sentrySpan?.finish(status: status.sentryStatus)
        
        #if DEBUG
        print("[Analytics] PERF: \(transaction.name).\(transaction.operation) = \(String(format: "%.1f", duration * 1000))ms [\(status.rawValue)]")
        #endif
    }
    
    // MARK: - User Identification
    
    /// Identify the current user for both Sentry and PostHog
    static func identify(userId: String, properties: [String: Any] = [:]) {
        guard isEnabled else { return }
        
        // SentrySDK.configureScope { scope in
        //     scope.setUser(User(userId: userId))
        // }
        // PostHogSDK.shared.identify(userId, userProperties: properties)
        
        #if DEBUG
        print("[Analytics] Identify: \(userId)")
        #endif
    }
    
    /// Reset user identity (on logout)
    static func reset() {
        guard isEnabled else { return }
        
        // SentrySDK.configureScope { scope in scope.setUser(nil) }
        // PostHogSDK.shared.reset()
        
        #if DEBUG
        print("[Analytics] Reset user identity")
        #endif
    }
}

// MARK: - Supporting Types

/// Opaque token for performance transactions
struct PerformanceTransaction {
    let name: String
    let operation: String
    let startTime: CFAbsoluteTime
    // var sentrySpan: Span?  // Uncomment when Sentry is integrated
}

/// Sentry-compatible severity levels
enum SentryLevel: String {
    case debug
    case info
    case warning
    case error
    case fatal
}

/// Transaction completion status
enum TransactionStatus: String {
    case ok
    case cancelled
    case unknownError = "unknown_error"
    case deadline
}

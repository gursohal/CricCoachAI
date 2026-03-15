# 📋 CricCoach AI — Implementation TODOs

> **Source:** CEO Plan Review (March 15, 2026)  
> **Review Mode:** HOLD SCOPE  
> **Status:** 6 P1 findings + 2 P2 findings to incorporate before building  
> **Last Updated:** March 15, 2026

---

## 🚦 Implementation Status

| # | Finding | Priority | Status | Files Changed |
|---|---------|----------|--------|---------------|
| 3 | Observability (Sentry + PostHog) | P1 | ✅ **DONE** | `AnalyticsService.swift`, `project.yml`, `Constants.swift`, `CricCoachAIApp.swift`, `HomeView.swift`, `RecordingView.swift`, `PaywallView.swift`, `VideoImportView.swift`, `AIAnalysisService.swift`, `SharingService.swift` |
| 5 | Feature Flags / Remote Config | P1 | ✅ **DONE** | `FeatureFlagService.swift`, `002_feature_flags.sql`, `CricCoachAIApp.swift`, `AIAnalysisService.swift` |
| — | GPT-4o → Claude Migration | Cross-cut | ✅ **DONE** | `index.ts` (Edge Function), `AIAnalysisService.swift` |
| 4 | API Versioning | P1 | ✅ **DONE** | `index.ts` (X-API-Version header routing) |
| 1 | Golden Test Dataset | P1 | ✅ **DONE** | `TestVideos/annotations/`, `PhaseDetectionGoldenTests.swift`, `cricket_batting.json` |
| 2 | AI Validation Layer | P1 | ✅ **DONE** | `AIResponseValidator.swift`, wired into `AIAnalysisService.analyzeSession()`, `AIResponseValidatorTests.swift` (14 tests) |
| 6 | Video Normalization | P1 | ✅ **DONE** | `VideoProcessingService.swift` (`normalizeVideo()`), `HomeView.swift` pipeline |
| — | Frame Sampling Rate (10fps) | Cross-cut | ✅ **DONE** | `PoseEstimationService.swift`, `Constants.swift`, `PoseFrame.swift` (interpolation) |
| 7 | User Feedback Mechanism | P2 | ✅ **DONE** | `AnalysisView.swift`, `AnalysisSession.swift`, `003_add_feedback.sql` |
| 8 | Scoring Thresholds Server-Side | P2 | ✅ **DONE** | `ScoringConfig.swift`, `ScoringConfigService.swift` (architecture ready) |

---

## Table of Contents

1. [P1-1: Golden Test Dataset](#p1-1-golden-test-dataset)
2. [P1-2: AI Validation Layer](#p1-2-ai-validation-layer)
3. [P1-3: Observability Setup](#p1-3-observability-setup)
4. [P1-4: API Versioning](#p1-4-api-versioning)
5. [P1-5: Feature Flags / Remote Config](#p1-5-feature-flags--remote-config)
6. [P1-6: Video Normalization](#p1-6-video-normalization)
7. [P2-7: User Feedback Mechanism](#p2-7-user-feedback-mechanism)
8. [P2-8: Scoring Thresholds Server-Side](#p2-8-scoring-thresholds-server-side)
9. [Cross-Cutting: GPT-4o → Claude Migration](#cross-cutting-gpt-4o--claude-migration)
10. [Cross-Cutting: Frame Sampling Rate Change](#cross-cutting-frame-sampling-rate-change)

---

## P1-1: Golden Test Dataset

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Effort** | Large |
| **Iteration** | 2 (before 2.1 — must exist before `PhaseDetectionService` tuning) |
| **Risk Mitigated** | Phase detection is the riskiest module; tuning thresholds without ground truth = debugging by vibes |

### What

Collect and manually annotate **30+ cricket videos** (batting + bowling, multiple styles/angles/conditions) with phase start frame, end frame, and key frame for each phase. This dataset becomes the **regression test suite** for `PhaseDetectionService`.

### Video Requirements

| Category | Minimum Count | Notes |
|----------|--------------|-------|
| Batting — right-hand | 8 | Include drives, pulls, cuts, defensive |
| Batting — left-hand | 4 | Mirror of right-hand phases |
| Bowling — pace (right arm) | 6 | Side-on and chest-on actions |
| Bowling — pace (left arm) | 3 | |
| Bowling — spin | 4 | Off-spin, leg-spin |
| Edge cases — poor lighting | 2 | Indoor nets, dusk |
| Edge cases — partial body visible | 2 | Legs cropped, side angle |
| Edge cases — slow-motion (240fps) | 2 | iPhone slo-mo recordings |

### Annotation Format

Create a JSON annotation file per video:

```json
{
  "video_file": "batting_drive_01.mp4",
  "analysis_type": "batting",
  "source_fps": 30,
  "resolution": "1080x1920",
  "annotations": {
    "stance": { "start_frame": 0, "end_frame": 45, "key_frame": 22 },
    "backlift": { "start_frame": 46, "end_frame": 82, "key_frame": 82 },
    "stride": { "start_frame": 83, "end_frame": 110, "key_frame": 110 },
    "downswing": { "start_frame": 111, "end_frame": 128, "key_frame": 120 },
    "contact": { "start_frame": 129, "end_frame": 135, "key_frame": 132 },
    "batting_follow_through": { "start_frame": 136, "end_frame": 180, "key_frame": 150 }
  },
  "notes": "Textbook cover drive, side-on camera angle, indoor nets"
}
```

### File & Directory Changes

```
NEW   TestVideos/annotations/                          # Directory for annotation JSONs
NEW   TestVideos/annotations/batting_drive_01.json     # One per video
NEW   TestVideos/annotations/bowling_pace_01.json
NEW   TestVideos/README.md                             # How to add/annotate videos
```

> **Note:** `TestVideos/` directory already exists with `cricket_batting.mp4`. Expand it.

### Test Infrastructure

Create test cases in `CricCoachAITests/` that:

1. Load each annotated video
2. Run `PoseEstimationService.processVideo()` → `PhaseDetectionService.detectPhases()`
3. Compare detected phases against ground truth annotations
4. Assert: each detected phase's `keyFrame` is within ±5 frames of annotation
5. Assert: no phases are missed (recall ≥ 90%)
6. Assert: no false phases are injected (precision ≥ 85%)

```
NEW   CricCoachAITests/PhaseDetectionGoldenTests.swift
EDIT  CricCoachAITests/CricCoachAITests.swift          # Import shared test helpers
```

### Acceptance Criteria

- [ ] 30+ videos collected and stored in `TestVideos/`
- [ ] Each video has a corresponding annotation JSON
- [ ] `PhaseDetectionGoldenTests` passes with ≥90% recall, ≥85% precision
- [ ] Tests run in CI (even if slow — mark as integration tests)

---

## P1-2: AI Validation Layer

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Effort** | Medium |
| **Iteration** | 3 (after AI integration, before UI display) |
| **Risk Mitigated** | One viral screenshot of wrong coaching advice destroys trust permanently |

### What

A post-processing module that parses Claude's coaching JSON response and cross-references every `measured_value` claim against the **actual pose data** that was sent. Flag or discard claims that contradict measurements by >20%.

### Why This Is Critical

Claude (or any LLM) can hallucinate specific numbers. The system prompt asks it to reference measured angles, but it may:
- Invent an angle that wasn't in the data ("your elbow is 45°" when it's actually 120°)
- Flip a value ("head moved 2 inches to leg-side" when it moved to off-side)
- Reference a checkpoint that doesn't exist in the rule scores

The app **already has the ground truth** — it sends measured angles and rule scores to Claude. The validation layer simply checks that Claude's response is consistent with what was sent.

### Architecture

```
AIAnalysisService.analyzeSession()
  → sendToBackend(payload)
  → receives AICoachingResponse
  → AIResponseValidator.validate(response, against: payload)  ← NEW
  → returns validated/cleaned AICoachingResponse
  → UI displays it
```

### File Changes

```
NEW   CricCoachAI/Services/AIResponseValidator.swift
EDIT  CricCoachAI/Services/AIAnalysisService.swift
NEW   CricCoachAITests/AIResponseValidatorTests.swift
```

### `AIResponseValidator.swift` — Detailed Design

```swift
import Foundation

/// Validates AI coaching responses against actual measured pose data
/// to catch hallucinated or contradictory claims
struct AIResponseValidator {

    struct ValidationResult {
        let cleanedResponse: AICoachingResponse
        let flaggedIssues: [ValidationFlag]
        let wasModified: Bool
    }

    struct ValidationFlag {
        let field: String          // e.g., "issues[0].measured_value"
        let claimedValue: String   // What Claude said
        let actualValue: String    // What the pose data shows
        let deviationPercent: Double
        let action: FlagAction     // .kept, .corrected, .removed
    }

    enum FlagAction: String {
        case kept       // Deviation < 20%, kept as-is
        case corrected  // Deviation 20-50%, replaced with actual value
        case removed    // Deviation > 50% or unparseable, issue removed
    }

    // MARK: - Main Validation

    /// Validate and clean an AI response against the payload that was sent
    static func validate(
        response: AICoachingResponse,
        against payload: AnalysisPayload,
        techniqueScores: [TechniqueScore]
    ) -> ValidationResult {
        // Implementation steps:
        // 1. Build a lookup of actual measured values from payload
        // 2. For each issue in response.issues:
        //    a. Parse the measured_value string for numeric values
        //    b. Find the corresponding actual measurement
        //    c. Compare: if deviation > 20%, flag it
        //    d. If deviation > 50%, remove the issue entirely
        //    e. If deviation 20-50%, replace measured_value with actual
        // 3. Validate overall_score is within ±10 of rule-based average
        // 4. Validate phase references exist in the detected phases
        // 5. Return cleaned response + list of flags for logging
    }

    // MARK: - Helpers

    /// Extract numeric values from a string like "45.2° elbow angle"
    static func extractNumericValue(from text: String) -> Double? { ... }

    /// Find the actual measurement for a given issue's phase and description
    static func findActualMeasurement(
        phase: String,
        issueTitle: String,
        payload: AnalysisPayload,
        techniqueScores: [TechniqueScore]
    ) -> Double? { ... }

    /// Calculate deviation percentage between claimed and actual
    static func deviationPercent(claimed: Double, actual: Double) -> Double { ... }
}
```

### Changes to `AIAnalysisService.swift`

In the `analyzeSession()` method, add validation between receiving the response and returning it:

```swift
// CURRENT (line ~25 in analyzeSession):
let response = try await sendToBackend(payload: payload)
return response

// CHANGE TO:
let response = try await sendToBackend(payload: payload)

// Validate AI claims against actual pose data
let validationResult = AIResponseValidator.validate(
    response: response,
    against: payload,
    techniqueScores: techniqueScores
)

// Log any flags for observability (P1-3)
if !validationResult.flaggedIssues.isEmpty {
    // TODO: Send to analytics (PostHog/Sentry)
    print("[AIValidator] \(validationResult.flaggedIssues.count) claims flagged")
    for flag in validationResult.flaggedIssues {
        print("  - \(flag.field): claimed=\(flag.claimedValue), actual=\(flag.actualValue), deviation=\(flag.deviationPercent)%, action=\(flag.action.rawValue)")
    }
}

return validationResult.cleanedResponse
```

### Validation Rules (Specific)

| Check | Threshold | Action |
|-------|-----------|--------|
| Issue `measured_value` vs actual angle | ≤20% deviation | Keep as-is |
| Issue `measured_value` vs actual angle | 20-50% deviation | Replace with actual value, keep issue |
| Issue `measured_value` vs actual angle | >50% deviation | Remove entire issue, log |
| `overall_score` vs rule-based average | ≤10 points | Keep |
| `overall_score` vs rule-based average | >10 points | Replace with rule-based average |
| Issue references non-existent `phase` | — | Remove issue |
| `positives` reference non-existent checkpoint | — | Remove positive |
| Total issues after validation < 1 | — | Fall back to `generateFallbackFeedback()` |

### Acceptance Criteria

- [ ] `AIResponseValidator.swift` exists and compiles
- [ ] All issues with >50% deviation are removed before reaching UI
- [ ] Overall score is capped to ±10 of rule-based average
- [ ] 10+ unit tests covering each validation rule
- [ ] Validation flags are logged (ready for Sentry/PostHog integration)
- [ ] Fallback to rule-based feedback if all AI issues are removed

---

## P1-3: Observability Setup

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Effort** | Small |
| **Iteration** | 1.1 (Project Setup — instrument from day one) |
| **Risk Mitigated** | ML-adjacent app with zero observability = flying blind in production |

### What

Integrate **Sentry** (crash reporting + error tracking) and **PostHog** (product analytics) into the app from the very first build.

### Why Both

- **Sentry**: Crashes, exceptions, performance traces. Tells you *what broke*.
- **PostHog**: User behavior, feature usage, funnel analysis. Tells you *what's working*.

> PostHog chosen over Mixpanel because it has a generous free tier (1M events/mo) and can self-host later. Swap for Mixpanel if preferred — the interface is the same.

### Package Dependencies

Add to `project.yml` under `CricCoachAI` target:

```yaml
# project.yml additions
packages:
  Sentry:
    url: https://github.com/getsentry/sentry-cocoa
    from: "8.0.0"
  PostHog:
    url: https://github.com/PostHog/posthog-ios
    from: "3.0.0"
```

### File Changes

```
EDIT  project.yml                                      # Add SPM dependencies
NEW   CricCoachAI/Services/AnalyticsService.swift      # Unified analytics wrapper
EDIT  CricCoachAI/App/CricCoachAIApp.swift             # Initialize SDKs on launch
EDIT  CricCoachAI/Utilities/Constants.swift             # Add DSN + API keys
EDIT  CricCoachAI/Services/AIAnalysisService.swift      # Add analytics events
EDIT  CricCoachAI/Services/PoseEstimationService.swift  # Add analytics events
EDIT  CricCoachAI/Services/PhaseDetectionService.swift  # Add analytics events
EDIT  CricCoachAI/Services/VideoProcessingService.swift # Add analytics events
EDIT  CricCoachAI/Views/RecordingView.swift             # Track recording events
EDIT  CricCoachAI/Views/PaywallView.swift               # Track subscription funnel
```

### `AnalyticsService.swift` — Design

```swift
import Foundation
import SentrySwift   // or import Sentry
import PostHog

/// Unified analytics wrapper — single point of control for all tracking
enum AnalyticsService {

    // MARK: - Initialization

    static func initialize() {
        // Sentry
        SentrySDK.start { options in
            options.dsn = AppConstants.sentryDSN
            options.tracesSampleRate = 0.2  // 20% of transactions
            options.profilesSampleRate = 0.1
            options.environment = AppConstants.isProduction ? "production" : "development"
            options.enableAutoSessionTracking = true
            options.attachScreenshot = true
        }

        // PostHog
        let config = PostHogConfig(apiKey: AppConstants.postHogAPIKey)
        config.host = "https://app.posthog.com"  // or self-hosted
        PostHogSDK.shared.setup(config)
    }

    // MARK: - Event Tracking

    static func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    // MARK: - Error Tracking

    static func captureError(_ error: Error, context: [String: Any] = [:]) {
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setExtra(value: value, key: key)
            }
        }
    }

    // MARK: - Performance

    static func startTransaction(name: String, operation: String) -> any SpanProtocol {
        return SentrySDK.startTransaction(name: name, operation: operation)
    }

    // MARK: - User Identification

    static func identify(userId: String, properties: [String: Any] = [:]) {
        SentrySDK.configureScope { scope in
            scope.setUser(User(userId: userId))
        }
        PostHogSDK.shared.identify(userId, userProperties: properties)
    }
}
```

### Events to Track

| Event Name | When | Properties |
|------------|------|------------|
| `recording_started` | User taps record | `analysis_type` |
| `recording_completed` | Recording stops | `duration_seconds`, `analysis_type` |
| `video_imported` | User imports from camera roll | `duration_seconds`, `source_fps`, `resolution` |
| `pose_estimation_started` | Processing begins | `frame_count`, `video_duration` |
| `pose_estimation_completed` | Processing done | `frame_count`, `valid_frames`, `filtered_frames`, `duration_ms` |
| `pose_estimation_failed` | Processing error | `error`, `frame_count` |
| `phase_detection_completed` | Phases detected | `phase_count`, `analysis_type`, `confidence_avg` |
| `scoring_completed` | Rule scoring done | `overall_score`, `phase_scores`, `analysis_type` |
| `ai_analysis_started` | API call initiated | `analysis_type`, `key_frame_count` |
| `ai_analysis_completed` | API response received | `latency_ms`, `overall_score`, `issue_count` |
| `ai_analysis_failed` | API error | `error_type`, `status_code` |
| `ai_validation_flags` | Validator found issues | `flag_count`, `removed_count`, `corrected_count` |
| `subscription_paywall_viewed` | Paywall shown | `trigger` |
| `subscription_started` | User subscribes | `plan`, `price` |
| `session_shared` | User shares analysis | `platform` |
| `feedback_submitted` | User taps 👍/👎 (P2-7) | `helpful`, `session_id`, `overall_score` |

### Constants Additions (`Constants.swift`)

```swift
// MARK: - Observability
static let sentryDSN = "https://YOUR_KEY@o0.ingest.sentry.io/0"
static let postHogAPIKey = "phc_YOUR_KEY"
static let isProduction = false  // Toggle for release builds
```

### App Entry Point Changes (`CricCoachAIApp.swift`)

```swift
@main
struct CricCoachAIApp: App {
    @StateObject private var storageService = StorageService()

    init() {
        AnalyticsService.initialize()  // ← ADD THIS
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageService)
                .modelContainer(storageService.modelContainer)
                .preferredColorScheme(.dark)
        }
    }
}
```

### Acceptance Criteria

- [ ] Sentry SDK initializes on app launch (verify in Sentry dashboard)
- [ ] PostHog SDK initializes on app launch (verify in PostHog dashboard)
- [ ] All events in the table above fire at the correct times
- [ ] Crashes appear in Sentry within 30 seconds
- [ ] No analytics code leaks outside `AnalyticsService` (single wrapper)
- [ ] Analytics disabled in unit tests / previews

---

## P1-4: API Versioning

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Effort** | Trivial |
| **Iteration** | 3 (Backend specification) |
| **Risk Mitigated** | iOS apps can't be force-updated; 3+ app versions will hit the API simultaneously |

### What

All API endpoints use `/api/v1/` prefix. When prompt/response format changes, deploy `v2` alongside `v1`.

### Current State (Problem)

The current endpoint path in `Constants.swift`:
```swift
static let analyzeEndpoint = "/functions/v1/analyze"
```

This uses Supabase's internal function versioning (`/functions/v1/`), **not** application-level API versioning. When the prompt or response schema changes, all older app versions break instantly.

The Edge Function in `Backend/supabase/functions/analyze/index.ts` serves a single response format with no version awareness.

### File Changes

```
EDIT  CricCoachAI/Utilities/Constants.swift
RENAME Backend/supabase/functions/analyze/ → Backend/supabase/functions/v1-analyze/
EDIT  Backend/supabase/functions/v1-analyze/index.ts
NEW   Backend/supabase/migrations/002_api_versioning.sql  (optional — for logging)
```

### iOS Changes (`Constants.swift`)

```swift
// CURRENT:
static let analyzeEndpoint = "/functions/v1/analyze"

// CHANGE TO:
static let apiVersion = "v1"
static let analyzeEndpoint = "/functions/v1/v1-analyze"  // Supabase function name includes version
```

> **Alternative approach (cleaner):** Use a single Edge Function that reads an `X-API-Version` header:

```swift
// Constants.swift
static let apiVersion = "v1"
static let analyzeEndpoint = "/functions/v1/analyze"

// AIAnalysisService.swift — in sendToBackend():
request.setValue(AppConstants.apiVersion, forHTTPHeaderField: "X-API-Version")
```

### Backend Changes (`index.ts`)

Add version routing at the top of the handler:

```typescript
// At the top of the request handler, after auth check:
const apiVersion = req.headers.get("X-API-Version") || "v1";

if (apiVersion === "v1") {
  return handleV1(payload, user);
} else if (apiVersion === "v2") {
  return handleV2(payload, user);  // Future: new prompt, new response schema
} else {
  return new Response(
    JSON.stringify({ error: `Unsupported API version: ${apiVersion}` }),
    { status: 400 }
  );
}
```

### Versioning Contract

| Version | Prompt | Response Schema | Status |
|---------|--------|----------------|--------|
| `v1` | Initial Claude prompt | `AICoachingResponse` as-is | Active |
| `v2` | (future) | (future) | Not yet |

**Rule:** `v1` endpoint NEVER changes its response schema after the first App Store release. New schema = new version.

### Acceptance Criteria

- [ ] All API requests include `X-API-Version: v1` header
- [ ] Edge Function routes based on version header
- [ ] Unrecognized versions return `400 Bad Request`
- [ ] Old app versions (v1) continue working when v2 is deployed

---

## P1-5: Feature Flags / Remote Config

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Effort** | Small |
| **Iteration** | 1.1 (infrastructure), 3 (AI flag usage) |
| **Risk Mitigated** | iOS apps can't be rolled back; feature flags ARE the rollback mechanism |

### What

A `feature_flags` table in Supabase polled on app launch. Minimum flags:

| Flag Key | Type | Default | Purpose |
|----------|------|---------|---------|
| `ai_coaching_enabled` | `bool` | `true` | Kill switch if Claude API is flaky post-launch |
| `prompt_version` | `string` | `"v1"` | Switch prompts without app update |
| `free_tier_limit` | `int` | `3` | Adjust free analyses/month server-side |
| `min_app_version` | `string` | `"1.0.0"` | Force-upgrade gate (show "please update" if below) |
| `maintenance_mode` | `bool` | `false` | Show maintenance banner, disable analysis |

### Database Changes

```
NEW  Backend/supabase/migrations/002_feature_flags.sql
```

```sql
-- Feature flags table (public read, admin write)
CREATE TABLE IF NOT EXISTS feature_flags (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed default values
INSERT INTO feature_flags (key, value, description) VALUES
  ('ai_coaching_enabled', 'true', 'Kill switch for AI coaching feature'),
  ('prompt_version', '"v1"', 'Active prompt version for Claude API'),
  ('free_tier_limit', '3', 'Number of free analyses per month'),
  ('min_app_version', '"1.0.0"', 'Minimum supported app version'),
  ('maintenance_mode', 'false', 'Show maintenance banner and disable analysis')
ON CONFLICT (key) DO NOTHING;

-- RLS: Anyone can read, only service role can write
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read feature flags" ON feature_flags
  FOR SELECT USING (true);

-- No INSERT/UPDATE/DELETE policies for anon — admin only via dashboard/service key
```

### iOS File Changes

```
NEW   CricCoachAI/Services/FeatureFlagService.swift
EDIT  CricCoachAI/App/CricCoachAIApp.swift             # Fetch flags on launch
EDIT  CricCoachAI/Services/AIAnalysisService.swift      # Check ai_coaching_enabled
EDIT  CricCoachAI/Utilities/Constants.swift             # Use flag for free tier limit
```

### `FeatureFlagService.swift` — Design

```swift
import Foundation

/// Service for fetching and caching feature flags from Supabase
@MainActor
class FeatureFlagService: ObservableObject {

    static let shared = FeatureFlagService()

    @Published private(set) var flags: [String: Any] = [:]
    @Published private(set) var isLoaded = false

    // Defaults (used until server responds)
    private let defaults: [String: Any] = [
        "ai_coaching_enabled": true,
        "prompt_version": "v1",
        "free_tier_limit": 3,
        "min_app_version": "1.0.0",
        "maintenance_mode": false
    ]

    // MARK: - Fetch

    func fetchFlags() async {
        let url = URL(string: "\(AppConstants.apiBaseURL)/rest/v1/feature_flags?select=key,value")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(AppConstants.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConstants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 5  // Don't block app launch

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let rows = try JSONDecoder().decode([[String: AnyCodable]].self, from: data)
            var parsed: [String: Any] = defaults
            for row in rows {
                if let key = row["key"]?.value as? String,
                   let value = row["value"]?.value {
                    parsed[key] = value
                }
            }
            self.flags = parsed
        } catch {
            // Use defaults on failure — app must work offline
            self.flags = defaults
            print("[FeatureFlags] Fetch failed, using defaults: \(error.localizedDescription)")
        }
        self.isLoaded = true
    }

    // MARK: - Typed Accessors

    var isAICoachingEnabled: Bool {
        flags["ai_coaching_enabled"] as? Bool ?? true
    }

    var promptVersion: String {
        flags["prompt_version"] as? String ?? "v1"
    }

    var freeTierLimit: Int {
        flags["free_tier_limit"] as? Int ?? 3
    }

    var minimumAppVersion: String {
        flags["min_app_version"] as? String ?? "1.0.0"
    }

    var isMaintenanceMode: Bool {
        flags["maintenance_mode"] as? Bool ?? false
    }
}
```

### App Launch Integration (`CricCoachAIApp.swift`)

```swift
@main
struct CricCoachAIApp: App {
    @StateObject private var storageService = StorageService()
    @StateObject private var featureFlags = FeatureFlagService.shared  // ← ADD

    init() {
        AnalyticsService.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageService)
                .environmentObject(featureFlags)          // ← ADD
                .modelContainer(storageService.modelContainer)
                .preferredColorScheme(.dark)
                .task {
                    await featureFlags.fetchFlags()       // ← ADD
                }
        }
    }
}
```

### AI Service Integration (`AIAnalysisService.swift`)

```swift
// In analyzeSession(), before calling sendToBackend():
guard FeatureFlagService.shared.isAICoachingEnabled else {
    // AI coaching disabled server-side — return fallback
    return generateFallbackFeedback(
        techniqueScores: techniqueScores,
        analysisType: analysisType
    )
}
```

### Free Tier Integration

Wherever `AppConstants.freeAnalysesPerMonth` is currently used (in `Constants.swift` and `UserProfile`), replace with:
```swift
FeatureFlagService.shared.freeTierLimit
```

### Acceptance Criteria

- [ ] `feature_flags` table exists in Supabase with seed data
- [ ] Flags are fetched on app launch (non-blocking, ≤5s timeout)
- [ ] App works with defaults if fetch fails (offline support)
- [ ] Flipping `ai_coaching_enabled` to `false` in Supabase immediately disables AI coaching
- [ ] `free_tier_limit` change in Supabase reflects in-app on next launch
- [ ] `maintenance_mode` shows a banner and disables new analyses

---

## P1-6: Video Normalization

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Effort** | Small |
| **Iteration** | 1.2 (Video Input Module — after capture/import, before processing) |
| **Risk Mitigated** | iPhones record at 24/30/60/120/240fps; slow-mo breaks sampling AND phase detection velocity thresholds |

### What

All imported/recorded video is normalized to **1080p @ 30fps** before pose processing using AVFoundation frame rate conversion. One canonical format means all downstream code works without conditional FPS branches.

### Current State (Problem)

1. **`VideoProcessingService.extractFrames()`** accepts `fps: Double = 30` but doesn't convert — it just *skips frames* to approximate the target FPS. A 240fps video still decodes all 240 frames/second and skips 7 of every 8.

2. **`PoseEstimationService.processVideo()`** has `targetAnalysisFPS = 15` and does frame skipping similarly. With a 240fps input, the timestamp math works but velocity calculations in `PhaseDetectionService` are wrong because the time between sampled frames is inconsistent.

3. **`PhaseDetectionService`** uses hardcoded velocity thresholds (`0.02`, `0.01`, etc.) that assume ~30fps input. At 240fps with frame skipping, the inter-frame time varies and these thresholds break.

### Solution

Add a **normalization step** using `AVAssetExportSession` that re-encodes the video to 30fps before any processing. This is a one-time cost that prevents cascading bugs.

### File Changes

```
EDIT  CricCoachAI/Services/VideoProcessingService.swift   # Add normalizeVideo() method
EDIT  CricCoachAI/Services/PoseEstimationService.swift    # Call normalize before processing
NEW   CricCoachAITests/VideoNormalizationTests.swift      # Test with different FPS inputs
```

### `VideoProcessingService.swift` — New Method

```swift
// MARK: - Video Normalization

/// Normalize video to 1080p @ 30fps
/// This ensures consistent frame timing for phase detection velocity thresholds
func normalizeVideo(from sourceURL: URL, sessionId: UUID) async throws -> URL {
    let asset = AVURLAsset(url: sourceURL)

    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
        throw VideoProcessingError.noVideoTrack
    }

    let frameRate = try await videoTrack.load(.nominalFrameRate)
    let naturalSize = try await videoTrack.load(.naturalSize)

    // Skip normalization if already 30fps and ≤1080p
    let needsFPSConversion = abs(Double(frameRate) - 30.0) > 1.0
    let needsResize = max(naturalSize.width, naturalSize.height) > 1920
    guard needsFPSConversion || needsResize else {
        return sourceURL  // Already normalized
    }

    // Create output URL
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let normalizedDir = documentsPath.appendingPathComponent("normalized", isDirectory: true)
    try FileManager.default.createDirectory(at: normalizedDir, withIntermediateDirectories: true)
    let outputURL = normalizedDir.appendingPathComponent("\(sessionId.uuidString)_normalized.mp4")

    // Remove existing file if needed
    if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
    }

    // Use AVAssetReader + AVAssetWriter for precise FPS control
    // AVAssetExportSession doesn't give us frame rate control
    let composition = AVMutableComposition()
    guard let compositionTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        throw VideoProcessingError.cannotReadVideo
    }

    let duration = try await asset.load(.duration)
    try compositionTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: duration),
        of: videoTrack,
        at: .zero
    )

    // Scale time to 30fps
    let targetFrameDuration = CMTime(value: 1, timescale: 30)
    compositionTrack.scaleTimeRange(
        CMTimeRange(start: .zero, duration: duration),
        toDuration: duration  // keep same duration, just resample
    )

    guard let exportSession = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPreset1920x1080
    ) else {
        throw VideoProcessingError.cannotReadVideo
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true

    await exportSession.export()

    guard exportSession.status == .completed else {
        throw VideoProcessingError.cannotReadVideo
    }

    return outputURL
}
```

### Integration Point

In the main analysis pipeline (wherever video processing begins), add normalization as the first step:

```swift
// Before:
let poseSequence = try await poseEstimationService.processVideo(url: videoURL)

// After:
let normalizedURL = try await videoProcessingService.normalizeVideo(
    from: videoURL, sessionId: session.id
)
let poseSequence = try await poseEstimationService.processVideo(url: normalizedURL)
```

### Cleanup

Add normalized video cleanup to `deleteSessionFiles()`:

```swift
// In deleteSessionFiles(sessionId:):
let normalizedPath = documentsPath
    .appendingPathComponent("normalized")
    .appendingPathComponent("\(sessionId.uuidString)_normalized.mp4")
if FileManager.default.fileExists(atPath: normalizedPath.path) {
    try FileManager.default.removeItem(at: normalizedPath)
}
```

### Acceptance Criteria

- [ ] 240fps slo-mo video is converted to 30fps before processing
- [ ] 60fps video is converted to 30fps
- [ ] 30fps video passes through without re-encoding (fast path)
- [ ] 4K video is downscaled to 1080p
- [ ] Phase detection velocity thresholds work correctly with normalized video
- [ ] Normalized temp files are cleaned up when session is deleted

---

## P2-7: User Feedback Mechanism

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Effort** | Small |
| **Iteration** | 3.3 (Analysis Results UI) |
| **Risk Mitigated** | Phase detection producing *wrong* phases is undetectable without user signal |

### What

A "Was this analysis helpful? 👍/👎" prompt shown after each AI coaching result. Flagged sessions (👎) are stored for review to improve phase detection and prompt quality.

### File Changes

```
EDIT  CricCoachAI/Views/AnalysisView.swift              # Add feedback prompt
EDIT  CricCoachAI/Models/AnalysisSession.swift           # Add feedback field
EDIT  Backend/supabase/migrations/001_initial_schema.sql  # Add feedback column
      (or NEW 003_add_feedback.sql)
```

### UI Change (`AnalysisView.swift`)

Add at the bottom of the `ScrollView`, after the "Next Session Focus" card:

```swift
// Feedback prompt — only show after AI analysis is complete
if session.isAIAnalysisComplete && session.userFeedback == nil {
    feedbackPrompt
}

// If already submitted
if let feedback = session.userFeedback {
    HStack {
        Image(systemName: feedback ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
            .foregroundColor(feedback ? .green : .orange)
        Text(feedback ? "Thanks! Glad it helped." : "Thanks — we'll improve.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}
```

```swift
private var feedbackPrompt: some View {
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

            Button(action: { submitFeedback(helpful: false) }) {
                Label("Not Helpful", systemImage: "hand.thumbsdown")
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
        }
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: DesignSystem.Layout.cornerRadius)
        .fill(Color(UIColor.secondarySystemBackground)))
}

private func submitFeedback(helpful: Bool) {
    session.userFeedback = helpful
    try? storageService.modelContext.save()

    AnalyticsService.track(.feedbackSubmitted, properties: [
        "helpful": helpful,
        "session_id": session.id.uuidString,
        "overall_score": session.overallScore,
        "analysis_type": session.analysisType
    ])
}
```

### Model Change (`AnalysisSession.swift`)

Add a new property to the `AnalysisSession` SwiftData model:

```swift
var userFeedback: Bool?  // nil = not submitted, true = helpful, false = not helpful
```

### Database Change

```sql
-- Migration 003: Add user feedback
ALTER TABLE analysis_sessions ADD COLUMN user_feedback BOOLEAN DEFAULT NULL;
```

### Acceptance Criteria

- [ ] Feedback prompt appears after AI analysis completes
- [ ] 👍/👎 is persisted locally (SwiftData) and tracked in analytics
- [ ] Prompt disappears after submission, replaced with thank-you text
- [ ] 👎 sessions can be queried in PostHog for review

---

## P2-8: Scoring Thresholds Server-Side

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Effort** | Medium |
| **Iteration** | Post-Iteration 4 (but architecture should support it now) |
| **Risk Mitigated** | Iterating on scoring accuracy requires app updates (1-3 day App Store review) if thresholds are hardcoded |

### What

Move hardcoded angle thresholds from `Constants.swift` → `IdealValues` enum to a Supabase table or JSON config fetched on app launch. This enables same-day tuning without app updates.

### Current State

All thresholds are in `CricCoachAI/Utilities/Constants.swift` under the `IdealValues` enum — approximately 30+ hardcoded values like:

```swift
static let kneeBendRange: ClosedRange<Double> = 160...175  // degrees
static let frontLegBraceRange: ClosedRange<Double> = 160...180
static let armAngleFromVerticalMax: Double = 15
```

These values are referenced in `RuleScoringService.swift` throughout every `score*()` method.

### Architectural Preparation (Do Now)

Even if the full migration is deferred, **prepare the architecture now** by:

1. Defining a `ScoringConfig` struct that mirrors `IdealValues`
2. Adding a `ScoringConfigService` that loads from local defaults, overridable by server
3. Updating `RuleScoringService` to accept config injection instead of reading `IdealValues` directly

### File Changes (Architecture Only — Do Now)

```
NEW   CricCoachAI/Models/ScoringConfig.swift       # Codable struct mirroring IdealValues
NEW   CricCoachAI/Services/ScoringConfigService.swift  # Loads config (local → server)
EDIT  CricCoachAI/Services/RuleScoringService.swift    # Accept ScoringConfig parameter
```

### `ScoringConfig.swift` — Sketch

```swift
/// Server-overridable scoring thresholds
/// Default values match current IdealValues in Constants.swift
struct ScoringConfig: Codable {
    struct BattingStance: Codable {
        var feetWidthMin: Double = 1.0
        var feetWidthMax: Double = 1.3
        var kneeBendMin: Double = 160
        var kneeBendMax: Double = 175
        var headAlignmentThreshold: Double = 0.05
        // ... all current IdealValues.BattingStance fields
    }

    struct BowlingRelease: Codable {
        var armAngleFromVerticalMax: Double = 15
        var frontLegBraceMin: Double = 160
        var frontLegBraceMax: Double = 180
        var hipShoulderSeparationMin: Double = 30
        var hipShoulderSeparationMax: Double = 50
        // ... all current IdealValues.BowlingRelease fields
    }

    var battingStance: BattingStance = .init()
    var bowlingRelease: BowlingRelease = .init()
    // ... one sub-struct per phase

    /// Version tag for cache invalidation
    var version: String = "1.0"
}
```

### File Changes (Full Migration — Do Later)

```
NEW   Backend/supabase/migrations/004_scoring_config.sql
EDIT  CricCoachAI/Services/ScoringConfigService.swift   # Add Supabase fetch
EDIT  CricCoachAI/Services/RuleScoringService.swift     # Use injected config everywhere
```

### Acceptance Criteria (Architecture Phase)

- [ ] `ScoringConfig` struct exists with all current thresholds as defaults
- [ ] `RuleScoringService` can accept a `ScoringConfig` (dependency injection)
- [ ] Current behavior unchanged (defaults match existing `IdealValues`)
- [ ] Adding server fetch later requires no changes to `RuleScoringService`

---

## Cross-Cutting: GPT-4o → Claude Migration

| Field | Value |
|-------|-------|
| **Priority** | P1 (Decision #5) |
| **Effort** | Small |
| **Touches** | Backend, README, Constants |

### What

The CEO decided to use **Claude (Anthropic)** instead of GPT-4o for AI coaching. All references must be updated.

### File Changes

```
EDIT  Backend/supabase/functions/analyze/index.ts    # Switch API call from OpenAI to Anthropic
EDIT  README.md                                       # Update all GPT-4o references
EDIT  CricCoachAI/Utilities/Constants.swift           # Update comments
```

### Backend Changes (`index.ts`)

Replace the OpenAI API call with Anthropic's Messages API:

```typescript
// CURRENT:
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;
// ...
const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", { ... });

// CHANGE TO:
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
// ...
const claudeResponse = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: {
    "x-api-key": ANTHROPIC_API_KEY,
    "anthropic-version": "2023-06-01",
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    model: "claude-sonnet-4-20250514",
    max_tokens: 2000,
    system: SYSTEM_PROMPT,
    messages: [
      {
        role: "user",
        content: userContent  // Same content array with text + images
      }
    ],
    temperature: 0.3,
  }),
});
```

> **Note:** Claude uses `content` blocks with `type: "image"` using base64, similar to GPT-4o Vision but with slightly different format. The image blocks become:
> ```json
> { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": "..." } }
> ```

### Environment Variable Change

```bash
# Remove:
supabase secrets set OPENAI_API_KEY=sk-...
# Add:
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```

### README Changes

Replace all instances of:
- "GPT-4o" → "Claude"  
- "GPT-4o Vision" → "Claude Vision"
- "OpenAI" → "Anthropic"
- "OpenAI API key" → "Anthropic API key"

### Acceptance Criteria

- [ ] Edge Function calls Anthropic API instead of OpenAI
- [ ] Response parsing handles Claude's response format
- [ ] README has zero references to GPT-4o or OpenAI
- [ ] `ANTHROPIC_API_KEY` environment variable set in Supabase

---

## Cross-Cutting: Frame Sampling Rate Change

| Field | Value |
|-------|-------|
| **Priority** | P1 (Decision #1) |
| **Effort** | Small |
| **Touches** | PoseEstimationService, Constants |

### What

Change pose estimation sampling from 15fps to **10fps (every 3rd frame at 30fps)** with interpolation for smoother skeleton overlay. This is 3x faster processing while still capturing all phase transitions.

### Current State

`PoseEstimationService.swift` currently uses:
```swift
private let targetAnalysisFPS: Double = 15
```

### Changes

```
EDIT  CricCoachAI/Services/PoseEstimationService.swift  # Change to 10fps + add interpolation
EDIT  CricCoachAI/Utilities/Constants.swift              # Add sampling rate constant
```

### `Constants.swift`

```swift
// MARK: - Pose Estimation
static let minimumConfidence: Float = 0.5
static let smoothingWindowSize = 5
static let poseEstimationFPS: Double = 10  // ← ADD: 10fps = every 3rd frame at 30fps
```

### `PoseEstimationService.swift`

```swift
// CURRENT:
private let targetAnalysisFPS: Double = 15

// CHANGE TO:
private let targetAnalysisFPS: Double = AppConstants.poseEstimationFPS  // 10fps
```

### Interpolation (for Skeleton Overlay)

Add a method to `PoseSequence` for interpolating between frames to get smooth 30fps skeleton overlay:

```swift
// In PoseSequence (PoseFrame.swift):

/// Interpolate pose at any timestamp (for smooth skeleton overlay at 30fps)
/// Uses linear interpolation between the two nearest sampled frames
func interpolatedFrame(at timestamp: TimeInterval) -> PoseFrame? {
    guard let before = frames.last(where: { $0.timestamp <= timestamp }),
          let after = frames.first(where: { $0.timestamp > timestamp }) else {
        return frame(at: timestamp)  // Fall back to nearest
    }

    let dt = after.timestamp - before.timestamp
    guard dt > 0 else { return before }
    let t = (timestamp - before.timestamp) / dt  // 0...1

    var interpolatedLandmarks: [String: NormalizedPoint] = [:]
    for (key, beforePoint) in before.landmarks {
        if let afterPoint = after.landmarks[key] {
            interpolatedLandmarks[key] = NormalizedPoint(
                x: beforePoint.x + Float(t) * (afterPoint.x - beforePoint.x),
                y: beforePoint.y + Float(t) * (afterPoint.y - beforePoint.y)
            )
        } else {
            interpolatedLandmarks[key] = beforePoint
        }
    }

    return PoseFrame(
        timestamp: timestamp,
        frameIndex: before.frameIndex,  // approximate
        landmarks: interpolatedLandmarks,
        confidence: before.confidence  // use earlier frame's confidence
    )
}
```

### Acceptance Criteria

- [ ] Pose estimation runs at 10fps (not 15fps)
- [ ] Processing speed improves ~33%
- [ ] Skeleton overlay is smooth at 30fps via interpolation
- [ ] Phase detection still works correctly at 10fps (verify with golden tests)

---

## Summary of All File Changes

### New Files (9)

| File | Related Finding |
|------|----------------|
| `CricCoachAI/Services/AIResponseValidator.swift` | P1-2 |
| `CricCoachAI/Services/AnalyticsService.swift` | P1-3 |
| `CricCoachAI/Services/FeatureFlagService.swift` | P1-5 |
| `CricCoachAI/Models/ScoringConfig.swift` | P2-8 |
| `CricCoachAI/Services/ScoringConfigService.swift` | P2-8 |
| `CricCoachAITests/PhaseDetectionGoldenTests.swift` | P1-1 |
| `CricCoachAITests/AIResponseValidatorTests.swift` | P1-2 |
| `CricCoachAITests/VideoNormalizationTests.swift` | P1-6 |
| `Backend/supabase/migrations/002_feature_flags.sql` | P1-5 |

### Modified Files (12)

| File | Related Findings |
|------|-----------------|
| `project.yml` | P1-3 (Sentry + PostHog deps) |
| `README.md` | Claude migration |
| `CricCoachAI/App/CricCoachAIApp.swift` | P1-3, P1-5 |
| `CricCoachAI/Utilities/Constants.swift` | P1-3, P1-4, sampling rate |
| `CricCoachAI/Services/AIAnalysisService.swift` | P1-2, P1-3, P1-4, P1-5 |
| `CricCoachAI/Services/VideoProcessingService.swift` | P1-6 |
| `CricCoachAI/Services/PoseEstimationService.swift` | P1-3, sampling rate |
| `CricCoachAI/Services/PhaseDetectionService.swift` | P1-3 |
| `CricCoachAI/Services/RuleScoringService.swift` | P2-8 |
| `CricCoachAI/Views/AnalysisView.swift` | P2-7 |
| `CricCoachAI/Models/AnalysisSession.swift` | P2-7 |
| `CricCoachAI/Models/PoseFrame.swift` | Sampling rate (interpolation) |
| `Backend/supabase/functions/analyze/index.ts` | P1-4, Claude migration |

### New Directories / Assets

| Path | Purpose |
|------|---------|
| `TestVideos/annotations/` | Ground truth annotations for golden tests |
| 30+ video files in `TestVideos/` | Golden test dataset |

---

## Implementation Order

```
Iteration 1.1 (Project Setup):
  ├── P1-3: Observability (Sentry + PostHog)          ← Do first, instrument everything
  ├── P1-5: Feature Flags infrastructure               ← Do second, enables safe rollback
  └── Cross-cut: GPT-4o → Claude migration             ← Update references early

Iteration 1.2 (Video Input):
  └── P1-6: Video Normalization                        ← Before any processing code

Iteration 2 (Phase Detection):
  ├── P1-1: Golden Test Dataset                        ← Before writing/tuning PhaseDetectionService
  └── Cross-cut: Frame Sampling Rate (10fps)           ← Before phase detection tuning

Iteration 3 (AI Coaching):
  ├── P1-4: API Versioning                             ← Before first API deployment
  ├── P1-2: AI Validation Layer                        ← Between AI response and UI
  └── P2-7: User Feedback Mechanism                    ← In Analysis Results UI

Post-Iteration 4 (Polish):
  └── P2-8: Scoring Thresholds Server-Side             ← Architecture now, migration later
```

---

## Unresolved Decisions

**None** — all decisions were resolved during the CEO review.

# 🏏 CricCoach AI

**Your AI cricket coach. Record. Analyze. Improve.**

CricCoach AI is an iOS app that analyzes cricket batting and bowling technique from video using on-device pose estimation (Apple Vision) and AI-powered coaching feedback (Claude Vision by Anthropic).

## Architecture

```
iOS App (SwiftUI)          →  On-device pose estimation (Apple Vision)
                           →  Video normalization (30fps/1080p)
                           →  Rule-based biomechanical scoring
                           →  Phase detection (batting/bowling)
                           →  AI response validation layer
                           ↓
Supabase Backend           →  Edge Functions (Claude Vision API, versioned)
                           →  PostgreSQL (sessions, scores, feature flags)
                           →  Storage (key frame images)

Observability              →  Sentry (crashes, errors, performance)
                           →  PostHog (product analytics, funnels)
```

## Project Structure

```
CricCoachAI/
├── App/
│   ├── CricCoachAIApp.swift          # App entry point (init: Sentry + PostHog + feature flags)
│   └── ContentView.swift             # Root navigation with tabs
├── Models/
│   ├── AnalysisSession.swift         # SwiftData model + AI response types
│   ├── PoseFrame.swift               # Pose landmarks, PoseSequence, interpolation
│   ├── PosePhase.swift               # Batting/bowling phase enums
│   ├── TechniqueScore.swift          # Scoring models, checkpoints
│   └── ScoringConfig.swift           # Server-overridable scoring thresholds
├── Views/
│   ├── HomeView.swift                # Main screen with sessions list + analysis pipeline
│   ├── RecordingView.swift           # Camera recording with AVCaptureSession
│   ├── SetupGuideView.swift          # Camera placement guide
│   ├── VideoImportView.swift         # PhotosPicker for importing videos
│   ├── SkeletonOverlayView.swift     # Video + skeleton overlay + controls
│   ├── AnalysisView.swift            # Full analysis results + user feedback (👍/👎)
│   ├── PhaseDetailView.swift         # Per-phase checkpoint details
│   ├── SessionProgressView.swift     # Progress tracking with Charts
│   ├── OnboardingView.swift          # First-launch onboarding flow
│   ├── PaywallView.swift             # Pro subscription screen
│   └── Components/
│       ├── ScoreCardView.swift       # Reusable score display
│       ├── AngleBadgeView.swift      # Angle overlay badges
│       └── PhaseTimelineView.swift   # Video timeline with phases
├── Services/
│   ├── PoseEstimationService.swift   # Apple Vision body pose (10fps + interpolation)
│   ├── PhaseDetectionService.swift   # State machine for phase detection
│   ├── RuleScoringService.swift      # Biomechanical scoring (config-injectable)
│   ├── AIAnalysisService.swift       # Claude Vision API integration (versioned)
│   ├── AIResponseValidator.swift     # Post-processing hallucination guard
│   ├── VideoProcessingService.swift  # Frame extraction, normalization, file mgmt
│   ├── StorageService.swift          # SwiftData persistence + queries
│   ├── SharingService.swift          # Shareable analysis card generation
│   ├── AnalyticsService.swift        # Unified Sentry + PostHog wrapper
│   ├── FeatureFlagService.swift      # Remote feature flags from Supabase
│   └── ScoringConfigService.swift    # Server-overridable scoring thresholds
├── Utilities/
│   ├── AngleCalculator.swift         # Joint angle calculations
│   ├── PoseNormalizer.swift          # Coordinate normalization
│   ├── Constants.swift               # Ideal values, thresholds, config
│   └── DesignSystem.swift            # Colors, layout, UI extensions
└── Resources/
    └── Assets.xcassets

Backend/
└── supabase/
    ├── migrations/
    │   ├── 001_initial_schema.sql    # Database schema with RLS
    │   ├── 002_feature_flags.sql     # Feature flags table + seed data
    │   └── 003_add_feedback.sql      # User feedback column
    └── functions/
        └── analyze/
            └── index.ts              # Claude Vision edge function (API versioned)

TestVideos/
├── cricket_batting.mp4               # Test video
└── annotations/                      # Golden test dataset annotations
    ├── README.md                     # Annotation guide
    └── cricket_batting.json          # Ground truth phase annotations

CricCoachAITests/
├── CricCoachAITests.swift            # Unit tests
├── PhaseDetectionGoldenTests.swift   # Golden dataset regression tests
└── AIResponseValidatorTests.swift    # AI validation layer tests
```

## Setup

### Prerequisites
- Xcode 15+ with iOS 17 SDK
- macOS Sonoma+
- A Supabase project (for backend)
- Anthropic API key (for AI coaching via Claude)

### iOS App

1. **Install XcodeGen** (for generating the Xcode project):
   ```bash
   brew install xcodegen
   ```

2. **Generate the Xcode project**:
   ```bash
   cd CricAnalyzer
   xcodegen generate
   ```

3. **Open in Xcode**:
   ```bash
   open CricCoachAI.xcodeproj
   ```

4. **Update Constants.swift** with your Supabase URL, anon key, Sentry DSN, and PostHog key:
   ```swift
   static let apiBaseURL = "https://YOUR-PROJECT.supabase.co"
   static let supabaseAnonKey = "YOUR-ANON-KEY"
   static let sentryDSN = "https://YOUR_KEY@o0.ingest.sentry.io/0"
   static let postHogAPIKey = "phc_YOUR_KEY"
   ```

5. **Build and run** on a physical device (camera required)

### Backend (Supabase)

1. Create a new Supabase project at [supabase.com](https://supabase.com)

2. Run the migration SQL files in order:
   - `Backend/supabase/migrations/001_initial_schema.sql`
   - `Backend/supabase/migrations/002_feature_flags.sql`
   - `Backend/supabase/migrations/003_add_feedback.sql`

3. Deploy the Edge Function:
   ```bash
   supabase functions deploy analyze
   ```

4. Set environment variables:
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   ```

## Key Features

### Iteration 1: Video + Pose Skeleton
- Record video with back camera (1080p, 30fps)
- Import from camera roll (up to 2 minutes)
- **Video normalization** to 30fps/1080p (handles slow-mo 240fps, 4K)
- On-device pose estimation (Apple Vision, 19 landmarks, **10fps + interpolation**)
- Real-time skeleton overlay on video playback
- Frame-by-frame controls + slow motion (0.25x, 0.5x, 1x)
- **Sentry + PostHog** instrumented from day one
- **Feature flags** fetched on app launch (kill switches, remote config)

### Iteration 2: Phase Detection + Scoring
- **Golden test dataset** (30+ annotated videos) for regression testing
- **Batting phases**: Stance → Backlift → Stride → Downswing → Contact → Follow-through
- **Bowling phases**: Run-up → Gather → Back Foot → Front Foot → Release → Follow-through
- Rule-based scoring against ideal biomechanical benchmarks
- Per-checkpoint scores with measured vs ideal comparisons
- **Config-injectable scoring thresholds** (ready for server-side tuning)

### Iteration 3: AI Coaching
- Claude Vision analyzes key frames + pose data (via **versioned API** `/api/v1/`)
- **AI response validation layer** — cross-checks claims against measured pose data
- Top 3 issues ranked by impact, with specific drills
- Positive reinforcement for good technique
- Session-to-session progress commentary
- **User feedback** (👍/👎) after each analysis

### Iteration 4: Progress + Polish
- Score trends over time (Charts framework)
- Session comparison side-by-side
- Weekly streak tracking
- Shareable analysis cards (Instagram/WhatsApp)
- Onboarding flow + Pro subscription paywall
- Dark mode primary design

## Key Architectural Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Pose frame sampling | **10fps + interpolation** | 3x faster processing, smooth 30fps overlay |
| 2 | API versioning | **`X-API-Version: v1` header** | Prevents breaking old app versions |
| 3 | AI hallucination guard | **Post-processing validation layer** | Cross-checks claims vs measured data |
| 4 | API key security | **Key in Supabase Edge Function only** | iOS app never touches it |
| 5 | AI provider | **Claude (Anthropic)** | Better structured output for coaching |
| 6 | Video normalization | **30fps/1080p canonical format** | Handles slow-mo uniformly |
| 7 | Phase detection testing | **Golden dataset of 30+ annotated videos** | Regression suite before tuning |
| 8 | Observability | **Sentry + PostHog from day one** | No flying blind in production |

## Biomechanical Scoring

| Batting Phase | Checkpoints |
|--------------|-------------|
| Stance | Feet width, knee bend, head position, weight distribution |
| Backlift | Height, direction, head stability, front shoulder |
| Stride | Length, direction, front knee, head position |
| Contact | Head stability, head over ball, front elbow, weight transfer |
| Follow-through | Bat swing completion, balance |

| Bowling Phase | Checkpoints |
|--------------|-------------|
| Back Foot Contact | Hip-shoulder separation, body alignment (mixed action ⚠️) |
| Front Foot Contact | Front leg brace |
| Release | Arm height, front leg brace, head position |
| Follow-through | Balance |

## Business Model

- **Free**: 3 analyses/month (configurable via feature flag), skeleton overlay, basic scores
- **Pro** ($7.99/mo or $49.99/yr): Unlimited analyses, AI coaching, progress tracking, sharing

## Tech Stack

| Component | Technology |
|-----------|-----------|
| iOS App | Swift, SwiftUI, SwiftData |
| Pose Estimation | Apple Vision (VNDetectHumanBodyPoseRequest) |
| Video | AVFoundation, AVKit |
| Charts | Swift Charts |
| Backend | Supabase (PostgreSQL, Edge Functions, Auth) |
| AI | Anthropic Claude Vision API |
| Observability | Sentry (crashes), PostHog (analytics) |
| Payments | RevenueCat / StoreKit 2 (TODO) |

## License

Private — All rights reserved.

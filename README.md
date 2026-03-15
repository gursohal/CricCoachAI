# 🏏 CricCoach AI

**Your AI cricket coach. Record. Analyze. Improve.**

CricCoach AI is an iOS app that analyzes cricket batting and bowling technique from video using on-device pose estimation (Apple Vision) and AI-powered coaching feedback (GPT-4o Vision).

## Architecture

```
iOS App (SwiftUI)          →  On-device pose estimation (Apple Vision)
                           →  Rule-based biomechanical scoring
                           →  Phase detection (batting/bowling)
                           ↓
Supabase Backend           →  Edge Functions (GPT-4o Vision API)
                           →  PostgreSQL (sessions, scores)
                           →  Storage (key frame images)
```

## Project Structure

```
CricCoachAI/
├── App/
│   ├── CricCoachAIApp.swift          # App entry point
│   └── ContentView.swift             # Root navigation with tabs
├── Models/
│   ├── AnalysisSession.swift         # SwiftData model + AI response types
│   ├── PoseFrame.swift               # Pose landmarks, PoseSequence
│   ├── PosePhase.swift               # Batting/bowling phase enums
│   └── TechniqueScore.swift          # Scoring models, checkpoints
├── Views/
│   ├── HomeView.swift                # Main screen with sessions list
│   ├── RecordingView.swift           # Camera recording with AVCaptureSession
│   ├── SetupGuideView.swift          # Camera placement guide
│   ├── VideoImportView.swift         # PhotosPicker for importing videos
│   ├── SkeletonOverlayView.swift     # Video + skeleton overlay + controls
│   ├── AnalysisView.swift            # Full analysis results
│   ├── PhaseDetailView.swift         # Per-phase checkpoint details
│   ├── SessionProgressView.swift     # Progress tracking with Charts
│   ├── OnboardingView.swift          # First-launch onboarding flow
│   ├── PaywallView.swift             # Pro subscription screen
│   └── Components/
│       ├── ScoreCardView.swift       # Reusable score display
│       ├── AngleBadgeView.swift      # Angle overlay badges
│       └── PhaseTimelineView.swift   # Video timeline with phases
├── Services/
│   ├── PoseEstimationService.swift   # Apple Vision body pose extraction
│   ├── PhaseDetectionService.swift   # State machine for phase detection
│   ├── RuleScoringService.swift      # Biomechanical scoring engine
│   ├── AIAnalysisService.swift       # GPT-4o Vision API integration
│   ├── VideoProcessingService.swift  # Frame extraction, file management
│   ├── StorageService.swift          # SwiftData persistence + queries
│   └── SharingService.swift          # Shareable analysis card generation
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
    │   └── 001_initial_schema.sql    # Database schema with RLS
    └── functions/
        └── analyze/
            └── index.ts              # GPT-4o Vision edge function
```

## Setup

### Prerequisites
- Xcode 15+ with iOS 17 SDK
- macOS Sonoma+
- A Supabase project (for backend)
- OpenAI API key (for AI coaching)

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

4. **Update Constants.swift** with your Supabase URL and anon key:
   ```swift
   static let apiBaseURL = "https://YOUR-PROJECT.supabase.co/functions/v1"
   static let supabaseAnonKey = "YOUR-ANON-KEY"
   ```

5. **Build and run** on a physical device (camera required)

### Backend (Supabase)

1. Create a new Supabase project at [supabase.com](https://supabase.com)

2. Run the migration SQL in the SQL Editor:
   - Copy contents of `Backend/supabase/migrations/001_initial_schema.sql`

3. Deploy the Edge Function:
   ```bash
   supabase functions deploy analyze
   ```

4. Set environment variables:
   ```bash
   supabase secrets set OPENAI_API_KEY=sk-...
   ```

## Key Features

### Iteration 1: Video + Pose Skeleton
- Record video with back camera (1080p, 30fps)
- Import from camera roll (up to 2 minutes)
- On-device pose estimation (Apple Vision, 19 landmarks)
- Real-time skeleton overlay on video playback
- Frame-by-frame controls + slow motion (0.25x, 0.5x, 1x)

### Iteration 2: Phase Detection + Scoring
- **Batting phases**: Stance → Backlift → Stride → Downswing → Contact → Follow-through
- **Bowling phases**: Run-up → Gather → Back Foot → Front Foot → Release → Follow-through
- Rule-based scoring against ideal biomechanical benchmarks
- Per-checkpoint scores with measured vs ideal comparisons

### Iteration 3: AI Coaching
- GPT-4o Vision analyzes key frames + pose data
- Top 3 issues ranked by impact, with specific drills
- Positive reinforcement for good technique
- Session-to-session progress commentary

### Iteration 4: Progress + Polish
- Score trends over time (Charts framework)
- Session comparison side-by-side
- Weekly streak tracking
- Shareable analysis cards (Instagram/WhatsApp)
- Onboarding flow + Pro subscription paywall
- Dark mode primary design

## Biomechanical Scoring

The app measures and scores these checkpoints:

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

- **Free**: 3 analyses/month, skeleton overlay, basic scores
- **Pro** ($7.99/mo or $49.99/yr): Unlimited analyses, AI coaching, progress tracking, sharing

## Tech Stack

| Component | Technology |
|-----------|-----------|
| iOS App | Swift, SwiftUI, SwiftData |
| Pose Estimation | Apple Vision (VNDetectHumanBodyPoseRequest) |
| Video | AVFoundation, AVKit |
| Charts | Swift Charts |
| Backend | Supabase (PostgreSQL, Edge Functions, Auth) |
| AI | OpenAI GPT-4o Vision API |
| Payments | RevenueCat / StoreKit 2 (TODO) |

## License

Private — All rights reserved.

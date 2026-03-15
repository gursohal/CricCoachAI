# 🎥 Golden Test Dataset — Annotation Guide

## Purpose

This directory contains ground-truth annotations for the **phase detection regression test suite**. Each video in `TestVideos/` should have a corresponding annotation JSON file here.

## Annotation Format

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

## How to Annotate

1. Open the video in a frame-by-frame viewer (e.g., QuickTime Player → View → Show Playback Controls)
2. For each phase:
   - **start_frame**: First frame where the phase begins
   - **end_frame**: Last frame of the phase  
   - **key_frame**: The most representative frame (peak of the action)
3. Calculate frame numbers: `frame = timestamp_seconds × fps`

## Video Requirements

| Category | Minimum Count | Notes |
|----------|--------------|-------|
| Batting — right-hand | 8 | Include drives, pulls, cuts, defensive |
| Batting — left-hand | 4 | Mirror of right-hand phases |
| Bowling — pace (right arm) | 6 | Side-on and chest-on actions |
| Bowling — pace (left arm) | 3 | |
| Bowling — spin | 4 | Off-spin, leg-spin |
| Edge cases — poor lighting | 2 | Indoor nets, dusk |
| Edge cases — partial body | 2 | Legs cropped, side angle |
| Edge cases — slow-mo (240fps) | 2 | iPhone slo-mo recordings |

**Total: 30+ videos minimum**

## Naming Convention

- `batting_drive_01.mp4` → `batting_drive_01.json`
- `bowling_pace_rh_01.mp4` → `bowling_pace_rh_01.json`
- `edge_lowlight_01.mp4` → `edge_lowlight_01.json`

## Test Success Criteria

Tests in `CricCoachAITests/PhaseDetectionGoldenTests.swift` assert:
- Each detected phase's `keyFrame` is within **±5 frames** of annotation
- **Recall ≥ 90%** (no phases missed)
- **Precision ≥ 85%** (no false phases injected)

# Changelog

All notable changes to ShotBuddy are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added — 2026-07-31 (Phase 0)
- Project plan: `README.md`, `docs/ROADMAP.md`, `docs/TECH_STACK.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`
- `SECURITY.md` — threat model, disclosure process, public-repo and content rules
- `CONTRIBUTING.md`
- AGPL-3.0 `LICENSE` (see [D-005](docs/DECISIONS.md))
- `.gitignore` covering secrets, keystores, and capture data

### Added — 2026-07-31 (Phase 1, first working build)
- Flutter Android app, landscape-locked, minSdk 24
- On-device detection with COCO EfficientDet-Lite0 via `tflite_flutter` — uses the
  stock `sports ball` class so no model training was needed to get started ([D-008](docs/DECISIONS.md))
- Tap-to-calibrate rim, with an adjustable gate width
- `BallTracker`: frame-to-frame association, implausible-jump rejection, and a
  least-squares parabolic fit so occlusions cost precision rather than correctness
- `MakeMissRules`: geometric make/miss state machine with rim-out handling
- Live overlay — rim gate, ball box coloured by shot phase, trajectory trail
- Manual MAKE/MISS, undo, and flip, always on screen
- Debug panel: FPS, inference time, all detections with labels, rim-width slider
- Session persistence via `shared_preferences`, written after every shot
- 7 unit tests covering makes, misses, rim-outs, dribbling, and tracker behavior
- GitHub Actions CI: format, analyze, test, and debug APK artifact
- `docs/GAMEDAY.md` — court setup and honest limitations

### Known limitations
- Detector is not basketball-specific; expect trouble in dim light or with
  multiple balls in frame
- Inference blocks the UI thread ([D-010](docs/DECISIONS.md)) — some jank is expected
- Accuracy has not been measured in a real gym

### Not yet started
- Purpose-trained ball+rim model, Drift persistence, stats and shot charts

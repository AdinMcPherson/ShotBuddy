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

### Fixed — 2026-07-31
- Detector model asset was the raw EfficientDet-Lite0 export, whose per-anchor
  outputs have no NMS — the app failed at load with an output-signature error and
  never reached the camera. Replaced with the post-processed build of the same
  model, which also cut the release APK from 75.8 MB to 67.0 MB
- Preview no longer crops the frame. `BoxFit.cover` meant the detector reasoned
  about pixels the user could not see, and a rim tap landed on different pixels
  than the ones scored against it ([D-011](docs/DECISIONS.md))

### Changed — 2026-07-31
- Portrait and landscape are both supported; the frame is rotated into display
  orientation during conversion, so one coordinate space holds throughout
  ([D-011](docs/DECISIONS.md)). Rotating the phone clears the rim and re-prompts
- Conversion and inference moved to a background isolate — the UI thread no
  longer blocks on a frame ([D-012](docs/DECISIONS.md)). Frames are still dropped
  rather than queued while the worker is busy
- Two orientation-specific layouts, plus last-10 percentage, current and best
  streak, a session clock, and a strip of the last twelve shots with
  hand-corrected calls ringed
- 8 further unit tests covering the rotation and the converter's output shape

### Added — 2026-07-31
- **"Rim lost" detection.** If the phone is moved after the rim was marked,
  counting stops and says so rather than scoring shots against a rim that is no
  longer there ([D-013](docs/DECISIONS.md)). Detected from whole-scene motion,
  since the stock model cannot see a rim; built to ignore rebounders crossing
  frame and gym-light changes. Recorded shots are kept and manual MAKE/MISS
  keeps working
- 13 unit tests for the displacement detector, including the false-positive
  cases it exists to survive

### Known limitations
- Detector is not basketball-specific; expect trouble in dim light or with
  multiple balls in frame
- Accuracy has not been measured in a real gym, and neither has the FPS the
  isolate work was meant to buy

### Not yet started
- Purpose-trained ball+rim model, Drift persistence, stats and shot charts

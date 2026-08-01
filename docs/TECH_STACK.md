# Tech Stack

Every choice below is free at the scale this project will operate at. Where a paid tier exists, the line where we'd cross into it is noted.

## Constraints that drove these choices

1. **Android-first, mobile-first.** iOS is not a goal, but nothing should make it impossible later.
2. **$0 recurring cost.** No inference APIs, no hosted backend, no paid dataset licenses.
3. **Real-time on mid-range hardware.** Target 15+ FPS of inference on a ~$300 Android phone.
4. **Public repo, so nothing secret can be required to build it.**

---

## App layer

| Concern | Choice | License | Why |
|---|---|---|---|
| Framework | **Flutter 3.41+ / Dart 3.11** | BSD-3 | Already installed and the language you know best. Good camera plugins, and the UI layer is where most of the code will live. |
| Camera | **`camera`** (official Flutter plugin) | BSD-3 | `startImageStream` gives raw YUV420 frames without writing platform channel code. This is the make-or-break API for Phase 1. |
| ML runtime | **`tflite_flutter`** + `tflite_flutter_helper` | Apache-2.0 | Loads `.tflite` models, exposes GPU and NNAPI delegates. Actively maintained, unlike most Flutter TF wrappers. |
| Pose (Phase 3) | **MediaPipe Pose Landmarker** (BlazePose, `.task` bundle) | Apache-2.0 | 33 body landmarks, runs on-device, free. The permissive license matters — this is what a form-comparison feature is built on. |
| State | **Riverpod** | MIT | Testable, no `BuildContext` dependency, works cleanly with the frame-stream isolate. |
| Database | **Drift** (SQLite) | MIT | Type-safe SQL, real migrations, generated code. Room-equivalent for Flutter. Better than Hive/Isar for the relational stats queries in Phase 2. |
| Charts | **`fl_chart`** | MIT | Pure Dart, no platform code, handles the shot-chart and trend views. |

**Deliberately not used:** Firebase, Supabase, any auth SDK, any analytics SDK. Phase 1–4 have no server. Adding one is a Phase 5 decision, not a default.

## Machine learning

### Phase 1 — ball + hoop detection

| Concern | Choice | Cost |
|---|---|---|
| Architecture | **YOLO11n** (nano) object detector, 2 classes: `ball`, `rim` | Free |
| Training framework | **Ultralytics** (Python) | Free, AGPL-3.0 |
| Dataset | **Roboflow Universe** public basketball datasets, merged and re-labeled to our 2 classes | Free tier |
| Training compute | **Google Colab** free tier (T4 GPU) | Free — a nano model on ~5k images trains in well under the session limit |
| Export | TFLite, INT8 quantized, 320×320 input, ~3–6 MB | Free |
| Delegate | NNAPI, GPU fallback, CPU last resort | Free |

Model weights are committed to the repo via **Git LFS** (free up to 1 GB storage / 1 GB bandwidth per month — a 6 MB model with occasional retrains stays far inside that). Training notebooks and the dataset manifest are committed so anyone can reproduce the model.

### Make/miss classification — no second model

This is the design decision most likely to be misjudged, so it's stated explicitly: **make/miss is decided by geometry, not by a neural network.**

The detector gives us a ball box and a rim box per frame. From there:

1. Track the ball centroid across frames (simple IoU/nearest-neighbour tracker + Kalman smoothing).
2. Fit the recent points to a parabola to survive frames where the ball is occluded or missed.
3. A **make** is the ball centroid crossing the rim plane downward, inside the rim's horizontal extent, and continuing downward for N frames without reversing.
4. A **miss** is a trajectory that peaks and descends outside that gate, or crosses and immediately reverses upward (rim-out).

Rule-based means it's debuggable, tunable, needs zero extra training data, and its failure modes are explainable. A learned classifier is a Phase 2+ option only if the geometry proves insufficient.

### Phase 3–4 — form analysis and player comparison

Pose landmarks → derived numeric features per shot: release angle, release height (as a fraction of body height), elbow angle at set point, knee flexion, release time, follow-through hold, left/right asymmetry.

Player "templates" are **numeric joint-angle curves**, not video. See [SECURITY.md](../SECURITY.md#legal-and-content-rules) — no NBA footage or images are ever committed to this repo, and templates must be documented with their derivation source.

## Repo and CI

| Concern | Choice | Cost |
|---|---|---|
| Hosting | GitHub public repo | Free |
| CI | GitHub Actions (`flutter analyze`, `flutter test`, debug APK build) | Free for public repos |
| Secret scanning + push protection | GitHub native | Free for public repos |
| Dependency alerts | Dependabot | Free |
| Static analysis | CodeQL | Free for public repos |
| Large files | Git LFS (model weights only) | Free tier |

## The only real cost in the whole project

**Google Play Developer account: $25, one time.** Unavoidable if the app ships to the Play Store. Everything before that — building, testing on your own device via sideloaded APK, and distributing APKs through GitHub Releases — is free. This is a Phase 5 decision; it does not block Phases 0–4.

## Licensing

**The repo is AGPL-3.0.**

Ultralytics YOLO is AGPL-3.0, and models trained with it inherit that obligation. Since ShotBuddy is open source anyway, adopting AGPL-3.0 up front is the honest, friction-free choice — no license audit surprise three phases in.

The consequence to understand now: **AGPL-3.0 forecloses a closed-source commercial version of this app.** If that ever becomes a goal, the escape hatch is to retrain the detector with a permissively licensed framework (YOLOX or plain PyTorch, both Apache-2.0) and relicense. That swap is contained — it touches the training pipeline and the model file, not the app code — but it gets more expensive the later it happens. Flag it now if commercial use is on your mind.

Every other dependency listed above is MIT, BSD-3, or Apache-2.0 and imposes no such constraint.

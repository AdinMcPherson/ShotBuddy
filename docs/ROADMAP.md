# Roadmap

Six phases. Each one ends with something installable on your phone that does more than the last. We do them one at a time and do not start the next until the current one's exit criteria are met.

Phase order is set by **risk, not by ease**. Camera detection is the feature the whole product depends on, so it goes first — if it can't be made to work, that should be discovered in week two, not month four.

---

## Phase 0 — Foundation

*Nothing user-facing. Makes every later phase safe and reproducible.*

**Build**
- Flutter project scaffold, Android-only targets, min SDK 24
- `.gitignore` covering keystores, `key.properties`, `.env`, build output
- AGPL-3.0 `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`
- GitHub Actions: `flutter analyze` + `flutter test` + debug APK on every PR
- Enable secret scanning, push protection, Dependabot, CodeQL
- Git LFS configured for `assets/models/*.tflite`
- `CHANGELOG.md` started

**Exit criteria** — a fresh `git clone` + `flutter run` puts a blank ShotBuddy app on a physical Android device, and CI is green.

**Risk:** none. This is the cheap phase; don't skip it to get to the fun part.

---

## Phase 1 — Live shot detection (the hard one)

*The camera watches, the counter goes up. This is the product's core bet.*

**Build**
- Dataset: pull public basketball datasets from Roboflow Universe, merge, normalize to 2 classes (`ball`, `rim`), split train/val/test. Commit the manifest and prep script.
- Train YOLO11n in Colab. Export INT8 TFLite at 320×320. Target: mAP50 ≥ 0.80 on the held-out set.
- Frame pipeline: `camera` image stream → downscale/convert YUV→RGB in a background isolate → TFLite inference → detections. **The UI isolate must never block on inference.**
- Ball tracker: nearest-neighbour association + Kalman smoothing + parabolic fit across gaps.
- Rim calibration: lock the rim position from the first stable seconds; re-detect if the phone moves.
- Make/miss rule engine (see [TECH_STACK.md](TECH_STACK.md#makemiss-classification--no-second-model)).
- Live UI: camera preview, detection overlay boxes, running `makes / attempts` and %, big legible numbers readable from the free-throw line.
- Debug mode: on-screen FPS, inference latency, confidence scores, trajectory trail.

**Exit criteria** — in a real gym, from a tripod or propped phone at the wing, ShotBuddy counts a 25-shot session with **≥90% make/miss accuracy** and holds **≥15 FPS** on your test device.

**Risks, and what we do about them**
| Risk | Mitigation |
|---|---|
| Public datasets are broadcast-angle; your phone is courtside | Budget time to label 300–500 of your own frames from your gym. This is the single highest-value fallback. |
| Inference too slow → dropped frames → missed arcs | Drop to 256×256 input, skip frames adaptively, lean on NNAPI. Parabolic fit already tolerates gaps. |
| Ball lost behind the backboard/net | Trajectory fit predicts through the occlusion instead of requiring detection every frame. |
| Rim moves when the phone gets bumped | Re-calibration trigger + a visible "rim lost" state rather than silently logging garbage. |

**If this phase fails outright:** fall back to tap-to-log as the shipping product and keep detection as an experimental toggle. Deciding that early is a success, not a defeat.

---

## Phase 2 — Memory and stats

*Sessions persist. Numbers become trends.*

**Build**
- Drift schema: `sessions`, `shots` (timestamp, made, court position, confidence, trajectory summary), `settings`. Migrations from day one.
- Manual correction UI — tap any shot in the session review to flip make↔miss. **Non-negotiable:** the model will be wrong sometimes and the user must be able to fix it. Corrections are also the training data for future retrains.
- Session history list, per-session detail
- Stats: overall %, by session, by day, streaks, best/worst session
- Court zone chart (shot chart) with per-zone %
- Trend charts via `fl_chart`
- Export session data to CSV/JSON — your data, your device, portable out

**Exit criteria** — shoot a session, close the app, reopen it, and see the session with correct stats and a shot chart.

---

## Phase 3 — Form analysis

*Stop counting shots, start reading them.*

**Build**
- MediaPipe Pose Landmarker integrated on the same frame stream (run at lower frequency than detection, or only on shot-detected windows, to protect FPS)
- Per-shot form features: release angle, release height, elbow angle at set, knee flexion, release time, follow-through duration, lateral asymmetry
- Shot arc metrics from the existing trajectory: entry angle, apex height, depth
- Per-shot form card; correlate form features against make rate ("your makes average a 47° entry angle; your misses average 39°")
- Consistency scoring — variance across shots, which matters more than any single ideal number

**Exit criteria** — after a session, the app shows real form metrics per shot and at least one honest, data-backed observation about what separates your makes from your misses.

**Risk:** a single phone gives one 2D viewpoint. Angles measured off-axis are distorted. Mitigation: detect and state the camera angle, restrict the metrics we report to ones that are stable from that angle, and *say so in the UI* rather than reporting confident nonsense.

---

## Phase 4 — Shoot like the pros

*Pick a player, get told what to change.*

**Build**
- A small curated set of player form templates (start with 5–8 distinct shooting styles — e.g. a high-release big, a quick-release guard, a set shooter)
- Each template is a **numeric joint-angle profile**, not video — see [SECURITY.md](../SECURITY.md#legal-and-content-rules)
- Similarity scoring: your normalized form features vs. the template, per-feature and overall
- Coaching output: the 2–3 largest gaps, phrased as actionable cues, not a score to obsess over
- Progress tracking toward a chosen template over time

**Exit criteria** — pick a player, shoot a session, and get a specific, honest, reproducible comparison.

**Risks**
- **Legal.** No NBA footage, images, logos, or marks in the repo or the app. Templates are derived numeric data with documented provenance. Player names used descriptively/nominatively only. Revisit before any public release.
- **Honesty.** Body proportions and height make some pro form literally unreachable. The app should frame this as "here's how your mechanics differ," never "you're doing it wrong."

---

## Phase 5 — Release

**Build**
- Onboarding: phone placement guide, calibration walkthrough
- Accessibility pass, dark mode, large-text support
- Battery and thermal work — sustained camera + inference is the real constraint on a long session
- Play Store listing, privacy policy, screenshots ($25 developer account)
- Signed release build via GitHub Actions with the keystore in Actions secrets — **never in the repo**
- *Optional, only if wanted:* opt-in cloud sync. This is the phase where the `INTERNET` permission would first appear, and it needs its own security review.

---

## Sequencing rules

1. One phase at a time. No starting Phase 2 while Phase 1 is at 70%.
2. Every phase ends with a tagged release and a `CHANGELOG.md` entry.
3. Exit criteria are measured on a real device in a real gym, not in an emulator.
4. If a phase's exit criteria can't be met, we change the plan in writing before changing the code.

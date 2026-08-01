# Architecture

How the pieces fit. This describes the target design for Phase 1–2; Phase 3–4 additions are marked.

## Layers

```
┌─────────────────────────────────────────────────────┐
│  UI (Flutter widgets)                               │
│  live session · session history · shot chart · form │
└───────────────▲─────────────────────────────────────┘
                │ Riverpod providers (state, no logic)
┌───────────────┴─────────────────────────────────────┐
│  Domain                                             │
│  ShotEngine · TrajectoryTracker · MakeMissRules     │
│  FormAnalyzer (Phase 3) · PlayerComparer (Phase 4)  │
└───────────────▲──────────────────▲──────────────────┘
                │                  │
┌───────────────┴──────┐  ┌────────┴──────────────────┐
│  Vision (isolate)    │  │  Data                     │
│  frame convert       │  │  Drift / SQLite           │
│  TFLite detector     │  │  sessions · shots         │
│  Pose (Phase 3)      │  │  settings                 │
└──────────────────────┘  └───────────────────────────┘
```

Rules that keep this honest:

- **Domain has no Flutter imports.** It's pure Dart, so the make/miss logic is unit-testable without a device or a camera.
- **Vision runs in a background isolate.** The UI thread never waits on inference.
- **Data is written by the domain layer only.** Widgets never touch Drift directly.

## The frame pipeline

This is the performance-critical path. Everything else can be slow; this cannot.

```
CameraController.startImageStream
        │  YUV420 frames, ~30/sec
        ▼
  [ frame gate ]  ── drop frames while the previous inference is in flight
        │            (backpressure — never queue, always drop)
        ▼
  SendPort → detection isolate
        │
        ├─ YUV420 → RGB, downscale to 320×320, normalize
        ├─ TFLite invoke (NNAPI → GPU → CPU fallback)
        └─ NMS → List<Detection>{class, bbox, confidence}
        │
        ▼  ReceivePort
  TrajectoryTracker
        ├─ associate ball detection with the active track
        ├─ Kalman smoothing
        └─ parabolic fit over the recent window (survives occlusion)
        │
        ▼
  MakeMissRules
        ├─ rim plane locked from calibration
        ├─ downward crossing inside rim x-extent?
        └─ sustained descent, no reversal?
        │
        ▼
  ShotEngine → emit Shot{made, position, confidence, trajectory}
        ├─ → UI (live counter, overlay)
        └─ → Drift (Phase 2)
```

### Why frames are dropped, not queued

If inference takes 60ms and frames arrive every 33ms, a queue grows without bound and the overlay drifts seconds behind reality. Dropping keeps the app in the present. The parabolic fit is what makes dropping safe — the trajectory is reconstructed from the frames we *did* process, so a gap costs precision, not correctness.

## Rim calibration

The rim is effectively static, so detecting it every frame is wasted compute and a source of jitter.

1. On session start, run detection at full rate for ~2 seconds.
2. Take the median rim box across stable frames → lock it as the rim plane.
3. Thereafter, verify the rim every N frames rather than every frame.
4. If verification fails repeatedly, enter a visible **"rim lost — reposition"** state and stop logging shots.

Refusing to log is deliberate. Silently recording garbage after the phone gets bumped is worse than recording nothing.

## Shot lifecycle state machine

```
IDLE ──ball detected & rising──▶ IN_FLIGHT
IN_FLIGHT ──crosses rim plane downward, inside gate──▶ MAKE_PENDING
IN_FLIGHT ──descends past rim plane outside gate─────▶ MISS
MAKE_PENDING ──continues down N frames───────────────▶ MAKE
MAKE_PENDING ──reverses upward (rim-out)─────────────▶ IN_FLIGHT
any ──ball lost > timeout──▶ IDLE  (no shot recorded)
```

`MAKE_PENDING` exists solely to handle rim-outs, which are the most common way a naive implementation over-counts makes.

## Data model (Phase 2)

```
sessions
  id · started_at · ended_at · location_label? · device_orientation

shots
  id · session_id → sessions.id
  timestamp · made (bool) · corrected_by_user (bool)
  court_x · court_y · confidence
  arc_entry_angle? · apex_height?
  form_features?  (JSON, Phase 3)

settings
  key · value
```

`corrected_by_user` is load-bearing. It separates model output from ground truth, which means corrected shots become a training set for future retrains — the app gets better the more you use it.

## Phase 3–4 additions

Pose estimation joins the same isolate but runs on a **shot-triggered window** rather than continuously: when the state machine enters `IN_FLIGHT`, the preceding ~1s of buffered frames is analyzed for form. Running BlazePose on every frame alongside detection would not hold the FPS target on mid-range hardware.

`PlayerComparer` is pure math over normalized feature vectors — no model, no inference, no network.

## Testing strategy

| Layer | How |
|---|---|
| Domain | Pure Dart unit tests. Synthetic trajectories for makes, misses, rim-outs, airballs, occlusion gaps. |
| Vision | Golden-frame tests: fixed input images → expected detections, run against the committed model. |
| Data | Drift migration tests, every schema version. |
| UI | Widget tests for the session flow. |
| End-to-end | Recorded gym video replayed through the pipeline with hand-labeled ground truth. Built during Phase 1 and kept as the regression suite for every later model retrain. |

That last row is the one that pays for itself. Without a labeled replay set, there is no way to know whether a model retrain improved anything.

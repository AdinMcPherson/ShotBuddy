# Decision log

Short records of choices made, why, and what would make us revisit. Append new entries; don't rewrite old ones.

---

### D-001 — Flutter, not native Kotlin or React Native
**2026-07-31 · Accepted**

Flutter is the stack you already know, which matters more than a marginal performance edge on a solo project. The camera→inference path is handled by `camera` + `tflite_flutter` without writing platform channels.

*Revisit if:* the frame pipeline can't hold 15 FPS on target hardware after optimization. The fix would be a native Kotlin frame processor behind a platform channel, not a full rewrite.

---

### D-002 — Camera auto-detection in Phase 1, not manual tap logging
**2026-07-31 · Accepted**

Auto-detection is the product. Shipping a tap-logger first would build a lot of UI around an unvalidated core. Doing the risky thing first means we learn early whether the idea works.

*Accepted cost:* Phase 1 takes longer to produce something usable, and there's a real chance it needs custom labeled data from your gym.

*Fallback if it fails:* ship tap-to-log as the product, keep detection as an experimental toggle.

---

### D-003 — Make/miss by geometry, not a second neural network
**2026-07-31 · Accepted**

The object detector gives ball and rim positions. Whether the ball went through is a geometry question. A rule engine over the fitted trajectory is debuggable, needs no extra training data, and fails in explainable ways.

*Revisit if:* real-gym accuracy plateaus below 90% and error analysis shows the failures are ambiguity the rules can't express, rather than detection quality.

---

### D-004 — Local-only, and no `INTERNET` permission through Phase 4
**2026-07-31 · Accepted**

Omitting the permission entirely turns a privacy promise into an OS-enforced guarantee that any user can verify from the manifest. It also removes an entire class of security work from a public repo with no server.

*Revisit at:* Phase 5, only if cloud sync is actually wanted. It would need opt-in design, a privacy policy, and its own security review.

---

### D-005 — AGPL-3.0
**2026-07-31 · Accepted**

Ultralytics YOLO is AGPL-3.0 and models trained with it inherit the obligation. The project is open source regardless, so adopting AGPL up front avoids a licensing surprise later.

*Consequence:* a closed-source commercial version is foreclosed while the Ultralytics-trained model is in use.

*Revisit if:* commercialization becomes a goal. The escape is retraining with YOLOX or plain PyTorch (Apache-2.0) and relicensing — contained to the training pipeline, but cheaper the earlier it's done.

---

### D-006 — Drift over Hive/Isar
**2026-07-31 · Accepted**

Phase 2's stats are relational aggregations (per-zone percentages, per-day trends, streaks). Real SQL and real migrations are worth more here than a document store's convenience.

---

### D-007 — NBA player templates as numeric data, never footage
**2026-07-31 · Accepted**

Committing NBA video or images to a public repo is a copyright problem regardless of intent. Joint-angle profiles with documented provenance carry the feature without the exposure.

*Open question:* exactly how each template gets derived, and from what source, must be settled before Phase 4 starts. Not resolved yet.

---

### D-008 — Ship a stock COCO detector first; train the real model after
**2026-07-31 · Accepted**

The plan called for a purpose-trained two-class ball+rim detector, which is days of dataset work. The COCO-pretrained EfficientDet-Lite0 already has a `sports ball` class, so ball detection works with no training at all. The missing half — the rim — is supplied by the user tapping it once, instead of a detector finding it.

This gets real auto make/miss counting into a gym immediately, and the first real session becomes evidence for what the trained model actually needs to handle.

*Cost:* accuracy is worse than a purpose-trained model, especially in poor light and with several balls in frame. `BallDetector` is the seam where the trained model drops in; nothing above it changes.

*Revisit:* as soon as there is labeled footage from a real session.

---

### D-009 — Landscape-only
**2026-07-31 · Accepted · Superseded by D-011**

The camera delivers frames in sensor orientation while the preview is rotated for display. Locking to landscape makes those two coordinate spaces agree, which means a tap on the rim in the preview means the same thing to the detector — no rotation matrix, no per-device orientation quirks to chase. It is also the orientation you would prop a phone in to film a hoop anyway.

*Revisit if:* portrait becomes worth supporting. That requires an explicit transform between preview and frame space, and a device matrix to test it on.

---

### D-010 — Inference runs on the main isolate for now
**2026-07-31 · Accepted · Superseded by D-012**

`IsolateInterpreter` would keep the UI thread free, but it needs shaped nested-list inputs, which means allocating and reshaping ~300k elements per frame. The direct `setTo`/`invoke` path avoids that allocation entirely, at the cost of blocking the UI thread for the duration of inference.

Frames are dropped rather than queued while inference is in flight, so the overlay stays in the present. Expect some jank; it does not affect counting.

*Revisit if:* the debug panel shows FPS below ~10 on target hardware, or the jank proves annoying in real use.

---

### D-011 — Both orientations, with the rotation applied during conversion
**2026-07-31 · Accepted · Supersedes D-009**

Portrait is how you hold the phone when you are the one shooting, so the landscape lock was worth removing. The transform D-009 was wary of turned out to be nearly free: the converter already samples from the YUV planes into a 320×320 destination, so rotating is an index permutation in a loop that runs anyway, not a second pass over the pixels. The detector therefore always receives frames in *display* orientation and one coordinate space holds end to end.

Two consequences we accept:

- **Rotating clears the rim.** It was marked in normalized frame coordinates, which mean something different after a quarter-turn. Re-prompting is better than scoring against a rim that is no longer where the user pointed.
- **The preview is letterboxed, not cropped.** `BoxFit.cover` cropped the frame, so the detector reasoned about pixels the user could not see and a rim tap landed on different pixels than the ones scored against it. `contain` costs black bars and buys a coordinate space that is actually true.

The rotation is covered by unit tests (`test/frame_converter_test.dart`), including a case that distinguishes clockwise from counter-clockwise — the failure mode here is subtle enough that the corner cases alone would not catch it.

*Revisit if:* a device turns up whose sensor orientation is not 90°, which would make the landscape case need a turn too.

---

### D-012 — Detection runs in a background isolate
**2026-07-31 · Accepted · Supersedes D-010**

D-010 traded UI smoothness for avoiding a per-frame reshape. That trade is no longer necessary: rather than using `IsolateInterpreter` with its shaped nested-list inputs, we spawn our own isolate that owns the interpreter outright and keeps the flat `setTo`/`invoke` path. No reshaping, and nothing blocks the UI.

Conversion moved across with it. Inference is the obvious cost, but YUV→RGB is pure Dart over ~300k pixels per frame, so leaving it behind would still jank the preview.

Details worth knowing:

- The worker cannot use `rootBundle` — a spawned isolate has no binary messenger — so the model bytes are read once on the main isolate and passed to `Interpreter.fromBuffer`.
- Frame planes travel as `TransferableTypedData`, which moves the buffers rather than copying ~460 KB thirty times a second. Safe because the camera plugin hands us a fresh copy per frame.
- Backpressure is unchanged and still the point: `process` returns null while the worker is busy, and the caller drops that frame without copying anything.
- A frame that throws inside the worker resolves as "no detections" rather than as an error. The tracker is built to ride through a missing frame; that is a strictly easier problem than an exception at the call site.

*Revisit if:* profiling shows the isolate hop is a meaningful share of per-frame latency, which would argue for batching or a shared-memory ring buffer.

---

## Deferred — decide later, on purpose

| Question | Decide by |
|---|---|
| Is there an iOS version? | After Phase 2. Flutter keeps it open; nothing before then should close it. |
| Cloud sync / accounts? | Phase 5, and only if wanted. |
| Multi-user or team features? | Post-1.0. |
| How player templates are actually derived | Before Phase 4 begins. |
| Monetization, if any | Not before 1.0 ships — and note D-005 constrains the options. |

# Game day guide

How to actually use ShotBuddy at the court, and what to expect from it.

## Install

Plug the phone in with USB debugging on, then:

```bash
flutter install
```

Or build an APK and sideload it:

```bash
flutter build apk --debug
```

The file lands at `build/app/outputs/flutter-apk/app-debug.apk`.

## Setting up at the court

1. **Prop the phone in landscape**, roughly side-on to the hoop — a bag, a water bottle, or a cheap tripod all work. Baseline-corner or wing works better than straight-on from the free-throw line, because dead-on the ball passes in front of the rim and the depth is impossible to read.
2. **Frame it so the whole arc fits**, not just the hoop. The rules need to see the ball rise above the rim before they'll count anything coming down.
3. **Tap the front of the rim** when prompted. That's the calibration.
4. Shoot. The counter updates on its own.
5. **Don't move the phone.** If it gets bumped, hit the crosshair button and tap the rim again.

## The buttons

| Button | What it does |
|---|---|
| **MAKE / MISS** | Log a shot by hand. Always available. |
| ↩ Undo | Remove the last shot |
| ⇄ Flip | Change the last shot from make to miss or back |
| ⌖ Crosshair | Recalibrate the rim |
| 🐛 Bug | Debug panel: FPS, inference time, all detected objects, rim-width slider |
| ↻ Reset | Start a fresh session (asks first) |

The ball's box changes colour with the shot state: **white** idle, **yellow** the ball is up and an attempt is live, **green** it's crossing the rim.

## What to expect tonight

Be realistic — this is a stock COCO detector doing a job it wasn't trained for, plus one evening of tuning.

**Should work reasonably:** good outdoor or bright gym light, an orange ball against a contrasting background, one shooter at a time, phone 4–8 metres from the hoop.

**Will struggle:** dim gyms, several balls in frame at once, the ball passing in front of a similarly coloured wall, anyone standing between the phone and the hoop, very fast shots at low frame rates.

**The tally can be trusted because you can fix it.** MAKE/MISS/Undo/Flip are always on screen. If detection has a bad run, tap it in and keep playing — those corrections are exactly the signal we want.

## If it's not detecting the ball

Open the debug panel (🐛) and look:

- **`ball —` and few objects** → the detector isn't finding the ball. Better light, or move the phone closer.
- **`fps` under 8** → too slow to follow the arc. Close background apps; the detector is doing real work per frame.
- **Boxes drawn in the wrong place** → the preview and the detector disagree about coordinates. Note the phone model and file an issue; that's a bug, not a setup problem.
- **Counting makes that missed** → widen or narrow the gate with the rim-width slider in the debug panel. Narrower is stricter.

## What to bring back

The most valuable thing from tomorrow isn't the stats — it's knowing where it fails. Note:

- roughly how many of 50 shots it got right
- what the FPS held at
- which situations broke it

That's what Phase 1 proper gets trained on.

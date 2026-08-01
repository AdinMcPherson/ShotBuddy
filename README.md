# ShotBuddy

**An open-source, offline-first Android app that watches you shoot hoops and tracks every make and miss — using on-device AI.**

Point your phone at the hoop, hit record, and shoot. ShotBuddy detects the ball and the rim, follows the ball's arc, and decides whether it went in. No manual tapping, no cloud, no account.

> **Status: Phase 1 in progress — first working build.** Live camera detection, tap-to-calibrate rim, automatic make/miss counting, and manual override all work. Accuracy is untested in a real gym. See [docs/GAMEDAY.md](docs/GAMEDAY.md) to run it and [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

## Try it

```bash
flutter pub get && flutter run
```

Needs a physical Android device — an emulator's fake camera can't validate anything. Prop the phone in landscape, tap the rim once, and shoot.

---

## The vision, in three steps

| | What it does | Phase |
|---|---|---|
| 🏀 **Count** | Auto-detect makes and misses from the camera in real time | 1–2 |
| 📊 **Understand** | Session history, shooting %, hot/cold zones, streaks, trends | 2 |
| 🎯 **Improve** | Analyze your shooting form, then compare it to NBA players you pick | 3–4 |

## Principles

1. **Free to build, free to run.** Every tool in the stack has a free tier we stay inside. No paid APIs, no cloud inference bills.
2. **On-device only.** Video frames never leave the phone. Through Phase 4 the app ships *without* the `INTERNET` permission — the privacy claim is enforced by Android, not by a promise.
3. **Open by default.** Public repo, documented decisions, reproducible model training.
4. **Ship the risky part first.** Camera detection is the hard problem, so it's Phase 1. No point polishing a UI around a feature that might not work.

## Documentation

- [docs/GAMEDAY.md](docs/GAMEDAY.md) — how to set up at the court and what to expect
- [docs/ROADMAP.md](docs/ROADMAP.md) — the phases, what "done" means for each, and the risks
- [docs/TECH_STACK.md](docs/TECH_STACK.md) — every dependency, why it was chosen, and its license
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the detection pipeline and app layers fit together
- [docs/DECISIONS.md](docs/DECISIONS.md) — the record of choices made and the ones deliberately deferred
- [SECURITY.md](SECURITY.md) — threat model, disclosure process, and public-repo rules
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to set up and contribute

## License

[AGPL-3.0](LICENSE). See [docs/TECH_STACK.md#licensing](docs/TECH_STACK.md#licensing) for why this license and not MIT.

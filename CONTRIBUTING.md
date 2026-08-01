# Contributing

Thanks for looking. ShotBuddy is in Phase 0 (planning) — see [docs/ROADMAP.md](docs/ROADMAP.md). The most useful contributions right now are feedback on the plan.

## Setup

Requires Flutter 3.41+ and an Android device or emulator. Model weights are in Git LFS, so install it first.

```bash
git lfs install
```

```bash
git clone https://github.com/AdinMcPherson/ShotBuddy.git
```

```bash
cd ShotBuddy && flutter pub get && flutter run
```

Detection needs a **physical device** — an emulator's fake camera can't validate anything real.

## Before you open a PR

```bash
flutter analyze && flutter test && dart format --set-exit-if-changed .
```

## Ground rules

Read [SECURITY.md](SECURITY.md) first. The short version, because this is a public repo:

- **No secrets in any commit** — no keys, tokens, keystores, or `.env` files.
- **No personal data** — no sample video, no photos of identifiable people, no location data, in commits or in issues.
- **No NBA footage, images, or logos.** Player form data is numeric only, with documented provenance.
- **Adding the `INTERNET` permission requires a security review.** Phases 0–4 ship without it deliberately (see [D-004](docs/DECISIONS.md)).
- **New dependencies** need a note on license and network behavior in the PR description.

## Code conventions

- The `domain/` layer stays pure Dart — no Flutter imports, so shot logic is testable without a device.
- Widgets don't touch the database; the domain layer owns writes.
- Any change to make/miss logic needs unit tests covering makes, misses, rim-outs, and occlusion gaps.

## Architectural changes

If you're proposing something that changes the design, open an issue first and, if it's accepted, add an entry to [docs/DECISIONS.md](docs/DECISIONS.md) in the PR.

## License

Contributions are licensed under [AGPL-3.0](LICENSE).

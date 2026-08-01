# Security

ShotBuddy is a public, open-source app that uses a phone camera, potentially pointed at minors on a public court. That combination deserves to be taken seriously, so the security posture is written down before any code exists.

## Reporting a vulnerability

Report privately via **GitHub → Security → Report a vulnerability** on this repository. Please do not open a public issue for a security problem.

Expect an acknowledgement within 7 days. Please allow 90 days before public disclosure.

## Threat model

The genuinely sensitive asset here is **video of people**. Everything else follows from protecting that.

| Threat | Control |
|---|---|
| Camera frames leaking off-device | Phases 0–4 ship **without the `INTERNET` permission**. Exfiltration is blocked by the OS, not by our good intentions. Any PR adding that permission requires an explicit security review. |
| Video written to disk and forgotten | Frames are processed in memory and discarded. No video or images are persisted. Only numeric shot records are stored. |
| Third-party SDK phoning home | No analytics, crash-reporting, ads, or auth SDKs. Every new dependency is reviewed for network behavior. |
| Signing key compromise | Keystores and `key.properties` are gitignored and never committed. Release signing uses GitHub Actions secrets. |
| Malicious dependency | `pubspec.lock` is committed, Dependabot is enabled, and version bumps get reviewed rather than auto-merged. |
| Secret accidentally committed | GitHub secret scanning + push protection enabled. If a secret is ever pushed, it is treated as compromised and rotated — removing the commit is not sufficient. |
| Tampered model weights | Model files are tracked in Git LFS with recorded checksums, and are reproducible from the committed training notebook and dataset manifest. |

## Rules for this repo

Because it is public:

1. **No secrets, ever.** No API keys, tokens, keystores, `.env` files, or credentials in any commit — including in history, comments, test fixtures, or screenshots.
2. **No personal data.** No sample video, no photos of identifiable people, no location data, no device identifiers in issues or logs.
3. **Committed logs and debug output must be scrubbed** of paths, device names, and anything identifying.
4. **Dependencies are pinned** and reviewed before upgrade.
5. **CI never runs untrusted code with secrets.** Workflows triggered by forked PRs get no access to repository secrets.

## Privacy commitments (Phase 1–4)

- The camera is active only while a session is running, with a visible indicator.
- No video or still images are stored, anywhere, at any time.
- No data leaves the device. There is no server.
- Stored data is limited to: timestamps, make/miss, court position, confidence values, and derived numeric form metrics.
- The user can export or delete all of their data from within the app.

If Phase 5 introduces optional cloud sync, it will be opt-in, off by default, documented in a real privacy policy, and reviewed against this document before shipping.

## Legal and content rules

These are enforced as strictly as the security rules.

- **No NBA or team footage, images, logos, or marks** in this repository or bundled in the app.
- Player form "templates" are **derived numeric data** (joint-angle profiles), and each must ship with documented provenance describing how it was derived and from what source.
- Player names are used descriptively only, to identify a shooting style. No endorsement is implied or claimed.
- No scraping of any service in violation of its terms. Datasets are used under their stated licenses, and each dataset's license is recorded in the dataset manifest.

## Responsible use

Anyone recording on a public court should be mindful of others in frame. The app's design — process in memory, store nothing, transmit nothing — is intended to make this the default rather than a setting the user has to find.

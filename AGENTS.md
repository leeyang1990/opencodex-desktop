# Repository guide

OpenCodex Desktop is a standalone macOS launcher written in Swift. The tracked
repository must never contain the OpenCodex upstream source, generated app
bundles, downloaded runtimes, provider configuration, credentials, or logs.

## Layout

- `Sources/OpenCodexDesktop/` — app, management client, and core installer.
- `Tests/OpenCodexDesktopTests/` — XCTest coverage.
- `Assets/` — launcher-owned visual assets.
- `scripts/` — local build tooling.
- `vendor/opencodex/` — optional ignored upstream checkout for API reference.

## Rules

- Keep the launcher and core lifecycle separate.
- Pin every downloaded artifact to HTTPS and an exact digest.
- Never send the management token to a non-loopback host.
- Do not persist or log API keys, account identifiers, or request bodies.
- Core updates must be compatibility-bound by the launcher; do not follow an
  unverified upstream `latest` release at runtime.
- Run `swift test` and `./scripts/build-app.sh` for functional changes.

# Contributing to OpenCodex Desktop

Thank you for helping improve OpenCodex Desktop. Contributions should preserve the launcher's small trust boundary and keep the OpenCodex Core lifecycle separate from the macOS client.

## Development setup

Requirements:

- macOS 14 or later
- Xcode Command Line Tools
- Swift 5.10 or later

```bash
git clone https://github.com/leeyang1990/opencodex-desktop.git
cd opencodex-desktop
swift test
./scripts/build-app.sh
```

The build is written to `dist/OpenCodex Desktop.app`. Generated bundles, downloaded runtimes, local Core source, Provider configuration, credentials, and logs must never be committed.

## Before opening a pull request

```bash
./scripts/check-source-quality.sh
swift test
./scripts/build-app.sh
```

- Keep changes focused and include tests for behavior changes.
- Update both `README.md` and `README.en.md` when user-facing documentation changes.
- Update `CHANGELOG.md` for notable user-facing changes.
- Pin downloaded artifacts to HTTPS and an exact SHA-256 digest.
- Never log or persist API keys, account identifiers, management tokens, or request bodies.
- Do not weaken the loopback-only management boundary.

## Pull requests

Describe the problem, the chosen design, verification performed, and any compatibility or security impact. Screenshots are welcome for UI changes, but redact account information, API keys, internal hostnames, and other private data.

Review [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/API_CONTRACT.md](docs/API_CONTRACT.md) before changing lifecycle, networking, or configuration behavior.

For vulnerabilities, do not open a public issue. Follow [SECURITY.md](SECURITY.md).

<p align="center">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

<div align="center">
  <img src="Assets/AppIcon-Source.png" width="136" alt="OpenCodex Desktop icon">
  <h1>OpenCodex Desktop</h1>
  <p><strong>A native macOS control panel for OpenCodex Core</strong></p>
  <p>
    Install and manage the local core, Providers, models, and account pools from a clean SwiftUI interface.
  </p>
  <p>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple&logoColor=white">
    <img alt="Swift 5.10" src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white">
    <img alt="Apple Silicon" src="https://img.shields.io/badge/macOS-Apple_Silicon-2563EB?style=flat-square&logo=apple&logoColor=white">
    <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-10B981?style=flat-square"></a>
  </p>
  <p>
    <a href="https://github.com/leeyang1990/opencodex-desktop/releases">Releases</a>
    · <a href="#interface-preview">Interface Preview</a>
    · <a href="#development">Local Build</a>
    · <a href="#security-boundary">Security</a>
    · <a href="#contributing">Contributing</a>
    · <a href="#acknowledgements">Acknowledgements</a>
  </p>
</div>

---

## Overview

OpenCodex Desktop is a standalone, lightweight macOS launcher. It is not a fork of OpenCodex, and it neither modifies nor bundles the upstream project. The app communicates with OpenCodex Core through a local management API and provides a native desktop experience for everyday configuration and operations.

### Highlights

- **Core lifecycle management** — Install, launch, and inspect an OpenCodex Core version compatible with the desktop client.
- **Provider configuration** — Manage service providers and connection settings through a graphical interface.
- **Model management** — Browse the model catalog and maintain custom models and capabilities.
- **Account pool management** — Inspect account health and configure rotation strategies.
- **Local-first design** — The management interface only connects to loopback addresses, and sensitive configuration is never bundled with the app or committed to the repository.
- **Verifiable installation** — Downloads use pinned HTTPS URLs, with SHA-256 verification for the core, lockfile, and runtime.

## Interface Preview

<p align="center">
  <a href="Assets/screenshots/overview.png">
    <img src="Assets/screenshots/overview.png" width="100%" alt="OpenCodex Desktop overview">
  </a>
</p>
<p align="center">
  <sub>Service, Provider, default route, and local runtime status at a glance</sub>
</p>

<table>
  <tr>
    <td width="50%">
      <a href="Assets/screenshots/accounts.png">
        <img src="Assets/screenshots/accounts.png" alt="OpenCodex Desktop account pool">
      </a>
    </td>
    <td width="50%">
      <a href="Assets/screenshots/models.png">
        <img src="Assets/screenshots/models.png" alt="OpenCodex Desktop model management">
      </a>
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>Account Pools and Rotation</strong><br>
      <sub>Review health and usage, then configure account rotation</sub>
    </td>
    <td align="center">
      <strong>Model Catalog and Routing</strong><br>
      <sub>Filter models by Provider and control their visibility to Codex</sub>
    </td>
  </tr>
</table>

## Compatibility

Each desktop release is bound to a verified set of core and runtime versions. The app never follows an unverified `latest` release at runtime.

| Component | Current version |
| :--- | :--- |
| OpenCodex Desktop | `0.6.1` (`6`) |
| OpenCodex Core | `2.12.0` (`6d881db`) |
| Bun | `1.3.14` |
| macOS | `14.0` or later |
| Architecture | Apple Silicon (arm64) |

## Architecture

```text
┌──────────────────────────┐       loopback management API       ┌──────────────────────┐
│  OpenCodex Desktop       │ ◀─────────────────────────────────▶ │  OpenCodex Core      │
│  SwiftUI launcher        │                                     │  pinned + verified   │
└──────────────────────────┘                                     └──────────────────────┘
            │                                                               │
            │ installs runtime                                              │ reads configuration
            ▼                                                               ▼
~/Library/Application Support/                                  ~/Library/Application Support/
OpenCodex Desktop/Core/                                          OpenCodex/Data/
```

The desktop app installs and runs a compatible core. User data—including Providers, accounts, and tokens—remains in a separate data directory. Updating or removing the core runtime does not delete this configuration.

## Development

### Requirements

- macOS 14+
- Xcode Command Line Tools
- Swift 5.10+

Clone and verify the project:

```bash
git clone https://github.com/leeyang1990/opencodex-desktop.git
cd opencodex-desktop
swift test
./scripts/check-source-quality.sh
```

Build the Apple Silicon app bundle:

```bash
./scripts/build-app.sh
```

The resulting bundle is written to:

```text
dist/OpenCodex Desktop.app
```

The build script packages only the Swift client, app icon, and license files. It does not copy `vendor/`, OpenCodex source code, `node_modules`, or Bun into the bundle.

### Creating a GitHub Release

Update the version and build number in `Info.plist`, then run the release script from a clean Git worktree:

```bash
./scripts/release.sh 0.6.1
```

The script runs the test suite, builds the Apple Silicon app, verifies the pure `arm64` architecture and ad-hoc signature, and produces an installer-style DMG with an Applications shortcut, a portable ZIP, and SHA-256 checksums for both under `dist/release/`. Core files, runtimes, Provider configuration, credentials, and logs are excluded.

Release builds currently use free ad-hoc signing and are not notarized by Apple. On first launch, right-click the app and choose **Open**. If Gatekeeper still blocks the app, verify that the downloaded SHA-256 matches the Release attachment, then run:

```bash
xattr -dr com.apple.quarantine "/Applications/OpenCodex Desktop.app"
```

Use `--allow-dirty` only to validate local, uncommitted changes. Production releases should always be built from a clean tag.

The repository includes an automated release workflow. After merging the version change, create and push a tag that matches `Info.plist`:

```bash
git tag v0.6.1
git push origin v0.6.1
```

GitHub Actions runs the same tests, build, and verification steps on a macOS ARM runner, then creates a GitHub Release with generated release notes, the arm64 DMG and ZIP, and their SHA-256 checksums. The workflow requires no signing certificate or custom secret; it uses only the repository-scoped token provided by GitHub.

## Project Structure

```text
.
├── Assets/                         # Launcher-owned visual assets
├── Sources/OpenCodexDesktop/       # SwiftUI client and core installer
├── Tests/OpenCodexDesktopTests/    # XCTest coverage
├── scripts/build-app.sh            # Apple Silicon packaging script
├── scripts/check-source-quality.sh # Swift format and credential-pattern checks
├── scripts/release.sh              # Release validation, archive, and checksum
├── docs/API_CONTRACT.md             # Local Desktop-to-Core API contract
├── CONTRIBUTING.md                  # Contribution and verification workflow
├── SECURITY.md                      # Vulnerability reporting and boundaries
├── CHANGELOG.md                     # Release history
├── Info.plist                      # App bundle metadata
├── Package.swift                   # Swift Package manifest
└── THIRD_PARTY_NOTICES.md          # Third-party component notices
```

To reference the upstream API locally, clone a pinned source version into the ignored `vendor/opencodex/` directory:

```bash
git clone --branch v2.12.0 --single-branch \
  https://github.com/lidge-jun/opencodex.git vendor/opencodex
```

## Local Files

```text
~/Library/Application Support/OpenCodex Desktop/
├── Core/versions/<version>/    # Separately installed core and Bun runtime
├── Core/cache/                 # Download cache
└── Logs/core.log               # Core runtime log

~/Library/Application Support/OpenCodex/
└── Data/                       # Provider, account, and model configuration
```

## Security Boundary

- The management token is never sent to a non-loopback host.
- API keys, account identifiers, and request bodies are never persisted in logs.
- Downloaded artifacts must use pinned HTTPS URLs and exact digests.
- Core compatibility must be explicitly verified before the desktop client updates it.
- External login links are restricted to official OpenAI and ChatGPT HTTPS domains.
- Core data, state, and logs use permissions limited to the current user.
- Generated apps, runtimes, configuration, credentials, and logs are excluded from version control.

## Contributing

Issues and pull requests are welcome. Start with the [contribution guide](CONTRIBUTING.md), [architecture guide](docs/ARCHITECTURE.md), [security policy](SECURITY.md), and [Core API contract](docs/API_CONTRACT.md). User-facing changes are recorded in [CHANGELOG.md](CHANGELOG.md). Report vulnerabilities through GitHub private vulnerability reporting and never post keys, account identifiers, or unredacted configuration publicly.

## Acknowledgements

OpenCodex Desktop is made possible by [OpenCodex](https://github.com/lidge-jun/opencodex). Our sincere thanks go to the OpenCodex maintainers and every contributor who invests their time and effort in building and maintaining this excellent open-source project for the community.

This project is an independently developed community desktop client and is not an official OpenCodex distribution. We deeply appreciate the upstream project and encourage users to explore, use, and support the original work.

## License and Third-Party Components

OpenCodex Desktop is released under the [MIT License](LICENSE). OpenCodex Core is an independent third-party project downloaded on demand from its official distribution channel and governed by its own license. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

<p align="center">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

<div align="center">
  <img src="Assets/AppIcon-Source.png" width="120" alt="OpenCodex Desktop icon">
  <h1>OpenCodex Desktop</h1>
  <p><strong>Native macOS launching, diagnostics, and updates for OpenCodex</strong></p>
  <p>Manage the local Core and Codex CLI while leaving Providers, accounts, models, and routing to the OpenCodex Console.</p>
  <p>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple&logoColor=white">
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple_Silicon-arm64-2563EB?style=flat-square&logo=apple&logoColor=white">
    <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-10B981?style=flat-square"></a>
  </p>
  <p>
    <a href="https://github.com/leeyang1990/opencodex-desktop/releases/latest"><strong>Download Latest</strong></a>
    · <a href="CONTRIBUTING.md">Contributing</a>
    · <a href="SECURITY.md">Security</a>
  </p>
</div>

---

OpenCodex Desktop is an independently developed community macOS client. It is not an OpenCodex source fork and does not bundle upstream source, account data, or Provider configuration. It focuses only on local capabilities a web page cannot perform independently.

## Preview

<p align="center">
  <a href="Assets/screenshots/native-control-center-v010.png">
    <img src="Assets/screenshots/native-control-center-v010.png" width="100%" alt="Real OpenCodex Desktop interface">
  </a>
</p>
<p align="center"><sub>Generated from the real app UI with local ports, PIDs, timestamps, and capacity details redacted.</sub></p>

## Highlights

- **Core lifecycle** — Install, start, stop, and restart a compatible Core, retaining verified versions for failed-update rollback.
- **Select a Codex CLI for Core** — Discover and validate CLIs from NVM, Homebrew, Codex.app, ChatGPT.app, and PATH. Selection affects only Core; it does not change the system command or switch accounts.
- **Diagnostics and repair** — Inspect integrity, ports, disk space, token permissions, listening scope, code signature, and login items even while Core is offline.
- **Native macOS integration** — Menu bar controls, Dock visibility, login items, notifications, Shortcuts, and a safe URL scheme.
- **Verified updates** — Check GitHub Releases, download the exact Apple Silicon DMG, and verify its SHA-256 before opening it.
- **OpenCodex Console entry** — Use Core-provided Provider, account, model, routing, log, and usage management in a dedicated tab.

## Desktop and Console Responsibilities

| OpenCodex Desktop | OpenCodex Console |
| :--- | :--- |
| Core installation, lifecycle, updates, and rollback | Providers, accounts, models, and routing |
| Local Codex CLI discovery, validation, and selection | Codex login and account pools |
| Host diagnostics, security audit, and macOS integration | Logs, usage, and business configuration |

## Download and Install

Requires macOS 14 or later. Builds are currently available for Apple Silicon (arm64) only.

Download the DMG from [GitHub Releases](https://github.com/leeyang1990/opencodex-desktop/releases/latest) and drag the app into Applications; the ZIP is available for portable use. Releases use free ad-hoc signing and are not Apple-notarized, so the first launch may require right-clicking the app and choosing **Open**. Verify the SHA-256 attachment when possible.

## Behavior Boundaries

- Core is decoupled from the Desktop window after launch; quitting Desktop does not stop an already-running Core.
- To disable the proxy, explicitly choose **Stop Core** in Desktop.
- Selecting a Codex CLI only specifies an executable for the Core process. It does not modify global `PATH`, terminal commands, or Codex accounts.
- Provider, account, and model configuration remains in a separate OpenCodex data directory and survives Core updates or removal.
- Desktop management requests connect only to loopback hosts.

## Local Development

Requires macOS 14+, Xcode Command Line Tools, and Swift 5.10+:

```bash
git clone https://github.com/leeyang1990/opencodex-desktop.git
cd opencodex-desktop
swift test
./scripts/check-source-quality.sh
./scripts/build-app.sh
```

The app bundle is written to `dist/OpenCodex Desktop.app`. See [CONTRIBUTING.md](CONTRIBUTING.md), the [architecture guide](docs/ARCHITECTURE.md), and the [Core API contract](docs/API_CONTRACT.md) for the complete development rules.

## Security and Privacy

- The management token is never sent to a non-loopback host.
- API keys, account identifiers, prompts, and request bodies are not written to the event timeline.
- Sanitized diagnostic bundles exclude credentials, account identifiers, request bodies, path inventories, and raw Core logs.
- Core, Bun, and client updates use pinned HTTPS URLs and exact digest verification.
- Generated apps, downloaded runtimes, configuration, credentials, and logs are excluded from Git.

Report vulnerabilities through GitHub private vulnerability reporting. Never include keys or unredacted configuration in a public issue.

## Acknowledgements and License

Thanks to the authors and contributors of [OpenCodex](https://github.com/lidge-jun/opencodex). This project is an independent community client, not an official OpenCodex distribution.

OpenCodex Desktop is released under the [MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components and [CHANGELOG.md](CHANGELOG.md) for release history.

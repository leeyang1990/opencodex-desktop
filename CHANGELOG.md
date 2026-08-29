# Changelog

All notable changes to OpenCodex Desktop are documented here. The project follows semantic versioning for tagged releases.

## 0.10.1 - 2026-08-30

### Changed

- Simplify Codex CLI selection: show the Core's actual selection first, recommend a stable local CLI, and keep alternate versions under an advanced disclosure.
- Rename binding language to make clear that Desktop only selects a Codex CLI for the Core process and does not modify the system command or switch accounts.
- Replace the illustrative mockup with a privacy-sanitized showcase generated from the real app UI.
- Reduce the Chinese and English READMEs to focused product, installation, development, and security guidance.

### Fixed

- Discover and validate Codex CLI installations from the Desktop process instead of treating a legacy Core process environment as the local installation result.
- Distinguish the Core's current runtime from historical saved paths so an available CLI is no longer presented as already selected.

## 0.10.0 - 2026-08-29

### Added

- Add a native Diagnostics & Repair center for Core installation integrity, disk capacity, local port ownership, Codex CLI discovery, management-token presence, and login-item approval.
- Add safe Core install, start, restart, log, and Finder actions that remain available even when the Core console is offline.
- Add a sanitized diagnostic ZIP export containing local runtime metadata and check results while explicitly excluding credentials, account identifiers, request bodies, and raw Core logs.
- Expand the menu bar with Core version/PID status, Console and Diagnostics navigation, restart, and log actions.
- Add a native runtime center for Core version, Codex CLI, uptime, local security, lifecycle controls, and recent events.
- Discover and validate Codex CLIs from an explicit Desktop preference, Core state, NVM, Homebrew, Codex.app, ChatGPT.app, and PATH.
- Add a seven-day, allowlisted local event timeline for Core lifecycle and macOS sleep/wake checks, with optional native failure notifications.
- Add a local security audit for listening scope, management-token permissions, data-directory permissions, and app-bundle signature structure.
- Remember known-good Core installations, expose an explicit rollback action, and recover after a failed Core update.
- Add read-only `opencodex://` navigation routes and App Shortcuts for runtime status, diagnostics, and the OpenCodex Console.

### Changed

- Reposition the native app as a focused macOS launcher: the sidebar now contains only local Core status, Diagnostics & Repair, an OpenCodex Console entry, and macOS client settings.
- Remove Desktop's duplicate Provider, account-pool, model, routing, runtime-tuning, vision, and image-generation screens, state, API mutations, and tests. Those capabilities now live exclusively in the console provided by Core.
- Expand sanitized support bundles with security results, validated Runtime metadata, and allowlisted recent events while continuing to exclude raw paths and sensitive payloads.

### Fixed

- Avoid a transient false offline/port warning when diagnostics run during a background health refresh.

## 0.9.0 - 2026-08-28

### Added

- Add daily GitHub Release checks plus a manual update flow that downloads the exact Apple Silicon DMG, verifies its SHA-256 sidecar, and opens the validated installer image.
- Keep the local Core process running when the Desktop client exits or crashes so existing Codex account routing remains available until the user explicitly stops the service.

## 0.8.0 - 2026-08-28

### Added

- Add a persistent setting that hides the client from the Dock and app switcher while keeping its menu bar controls available.

## 0.7.1 - 2026-08-26

### Fixed

- Remove the pre-masked transparent icon corners so macOS can apply its native rounded mask without a white halo.

## 0.7.0 - 2026-08-25

### Added

- Add a first-launch environment check and a reusable Settings diagnostic for local storage, Core, management-token, Codex runtime, and login-item status.
- Add a Core version policy with a regression-tested build version and an explicitly selected, digest-pinned trusted version.

### Fixed

- Preserve the configured Codex CLI runtime when the desktop app starts from Finder with a minimal system `PATH`.
- Use the packaged application icon in the sidebar brand header instead of an unrelated system symbol.

## 0.6.1 - 2026-08-21

### Security

- Restrict externally opened Codex login URLs to official OpenAI and ChatGPT HTTPS domains.
- Enforce private permissions on Core data, state, cache, and log paths.
- Warn before using a non-loopback Provider over unencrypted HTTP.

### Changed

- Correct the macOS app icon scale and restore transparent rounded corners in packaged releases.
- Add a verified DMG release artifact with an Applications shortcut, alongside the portable ZIP.
- Split AppModel behavior into account, Provider, model, settings, and Core lifecycle domains.
- Centralize connection, timeout, and polling constants.
- Make Core configuration changes transactional and restore the prior configuration if restart fails.

### Tests

- Add request-header, unauthorized-response, login URL, Provider transport, file-permission, and app-icon coverage.

## 0.6.0 - 2026-08-20

- Add image generation Provider routing controls.
- Add forced GPT vision routing controls.
- Preserve existing Provider configuration while maintaining isolated image routes.

## 0.5.0 - 2026-08-19

- Initial public macOS launcher release.
- Add pinned Core and Bun installation, Provider/model/account management, local-only administration, arm64 packaging, and automated GitHub releases.

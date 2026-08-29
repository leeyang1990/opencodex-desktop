# Architecture

OpenCodex Desktop is a native SwiftUI launcher around a separately installed, compatibility-bound OpenCodex Core. The launcher does not bundle upstream source, runtimes, user configuration, credentials, or logs.

## Layers

```text
SwiftUI runtime center, diagnostics, console, and macOS settings
              │
              ▼
AppModel + Settings/Core lifecycle
              │
       ┌──────────┴──────────┬──────────────────┬──────────────────┬────────────────┐
       ▼                     ▼                  ▼                  ▼                ▼
OpenCodexAPIClient  CoreManager / Installer  Diagnostics     Runtime Discovery  App Updates
       │                     │                  │                  │                │
       ▼                     ▼                  ▼                  ▼                ▼
loopback API        pinned HTTPS artifacts  local macOS      local executables  GitHub Releases
       │                    │
       └─────────┬──────────┘
                 ▼
          OpenCodex Core process
```

`AppModel.swift` owns observable launcher state, health monitoring, and sleep/wake observation. `AppModel+Settings.swift` manages the Desktop connection, while `AppModel+Core.swift` owns installation and local process lifecycle. `CodexRuntimeDiscovery.swift` finds and validates local CLI candidates without reading Codex accounts. `EnvironmentDiagnostics.swift` and `SecurityAudit.swift` inspect local installation, port, disk, permissions, listening scope, runtime, login-item, and signature state. `DesktopEvents.swift` stores only allowlisted lifecycle events for seven days. `DiagnosticBundle.swift` exports a metadata-only support archive. Provider, account, model, routing, runtime tuning, vision, image generation, logs, usage, and integrations remain exclusively in the Core-provided console.

## Trust boundaries

1. **Management API** — the client constructs management URLs itself and accepts only loopback hosts. The management token is attached only after that check succeeds.
2. **Core installation** — the package, lockfile, and Bun runtime use pinned HTTPS URLs, size ceilings, and exact SHA-256 digests. Installation happens in a private staging directory before atomic publication.
3. **Client updates** — metadata is read only from this repository's latest stable GitHub Release. The updater requires an exact semantic tag and arm64 DMG/checksum asset names, restricts HTTPS hosts and sizes, and verifies SHA-256 before exposing the downloaded image to the user. It never silently installs or replaces the running app.
4. **Local data** — Core data, configuration state, cache, and logs are stored outside the app bundle with current-user-only permissions. The repository and release bundle exclude them. Desktop does not parse or mutate Provider, account, model, routing, vision, or image-generation configuration.
5. **Diagnostic exports** — support archives include only local runtime metadata and evaluated check results. Raw Core logs, credential values, account identifiers, and request bodies are deliberately excluded.
6. **System entry points** — App Shortcuts and `opencodex://` routes navigate to read-only app surfaces. They cannot start, stop, reinstall, or mutate Core configuration.

## Lifecycle

- The launcher discovers only manifests that match their version directory and use a safe semantic version.
- A runnable installation must match the bound Core version, commit, Bun version, and package digest.
- A started Core outlives the Desktop process. App termination detaches local process bookkeeping without sending a termination signal; reopening the app connects to the existing loopback service.
- Startup waits on the unauthenticated readiness endpoint with a deadline and cancellation support.
- Unexpected process termination is reported immediately from the process termination handler.
- A successful launch becomes the known-good Core version. A failed update can select and restart a previously verified installed release without deleting user configuration.
- A 60-second health monitor and macOS wake observer record only allowlisted state transitions; native notifications remain opt-in.
- Stop escalates from terminate to interrupt and finally `SIGKILL`; the launcher does not discard ownership while the process is still running.

## Compatibility changes

Changing the pinned Core requires updating `CoreRelease.compatible`, its tests, [API_CONTRACT.md](API_CONTRACT.md), both READMEs, and [CHANGELOG.md](../CHANGELOG.md). Functional changes must pass the source-quality check, test suite, and app-bundle build.

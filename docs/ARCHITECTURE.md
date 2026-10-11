# Architecture

OpenCodex Desktop is a small native SwiftUI shell around a separately installed, compatibility-bound OpenCodex Core. The launcher does not bundle upstream source, runtimes, user configuration, credentials, or logs.

The shell owns five main-window pages — overview, accounts, channels, subagents, and settings. It provides shorter native workflows for the settings users change every day. Advanced configuration opens the Core-served console in the default browser. Settings is a tab; both the menu-bar settings entry and the update indicator navigate to that same page. Diagnostics remains an auxiliary window available from Settings and the menu bar. There is no separate settings window or title-bar gear menu, and no embedded WebKit copy of the console.

`GlassDesignSystem.swift` draws light translucent cards and controls consistently across supported macOS versions. The window uses AppKit's active, behind-window `.underWindowBackground` material and a light appearance; reduced transparency uses opaque card surfaces. This is a frosted AppKit material, not the macOS 26 Liquid Glass API.

## Layers

```text
Shell surfaces: home · accounts · channels · subagents · diagnostics · settings
              │
              ▼
AppModel + Models/ChatGPT/Settings/Core lifecycle
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

`AppModel.swift` owns observable launcher state, health monitoring, and sleep/wake observation. `AppModel+Settings.swift` manages the Desktop connection, while `AppModel+Core.swift` owns installation and local process lifecycle. `AppModel+Accounts.swift` owns browser sign-in, account switching and pausing, plus the three common pool strategies. `AppModel+Channels.swift` owns channel creation, enablement, probing, default selection, and one-way key addition. `AppModel+Subagents.swift` owns model selection and preference order. `AppModel+Models.swift` reads the Core's model list and writes model visibility. `AppModel+Usage.swift` reads a seven-day aggregate for the home card; it never reads request content or account identity, and detailed usage analysis stays in the console. `AppModel+ChatGPT.swift` owns ChatGPT restarts, routing restore/re-point, and quit-time cleanup. `CodexRuntimeDiscovery.swift` finds and validates local CLI candidates without reading Codex accounts. `EnvironmentDiagnostics.swift` and `SecurityAudit.swift` inspect local installation, port, disk, permissions, listening scope, runtime, login-item, and signature state. `DesktopEvents.swift` stores only allowlisted lifecycle events for seven days. `DiagnosticBundle.swift` exports a metadata-only support archive. Account priority/cooldown/removal and detailed thresholds, channel dynamic models/key-pool maintenance/deletion, subagent fallback/polling, custom models, routing profiles, runtime tuning, vision, image generation, logs, detailed usage analysis, and integrations remain in the Core-provided console. Each Desktop page links directly to the matching console hash. Core is the only source of truth: the shell renders and mutates Core-owned state and never persists a parallel configuration model.

## Trust boundaries

1. **Management API** — the client constructs management URLs itself and accepts only loopback hosts. The management token is attached only after that check succeeds.
2. **Core installation** — the package, lockfile, and Bun runtime use pinned HTTPS URLs, size ceilings, and exact SHA-256 digests. Installation happens in a private staging directory before atomic publication.
3. **Client updates** — metadata is read only from this repository's latest stable GitHub Release. The updater requires an exact semantic tag and arm64 DMG/checksum asset names, restricts HTTPS hosts and sizes, and verifies SHA-256 before exposing the downloaded image to the user. It never silently installs or replaces the running app.
4. **Local data** — Core data, configuration state, cache, and logs are stored outside the app bundle with current-user-only permissions. The repository and release bundle exclude them. Desktop only reads and writes the documented high-frequency subset through the Core API; it does not parse Core configuration files or keep a second copy. It never reads key material: key-pool reads are masked. Model visibility is written through the Core's `PUT /api/model-visibility`, so toggling in the shell and toggling in the console are the same operation. Codex routing changes run through the Core's own `ocx restore` / `ocx restore back` commands, so ownership of the injected `openai_base_url` stays with the Core journal; the launcher only invokes the command and reads its machine-readable result.
5. **Channel credentials** — an API key typed into the shell is held in a session-scoped dictionary, sent once to `POST /api/providers/keys`, and dropped; it is never written to preferences, the event timeline, or a log, and the shell only ever reads back the Core's masked form. Codex sign-in never passes credentials through the client at all: the Core opens the browser and the client polls a flow id.
6. **Diagnostic exports** — support archives include only local runtime metadata and evaluated check results. Raw Core logs, credential values, account identifiers, and request bodies are deliberately excluded.
7. **System entry points** — App Shortcuts and `opencodex://` routes navigate to app surfaces only. They cannot start, stop, reinstall, or mutate Core configuration.

## Lifecycle

- The launcher discovers only manifests that match their version directory and use a safe semantic version.
- A runnable installation must match the bound Core version, commit, Bun version, and package digest.
- Closing the window leaves Desktop in the menu bar. App termination waits for the owned Core process to stop, restores the original Codex base URL through the Core CLI, then restarts the running Codex client. It never signals an unowned process.
- Startup waits on the unauthenticated readiness endpoint with a deadline and cancellation support.
- Unexpected process termination is reported immediately from the process termination handler.
- A successful launch becomes the known-good Core version. A failed update can select and restart a previously verified installed release without deleting user configuration.
- A 60-second health monitor and macOS wake observer record only allowlisted state transitions; native notifications remain opt-in.
- Stop escalates from terminate to interrupt and finally `SIGKILL`; the launcher does not discard ownership while the process is still running.
- Codex reads `~/.codex/config.toml` at launch, so Desktop quits the client cooperatively and relaunches it after restoring routing. Quit cleanup is mandatory; legacy preferences and cleanup timestamps cannot bypass it. A failed stop, restore, or client restart cancels termination and can be retried. If relaunch fails after the client quit, the next attempt still launches it. Concurrent quit requests share one cleanup task; only successful cleanup is marked complete.
- A quit-time restore records the Codex integration as off in the Core's desired state. The next launch re-points Codex at the running proxy, and a failed or timed-out restore keeps the client open with the reason rather than quitting silently.
- A one-shot Core CLI command (`ocx restore`) is bounded by its own deadline, event-driven rather than polled, so a hung command cannot block the quit path.
- An explicit **Stop** validates the Core's stop acknowledgement, confirms the owned process and loopback listener have stopped, then runs the Core-owned restore command and restarts ChatGPT only if it is running. A missing/negative acknowledgement, restore failure, or restart failure is reported without claiming complete success. A timeout is not proof of a stopped listener. Internal stops during restart, installation, or rollback do not restart ChatGPT; uninstall uses the explicit-stop cleanup. This is an intentional-stop workflow, not crash recovery.

## Compatibility changes

Changing the pinned Core requires updating `CoreRelease.compatible`, its tests, [API_CONTRACT.md](API_CONTRACT.md), both READMEs, and [CHANGELOG.md](../CHANGELOG.md). Functional changes must pass the source-quality check, test suite, and app-bundle build.

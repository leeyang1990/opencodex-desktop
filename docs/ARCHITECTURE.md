# Architecture

OpenCodex Desktop is a native SwiftUI launcher around a separately installed, compatibility-bound OpenCodex Core. The launcher does not bundle upstream source, runtimes, user configuration, credentials, or logs.

## Layers

```text
SwiftUI views and reusable components
              │
              ▼
AppModel state + domain extensions
  Accounts · Providers · Models · Settings · Core
              │
       ┌──────┴──────┐
       ▼             ▼
OpenCodexAPIClient  CoreManager / CoreInstaller
       │             │
       ▼             ▼
loopback API       pinned HTTPS artifacts
       │             │
       └──────┬──────┘
              ▼
       OpenCodex Core process
```

`AppModel.swift` owns observable application state and the initial refresh. Domain behavior is grouped in `AppModel+Accounts.swift`, `AppModel+Providers.swift`, `AppModel+Models.swift`, `AppModel+Settings.swift`, and `AppModel+Core.swift`. Large SwiftUI pages keep navigation in the page file and reusable cards/editors in component files.

## Trust boundaries

1. **Management API** — the client constructs management URLs itself and accepts only loopback hosts. The management token is attached only after that check succeeds.
2. **External login** — URLs returned by Core are opened only when they use HTTPS, contain no embedded credentials or non-standard port, and belong to an official OpenAI or ChatGPT domain.
3. **Core installation** — the package, lockfile, and Bun runtime use pinned HTTPS URLs, size ceilings, and exact SHA-256 digests. Installation happens in a private staging directory before atomic publication.
4. **Local data** — Core data, configuration state, cache, and logs are stored outside the app bundle with current-user-only permissions. The repository and release bundle exclude them.
5. **Configuration mutations** — settings that require a Core restart snapshot the configuration first. If the mutation or restart fails, the prior configuration is restored and the previous service is restarted when possible.

## Lifecycle

- The launcher discovers only manifests that match their version directory and use a safe semantic version.
- A runnable installation must match the bound Core version, commit, Bun version, and package digest.
- Startup waits on the unauthenticated readiness endpoint with a deadline and cancellation support.
- Unexpected process termination is reported immediately from the process termination handler.
- Stop escalates from terminate to interrupt and finally `SIGKILL`; the launcher does not discard ownership while the process is still running.

## Compatibility changes

Changing the pinned Core requires updating `CoreRelease.compatible`, its tests, [API_CONTRACT.md](API_CONTRACT.md), both READMEs, and [CHANGELOG.md](../CHANGELOG.md). Functional changes must pass the source-quality check, test suite, and app-bundle build.

# OpenCodex Core management contract

OpenCodex Desktop `0.10.2` keeps a pinned build Core and supports explicitly selected, digest-pinned Core versions. This document records the local API surface used by the launcher so Core upgrades can be reviewed as contract changes; online discovery is not a compatibility certification.

## Transport and authentication

- Scheme: HTTP on loopback only.
- Allowed hosts: `127.0.0.1`, `localhost`, and `::1`.
- Default port: `10100`.
- Health endpoint: unauthenticated.
- Management endpoints: `X-OpenCodex-API-Key`, loaded from the local token file or process environment.
- Request timeout: 12 seconds.

The client must never send the management token to a non-loopback host. API keys, account identifiers, and request bodies must not be logged.

## Read endpoints

| Method | Path | Purpose |
| :--- | :--- | :--- |
| `GET` | `/readyz` | Service readiness; unauthenticated |
| `GET` | `/api/settings` | Validated Codex runtime state for the native environment check; `startupHealth.routingInjected` tells the launcher whether Codex currently routes through this Core |
| `GET` | `/api/usage?range=7d` | Read-only seven-day aggregate for the home card: daily request counts, total tokens, metering coverage, and estimated cost; no prompt, response, credential, or account fields |
| `GET` | `/api/models` | Model rows for the native model list: `provider`, `id`, `namespaced`, `disabled`, and `native` for GPT passthrough rows |
| `GET` | `/api/config` | Provider summary for the shell: adapter, base URL, auth mode, account mode, and `hasApiKey`. Key material is never returned |
| `GET` | `/api/codex-auth/accounts` | Codex account pool: `id`, `email`, `plan`, `paused`, `priority`, `needsReauth`, weekly `quota`, and `health` |
| `GET` | `/api/codex-auth/active` | Scheduling state: active account, pinned flag, auto-switch threshold, failover threshold, pool strategy, sticky limit |
| `GET` | `/api/codex-auth/login-status?flowId=` | Progress of a browser sign-in; `done`, `pending`, `error`, `expired`, or `idle` |
| `GET` | `/api/providers` | API channels: adapter, base URL, `authMode`, `disabled`, `liveModels`, discovered models, and discovery health |
| `GET` | `/api/providers/keys?name=` | A channel's key pool, masked (`{"activeId":…,"keys":[{"id","masked","active"}]}`) |
| `GET` | `/api/subagent-models` | Chosen subagent models and the available list |

## Mutation endpoints

The launcher uses `POST /api/stop` to request a graceful Core shutdown, `PUT /api/model-visibility` to switch model visibility, and only the high-frequency mutation endpoints below. Detailed account tuning, full channel/key-pool maintenance, subagent fallback, routing profiles, runtime tuning, vision, and image generation remain owned by the Core-provided console.

### Accounts and scheduling

| Method | Path | Body |
| :--- | :--- | :--- |
| `POST` | `/api/codex-auth/login` | `{}` — the Core opens the browser and returns a `flowId` to poll |
| `GET` | `/api/codex-auth/login-status?flowId=` | Poll until `done`; surface `error` verbatim |
| `POST` | `/api/codex-auth/login/cancel` | `{flowId}` |
| `PUT` | `/api/codex-auth/active` | `{accountId}`; `null` returns to the plain Codex login |
| `PUT` | `/api/codex-auth/accounts/pause` | `{id, paused}` |
| `PUT` | `/api/codex-auth/pool-strategy` | `{strategy, stickyLimit}`; strategy is `quota`, `round-robin`, or `fill-first` |

Priority, cooldown recovery, account removal, auto-switch threshold, and upstream failover threshold are deliberately not mutated by Desktop; use the top-right Console entry for those controls.

### Channels

| Method | Path | Body |
| :--- | :--- | :--- |
| `POST` | `/api/providers` | `{name, provider:{adapter, baseUrl, …}, setDefault}` |
| `PATCH` | `/api/providers?name=` | A **flat** field mask (`{adapter?, baseUrl?, disabled?, liveModels?, note?}`) |
| `PATCH` | `/api/providers?name=` | `{setDefault:true}` — standalone only; the Core rejects it combined with any other field |
| `POST` | `/api/providers/test?name=` | No body; the name is a query parameter |
| `POST` | `/api/providers/keys` | `{name, key, label?}` — the only path that writes credentials |

Desktop uses provider `PATCH` only for `disabled` and the standalone default selection. Dynamic-model changes, key removal/activation, and channel deletion remain in the console at `#providers`.

Creation accepts `adapter`, `baseUrl`, `authMode`, `liveModels`, optional manual `models` and `defaultModel`, `allowPrivateNetwork` and `note`. Desktop re-reads names before the upsert endpoint, then creates without changing the default, writes a key through the separate credential endpoint, and only then sets the requested default. Explicit positive acknowledgements are required. Partial completion is reported without replaying creation; the Core API does not provide an atomic create-if-absent transaction. The form's Advanced configuration button opens `#providers` without placing form values or tokens in the URL.

Two traps verified against Core `2.31.0`: a nested `provider` object on `PATCH` returns
`no recognized fields to update` and changes nothing, and `apiKey` cannot be patched at all
(`apiKey cannot be patched here; use the provider API-key endpoints`).

### Subagents

| Method | Path | Body |
| :--- | :--- | :--- |
| `PUT` | `/api/subagent-models` | `{models:[...]}` — the Core keeps only the **first five**, silently |

Fallback models and their polling interval remain in the console at `#subagents`.

Because truncation is silent, the client caps the selection before sending and never claims a
sixth model was applied.

### Model visibility

```json
{"scope": "models", "provider": "new-api", "enabled": false,
 "targets": [{"id": "claude-haiku-4-5", "native": false}]}
```

- `scope` is `models` for individual rows and `provider` when every row of a provider is switched at once.
- `targets[].native` must agree with the provider: `true` only for `openai` GPT passthrough rows.
- `targets[].id` is the row's **bare `id`**, not its `namespaced` display form. The endpoint stores
  `provider/<id>` and compares against that, so sending a namespaced value persists a doubled
  prefix (`new-api/new-api/<id>`) that no later read matches — the write reports success and the
  model stays visible. Verified against Core `2.31.0`; routed rows read back as disabled only when
  addressed by their bare id.
- The response reports the persisted `disabled` list; a catalog refresh follows and is what makes
  the change visible to Codex, so a running ChatGPT still needs a restart to see it.

## Core CLI invocations

Codex routing is restored and re-pointed with the Core's own commands rather than by editing `~/.codex/config.toml`:

| Invocation | Purpose |
| :--- | :--- |
| `<core>/bin/bun <core>/package/src/cli/index.ts restore --json` | Restore native Codex routing while the proxy keeps running; the last stdout line is the machine-readable result and a missing `"success": true` must be treated as an unconfirmed restore |
| `<core>/bin/bun <core>/package/src/cli/index.ts restore back` | Re-point Codex at the running proxy after a restore |

Both run with the same `OPENCODEX_HOME`, `CODEX_HOME`, `CODEX_CLI_PATH`, and bundled-Bun variables the Core process receives, minus credential variables, and are bounded by a timeout so a hung command cannot block quitting.

A Core update is compatible only after response-decoding tests, security-boundary tests, and a real local lifecycle test all pass.

### Online version discovery

The Settings picker fetches public npm metadata for `@bitkyc08/opencodex` when opened or manually refreshed. Discovery does not install, restart, or change the selected Core. The build release remains the regression-tested default. Self-selected stable Core versions do not require a launcher-maintained Core or Bun allowlist. The selected version must declare an exact stable Bun version and verifiable package metadata; deprecated or incomplete releases remain unavailable. Installation validates the required CLI layout and frozen dependencies, and launch checks readiness rather than assuming a version number certifies compatibility.

Preparing an explicitly selected version re-fetches its immutable npm version record, verifies the package bytes against npm SHA-512 integrity, reads the lockfile at its exact `gitHead` via GitHub's content API and verifies the Git blob digest, and saves an exact SHA-256 installation descriptor. Installation later rechecks those digests. The lockfile trust root is GitHub HTTPS metadata at that commit; checksums are not a claim of upstream code review. Known bundled Bun digests remain available offline. For any other exact Bun version, preparation reads `oven-sh/bun`'s official GitHub release for `bun-v<version>`, requires the matching published tag, and pins the SHA-256 digests of both canonical macOS assets. Missing or malformed asset metadata fails preparation without changing the current selection. Prepared runtime digests survive offline restarts; installation rechecks the downloaded archive against them. Public metadata requests use an isolated ephemeral session with bounded responses, no management token/cookies/credentials, and no redirects.

The public metadata list and validated descriptors are cached locally without credentials. Failed refreshes preserve the last list and selection; cached descriptors let an explicit selection survive offline relaunch. Refreshing `latest` never changes an existing selection or its pinned digest.

## Upgrade checklist

1. Pin the Core package, lockfile, and Bun artifacts to immutable HTTPS URLs and exact digests.
2. Review every endpoint, method, authentication requirement, and response field used by `OpenCodexAPIClient`, including the bare-id addressing rule above.
3. Confirm every Desktop mutation belongs to the documented high-frequency subset and that advanced controls still open the matching console section.
4. Run `./scripts/check-source-quality.sh`, `swift test`, and `./scripts/build-app.sh`.
5. Update this document, both READMEs, and the changelog before tagging a release.

# OpenCodex Core management contract

OpenCodex Desktop `0.6.x` is compatibility-bound to OpenCodex Core `2.12.0` at commit `6d881db206c6a74da6b64fa22b6980faf05d0122`. This document records the local API surface used by the launcher so Core upgrades can be reviewed as contract changes.

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
| `GET` | `/api/config` | Active routing summary |
| `GET` | `/api/settings` | Runtime settings and Codex runtime state |
| `GET` | `/api/providers` | Redacted Provider configurations |
| `GET` | `/api/provider-presets` | Supported Provider presets |
| `GET` | `/api/models` | Managed model catalog |
| `GET` | `/api/selected-models` | Visibility and availability maps |
| `GET` | `/api/provider-context-caps` | Global and Provider context caps |
| `GET` | `/api/codex-auth/accounts` | Redacted Codex account state |
| `GET` | `/api/codex-auth/active` | Account pool selection and strategy |
| `GET` | `/api/codex-auth/login-status` | Browser login flow state |

## Mutation endpoints

The client uses `/api/providers`, `/api/providers/keys`, `/api/providers/test`, `/api/model-visibility`, `/api/custom-models`, `/api/provider-context-caps`, `/api/settings`, `/api/sync`, `/api/stop`, and the `/api/codex-auth/*` account management endpoints.

Provider and account responses must be redacted. A Core update is compatible only after decoding tests, security-boundary tests, and a real local lifecycle test all pass.

## Upgrade checklist

1. Pin the Core package, lockfile, and Bun artifacts to immutable HTTPS URLs and exact digests.
2. Review every endpoint, method, authentication requirement, and response field used by `OpenCodexAPIClient`.
3. Confirm Provider responses never include raw API keys and account responses expose only masked identity data.
4. Run `./scripts/check-source-quality.sh`, `swift test`, and `./scripts/build-app.sh`.
5. Update this document, both READMEs, and the changelog before tagging a release.

# OpenCodex Core management contract

OpenCodex Desktop `0.9.x` uses OpenCodex Core `2.12.0` at commit `6d881db206c6a74da6b64fa22b6980faf05d0122` as its compatibility-tested build version. This document records the intentionally small local API surface used by the launcher so Core upgrades can be reviewed as contract changes.

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
| `GET` | `/api/settings` | Validated Codex runtime state for the native environment check |

## Mutation endpoints

The launcher uses only `POST /api/stop` to request a graceful Core shutdown before applying its local lifecycle policy. All Provider, account, model, routing, runtime-tuning, vision, and image-generation mutations are owned by the Core-provided console.

A Core update is compatible only after response-decoding tests, security-boundary tests, and a real local lifecycle test all pass.

## Upgrade checklist

1. Pin the Core package, lockfile, and Bun artifacts to immutable HTTPS URLs and exact digests.
2. Review every endpoint, method, authentication requirement, and response field used by `OpenCodexAPIClient`.
3. Confirm Desktop has not gained new business-management endpoints that duplicate the Core console.
4. Run `./scripts/check-source-quality.sh`, `swift test`, and `./scripts/build-app.sh`.
5. Update this document, both READMEs, and the changelog before tagging a release.

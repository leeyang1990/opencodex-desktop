# Security Policy

## Supported versions

Security fixes are provided for the latest tagged OpenCodex Desktop release. Older releases should be upgraded before reporting a compatibility issue.

## Reporting a vulnerability

Please use [GitHub private vulnerability reporting](https://github.com/leeyang1990/opencodex-desktop/security/advisories/new). Do not include credentials, API keys, management tokens, account identifiers, request bodies, or unredacted configuration in a public issue.

Include only the minimum information needed to reproduce the problem:

- affected OpenCodex Desktop and Core versions;
- macOS version and architecture;
- security impact and reproduction steps;
- redacted logs or a minimal proof of concept;
- any known mitigation.

Please allow maintainers reasonable time to investigate and publish a coordinated fix before public disclosure.

## Security boundaries

- Management requests are restricted to loopback hosts.
- The management token is read only for authenticated local requests.
- Core, lockfile, and runtime downloads are pinned to HTTPS URLs and exact SHA-256 digests.
- Generated apps, downloaded runtimes, Provider configuration, credentials, and logs are excluded from version control and release bundles.
- External login links are restricted to official OpenAI or ChatGPT HTTPS domains.

OpenCodex Core is an independent upstream project. Vulnerabilities that affect only Core should also be reported to its maintainers through the upstream project's preferred channel.

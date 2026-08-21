# Changelog

All notable changes to OpenCodex Desktop are documented here. The project follows semantic versioning for tagged releases.

## Unreleased

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

- Add request-header, unauthorized-response, login URL, Provider transport, and file-permission coverage.

## 0.6.0 - 2026-08-20

- Add image generation Provider routing controls.
- Add forced GPT vision routing controls.
- Preserve existing Provider configuration while maintaining isolated image routes.

## 0.5.0 - 2026-08-19

- Initial public macOS launcher release.
- Add pinned Core and Bun installation, Provider/model/account management, local-only administration, arm64 packaging, and automated GitHub releases.

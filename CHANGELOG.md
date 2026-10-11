# Changelog

All notable changes to OpenCodex Desktop are documented here. The project follows semantic versioning for tagged releases.

## 0.10.6 - 2026-10-11

### 中文

- 移除设置页中无需用户操作的“退出清理 / 始终执行”说明。退出时仍自动停止本应用启动的 Core、恢复 Codex 原来的 base URL，并重启正在运行的 Codex。
- 修复 Core 命令快速退出时偶发丢失输出的问题，避免路由恢复成功后被误判为失败；继承输出管道的子进程不会阻塞退出。

### English

- Remove the informational "Quit Cleanup / Always enabled" row from Settings. Quitting still automatically stops the Core started by Desktop, restores the original Codex base URL, and restarts Codex if it is running.
- Preserve output when Core commands exit quickly, preventing successful routing restoration from being reported as a failure. Descendants inheriting the output pipe do not block completion.

### Downloads / 下载

- Apple Silicon (arm64), macOS 14+. DMG and ZIP include SHA-256 checksum files.
- Ad-hoc signed, not Apple-notarized. Core is installed separately; credentials, configuration and logs are not bundled.
- 仅提供 Apple Silicon 版本；安装包为临时签名，未经 Apple 公证。Core 单独安装，不包含账号、密钥、配置或日志。

## 0.10.4 - 2026-10-11

### 中文

- 退出固定执行停止本应用启动的 Core、恢复 Codex 原来的 base URL、重启正在运行的 Codex；移除退出清理开关和保留内核运行的旧说明。
- 停止、路由恢复或 Codex 重启失败时保留客户端并显示原因，再次退出会重试；并发退出共用一次清理，旧偏好和最近清理时间不再跳过必要步骤。
- 自选 Core 不再受客户端内置 Core/Bun 版本白名单限制。自动解析所选版本需要的 Bun，从官方发布信息锁定 macOS 安装包和 SHA-256，并保留下载校验、离线缓存与失败回滚。
- 账号列表显示可用充值卡，支持确认后使用一张重置额度；通过幂等请求和重复操作保护避免不确定网络响应造成重复消耗。
- 补充退出顺序、失败重试、进程归属、动态运行时解析、发布信息校验和充值卡请求测试。实测 Core 2.83.0 与 Bun 1.4.2 的下载、安装和版本选择。

### English

- Make quit cleanup mandatory: stop the Core started by Desktop, restore the original Codex base URL, then restart Codex if it was running. Remove the opt-out and stale background-Core guidance.
- Keep Desktop open when stopping, restoration or restart fails, and retry on the next quit. Concurrent quit requests share one cleanup; legacy preferences and recent cleanup timestamps cannot skip required steps.
- Let users select upstream Core releases without a built-in Core/Bun version allowlist. Resolve the required Bun version and macOS SHA-256 digests from official releases while retaining verified downloads, offline caching and rollback.
- Show available account quota-reset credits and allow using one after confirmation, with idempotent requests and duplicate-operation protection.
- Add coverage for cleanup ordering, retries, process ownership, dynamic runtime resolution, release metadata and reset-credit requests. Verify Core 2.83.0 with Bun 1.4.2 through real downloads, installation and version selection.

### Downloads / 下载

- Apple Silicon (arm64), macOS 14+. DMG and ZIP include SHA-256 checksum files.
- Ad-hoc signed, not Apple-notarized. Core is installed separately; credentials, configuration and logs are not bundled.
- 仅提供 Apple Silicon 版本；安装包为临时签名，未经 Apple 公证。Core 单独安装，不包含账号、密钥、配置或日志。

## 0.10.3 - 2026-09-21

### 中文

- 原生 App 支持中英文，自动跟随 macOS 首选语言，也支持系统中的单个 App 语言设置；没有匹配的语言时使用英文。更改语言后重新打开 App 即可。
- 补全导航、账号、渠道、子代理、设置、菜单栏、通知、诊断与错误提示，共 528 条本地化文案。
- 数字统计跟随界面语言显示；渠道名称、模型 ID、路径及服务端原始消息保持原样，不改动账号或路由配置。
- 中英文资源随 App 一起打包，不依赖开发目录。增加语言选择、动态插值安全、翻译完整性和快捷指令资源测试。
- 已实机检查中文、英文界面，验证设置和添加渠道表单的英文布局。

### English

- Localize the native app in English and Simplified Chinese, following macOS preferred languages and per-app language settings, with English as the fallback. Reopen the app after changing languages.
- Translate 528 app-owned strings across navigation, accounts, channels, subagents, settings, menus, notifications, diagnostics and errors.
- Format usage counts for the interface language. Preserve channel names, model IDs, paths and upstream messages without changing account or routing configuration.
- Package both languages inside the app without depending on development files. Add tests for language selection, safe interpolation, catalog completeness and shortcut resources.
- Verify both languages in the installed app, including English settings and channel-form layouts.

### Downloads / 下载

- Apple Silicon (arm64), macOS 14+. DMG and ZIP include SHA-256 checksum files.
- Ad-hoc signed, not Apple-notarized. Core is installed separately; credentials, configuration and logs are not bundled.
- 仅提供 Apple Silicon 版本；安装包为临时签名，未经 Apple 公证。Core 单独安装，不包含账号、密钥、配置或日志。

## 0.10.2 - 2026-09-21

### Added

- Native shortcuts for Codex account sign-in, switching, pausing and common scheduling strategies; channel setup and up to five ordered subagent model preferences.
- Complete common channel setup with protocol guidance, API-key or local authentication, automatic/manual model lists, a default model, private-network access and notes. **Advanced configuration** opens the Core WebUI's providers page without forwarding form values or credentials.
- Seven-day aggregate usage charts on the overview page, without reading request content.
- Independent startup controls for launching Desktop at login and starting Core with Desktop; automatic Core startup is off by default.
- Online Core version selection with a short recent-version list, exact artifact digests, compatibility limits and offline caching.
- Native ChatGPT restart and Core-owned routing restoration. Explicit **Stop** stops Core, restores routing and restarts ChatGPT if it is running. Optional quit-time restoration is separate; this does not provide crash recovery.

### Changed

- Keep overview, accounts, channels, subagents and settings in one main-window tab strip. Advanced management remains in the browser-based Core console; Desktop keeps no parallel provider configuration.
- Use a light AppKit frosted window, translucent white cards and higher-contrast controls. Refine the native menu-bar icon and Dock visibility behavior.
- Restore and re-point routing through bounded Core CLI commands rather than directly rewriting Codex configuration. Report partial failures instead of claiming successful cleanup.

### Fixed

- Correct channel API payloads and Gemini's `google` protocol identifier; validate names, addresses and model selections before saving.
- Check for existing channel names before Core's upsert endpoint, save credentials before switching the default, and display partial-save failures inside the form.
- Require positive write acknowledgements, prevent repeated saves, and cap subagent selections before sending them to Core.
- Improve local ChatGPT discovery, CLI checks, Dock policy reconciliation and stop/restore error handling.

### Downloads

- Apple Silicon (arm64), macOS 14 or later. DMG and ZIP include SHA-256 sidecars.
- Ad-hoc signed, not Apple-notarized. Core is installed separately; runtime files, user configuration, credentials and logs are excluded from the app bundle.

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

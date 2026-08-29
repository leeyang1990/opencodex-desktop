<p align="center">
  <strong>简体中文</strong> · <a href="README.en.md">English</a>
</p>

<div align="center">
  <img src="Assets/AppIcon-Source.png" width="120" alt="OpenCodex Desktop 图标">
  <h1>OpenCodex Desktop</h1>
  <p><strong>OpenCodex 的原生 macOS 启动、诊断与更新工具</strong></p>
  <p>管理本机 Core 与 Codex CLI；Provider、账号、模型和路由继续交给 OpenCodex 控制台。</p>
  <p>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple&logoColor=white">
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple_Silicon-arm64-2563EB?style=flat-square&logo=apple&logoColor=white">
    <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-10B981?style=flat-square"></a>
  </p>
  <p>
    <a href="https://github.com/leeyang1990/opencodex-desktop/releases/latest"><strong>下载最新版</strong></a>
    · <a href="CONTRIBUTING.md">参与贡献</a>
    · <a href="SECURITY.md">安全策略</a>
  </p>
</div>

---

OpenCodex Desktop 是独立开发的社区 macOS 客户端，不是 OpenCodex 的源码分支，也不会在 App 中内置上游源码、账号数据或 Provider 配置。它只处理 Web 页面无法独立完成的本机能力。

## 界面预览

<p align="center">
  <a href="Assets/screenshots/native-control-center-v010.png">
    <img src="Assets/screenshots/native-control-center-v010.png" width="100%" alt="OpenCodex Desktop 真实界面展示">
  </a>
</p>
<p align="center"><sub>基于真实 App 界面生成；已遮盖本机端口、PID、时间与容量信息。</sub></p>

## 核心能力

- **Core 生命周期** — 安装、启动、停止和重启兼容 Core，并保留已验证版本用于失败回滚。
- **为 Core 选择 Codex CLI** — 发现并验证 NVM、Homebrew、Codex.app、ChatGPT.app 与 PATH 中的 CLI；选择只对 Core 生效，不修改系统命令或切换账号。
- **诊断与修复** — 检查安装完整性、端口、磁盘、令牌权限、监听范围、代码签名和登录项，即使 Core 离线也可使用。
- **macOS 原生集成** — 菜单栏、Dock 显示策略、登录项、通知、快捷指令和安全 URL Scheme。
- **安全更新** — 检查 GitHub Release，下载精确匹配的 Apple Silicon DMG，并在打开前验证 SHA-256。
- **OpenCodex 控制台入口** — 在独立 Tab 中使用 Core 提供的 Provider、账号、模型、路由、日志和用量管理。

## 与 OpenCodex 控制台的分工

| OpenCodex Desktop | OpenCodex 控制台 |
| :--- | :--- |
| Core 安装、启停、更新与回滚 | Provider、账号、模型与路由 |
| 本机 Codex CLI 发现、验证与选择 | Codex 登录与账号池 |
| 本机诊断、安全审计和 macOS 集成 | 日志、用量和业务配置 |

## 下载与安装

要求 macOS 14 或更高版本，目前仅提供 Apple Silicon（arm64）版本。

从 [GitHub Releases](https://github.com/leeyang1990/opencodex-desktop/releases/latest) 下载 DMG，拖入“应用程序”即可；ZIP 可用于便携运行。发布包采用免费的 ad-hoc 签名，未经 Apple 公证，首次启动时可能需要右键 App 并选择“打开”。建议同时核对 Release 附件中的 SHA-256。

## 行为边界

- Core 启动后与 Desktop 窗口解耦；退出 Desktop 不会停止正在运行的 Core。
- 停用代理时，请在 Desktop 中明确点击“停止 Core”。
- 为 Core 选择 Codex CLI 只会向 Core 进程指定可执行文件，不修改全局 `PATH`、终端命令或 Codex 账号。
- Provider、账号和模型配置存放在独立的 OpenCodex 数据目录，更新或卸载 Core 不会删除它们。
- Desktop 的管理请求仅连接本机回环地址。

## 本地开发

需要 macOS 14+、Xcode Command Line Tools 与 Swift 5.10+：

```bash
git clone https://github.com/leeyang1990/opencodex-desktop.git
cd opencodex-desktop
swift test
./scripts/check-source-quality.sh
./scripts/build-app.sh
```

构建结果位于 `dist/OpenCodex Desktop.app`。完整贡献、架构和 API 约束参见 [CONTRIBUTING.md](CONTRIBUTING.md)、[架构说明](docs/ARCHITECTURE.md) 与 [Core API 契约](docs/API_CONTRACT.md)。

## 安全与隐私

- 管理令牌不会发送到非回环地址。
- API Key、账号标识、Prompt 和请求正文不会写入事件时间线。
- 脱敏诊断包不包含凭据、账号标识、请求正文、路径清单或 Core 原始日志。
- Core、Bun 与客户端更新均使用固定 HTTPS 地址和精确摘要校验。
- 生成的 App、下载运行时、配置、凭据和日志不会进入 Git 仓库。

安全问题请通过 GitHub 私密漏洞报告渠道提交，不要在公开 Issue 中附带密钥或未脱敏配置。

## 致谢与许可

感谢 [OpenCodex](https://github.com/lidge-jun/opencodex) 的作者和贡献者。本项目是独立社区客户端，并非 OpenCodex 官方发行版。

OpenCodex Desktop 采用 [MIT License](LICENSE)。第三方组件信息参见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，版本变更参见 [CHANGELOG.md](CHANGELOG.md)。

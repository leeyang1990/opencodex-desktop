<p align="center">
  <strong>简体中文</strong> · <a href="README.en.md">English</a>
</p>

<div align="center">
  <img src="Assets/AppIcon-Source.png" width="120" alt="OpenCodex Desktop 图标">
  <h1>OpenCodex Desktop</h1>
  <p><strong>OpenCodex 的日常 macOS 控制中心</strong></p>
  <p>常用配置在桌面快速完成，完整高级设置精准进入 OpenCodex 控制台。</p>
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

OpenCodex Desktop 是独立开发的社区 macOS 客户端，不是 OpenCodex 的源码分支，也不会在 App 中内置上游源码、账号数据或 Provider 配置。它既处理 Core 生命周期、诊断和 ChatGPT 生效等本机能力，也把账号、渠道和子代理中最常用的操作做成更短的原生流程。复杂参数仍由 OpenCodex 控制台完整管理。

## 界面预览

<p align="center">
  <img src="Assets/screenshots/native-shell-home.png" width="72%" alt="早期版本的原生界面预览">
</p>
<p align="center"><sub>早期版本的真实截图，布局以最新版为准。</sub></p>

## 核心能力

- **多账号快捷操作** — 在浏览器中添加 Codex 账号，查看额度，切换当前账号或暂停使用；凭证不经过客户端。
- **简化调度** — 直接选择按额度、轮询或用尽再换；阈值、优先级和冷却等细节留在控制台。
- **API 渠道快捷配置** — 添加、启停、设为默认并测试连通性；支持协议、密钥、自动/手动模型与内网地址。“高级配置”打开 WebUI 供应方页面。
- **子代理偏好** — 选择最多 5 个可用模型并调整偏好顺序；回退链和检查间隔留在控制台。
- **使用记录** — 概览页展示最近 7 天请求量、Token 与用量图表，不读取请求正文。
- **本机代理与 ChatGPT** — 启停代理、复制 Base URL、一键重启 ChatGPT；主动停止时还原路由，再重启正在运行的 ChatGPT。
- **安全更新** — 检查本仓库 Release，下载精确匹配的 Apple Silicon DMG，并在打开前验证 SHA-256。
- **在线内核版本** — 设置页自动获取上游稳定版本，支持手动刷新与离线缓存；自选版本按具体版本和摘要锁定，不随 `latest` 自动升级。未完整回归的新版本标为实验性，仅允许 Core 2.x 和已适配的 Bun。

## 界面

顶部导航包含概览、账号、渠道、子代理和设置，均在主窗口内切换：

| 页面 | 内容 |
| :--- | :--- |
| 概览 | 代理状态、Base URL、ChatGPT 重启、最近 7 天用量图表 |
| 账号 | 添加、查看、切换和暂停账号，选择常用调度策略 |
| 渠道 | 添加、启停、设为默认、连通测试和添加 Key |
| 子代理 | 子代理模型选择与偏好排序 |
| 设置 | 客户端偏好、启动开关、内核版本和更新；提供诊断与日志入口 |

## 与 OpenCodex 控制台的分工

| OpenCodex Desktop（桌面壳） | OpenCodex 控制台（网页，一键打开） |
| :--- | :--- |
| 添加/切换/暂停账号，选择常用调度策略 | 账号优先级、冷却恢复、移除、自动切换与失败阈值 |
| 添加/启停/测试渠道，配置 Key 与模型列表，设置默认渠道 | 完整密钥池、渠道删除、自定义模型与路由 |
| 子代理模型选择与排序、聚合用量图表 | 回退链、检查间隔、详细用量、日志、集成与实验特性 |
| Core 生命周期、诊断、更新、ChatGPT 重启 | — |

两边读写的是同一份 Core 配置，没有平行副本。窗口右上角的“控制台”打开完整设置；添加渠道窗口中的“高级配置”直达供应方页面。均在默认浏览器中打开，不自动带入未保存的表单。

## 下载与安装

要求 macOS 14 或更高版本，目前仅提供 Apple Silicon（arm64）版本。

界面支持中英文，自动跟随 macOS 首选语言（也支持系统中的单个 App 语言设置）；其他语言回退到英文。更改语言后重新打开 App 即可。

从 [GitHub Releases](https://github.com/leeyang1990/opencodex-desktop/releases/latest) 下载 DMG，拖入“应用程序”即可；ZIP 可用于便携运行。发布包采用免费的 ad-hoc 签名，未经 Apple 公证，首次启动时可能需要右键 App 并选择“打开”。建议同时核对 Release 附件中的 SHA-256。

## 行为边界

- Core 启动后与 Desktop 窗口解耦；退出 Desktop 不会停止正在运行的 Core。
- 默认不随 App 启动 Core；“随 App 自动启动 Core”和“开机启动 App”是两个独立开关。
- 默认在退出客户端前还原 Codex 原生路由并重启 ChatGPT，避免 ChatGPT 继续指向即将消失的代理；该行为可在“设置 › 客户端”中关闭。
- 还原与重新指向都通过 Core 自带的恢复流程完成，Desktop 不解析、不直接改写 `~/.codex/config.toml`；下次启动客户端时会重新指向本机代理，并在需要时提示重启 ChatGPT。
- Desktop 只原生写入经过筛选的高频配置，全部走 Core 自己的接口；细粒度账号调度、完整渠道与子代理参数、自定义模型、路由、用量和日志仍在控制台管理。
- 渠道 API Key 仅存在于本次会话内存，写入内核后立即清除，不写入偏好设置、事件记录或日志；客户端只读取内核返回的掩码形式。Codex 登录由内核打开浏览器完成，凭证完全不经过客户端。
- 内嵌网页已移除：控制台由本机 Core 提供，客户端只在默认浏览器中打开它。
- 停用代理时，请在 Desktop 中明确点击“停止”：停止 Core、还原路由，再重启已打开的 ChatGPT。这不是崩溃自动恢复功能。
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

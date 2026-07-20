# 拾笺（ClipFlow）

[English](README.md) | 简体中文

拾笺（ClipFlow）是一款原生、注重隐私的 macOS 剪贴板管理器。它将剪贴板历史保存在本机，方便你快速检索过去复制过的内容，并为键盘优先的工作流而设计。

## 主要功能

### 快速记录、搜索与粘贴

- 捕获文本、富文本、链接、文件、图片、PDF 及其他受支持的剪贴板表示形式；重复复制会自动去重。
- 用同一个搜索框检索内容、来源应用、链接、文件、图片、浏览器标签页、OCR 文字、收藏和智能分类。
- 通过可配置的唤醒快捷键（默认 `Command` + `Shift` + `V`）打开悬浮面板，在不离开键盘的情况下粘贴、预览、收藏、重命名、分类或删除条目。
- 支持保留原始格式或纯文本粘贴。文件、图片、链接和文本会提供专属操作，例如“粘贴文件路径”“在 Finder 中显示”“打开链接”“复制域名”和完整预览。

### 快捷粘贴与连续粘贴

- 将常用内容固定到 1 至 9 号槽位；即使面板关闭，也能用 `Option` + `Command` + `1` 至 `9` 全局粘贴对应内容。
- 可从一个或多个历史条目批量建立“连续粘贴”队列，再用 `Option` + `Shift` + `Command` + `V` 全局粘贴下一条。
- 面板会清楚展示当前粘贴目标应用、快捷槽位、队列状态和组合键提示。

### 整理与复用内容

- 按内容类型和智能分类自动整理，并使用 macOS Vision 在本机识别新复制图片中的文字。
- 可将敏感内容标记为一次性或自动过期；成功粘贴或到期后会删除，且不会进入备份。
- 可将文本保存为 `你好，{{name}}` 这类变量模板，填写变量后粘贴渲染结果。
- 可选集成 Safari、Google Chrome 和 Microsoft Edge 的浏览器标签页浏览与激活功能。

### 隐私优先

- 支持加密备份、导入和完整性校验，并限制导入资源用量。
- 使用 SQLCipher 加密剪贴板元数据，并单独加密较大的本地负载文件。
- 完全在你的 Mac 本机运行：没有账户、广告、分析、遥测或云端剪贴板处理。

## 界面预览

| 剪贴板历史 | 文件专属操作 |
| --- | --- |
| ![拾笺深色简体中文主控面板，展示快捷粘贴组合键提示](docs/images/main-panel-dark-zh.png) | ![拾笺文件条目的粘贴、路径、打开和 Finder 操作](docs/images/file-actions-light-en.png) |

| 设置 | 首次引导 |
| --- | --- |
| ![拾笺的快捷键、外观、语言、保留策略和存储设置](docs/images/settings-dark-zh.png) | ![拾笺首次安装权限引导](docs/images/onboarding-light-zh.png) |

| 图片预览 | 浏览器标签页 |
| --- | --- |
| ![拾笺图片条目的专属粘贴与预览操作](docs/images/image-actions-light-en.png) | ![拾笺的浏览器标签页空状态与受支持浏览器状态](docs/images/browser-tabs-light-en.png) |

## 隐私与权限

剪贴板数据仅存储在本机。ClipFlow 仅在相关功能启用时请求可选的 macOS 权限：

- **辅助功能**：允许 ClipFlow 自动粘贴到此前活跃的应用。未授权时，ClipFlow 会先把内容复制到剪贴板、保留面板，并提示你手动粘贴或重新授权当前安装的 App。
- **自动化**：仅在启用浏览器标签页集成时需要；浏览器控制始终在本机执行。
- **登录时启动**：可选。

当前测试包采用 Ad-hoc 签名，尚未 notarize。发给朋友体验时，首次打开可能需要在 **系统设置 -> 隐私与安全性** 中选择 **仍要打开**。自动粘贴还需要在 **系统设置 -> 隐私与安全性 -> 辅助功能** 中启用拾笺。

## 环境要求

- macOS 14 Sonoma 或更高版本
- Swift 6.2 工具链
- Homebrew（仅在初始化本地 SQLCipher 开发库时需要）

## 下载测试包

在 GitHub Releases 中分发给朋友时，优先使用 DMG：

1. 下载 `ClipFlow-<version>-macos.dmg`。
2. 打开 DMG，将 `ClipFlow.app` 拖到 `Applications`。
3. 从“应用程序”中启动拾笺。
4. 如果 macOS 阻止打开，到 **系统设置 -> 隐私与安全性** 中选择 **仍要打开**。

更新时，请先完全退出拾笺，再替换“应用程序”中的旧版本并重新启动。如果“设置 -> 权限”仍显示“自动粘贴：未授权”，请选择“重新绑定当前 App”，在 **系统设置 -> 隐私与安全性 -> 辅助功能** 中启用拾笺后再重新检测授权状态。

## 从源码构建

```bash
git clone git@github.com:osbrain/ClipFlow.git
cd ClipFlow

./scripts/bootstrap-dev-deps.sh
swift build
swift run ClipFlowCoreTests
```

打包本地 ad-hoc 签名的应用：

```bash
./scripts/package-app.sh debug
open artifacts/ClipFlow.app
```

如需 Release 配置，请执行：

```bash
./scripts/package-app.sh release
./scripts/package-dmg.sh
```

打包产物会输出到 `artifacts/`。

## 贡献

欢迎提交 Issue 和 Pull Request。请保持改动聚焦；在适用时补充相关测试；未经过讨论，请勿加入网络服务、分析工具或远程剪贴板处理功能。

## 许可证

ClipFlow 使用 [PolyForm Noncommercial License 1.0.0](LICENSE)。该许可证允许个人及其他非商业用途下的使用、修改和分发，但**禁止任何商业用途**。

本项目为源码可用（source-available）项目，而非 OSI 定义的开源软件：OSI 开源许可证必须允许商业使用。完整条款请查看 [LICENSE](LICENSE)。

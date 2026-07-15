# ClipFlow

[English](README.md) | 简体中文

ClipFlow 是一款原生、注重隐私的 macOS 剪贴板管理器。它将剪贴板历史保存在本机，方便你快速检索过去复制过的内容，并为键盘优先的工作流而设计。

## 主要功能

- 捕获和还原文本、富文本、链接、文件、图片、PDF、颜色及受支持的剪贴板数据。
- 搜索剪贴板历史，并按内容类型、收藏与自定义分类浏览。
- 使用 `Command` + `Shift` + `V` 打开悬浮面板，粘贴、复制、收藏、重命名、分类、预览或删除条目。
- 支持保留原始格式或纯文本粘贴，也可为不同应用单独设置。
- 可选集成 Safari、Google Chrome 和 Microsoft Edge 的浏览器标签页浏览与激活功能。
- 使用 SQLCipher 加密剪贴板元数据，并单独加密较大的本地负载文件。
- 完全在你的 Mac 本机运行：没有账户、广告、分析、遥测或云端剪贴板处理。

## 隐私与权限

剪贴板数据仅存储在本机。ClipFlow 仅在相关功能启用时请求可选的 macOS 权限：

- **辅助功能**：允许 ClipFlow 自动粘贴到此前活跃的应用。未授权时，ClipFlow 会还原剪贴板，你可以手动粘贴。
- **自动化**：仅在启用浏览器标签页集成时需要；浏览器控制始终在本机执行。
- **登录时启动**：可选。

## 环境要求

- macOS 14 Sonoma 或更高版本
- Swift 6.2 工具链
- Homebrew（仅在初始化本地 SQLCipher 开发库时需要）

## 从源码构建

```bash
git clone https://github.com/<your-account>/ClipFlow.git
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
```

## 贡献

欢迎提交 Issue 和 Pull Request。请保持改动聚焦；在适用时补充相关测试；未经过讨论，请勿加入网络服务、分析工具或远程剪贴板处理功能。

## 许可证

ClipFlow 使用 [PolyForm Noncommercial License 1.0.0](LICENSE)。该许可证允许个人及其他非商业用途下的使用、修改和分发，但**禁止任何商业用途**。

本项目为源码可用（source-available）项目，而非 OSI 定义的开源软件：OSI 开源许可证必须允许商业使用。完整条款请查看 [LICENSE](LICENSE)。

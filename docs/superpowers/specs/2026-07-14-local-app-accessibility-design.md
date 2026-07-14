# ClipFlow 本地应用包与辅助功能授权设计

## 目标

让本地开发版本以稳定的 `ClipFlow.app` 身份运行，并在用户点击“打开系统设置”时向 macOS 发起辅助功能授权请求，使 ClipFlow 出现在“隐私与安全性 > 辅助功能”列表中。

## 应用身份

- 应用包：`artifacts/ClipFlow.app`
- Bundle ID：`com.aiesst.clipflow`
- 最低系统版本：macOS 14
- 应用类型：菜单栏辅助应用（`LSUIElement = true`）
- 本地签名：Ad-hoc（`codesign --sign -`），不依赖 Apple 开发者账号
- SwiftPM 本地化资源包复制到 `Contents/Resources/ClipFlow_ClipFlowUI.bundle`

## 授权流程

`PermissionStatusProviding` 增加授权请求能力。系统实现调用 `AXIsProcessTrustedWithOptions`，并传入 `kAXTrustedCheckOptionPrompt = true`。设置按钮先触发请求；未获授权时继续打开辅助功能设置页面，设置模型随后刷新授权状态。

## 打包流程

`scripts/package-app.sh` 构建 Debug 或 Release 产品，创建标准 `.app` 目录，复制可执行文件和资源包，写入固定 Info.plist，执行 Ad-hoc 签名，并验证 Bundle ID、签名和资源完整性。脚本使用临时目录组装，成功后原子替换目标应用包。

## 验收标准

- 自动测试证明按钮对应的模型操作会调用授权请求并刷新状态。
- `codesign --verify --deep --strict artifacts/ClipFlow.app` 成功。
- `defaults read .../Info CFBundleIdentifier` 返回 `com.aiesst.clipflow`。
- 从 `artifacts/ClipFlow.app` 启动后，系统将其识别为应用包而不是裸可执行文件。
- 本地打包不声称具备 Developer ID 分发、公证或 Gatekeeper 免警告能力。


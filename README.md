# ClipFlow

English | [简体中文](README.zh-CN.md)

ClipFlow is a native, privacy-first clipboard manager for macOS. It keeps your clipboard history local, makes it easy to find past clips, and is designed for fast keyboard-driven workflows.

## Highlights

- Capture and restore text, rich text, links, files, images, PDFs, and other supported pasteboard representations.
- Search clipboard history and browse it by content type, favorites, and custom categories.
- Open a floating clipboard panel with `Command` + `Shift` + `V`, then paste, favorite, rename, categorize, preview, or delete an item.
- Choose original-format or plain-text paste behavior.
- Optionally browse and activate tabs from Safari, Google Chrome, and Microsoft Edge.
- Encrypt clipboard metadata with SQLCipher and encrypt large local payload files separately.
- Run entirely on your Mac: no accounts, advertising, analytics, telemetry, or cloud clipboard processing.

## Privacy and Permissions

Clipboard data is stored locally. ClipFlow requests optional macOS permissions only when a related feature needs them:

- **Accessibility** lets ClipFlow automatically paste into the previously active app. Without it, ClipFlow restores the clipboard and you can paste manually.
- **Automation** is required only if you enable browser-tab integration; browser control stays on your Mac.
- **Launch at Login** is optional.

## Requirements

- macOS 14 Sonoma or later
- Swift 6.2 toolchain
- Homebrew, only when bootstrapping the local SQLCipher development libraries

## Build from Source

```bash
git clone git@github.com:osbrain/ClipFlow.git
cd ClipFlow

./scripts/bootstrap-dev-deps.sh
swift build
swift run ClipFlowCoreTests
```

Package a locally ad-hoc-signed app:

```bash
./scripts/package-app.sh debug
open artifacts/ClipFlow.app
```

For a release configuration, use:

```bash
./scripts/package-app.sh release
```

## Contributing

Issues and pull requests are welcome. Please keep changes focused, include relevant tests where practical, and do not add network services, analytics, or remote clipboard processing without prior discussion.

## License

ClipFlow is available under the [PolyForm Noncommercial License 1.0.0](LICENSE). It permits personal and other non-commercial use, modification, and distribution, but **prohibits commercial use**.

This is a source-available project, not OSI-approved open source: OSI open-source licenses must allow commercial use. See [LICENSE](LICENSE) for the complete terms.

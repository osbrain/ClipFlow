# ClipFlow

English | [简体中文](README.zh-CN.md)

ClipFlow is a native, privacy-first clipboard manager for macOS. It keeps your clipboard history local, makes it easy to find past clips, and is designed for fast keyboard-driven workflows.

In Simplified Chinese, the app is presented as **拾笺**.

## Highlights

- Capture and restore text, rich text, links, files, images, PDFs, and other supported pasteboard representations.
- Search clipboard history and browse it by content type, favorites, links, files, images, browser tabs, and custom categories.
- Open a floating clipboard panel with `Command` + `Shift` + `V`, then paste, favorite, rename, categorize, preview, or delete an item without leaving the keyboard.
- Use type-specific actions such as paste file, paste file path, show in Finder, open links, copy domains, and full preview.
- Choose original-format or plain-text paste behavior.
- Optionally browse and activate tabs from Safari, Google Chrome, and Microsoft Edge.
- Encrypt clipboard metadata with SQLCipher and encrypt large local payload files separately.
- Deduplicate repeated clipboard captures and keep the history list responsive with bounded loads and static time labels.
- Run entirely on your Mac: no accounts, advertising, analytics, telemetry, or cloud clipboard processing.

## Screenshots

| Clipboard history | File actions |
| --- | --- |
| ![ClipFlow main clipboard panel in dark Simplified Chinese](docs/images/main-panel-dark-zh.png) | ![ClipFlow file entry with paste, path, open, and Finder actions](docs/images/file-actions-light-en.png) |

| Settings | First-run guide |
| --- | --- |
| ![ClipFlow settings for shortcuts, appearance, language, retention, and storage](docs/images/settings-dark-zh.png) | ![ClipFlow first-run permissions guide in Simplified Chinese](docs/images/onboarding-light-zh.png) |

| Image preview | Browser tabs |
| --- | --- |
| ![ClipFlow image entry with dedicated paste and preview actions](docs/images/image-actions-light-en.png) | ![ClipFlow browser tabs empty state and supported browser status](docs/images/browser-tabs-light-en.png) |

## Privacy and Permissions

Clipboard data is stored locally. ClipFlow requests optional macOS permissions only when a related feature needs them:

- **Accessibility** lets ClipFlow automatically paste into the previously active app. Without it, ClipFlow restores the clipboard and you can paste manually.
- **Automation** is required only if you enable browser-tab integration; browser control stays on your Mac.
- **Launch at Login** is optional.

Ad-hoc test builds are not notarized. On another Mac, the first launch may require **System Settings -> Privacy & Security -> Open Anyway**. Automatic paste also needs the app to be enabled in **System Settings -> Privacy & Security -> Accessibility**.

## Requirements

- macOS 14 Sonoma or later
- Swift 6.2 toolchain
- Homebrew, only when bootstrapping the local SQLCipher development libraries

## Downloading a Test Build

For GitHub Releases, use the DMG when sharing with friends:

1. Download `ClipFlow-<version>-macos.dmg`.
2. Open the DMG and drag `ClipFlow.app` to `Applications`.
3. Launch ClipFlow from Applications.
4. If macOS blocks it, open **System Settings -> Privacy & Security** and choose **Open Anyway**.

The ZIP asset contains the same app bundle and is mainly useful for direct archive testing.

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
./scripts/package-dmg.sh
```

The packaged app and DMG are written to `artifacts/`.

## Contributing

Issues and pull requests are welcome. Please keep changes focused, include relevant tests where practical, and do not add network services, analytics, or remote clipboard processing without prior discussion.

## License

ClipFlow is available under the [PolyForm Noncommercial License 1.0.0](LICENSE). It permits personal and other non-commercial use, modification, and distribution, but **prohibits commercial use**.

This is a source-available project, not OSI-approved open source: OSI open-source licenses must allow commercial use. See [LICENSE](LICENSE) for the complete terms.

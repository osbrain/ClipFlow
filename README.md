# ClipFlow

English | [简体中文](README.zh-CN.md)

ClipFlow is a native, privacy-first clipboard manager for macOS. It keeps your clipboard history local, makes it easy to find past clips, and is designed for fast keyboard-driven workflows.

In Simplified Chinese, the app is presented as **拾笺**.

## Highlights

### Fast capture, search, and paste

- Capture text, rich text, links, files, images, PDFs, and other supported pasteboard representations; repeated captures are deduplicated.
- Search one history across content, source app, links, files, images, browser tabs, OCR text, favorites, and smart categories.
- Open the floating panel with the configurable wake shortcut (default: `Command` + `Shift` + `V`), then paste, preview, favorite, rename, categorize, or delete without leaving the keyboard.
- Paste in original format or as plain text. File, image, link, and text clips expose purpose-built actions such as **Paste File Path**, **Show in Finder**, **Open Link**, **Copy Domain**, and full preview.

### Quick Paste and Sequential Paste

- Pin frequently used clips to slots `1` through `9`. Use `Option` + `Command` + `1` through `9` to paste a slot globally, even with the panel closed.
- Build a **Sequential Paste** queue from one or many history items, then paste the next item globally with `Option` + `Shift` + `Command` + `V`.
- The panel clearly shows the current destination app, quick-paste slots, queue state, and shortcut hints.

### Organize and reuse content

- Classify clips automatically by type and smart categories, and recognize text in newly copied images locally with macOS Vision.
- Mark sensitive clips as one-time or auto-expiring. Temporary clips are removed after successful paste or expiry and are excluded from backups.
- Save reusable text as variable templates such as `Hello {{name}}`, fill the variables when needed, and paste the rendered result.
- Optionally browse and activate tabs from Safari, Google Chrome, and Microsoft Edge.

### Private by design

- Back up and restore encrypted ClipFlow data with integrity validation and import limits.
- Encrypt clipboard metadata with SQLCipher and encrypt large local payload files separately.
- Keep all processing on your Mac: no accounts, advertising, analytics, telemetry, or cloud clipboard processing.

## Screenshots

| Clipboard history | File actions |
| --- | --- |
| ![ClipFlow main clipboard panel with quick-paste shortcut hint in dark Simplified Chinese](docs/images/main-panel-dark-zh.png) | ![ClipFlow file entry with paste, path, open, and Finder actions](docs/images/file-actions-light-en.png) |

| Settings | First-run guide |
| --- | --- |
| ![ClipFlow settings for shortcuts, appearance, language, retention, and storage](docs/images/settings-dark-zh.png) | ![ClipFlow first-run permissions guide in Simplified Chinese](docs/images/onboarding-light-zh.png) |

| Image preview | Browser tabs |
| --- | --- |
| ![ClipFlow image entry with dedicated paste and preview actions](docs/images/image-actions-light-en.png) | ![ClipFlow browser tabs empty state and supported browser status](docs/images/browser-tabs-light-en.png) |

## Privacy and Permissions

Clipboard data is stored locally. ClipFlow requests optional macOS permissions only when a related feature needs them:

- **Accessibility** lets ClipFlow automatically paste into the previously active app. Without it, ClipFlow copies the selected content, keeps the panel open, and tells you how to paste manually or re-authorize the installed app.
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

When installing an update, quit ClipFlow completely before replacing the existing app in `Applications`, then launch the new copy. If **Settings -> Permissions** still shows Automatic Paste as not granted, select **Rebind Current App**, enable ClipFlow in **System Settings -> Privacy & Security -> Accessibility**, then refresh the permission status.

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

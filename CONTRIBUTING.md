# Contributing to ClipFlow

Thanks for contributing to ClipFlow. Keep each pull request focused and describe the user-facing behavior it changes.

## Development setup

ClipFlow targets macOS 14 Sonoma or later and uses Swift 6.2. Bootstrap the local SQLCipher dependencies, then run the core test executable:

```bash
./scripts/bootstrap-dev-deps.sh
swift run ClipFlowCoreTests
```

Package and verify a local app bundle before submitting packaging-related changes:

```bash
./scripts/package-app.sh release
./scripts/verify-local-app.sh artifacts/ClipFlow.app
```

The packaged app is Ad-hoc signed for local testing. Repackaging changes its code signature, so macOS may require you to grant Accessibility access again.

## Project principles

- Keep clipboard content on the user's Mac by default.
- Do not introduce telemetry, analytics, cloud clipboard synchronization, or network services without prior discussion in an issue.
- Preserve Chinese localization alongside user-visible English changes.
- Add or update focused tests when changing testable behavior.
- Do not commit build artifacts, databases, logs, provisioning profiles, or secrets.

## Pull requests

Before opening a pull request, run the relevant tests and `git diff --check`. Explain any manual testing, especially for macOS permissions, browser integration, keyboard shortcuts, and visual changes.

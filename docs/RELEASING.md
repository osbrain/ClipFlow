# Releasing ClipFlow

## Current local-release process

The current release process produces an Ad-hoc-signed app for local testing. It is suitable for verifying the app bundle on the development Mac, but it is not a notarized public distribution workflow.

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Config/Info.plist`.
2. Run the core tests:

   ```bash
   swift run ClipFlowCoreTests
   ```

3. Package the release app:

   ```bash
   ./scripts/package-app.sh release
   ```

4. Verify the generated bundle:

   ```bash
   ./scripts/verify-local-app.sh artifacts/ClipFlow.app
   ```

5. Launch `artifacts/ClipFlow.app` and manually verify the relevant UI, clipboard behavior, permissions, and integrations.

6. Create and validate a DMG for drag-to-Applications testing:

   ```bash
   ./scripts/package-dmg.sh
   ./Tests/package-dmg-test.sh
   ```

   The output is `artifacts/ClipFlow-<version>-macos.dmg`. It contains `ClipFlow.app`, an Applications alias, and a short installation note.

`scripts/package-app.sh` signs with `--sign -`. Every repackaging creates a new Ad-hoc code signature, so macOS can treat the app as a new Accessibility client. If automatic paste is being tested, open System Settings and re-enable the app under Accessibility after repackaging when necessary.

A DMG improves installation flow only. It does not make an Ad-hoc-signed app trusted by Gatekeeper. Friends may still need to use **System Settings → Privacy & Security → Open Anyway** after copying the app to Applications.

## Future public distribution

Before distributing outside local testing, use an Apple Developer ID certificate, enable the hardened runtime as appropriate, archive the signed app, and submit it for notarization. Do not describe an Ad-hoc-signed app as notarized or generally safe to distribute.

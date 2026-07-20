# Releasing ClipFlow

## Current local-release process

The current release process produces an Ad-hoc-signed app for trusted test distribution. It is suitable for GitHub Release assets while ClipFlow does not have an Apple Developer ID certificate, but it is not a notarized public distribution workflow.

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

5. Create the ZIP asset:

   ```bash
   VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' artifacts/ClipFlow.app/Contents/Info.plist)"
   /usr/bin/ditto -c -k --sequesterRsrc --keepParent artifacts/ClipFlow.app "artifacts/ClipFlow-$VERSION-macos.zip"
   /usr/bin/shasum -a 256 "artifacts/ClipFlow-$VERSION-macos.zip" > "artifacts/ClipFlow-$VERSION-macos.zip.sha256"
   ```

6. Create and validate a DMG for drag-to-Applications testing:

   ```bash
   VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' artifacts/ClipFlow.app/Contents/Info.plist)"
   ./scripts/package-dmg.sh
   ./Tests/package-dmg-test.sh
   /usr/bin/shasum -a 256 "artifacts/ClipFlow-$VERSION-macos.dmg" > "artifacts/ClipFlow-$VERSION-macos.dmg.sha256"
   ```

   The output is `artifacts/ClipFlow-<version>-macos.dmg`. It contains `ClipFlow.app`, an Applications alias, and a short installation note.

7. Launch `artifacts/ClipFlow.app` and manually verify the relevant UI, clipboard behavior, permissions, and integrations.

`scripts/package-app.sh` signs with `--sign -`. Every repackaging creates a new Ad-hoc code signature, so macOS can treat the app as a new Accessibility client. If automatic paste is being tested, open System Settings and re-enable the app under Accessibility after repackaging when necessary.

A DMG improves installation flow only. It does not make an Ad-hoc-signed app trusted by Gatekeeper. Friends may still need to use **System Settings → Privacy & Security → Open Anyway** after copying the app to Applications.

## GitHub Release notes template

```markdown
## ClipFlow 1.0.4

This release adds safer clipboard workflows and improves the settings experience.

- Adds smart categorization, fixed quick-paste slots, expanded content actions, and privacy capture rules.
- Adds encrypted backup import/export with integrity validation and import resource limits.
- Refreshes the settings layout, background treatment, exact timestamps, and open-source entry point.
- Improves file-path paste compatibility for Finder clipboard records.

Distribution note: this build is Ad-hoc signed and not notarized. On first launch, macOS may require System Settings -> Privacy & Security -> Open Anyway. Automatic paste requires enabling ClipFlow in Accessibility.

Recommended download: `ClipFlow-1.0.4-macos.dmg`
```

## Future public distribution

Before distributing outside local testing, use an Apple Developer ID certificate, enable the hardened runtime as appropriate, archive the signed app, and submit it for notarization. Do not describe an Ad-hoc-signed app as notarized or generally safe to distribute.

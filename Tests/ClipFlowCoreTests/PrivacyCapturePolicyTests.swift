import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowUI

@Suite("Privacy capture policy")
struct PrivacyCapturePolicyTests {
    @Test("excluded application identifiers block captures by bundle or name")
    func excludedApplicationsBlockByBundleOrName() {
        let policy = PrivacyCapturePolicy(
            excludedAppIdentifiers: ["com.apple.keychainaccess", "1Password"],
            excludedContentPatterns: [],
            ignoresSensitiveText: false
        )

        #expect(!policy.allows(Self.capture(app: "Keychain Access", bundleID: "com.apple.keychainaccess")))
        #expect(!policy.allows(Self.capture(app: "1Password", bundleID: "com.1password.1password")))
        #expect(policy.allows(Self.capture(app: "Notes", bundleID: "com.apple.Notes")))
    }

    @Test("excluded content patterns support substrings and regex prefixes")
    func excludedContentPatternsBlockSubstringsAndRegex() {
        let policy = PrivacyCapturePolicy(
            excludedAppIdentifiers: [],
            excludedContentPatterns: ["secret project", "regex:\\bAKIA[0-9A-Z]{16}\\b"],
            ignoresSensitiveText: false
        )

        #expect(!policy.allows(Self.capture(text: "Notes about Secret Project")))
        #expect(!policy.allows(Self.capture(text: "AWS key AKIA1234567890ABCDEF")))
        #expect(policy.allows(Self.capture(text: "ordinary meeting notes")))
    }

    @Test("sensitive text detection blocks obvious passwords and one time codes")
    func sensitiveTextDetectionBlocksPasswordsAndCodes() {
        let policy = PrivacyCapturePolicy(
            excludedAppIdentifiers: [],
            excludedContentPatterns: [],
            ignoresSensitiveText: true
        )

        #expect(!policy.allows(Self.capture(text: "password = hunter2")))
        #expect(!policy.allows(Self.capture(text: "Your verification code is 839201")))
        #expect(policy.allows(Self.capture(text: "remember to buy coffee")))
    }

    private static func capture(
        app: String = "Notes",
        bundleID: String? = "com.apple.Notes",
        text: String = "hello"
    ) -> NormalizedCapture {
        NormalizedCapture(
            sourceAppName: app,
            sourceBundleID: bundleID,
            kind: .text,
            previewText: text,
            searchText: text.lowercased(),
            byteSize: text.utf8.count,
            contentHash: UUID().uuidString,
            payloads: []
        )
    }
}

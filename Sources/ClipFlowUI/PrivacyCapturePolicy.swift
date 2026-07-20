import ClipFlowCore
import Foundation

public struct PrivacyCapturePolicy: Equatable, Sendable {
    public let excludedAppIdentifiers: [String]
    public let excludedContentPatterns: [String]
    public let ignoresSensitiveText: Bool

    public init(
        excludedAppIdentifiers: [String],
        excludedContentPatterns: [String],
        ignoresSensitiveText: Bool
    ) {
        self.excludedAppIdentifiers = Self.normalizedRules(excludedAppIdentifiers)
        self.excludedContentPatterns = Self.normalizedRules(excludedContentPatterns)
        self.ignoresSensitiveText = ignoresSensitiveText
    }

    public init(
        excludedAppIdentifiersText: String,
        excludedContentPatternsText: String,
        ignoresSensitiveText: Bool
    ) {
        self.init(
            excludedAppIdentifiers: Self.rules(from: excludedAppIdentifiersText),
            excludedContentPatterns: Self.rules(from: excludedContentPatternsText),
            ignoresSensitiveText: ignoresSensitiveText
        )
    }

    public func allows(_ capture: NormalizedCapture) -> Bool {
        !matchesExcludedApplication(capture)
            && !matchesExcludedContent(capture)
            && !(ignoresSensitiveText && looksSensitive(capture.previewText))
    }

    private func matchesExcludedApplication(_ capture: NormalizedCapture) -> Bool {
        let appName = capture.sourceAppName.lowercased()
        let bundleID = capture.sourceBundleID?.lowercased() ?? ""
        return excludedAppIdentifiers.contains { rule in
            let normalizedRule = rule.lowercased()
            return appName.contains(normalizedRule) || bundleID.contains(normalizedRule)
        }
    }

    private func matchesExcludedContent(_ capture: NormalizedCapture) -> Bool {
        let text = "\(capture.previewText)\n\(capture.searchText)"
        return excludedContentPatterns.contains { pattern in
            if pattern.lowercased().hasPrefix("regex:") {
                let expression = String(pattern.dropFirst("regex:".count))
                return Self.matchesRegex(expression, in: text)
            }
            return text.localizedCaseInsensitiveContains(pattern)
        }
    }

    private func looksSensitive(_ text: String) -> Bool {
        let expressions = [
            #"(?i)\b(password|passwd|passcode|pwd|密码|口令)\b\s*[:=：]?\s*\S{4,}"#,
            #"(?i)\b(verification code|security code|one-time code|otp|验证码|校验码|动态码)\b.{0,24}\b\d{4,8}\b"#,
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#
        ]
        return expressions.contains { Self.matchesRegex($0, in: text) }
    }

    private static func matchesRegex(_ expression: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: expression,
            options: [.caseInsensitive]
        ) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func rules(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
    }

    private static func normalizedRules(_ rules: [String]) -> [String] {
        rules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

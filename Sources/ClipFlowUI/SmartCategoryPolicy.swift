import ClipFlowCore
import Foundation

public enum SmartCategory: String, CaseIterable, Equatable, Sendable {
    case link
    case image
    case file
    case code
    case work
    case finance
    case todo

    public var localizationKey: String {
        "category.smart.\(rawValue)"
    }

    public var localizedName: String {
        L10n.string(localizationKey)
    }

    var localizedNameCandidates: Set<String> {
        Set(
            [
                localizedName,
                L10n.string(localizationKey, locale: "en"),
                L10n.string(localizationKey, locale: "zh-Hans")
            ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != localizationKey }
        )
    }

    func matches(categoryName: String) -> Bool {
        localizedNameCandidates.contains(
            categoryName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }
}

public struct SmartCategoryPolicy: Equatable, Sendable {
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public func suggestion(for capture: NormalizedCapture) -> SmartCategory? {
        guard isEnabled else { return nil }

        switch capture.kind {
        case .image:
            return .image
        case .file:
            return .file
        case .link:
            return .link
        case .text, .richText, .mixed, .unknown:
            break
        }

        let text = "\(capture.previewText)\n\(capture.searchText)"
        if looksLikeCode(text) {
            return .code
        }
        if looksLikeFinance(text) {
            return .finance
        }
        if looksLikeTodo(text) {
            return .todo
        }
        if looksLikeWork(capture: capture, text: text) {
            return .work
        }
        return nil
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let expressions = [
            #"(?m)^\s*```"#,
            #"(?m)^\s*(func|function|class|struct|enum|import|export|const|let|var)\b"#,
            #"\b(return|async|await|throws|guard|switch)\b.{0,80}[{}();]"#,
            #"<[A-Za-z][A-Za-z0-9-]*(\s+[^>]*)?>"#
        ]
        return expressions.contains { Self.matchesRegex($0, in: text) }
    }

    private func looksLikeFinance(_ text: String) -> Bool {
        let expressions = [
            #"(发票|报销|付款|收款|预算|账单|金额|转账|财务)"#,
            #"\b(invoice|receipt|reimbursement|payment|budget|expense|billing|amount)\b"#,
            #"(?<!\w)(¥|￥|\$|USD|CNY|RMB)\s?\d"#
        ]
        return expressions.contains { Self.matchesRegex($0, in: text) }
    }

    private func looksLikeTodo(_ text: String) -> Bool {
        let expressions = [
            #"(?i)\b(todo|to-do|follow up|deadline|due|reminder)\b"#,
            #"(?m)^\s*[-*]\s+\[[ xX]\]"#,
            #"(待办|提醒|记得|截止|跟进|稍后处理)"#
        ]
        return expressions.contains { Self.matchesRegex($0, in: text) }
    }

    private func looksLikeWork(capture: NormalizedCapture, text: String) -> Bool {
        let app = "\(capture.sourceAppName)\n\(capture.sourceBundleID ?? "")"
        let appExpressions = [
            #"(?i)\b(feishu|lark|dingtalk|slack|teams|zoom|notion|jira|confluence)\b"#,
            #"(飞书|钉钉|企业微信|会议)"#
        ]
        if appExpressions.contains(where: { Self.matchesRegex($0, in: app) }) {
            return true
        }

        let textExpressions = [
            #"(?i)\b(meeting|agenda|minutes|project|proposal|requirement|roadmap|sprint)\b"#,
            #"(会议|纪要|项目|需求|排期|方案|评审|周会)"#
        ]
        return textExpressions.contains { Self.matchesRegex($0, in: text) }
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
}

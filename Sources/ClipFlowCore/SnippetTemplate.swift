import Foundation

public struct SnippetTemplate: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, title: String, body: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var variables: [String] {
        SnippetTemplateRenderer.variables(in: body)
    }
}

public enum SnippetTemplateRenderer {
    public static func variables(in body: String) -> [String] {
        matches(in: body).reduce(into: [String]()) { result, variable in
            if !result.contains(variable) {
                result.append(variable)
            }
        }
    }

    public static func render(_ body: String, values: [String: String]) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"\{\{([A-Za-z0-9_]+)\}\}"#
        ) else {
            return body
        }
        let range = NSRange(body.startIndex..., in: body)
        let rendered = NSMutableString(string: body)
        for match in expression.matches(in: body, range: range).reversed() {
            let variable = (body as NSString).substring(with: match.range(at: 1))
            rendered.replaceCharacters(in: match.range, with: values[variable, default: ""])
        }
        return rendered as String
    }

    private static func matches(in body: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"\{\{([A-Za-z0-9_]+)\}\}"#
        ) else {
            return []
        }
        let range = NSRange(body.startIndex..., in: body)
        return expression.matches(in: body, range: range).compactMap { match in
            guard let variableRange = Range(match.range(at: 1), in: body) else { return nil }
            return String(body[variableRange])
        }
    }
}

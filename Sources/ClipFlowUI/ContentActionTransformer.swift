import Foundation

public enum ContentActionTransformer {
    public static func cleanedText(from source: String) -> String {
        source
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public static func firstLine(from source: String) -> String {
        source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    public static func extractedURLs(from source: String) -> String {
        extractedURLStrings(from: source).joined(separator: "\n")
    }

    public static func markdownLink(title: String, urlString: String) -> String {
        let cleanTitle = firstLine(from: title).isEmpty
            ? urlString
            : firstLine(from: title)
        let escapedTitle = cleanTitle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")

        return "[\(escapedTitle)](\(markdownDestination(urlString)))"
    }

    private static func extractedURLStrings(from source: String) -> [String] {
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: source) else { return nil }
            return trimTrailingURLPunctuation(String(source[swiftRange]))
        }
    }

    private static func trimTrailingURLPunctuation(_ value: String) -> String {
        var result = value
        while let last = result.unicodeScalars.last,
              CharacterSet(charactersIn: ".,;:!?)]}").contains(last) {
            result.removeLast()
        }
        return result
    }

    private static func markdownDestination(_ urlString: String) -> String {
        if urlString.contains(where: \.isWhitespace) ||
            urlString.contains("(") ||
            urlString.contains(")") {
            let escaped = urlString.replacingOccurrences(of: ">", with: "%3E")
            return "<\(escaped)>"
        }
        return urlString
    }
}

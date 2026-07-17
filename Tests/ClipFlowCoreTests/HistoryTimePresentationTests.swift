import Foundation
import Testing
@testable import ClipFlowUI

@Suite("History time presentation")
struct HistoryTimePresentationTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_721_044_800)

    @Test("English history rows use exact month day and time")
    func englishExactTimestamp() {
        let locale = Locale(identifier: "en")

        #expect(text(secondsAgo: 30, locale: locale) == "Jul 15 11:59:30")
        #expect(text(secondsAgo: 300, locale: locale) == "Jul 15 11:55:00")
        #expect(text(secondsAgo: 7_200, locale: locale) == "Jul 15 10:00:00")
        #expect(text(secondsAgo: 86_400, locale: locale) == "Jul 14 12:00:00")
    }

    @Test("Simplified Chinese history rows use exact month day and time")
    func chineseExactTimestamp() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(text(secondsAgo: 30, locale: locale) == "7月15日 11:59:30")
        #expect(text(secondsAgo: 300, locale: locale) == "7月15日 11:55:00")
        #expect(text(secondsAgo: 7_200, locale: locale) == "7月15日 10:00:00")
        #expect(text(secondsAgo: 86_400, locale: locale) == "7月14日 12:00:00")
    }

    @Test("Future dates still show their exact timestamp")
    func futureDateUsesExactTimestamp() {
        #expect(
            HistoryTimePresentation.text(
                for: now.addingTimeInterval(60),
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "en")
            ) == "Jul 15 12:01:00"
        )
    }

    @Test("Older dates include seconds instead of relative buckets")
    func olderDatesIncludeSeconds() {
        let result = text(secondsAgo: 7 * 86_400, locale: Locale(identifier: "en"))

        #expect(result == "Jul 8 12:00:00")
    }

    private func text(secondsAgo: TimeInterval, locale: Locale) -> String {
        HistoryTimePresentation.text(
            for: now.addingTimeInterval(-secondsAgo),
            now: now,
            calendar: calendar,
            locale: locale
        )
    }
}

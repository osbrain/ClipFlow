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

    @Test("English time buckets are static and concise")
    func englishBuckets() {
        let locale = Locale(identifier: "en")

        #expect(text(secondsAgo: 30, locale: locale) == "Just now")
        #expect(text(secondsAgo: 300, locale: locale) == "5 min ago")
        #expect(text(secondsAgo: 7_200, locale: locale) == "Today")
        #expect(text(secondsAgo: 86_400, locale: locale) == "Yesterday")
    }

    @Test("Simplified Chinese time buckets are localized")
    func chineseBuckets() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(text(secondsAgo: 30, locale: locale) == "刚刚")
        #expect(text(secondsAgo: 300, locale: locale) == "5 分钟前")
        #expect(text(secondsAgo: 7_200, locale: locale) == "今天")
        #expect(text(secondsAgo: 86_400, locale: locale) == "昨天")
    }

    @Test("Future dates use the just-now bucket")
    func futureDateUsesJustNow() {
        #expect(
            HistoryTimePresentation.text(
                for: now.addingTimeInterval(60),
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "en")
            ) == "Just now"
        )
    }

    @Test("Older dates use a stable short date")
    func olderDatesUseShortDate() {
        let result = text(secondsAgo: 7 * 86_400, locale: Locale(identifier: "en"))

        #expect(!result.isEmpty)
        #expect(result != "Today")
        #expect(result != "Yesterday")
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

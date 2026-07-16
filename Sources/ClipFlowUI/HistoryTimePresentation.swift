import Foundation

public enum HistoryTimePresentation {
    public static func text(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = L10n.locale
    ) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 {
            return localized("history.time.justNow", locale: locale)
        }
        if elapsed < 3_600 {
            let minutes = max(1, Int(elapsed / 60))
            return String(
                format: localized("history.time.minutesAgo", locale: locale),
                locale: locale,
                minutes
            )
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return localized("history.time.today", locale: locale)
        }
        if let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: now)
        ), calendar.isDate(date, inSameDayAs: yesterday) {
            return localized("history.time.yesterday", locale: locale)
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        L10n.string(key, locale: locale.identifier)
    }
}

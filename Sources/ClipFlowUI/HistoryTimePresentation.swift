import Foundation

public enum HistoryTimePresentation {
    public static func text(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = L10n.locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = locale.identifier.hasPrefix("zh")
            ? "M月d日 HH:mm:ss"
            : "MMM d HH:mm:ss"
        return formatter.string(from: date)
    }
}

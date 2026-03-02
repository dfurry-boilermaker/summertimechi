import Foundation

/// A single entry in a sun/shade timeline for one day.
struct SunTimelineEntry: Identifiable {
    let id = UUID()
    let date: Date
    let status: SunStatus

    var hour: Int {
        Calendar.current.component(.hour, from: date)
    }

    var minute: Int {
        Calendar.current.component(.minute, from: date)
    }

    var timeString: String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}

/// A full-day sun/shade timeline at 15-minute resolution.
struct SunTimeline {
    let bar: Bar
    let date: Date
    let entries: [SunTimelineEntry]

    /// Returns the entry for a given hour (first matching).
    func entry(at hour: Int) -> SunTimelineEntry? {
        entries.first { $0.hour == hour && $0.minute == 0 }
    }

    /// Returns `true` if the bar is in sunlight at the given date.
    func isInSun(at date: Date) -> Bool {
        guard let nearest = nearestEntry(to: date) else { return false }
        return nearest.status == .sunlit || nearest.status == .partialSun
    }

    /// Next transition time from current status.
    func nextTransition(from date: Date) -> (status: SunStatus, at: Date)? {
        guard let currentEntry = nearestEntry(to: date) else { return nil }
        let currentStatus = currentEntry.status
        return entries
            .filter { $0.date > date }
            .first { $0.status != currentStatus }
            .map { ($0.status, $0.date) }
    }

    private func nearestEntry(to date: Date) -> SunTimelineEntry? {
        entries.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }
}

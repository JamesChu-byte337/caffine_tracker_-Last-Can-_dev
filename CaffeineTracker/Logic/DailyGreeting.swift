import Foundation

/// The message shown on the first open of a new day, only when yesterday's caffeine clearly changed.
enum DailyGreeting {
    /// Yesterday must differ from the week before by at least this share to count as a change.
    static let changeThreshold = 0.15

    struct Message: Equatable {
        enum Trend { case up, down }
        let trend: Trend
        let percent: Int
        var text: String {
            switch trend {
            case .up: "Heavy workload, eh? Yesterday's caffeine was \(percent)% above your daily average for the week before. Eat well, rest well, study well."
            case .down: "Keep it up! Your caffeine yesterday was \(percent)% lower than your daily average for the week before."
            }
        }
    }

    static func message(doses: [CaffeineDose], now: Date, calendar: Calendar = .current) -> Message? {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let baselineStart = calendar.date(byAdding: .day, value: -8, to: today) else { return nil }

        func total(from start: Date, to end: Date) -> Double {
            doses.filter { $0.time >= start && $0.time < end }.reduce(0) { $0 + $1.mg }
        }
        let yesterdayTotal = total(from: yesterday, to: today)
        let baselineDaysLogged = Set(doses.filter { $0.time >= baselineStart && $0.time < yesterday }.map { calendar.startOfDay(for: $0.time) }).count
        // Too little history to say anything changed.
        guard baselineDaysLogged >= 3 else { return nil }
        let baselineAverage = total(from: baselineStart, to: yesterday) / 7
        guard baselineAverage > 0 else { return nil }

        let change = (yesterdayTotal - baselineAverage) / baselineAverage
        guard abs(change) >= changeThreshold else { return nil }
        return Message(trend: change > 0 ? .up : .down, percent: Int((abs(change) * 100).rounded()))
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// What changed in each release, shown from the version badge on the Today screen.
enum Changelog {
    struct Entry: Identifiable {
        let version: String
        let date: String
        let changes: [String]
        var id: String { version }
    }

    static let entries: [Entry] = [
        Entry(version: "1.0.2", date: "Nov 3, 2026", changes: [
            "The app is now called Last Can.",
            "New app icon: the Waterloo goose.",
            "Choose Light, Dark or System appearance in Settings.",
            "Removed the smoking and birth control questions from the half-life estimate.",
            "The goose now appears on the sign-in screen and in the daily message.",
        ]),
        Entry(version: "1.0.1", date: "Nov 3, 2026", changes: [
            "Added on-device pattern analysis and Apple Health insights (heart rate, resting heart rate, sleep, Apple Watch heart notifications). Optional, and only with your permission.",
            "Caffeine half-life is now estimated for you from research-based factors, with a Re-evaluate button.",
            "Sign in with your uwaterloo.ca email.",
            "Health conditions moved to one list with more options and your own entries.",
            "Daily message when your caffeine changes compared with the week before.",
            "Countdown notification now reads \u{201C}Caffeine countdown ended\u{201D}.",
            "Tidier top of screen and evenly sized History tiles.",
        ]),
        Entry(version: "1.0.0", date: "Oct 25, 2026", changes: [
            "First version: caffeine curve, \u{201C}what if\u{201D} preview, logging (saved, scan, manual), countdown, 400 mg guideline, history.",
        ]),
    ]

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? entries[0].version
    }
}

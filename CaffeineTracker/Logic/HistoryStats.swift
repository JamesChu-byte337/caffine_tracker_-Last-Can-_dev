import Foundation

struct DayStat: Identifiable, Equatable {
    let day: Date
    let totalMg: Double
    let drinkCount: Int
    /// Estimated caffeine at that evening's bedtime.
    let bedtimeMg: Double
    let hadLateCaffeine: Bool

    var id: Date { day }
    var isOverGuideline: Bool { totalMg > CaffeineModel.dailyGuidelineMg }
}

enum HistoryStats {
    /// Caffeine from 8 p.m. on counts as "late", as do drinks in the small hours (before 4 a.m.).
    static let lateHourStart = 20
    static let lateHourEnd = 4

    static func isLate(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= lateHourStart || hour < lateHourEnd
    }

    /// One stat per calendar day for the `days` days ending with the day containing `now`, oldest first.
    static func dailyStats(days: Int, endingAt now: Date, doses: [CaffeineDose], halfLifeHours: Double, bedtimeMinutes: Int, calendar: Calendar = .current) -> [DayStat] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset -> DayStat? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let dayDoses = doses.filter { $0.time >= day && $0.time < nextDay }
            let bedtime = CaffeineModel.bedtime(forEveningOf: day, bedtimeMinutes: bedtimeMinutes, calendar: calendar)
            return DayStat(
                day: day,
                totalMg: dayDoses.reduce(0) { $0 + $1.mg },
                drinkCount: dayDoses.count,
                bedtimeMg: CaffeineModel.remaining(at: bedtime, doses: doses, halfLifeHours: halfLifeHours),
                hadLateCaffeine: dayDoses.contains { isLate($0.time, calendar: calendar) }
            )
        }
    }

    /// Plain-language observations about the period. Informational only; never advice.
    static func insights(for stats: [DayStat], periodName: String) -> [String] {
        let loggedDays = stats.filter { $0.drinkCount > 0 }
        guard !loggedDays.isEmpty else { return [] }
        var lines: [String] = []

        let lateDays = stats.filter(\.hadLateCaffeine).count
        if lateDays > 0 {
            lines.append("You had caffeine after 8 p.m. on \(daysText(lateDays)) \(periodName).")
        }

        let overDays = stats.filter(\.isOverGuideline).count
        if overDays > 0 {
            lines.append("You went over 400 mg on \(daysText(overDays)) \(periodName).")
        }

        let averageBedtime = loggedDays.reduce(0) { $0 + $1.bedtimeMg } / Double(loggedDays.count)
        lines.append("On days you logged caffeine, your estimated amount at bedtime averaged \(Int(averageBedtime.rounded())) mg.")

        if let peak = loggedDays.max(by: { $0.totalMg < $1.totalMg }) {
            let dayName = peak.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            lines.append("Your highest day was \(dayName), with \(Int(peak.totalMg.rounded())) mg.")
        }
        return lines
    }

    private static func daysText(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}

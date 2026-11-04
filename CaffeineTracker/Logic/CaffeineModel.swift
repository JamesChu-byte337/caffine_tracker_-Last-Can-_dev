import Foundation

/// One amount of caffeine taken at a moment in time. Each dose is treated as absorbed immediately.
struct CaffeineDose: Hashable {
    var time: Date
    var mg: Double
}

/// Pure estimate math. Everything here is an estimate; the UI must label it that way.
enum CaffeineModel {
    static let defaultHalfLifeHours: Double = 5
    /// Typical adult half-life range the user may choose from.
    static let halfLifeRange: ClosedRange<Double> = 2...8
    /// Health Canada's maximum daily caffeine intake for healthy adults.
    static let dailyGuidelineMg: Double = 400
    /// Share of the guideline at which the app starts warning that the user is approaching it.
    static let approachingFraction: Double = 0.75
    /// Doses older than this contribute effectively nothing (<0.2% at an 8 h half-life).
    static let relevantWindow: TimeInterval = 72 * 3600

    /// Estimated caffeine in the body at `time`: the sum of dose × 0.5^(hours since dose / half-life).
    /// Doses after `time` contribute nothing.
    static func remaining(at time: Date, doses: [CaffeineDose], halfLifeHours: Double) -> Double {
        doses.reduce(0) { sum, dose in
            let hours = time.timeIntervalSince(dose.time) / 3600
            guard hours >= 0 else { return sum }
            return sum + dose.mg * pow(0.5, hours / halfLifeHours)
        }
    }

    /// Total caffeine taken in the 24 hours ending at `time` (inclusive of `time`).
    static func rolling24hTotal(endingAt time: Date, doses: [CaffeineDose]) -> Double {
        let start = time.addingTimeInterval(-24 * 3600)
        return doses
            .filter { $0.time > start && $0.time <= time }
            .reduce(0) { $0 + $1.mg }
    }

    enum GuidelineLevel {
        case below, approaching, above
    }

    static func guidelineLevel(for totalMg: Double) -> GuidelineLevel {
        if totalMg > dailyGuidelineMg { return .above }
        if totalMg >= dailyGuidelineMg * approachingFraction { return .approaching }
        return .below
    }

    /// The moment the estimate first falls below `thresholdMg`, assuming no further drinks.
    /// Returns nil when the estimate is already below the threshold.
    static func timeBelow(thresholdMg: Double, after now: Date, doses: [CaffeineDose], halfLifeHours: Double) -> Date? {
        guard thresholdMg > 0 else { return nil }
        // After the latest dose the estimate only decreases, so a bisection search is valid from there.
        let start = max(now, doses.map(\.time).max() ?? now)
        guard remaining(at: start, doses: doses, halfLifeHours: halfLifeHours) >= thresholdMg else { return nil }

        // Every dose has decayed at least as much as the total would from `start`, which bounds the search.
        let totalMg = doses.reduce(0) { $0 + $1.mg }
        let upperHours = max(halfLifeHours * log2(totalMg / thresholdMg), 0)
        var low = start
        var high = start.addingTimeInterval(upperHours * 3600 + 60)
        for _ in 0..<50 {
            let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            if remaining(at: mid, doses: doses, halfLifeHours: halfLifeHours) >= thresholdMg {
                low = mid
            } else {
                high = mid
            }
        }
        return high
    }

    /// Sampled points of the estimate between `start` and `end`, with extra points at each dose so the
    /// immediate-absorption step shows as a vertical jump.
    static func curve(doses: [CaffeineDose], from start: Date, to end: Date, halfLifeHours: Double, stepMinutes: Double = 10) -> [(time: Date, mg: Double)] {
        guard end > start else { return [] }
        var times: [Date] = []
        var t = start
        while t < end {
            times.append(t)
            t = t.addingTimeInterval(stepMinutes * 60)
        }
        times.append(end)
        for dose in doses where dose.time > start && dose.time < end {
            times.append(dose.time.addingTimeInterval(-1))
            times.append(dose.time)
        }
        return times.sorted().map { ($0, remaining(at: $0, doses: doses, halfLifeHours: halfLifeHours)) }
    }

    /// The next bedtime strictly after `date`.
    static func nextBedtime(after date: Date, bedtimeMinutes: Int, calendar: Calendar = .current) -> Date {
        let components = DateComponents(hour: bedtimeMinutes / 60, minute: bedtimeMinutes % 60, second: 0)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime) ?? date
    }

    /// The bedtime that belongs to the evening of `day`. Bedtimes before noon are taken to be after midnight.
    static func bedtime(forEveningOf day: Date, bedtimeMinutes: Int, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let dayOffset = bedtimeMinutes < 12 * 60 ? 1 : 0
        let base = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay
        return base.addingTimeInterval(TimeInterval(bedtimeMinutes * 60))
    }
}

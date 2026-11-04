import Foundation

/// Apple Health data the app has read, already reduced to what the analysis needs. Never leaves the device.
struct HealthSnapshot: Equatable {
    struct Reading: Equatable {
        let time: Date
        let value: Double
    }

    struct Night: Equatable {
        /// Start of the calendar day the night began on (the "evening of").
        let evening: Date
        let asleep: TimeInterval
    }

    /// Average heart rate for each hour, last 7 days.
    var hourlyHeartRate: [Reading] = []
    /// Resting heart rate for each day, last 30 days.
    var dailyRestingHeartRate: [Reading] = []
    var nights: [Night] = []
    var highHeartRateEvents: [Date] = []
    var irregularRhythmEvents: [Date] = []
    var latestWeightKg: Double?
    var latestHeightCm: Double?

    var hasHeartOrSleepData: Bool {
        !hourlyHeartRate.isEmpty || !dailyRestingHeartRate.isEmpty || !nights.isEmpty
            || !highHeartRateEvents.isEmpty || !irregularRhythmEvents.isEmpty
    }
}

struct HealthFinding: Identifiable, Equatable {
    enum Level: Int, Comparable {
        case notice, attention, talkToDoctor
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    let id: String
    let level: Level
    let title: String
    let detail: String
}

/// On-device, rule-based look for patterns between caffeine and heart rate or sleep.
/// It reports observations; it never diagnoses or says whether caffeine is safe.
enum HealthAnalyzer {
    static func analyze(_ snapshot: HealthSnapshot, doses: [CaffeineDose], profile: UserProfile, now: Date, calendar: Calendar = .current) -> [HealthFinding] {
        var findings: [HealthFinding] = []
        let halfLife = profile.halfLifeHours
        func estimate(at time: Date) -> Double {
            CaffeineModel.remaining(at: time, doses: doses, halfLifeHours: halfLife)
        }
        func dayText(_ date: Date) -> String {
            date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }

        // 1. Heart rhythm notifications from Apple Watch.
        let rhythmEvents = snapshot.irregularRhythmEvents.filter { now.timeIntervalSince($0) < 14 * 86_400 }
        if let latest = rhythmEvents.max() {
            findings.append(HealthFinding(
                id: "irregular-rhythm",
                level: .talkToDoctor,
                title: "Irregular rhythm notification",
                detail: "Your Apple Watch recorded an irregular heart rhythm notification on \(dayText(latest)). Caffeine can affect heart rhythm in some people. Please talk to a doctor about this."
            ))
        }

        // 2. High heart rate notifications (recorded while inactive).
        let highEvents = snapshot.highHeartRateEvents.filter { now.timeIntervalSince($0) < 7 * 86_400 }
        if !highEvents.isEmpty {
            let days = Set(highEvents.map { calendar.startOfDay(for: $0) }).count
            let withCaffeine = highEvents.filter { estimate(at: $0) >= 100 }.count
            var detail = "Your Apple Watch flagged a high heart rate while you were inactive on \(days == 1 ? "1 day" : "\(days) days") this week."
            if withCaffeine > 0 {
                detail += " Your estimated caffeine was over 100 mg at \(withCaffeine == 1 ? "one of those times" : "\(withCaffeine) of those times")."
            }
            detail += " Please talk to a doctor about this."
            findings.append(HealthFinding(id: "high-heart-rate", level: .talkToDoctor, title: "High heart rate notifications", detail: detail))
        }

        // 3. Daytime heart rate when estimated caffeine is high vs low.
        // Only 8 a.m.–10 p.m. hours are compared, so sleep doesn't make the low-caffeine group look calmer.
        let recentHours = snapshot.hourlyHeartRate.filter {
            now.timeIntervalSince($0.time) < 7 * 86_400 && (8..<22).contains(calendar.component(.hour, from: $0.time))
        }
        let high = recentHours.filter { estimate(at: $0.time.addingTimeInterval(1800)) >= 150 }.map(\.value)
        let low = recentHours.filter { estimate(at: $0.time.addingTimeInterval(1800)) < 50 }.map(\.value)
        if high.count >= 6, low.count >= 6 {
            let difference = mean(high) - mean(low)
            if difference >= 10 {
                findings.append(HealthFinding(
                    id: "caffeine-heart-rate",
                    level: .attention,
                    title: "Higher heart rate with more caffeine",
                    detail: "This week, your daytime heart rate averaged \(Int(difference.rounded())) bpm higher in hours when your estimated caffeine was above 150 mg than when it was below 50 mg. This is a pattern, not proof that caffeine caused it. If it worries you, talk to a doctor."
                ))
            }
        }

        // 4. Resting heart rate over the last 3 days vs the weeks before.
        let recentCutoff = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: now)) ?? now
        let recentResting = snapshot.dailyRestingHeartRate.filter { $0.time >= recentCutoff }.map(\.value)
        let baselineResting = snapshot.dailyRestingHeartRate.filter { $0.time < recentCutoff }.map(\.value)
        if recentResting.count >= 2, baselineResting.count >= 10 {
            let rise = mean(recentResting) - mean(baselineResting)
            if rise >= 7 {
                let recentCaffeine = dailyAverage(doses: doses, from: recentCutoff, to: now)
                var detail = "Your resting heart rate over the last few days is about \(Int(rise.rounded())) bpm above your usual."
                if recentCaffeine > 0 {
                    detail += " You've averaged \(recentCaffeine.mgText) of caffeine a day over the same period."
                }
                detail += " Stress, illness and poor sleep can also raise it. If it stays high, talk to a doctor."
                findings.append(HealthFinding(id: "resting-heart-rate", level: .attention, title: "Resting heart rate is up", detail: detail))
            }
        }

        // 5. Last night's sleep.
        let bedtimeCaffeine: (HealthSnapshot.Night) -> Double = { night in
            estimate(at: CaffeineModel.bedtime(forEveningOf: night.evening, bedtimeMinutes: profile.bedtimeMinutes, calendar: calendar))
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        if let lastNight = snapshot.nights.first(where: { calendar.isDate($0.evening, inSameDayAs: yesterday) }),
           lastNight.asleep < 6 * 3600 {
            let atBed = bedtimeCaffeine(lastNight)
            if atBed >= 50 {
                findings.append(HealthFinding(
                    id: "short-sleep",
                    level: .notice,
                    title: "Short sleep last night",
                    detail: "You slept \(lastNight.asleep.durationText) last night, with an estimated \(atBed.mgText) of caffeine at bedtime."
                ))
            }
        }

        // 6. Sleep on nights with vs without caffeine at bedtime.
        let recentNights = snapshot.nights.filter { now.timeIntervalSince($0.evening) < 15 * 86_400 }
        let caffeinatedNights = recentNights.filter { bedtimeCaffeine($0) >= 50 }.map(\.asleep)
        let otherNights = recentNights.filter { bedtimeCaffeine($0) < 50 }.map(\.asleep)
        if caffeinatedNights.count >= 3, otherNights.count >= 3 {
            let lost = mean(otherNights) - mean(caffeinatedNights)
            if lost >= 30 * 60 {
                findings.append(HealthFinding(
                    id: "sleep-pattern",
                    level: .notice,
                    title: "Less sleep after late caffeine",
                    detail: "Over the last two weeks, you slept about \(lost.durationText) less on nights with an estimated 50 mg or more of caffeine at bedtime."
                ))
            }
        }

        return findings.sorted { $0.level > $1.level }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func dailyAverage(doses: [CaffeineDose], from start: Date, to end: Date) -> Double {
        let days = max(end.timeIntervalSince(start) / 86_400, 1)
        return doses.filter { $0.time >= start && $0.time <= end }.reduce(0) { $0 + $1.mg } / days
    }
}

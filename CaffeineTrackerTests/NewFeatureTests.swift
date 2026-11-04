import Foundation
import Testing
@testable import CaffeineTracker

private func makeProfile(age: Int = 21, flags: Set<HealthFlag> = [], factors: BodyFactors = BodyFactors()) -> UserProfile {
    UserProfile(age: age, usualDrinkName: "Monster", usualDrinkMg: 160, bedtimeMinutes: 23 * 60, healthFlags: flags, bodyFactors: factors)
}

private var toronto: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Toronto")!
    return calendar
}

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    toronto.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
}

struct HalfLifeEstimatorTests {
    @Test func averageAdultGetsFiveHours() {
        let estimate = HalfLifeEstimator.estimate(for: makeProfile())
        #expect(estimate.hours == 5)
        #expect(estimate.adjustments.isEmpty)
    }

    @Test func slowingMedicationLengthens() {
        #expect(HalfLifeEstimator.estimate(for: makeProfile(factors: BodyFactors(slowingMedication: true))).hours == 8)
    }

    @Test func clampedToTypicalAdultRange() {
        let profile = makeProfile(flags: [.liverCondition], factors: BodyFactors(slowingMedication: true))
        #expect(HalfLifeEstimator.estimate(for: profile).hours == 8)
    }

    @Test func bmiOnlyCountsWithBothValues() {
        #expect(HalfLifeEstimator.estimate(for: makeProfile(factors: BodyFactors(weightKg: 110))).adjustments.isEmpty)
        let estimate = HalfLifeEstimator.estimate(for: makeProfile(factors: BodyFactors(weightKg: 110, heightCm: 175)))
        #expect(estimate.adjustments.map(\.label) == ["Body mass index 30 or over"])
        #expect(estimate.hours == 5.75)
    }
}

struct AccountTests {
    @Test func onlyWaterlooAddresses() {
        #expect(Account.isAllowed("j2zhu@uwaterloo.ca"))
        #expect(Account.isAllowed(" J2Zhu@UWaterloo.CA "))
        #expect(!Account.isAllowed("someone@gmail.com"))
        #expect(!Account.isAllowed("someone@uwaterloo.ca.evil.com"))
        #expect(!Account.isAllowed("someone@notuwaterloo.ca"))
        #expect(!Account.isAllowed("@uwaterloo.ca"))
    }
}

struct ProfileMigrationTests {
    @Test func oldSavedProfileStillLoads() throws {
        let old = #"{"age":21,"usualDrinkName":"Monster","usualDrinkMg":160,"bedtimeMinutes":1380,"healthFlags":["hypertension"],"halfLifeHours":6,"thresholdMg":50,"notificationsEnabled":true}"#
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(old.utf8))
        #expect(profile.healthFlags == [.hypertension])
        #expect(profile.customConditions.isEmpty)
        #expect(profile.bodyFactors == BodyFactors())
        #expect(profile.notificationsEnabled)
    }
}

struct DailyGreetingTests {
    private func week(mgPerDay: Double, through lastDay: Int) -> [CaffeineDose] {
        (lastDay - 6...lastDay).map { CaffeineDose(time: date($0, 10), mg: mgPerDay) }
    }

    @Test func decreaseIsCelebrated() {
        let doses = week(mgPerDay: 300, through: 8) + [CaffeineDose(time: date(9, 10), mg: 150)]
        let message = DailyGreeting.message(doses: doses, now: date(10, 9), calendar: toronto)
        #expect(message?.trend == .down)
        #expect(message?.percent == 50)
    }

    @Test func increaseGetsWorkloadMessage() {
        let doses = week(mgPerDay: 200, through: 8) + [CaffeineDose(time: date(9, 10), mg: 400)]
        let message = DailyGreeting.message(doses: doses, now: date(10, 9), calendar: toronto)
        #expect(message?.trend == .up)
        #expect(message?.text.contains("Eat well, rest well, study well.") == true)
    }

    @Test func smallChangeOrLittleHistoryShowsNothing() {
        let steady = week(mgPerDay: 200, through: 8) + [CaffeineDose(time: date(9, 10), mg: 210)]
        #expect(DailyGreeting.message(doses: steady, now: date(10, 9), calendar: toronto) == nil)
        let sparse = [CaffeineDose(time: date(5, 10), mg: 200), CaffeineDose(time: date(9, 10), mg: 50)]
        #expect(DailyGreeting.message(doses: sparse, now: date(10, 9), calendar: toronto) == nil)
    }
}

struct HealthAnalyzerTests {
    let profile = makeProfile()

    @Test func nothingUnusualGivesNoFindings() {
        var snapshot = HealthSnapshot()
        snapshot.nights = [HealthSnapshot.Night(evening: date(9, 0), asleep: 8 * 3600)]
        #expect(HealthAnalyzer.analyze(snapshot, doses: [], profile: profile, now: date(10, 12), calendar: toronto).isEmpty)
    }

    @Test func watchRhythmNotificationAsksForDoctor() throws {
        var snapshot = HealthSnapshot()
        snapshot.irregularRhythmEvents = [date(8, 14)]
        let findings = HealthAnalyzer.analyze(snapshot, doses: [], profile: profile, now: date(10, 12), calendar: toronto)
        let first = try #require(findings.first)
        #expect(first.level == .talkToDoctor)
        #expect(first.detail.contains("talk to a doctor"))
    }

    @Test func heartRateHigherWhenCaffeinated() {
        // 400 mg at 9 a.m. daily with a 2 h half-life: late morning is high-caffeine, evening is low.
        var doses: [CaffeineDose] = []
        var hours: [HealthSnapshot.Reading] = []
        for day in 4...9 {
            doses.append(CaffeineDose(time: date(day, 9), mg: 400))
            for hour in 9...12 { hours.append(.init(time: date(day, hour), value: 95)) }
            for hour in 19...21 { hours.append(.init(time: date(day, hour), value: 70)) }
        }
        var shortHalfLife = profile
        shortHalfLife.halfLifeHours = 2
        var snapshot = HealthSnapshot()
        snapshot.hourlyHeartRate = hours
        let findings = HealthAnalyzer.analyze(snapshot, doses: doses, profile: shortHalfLife, now: date(10, 8), calendar: toronto)
        #expect(findings.contains { $0.id == "caffeine-heart-rate" })
    }

    @Test func shortSleepWithBedtimeCaffeine() {
        var snapshot = HealthSnapshot()
        snapshot.nights = [HealthSnapshot.Night(evening: date(9, 0), asleep: 5 * 3600)]
        let doses = [CaffeineDose(time: date(9, 20), mg: 160)]
        let findings = HealthAnalyzer.analyze(snapshot, doses: doses, profile: profile, now: date(10, 12), calendar: toronto)
        #expect(findings.map(\.id) == ["short-sleep"])
    }

    @Test func overlappingSleepSourcesAreMerged() {
        let watch = DateInterval(start: date(9, 23), end: date(10, 6))
        let phone = DateInterval(start: date(10, 1), end: date(10, 7))
        let nights = HealthDataStore.nights(from: [watch, phone], calendar: toronto)
        #expect(nights.count == 1)
        #expect(nights[0].asleep == 8 * 3600)
        #expect(nights[0].evening == toronto.startOfDay(for: date(9, 12)))
    }
}

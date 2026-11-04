import Foundation
import Testing
@testable import CaffeineTracker

struct CaffeineModelTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func hours(_ h: Double) -> Date { start.addingTimeInterval(h * 3600) }

    @Test func halvesAfterOneHalfLife() {
        let doses = [CaffeineDose(time: start, mg: 200)]
        #expect(abs(CaffeineModel.remaining(at: hours(5), doses: doses, halfLifeHours: 5) - 100) < 0.001)
        #expect(abs(CaffeineModel.remaining(at: hours(10), doses: doses, halfLifeHours: 5) - 50) < 0.001)
    }

    @Test func sumsDosesAndIgnoresFutureOnes() {
        let doses = [CaffeineDose(time: start, mg: 160), CaffeineDose(time: hours(5), mg: 80), CaffeineDose(time: hours(8), mg: 300)]
        // 160 × 0.5 + 80 = 160; the drink at 8 h hasn't happened yet.
        #expect(abs(CaffeineModel.remaining(at: hours(5), doses: doses, halfLifeHours: 5) - 160) < 0.001)
    }

    @Test func rollingTotalUsesLast24Hours() {
        let doses = [CaffeineDose(time: hours(0), mg: 100), CaffeineDose(time: hours(10), mg: 200), CaffeineDose(time: hours(23), mg: 50)]
        #expect(CaffeineModel.rolling24hTotal(endingAt: hours(23), doses: doses) == 350)
        #expect(CaffeineModel.rolling24hTotal(endingAt: hours(24), doses: doses) == 250)
    }

    @Test func timeBelowThresholdMatchesClosedForm() throws {
        let doses = [CaffeineDose(time: start, mg: 200)]
        // 200 → 50 takes two half-lives.
        let crossing = try #require(CaffeineModel.timeBelow(thresholdMg: 50, after: start, doses: doses, halfLifeHours: 5))
        #expect(abs(crossing.timeIntervalSince(hours(10))) < 1)
        #expect(CaffeineModel.timeBelow(thresholdMg: 50, after: hours(11), doses: doses, halfLifeHours: 5) == nil)
    }

    @Test func newDrinkPushesCountdownLater() throws {
        let first = [CaffeineDose(time: start, mg: 160)]
        let before = try #require(CaffeineModel.timeBelow(thresholdMg: 50, after: hours(1), doses: first, halfLifeHours: 5))
        let after = try #require(CaffeineModel.timeBelow(thresholdMg: 50, after: hours(1), doses: first + [CaffeineDose(time: hours(1), mg: 80)], halfLifeHours: 5))
        #expect(after > before)
    }

    @Test func guidelineLevels() {
        #expect(CaffeineModel.guidelineLevel(for: 200) == .below)
        #expect(CaffeineModel.guidelineLevel(for: 300) == .approaching)
        #expect(CaffeineModel.guidelineLevel(for: 400) == .approaching)
        #expect(CaffeineModel.guidelineLevel(for: 401) == .above)
    }

    @Test func bedtimeAfterMidnightBelongsToPreviousEvening() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 9))!
        let bedtime = CaffeineModel.bedtime(forEveningOf: day, bedtimeMinutes: 60, calendar: calendar)
        #expect(calendar.dateComponents([.day, .hour], from: bedtime) == DateComponents(day: 11, hour: 1))
        let next = CaffeineModel.nextBedtime(after: day, bedtimeMinutes: 23 * 60, calendar: calendar)
        #expect(calendar.dateComponents([.day, .hour], from: next) == DateComponents(day: 10, hour: 23))
    }

    @Test func historyCountsLateDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let doses = [
            CaffeineDose(time: calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 21))!, mg: 160),
            CaffeineDose(time: calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 10))!, mg: 300),
            CaffeineDose(time: calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 15))!, mg: 200),
        ]
        let stats = HistoryStats.dailyStats(days: 7, endingAt: now, doses: doses, halfLifeHours: 5, bedtimeMinutes: 23 * 60, calendar: calendar)
        #expect(stats.count == 7)
        #expect(stats.filter(\.hadLateCaffeine).count == 1)
        #expect(stats.filter(\.isOverGuideline).count == 1)
        let insights = HistoryStats.insights(for: stats, periodName: "this week")
        #expect(insights.first == "You had caffeine after 8 p.m. on 1 day this week.")
    }
}

struct LabelParserTests {
    @Test func simpleAmount() {
        let result = LabelParser.parse(text: "ENERGY DRINK\nCaffeine 160 mg\n473 mL")
        #expect(result.caffeineMg == 160)
        #expect(result.servingML == 473)
    }

    @Test func amountBeforeWord() {
        #expect(LabelParser.parse(text: "Contains 80mg of caffeine per can").caffeineMg == 80)
    }

    @Test func frenchLabel() {
        #expect(LabelParser.parse(text: "Teneur en caféine : 80 mg par portion").caffeineMg == 80)
    }

    @Test func per100mLIsScaledToServing() {
        let result = LabelParser.parse(text: "HIGH CAFFEINE CONTENT (32 mg/100 mL). Serving size 1 can (473 mL)")
        #expect(result.per100mLMg == 32)
        #expect(result.servingML == 473)
        #expect(result.caffeineMg == 151)
    }

    @Test func per100mLWithoutServingNeedsUserInput() {
        let result = LabelParser.parse(text: "Caffeine 32 mg / 100 ml")
        #expect(result.per100mLMg == 32)
        #expect(result.caffeineMg == nil)
    }

    @Test func fluidOuncesFallback() {
        #expect(LabelParser.parse(text: "Caffeine 200mg 16 FL OZ").servingML == 473)
    }

    @Test func noCaffeineFound() {
        #expect(LabelParser.parse(text: "Sugar 54 g").caffeineMg == nil)
    }
}

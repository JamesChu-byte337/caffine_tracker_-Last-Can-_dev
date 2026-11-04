import Charts
import SwiftUI

struct HistoryView: View {
    let profile: UserProfile
    let drinks: [DrinkEntry]

    private enum Period: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
        var name: String { self == .week ? "this week" : "in the last 30 days" }
    }

    @State private var period: Period = .week

    var body: some View {
        let stats = HistoryStats.dailyStats(
            days: period.days,
            endingAt: .now,
            doses: drinks.map(\.dose),
            halfLifeHours: profile.halfLifeHours,
            bedtimeMinutes: profile.bedtimeMinutes
        )
        let insights = HistoryStats.insights(for: stats, periodName: period.name)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if insights.isEmpty {
                        ContentUnavailableView("No drinks yet", systemImage: "chart.bar", description: Text("Charts and patterns appear once you've logged some drinks."))
                    } else {
                        summary(stats)
                        Card {
                            Text("Patterns").font(.headline)
                            ForEach(insights, id: \.self) { line in
                                Label(line, systemImage: "sparkle").font(.subheadline)
                            }
                        }
                        totalsChart(stats)
                        drinksChart(stats)
                        bedtimeChart(stats)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    private func summary(_ stats: [DayStat]) -> some View {
        let logged = stats.filter { $0.drinkCount > 0 }
        let average = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.totalMg } / Double(logged.count)
        // Equal-height tiles even when one caption wraps to two lines and another doesn't.
        return HStack(spacing: 12) {
            StatTile(title: "Avg. on days logged", value: average.mgText)
            StatTile(title: "Drinks", value: "\(stats.reduce(0) { $0 + $1.drinkCount })")
            StatTile(title: "Days over 400 mg", value: "\(stats.filter(\.isOverGuideline).count) of \(stats.count)")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 7)) { _ in
            AxisGridLine()
            if period == .week {
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            } else {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
            }
        }
    }

    private func totalsChart(_ stats: [DayStat]) -> some View {
        Card {
            Text("Daily caffeine").font(.headline)
            Chart {
                ForEach(stats) { stat in
                    BarMark(x: .value("Day", stat.day, unit: .day), y: .value("Caffeine", stat.totalMg))
                        .foregroundStyle(stat.isOverGuideline ? Color.red : Theme.accent)
                }
                RuleMark(y: .value("Guideline", CaffeineModel.dailyGuidelineMg))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("400 mg").font(.caption2).foregroundStyle(.red)
                    }
            }
            .chartXAxis { xAxis }
            .frame(height: 180)
        }
    }

    private func drinksChart(_ stats: [DayStat]) -> some View {
        Card {
            Text("Drinks per day").font(.headline)
            Chart(stats) { stat in
                BarMark(x: .value("Day", stat.day, unit: .day), y: .value("Drinks", stat.drinkCount))
                    .foregroundStyle(Theme.accent.opacity(0.7))
            }
            .chartXAxis { xAxis }
            .chartYAxis { AxisMarks(values: .automatic(minimumStride: 1)) }
            .frame(height: 140)
        }
    }

    private func bedtimeChart(_ stats: [DayStat]) -> some View {
        Card {
            Text("Estimated caffeine at bedtime").font(.headline)
            Chart(stats) { stat in
                LineMark(x: .value("Day", stat.day, unit: .day), y: .value("Caffeine", stat.bedtimeMg))
                    .foregroundStyle(Theme.bedtime)
                PointMark(x: .value("Day", stat.day, unit: .day), y: .value("Caffeine", stat.bedtimeMg))
                    .foregroundStyle(Theme.bedtime)
                    .symbolSize(period == .week ? 40 : 15)
            }
            .chartXAxis { xAxis }
            .frame(height: 160)
            Text("Estimated amount remaining at your bedtime each night, including today's drinks so far.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

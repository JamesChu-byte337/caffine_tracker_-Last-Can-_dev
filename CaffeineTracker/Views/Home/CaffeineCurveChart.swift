import Charts
import SwiftUI

/// The day's estimated caffeine curve, with optional "what if" overlay for a drink not yet logged.
struct CaffeineCurveChart: View {
    let doses: [CaffeineDose]
    var previewDose: CaffeineDose? = nil
    let halfLifeHours: Double
    let now: Date
    let bedtime: Date
    let thresholdMg: Double

    private static let loggedSeries = "Logged drinks"
    private static let previewSeries = "With this drink"

    private struct Point: Identifiable {
        let id: String
        let time: Date
        let mg: Double
        let series: String
    }

    private var start: Date {
        min(Calendar.current.startOfDay(for: now), now.addingTimeInterval(-6 * 3600))
    }

    private var end: Date {
        max(bedtime, previewDose?.time ?? bedtime).addingTimeInterval(2 * 3600)
    }

    private var loggedPoints: [Point] {
        CaffeineModel.curve(doses: doses, from: start, to: end, halfLifeHours: halfLifeHours)
            .enumerated()
            .map { Point(id: "logged-\($0.offset)", time: $0.element.time, mg: $0.element.mg, series: Self.loggedSeries) }
    }

    private var previewPoints: [Point] {
        guard let previewDose else { return [] }
        // Before the drink the two curves are identical, so only draw the overlay from the drink onward.
        let from = max(start, previewDose.time.addingTimeInterval(-1))
        return CaffeineModel.curve(doses: doses + [previewDose], from: from, to: end, halfLifeHours: halfLifeHours)
            .enumerated()
            .map { Point(id: "preview-\($0.offset)", time: $0.element.time, mg: $0.element.mg, series: Self.previewSeries) }
    }

    var body: some View {
        let logged = loggedPoints
        let preview = previewPoints
        let peak = (logged + preview).map(\.mg).max() ?? 0
        let yMax = max(peak * 1.15, thresholdMg * 2, 100)

        Chart {
            ForEach(logged) { point in
                AreaMark(x: .value("Time", point.time), y: .value("Caffeine", point.mg))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            }
            ForEach(logged) { point in
                LineMark(x: .value("Time", point.time), y: .value("Caffeine", point.mg), series: .value("Series", point.series))
                    .foregroundStyle(by: .value("Series", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            ForEach(preview) { point in
                LineMark(x: .value("Time", point.time), y: .value("Caffeine", point.mg), series: .value("Series", point.series))
                    .foregroundStyle(by: .value("Series", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            }

            RuleMark(y: .value("Threshold", thresholdMg))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text(thresholdMg.mgText).font(.caption2).foregroundStyle(.secondary)
                }

            RuleMark(x: .value("Now", now))
                .foregroundStyle(.primary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, spacing: 2) {
                    Text("Now").font(.caption2.bold()).foregroundStyle(.secondary)
                }

            RuleMark(x: .value("Bedtime", bedtime))
                .foregroundStyle(Theme.bedtime.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .annotation(position: .top, spacing: 2) {
                    Image(systemName: "moon.fill").font(.caption2).foregroundStyle(Theme.bedtime)
                }
        }
        .chartForegroundStyleScale([Self.loggedSeries: Theme.accent, Self.previewSeries: Theme.preview])
        .chartLegend(previewDose == nil ? .hidden : .visible)
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let mg = value.as(Double.self) { Text("\(Int(mg))") }
                }
            }
        }
        .chartYAxisLabel("mg (estimate)", position: .topLeading)
        .accessibilityLabel("Estimated caffeine curve")
        .accessibilityValue("About \(CaffeineModel.remaining(at: now, doses: doses, halfLifeHours: halfLifeHours).mgText) now, about \(CaffeineModel.remaining(at: bedtime, doses: doses + (previewDose.map { [$0] } ?? []), halfLifeHours: halfLifeHours).mgText) at bedtime")
    }
}

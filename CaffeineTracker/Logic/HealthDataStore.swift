import Foundation
import HealthKit
import Observation

/// Reads heart, sleep and body data from Apple Health, only after the user opts in.
/// Everything stays on this device; nothing is written back to Health.
@MainActor
@Observable
final class HealthDataStore {
    enum Status: Equatable {
        case idle, loading, loaded, failed
    }

    private(set) var snapshot: HealthSnapshot?
    private(set) var status: Status = .idle
    private(set) var lastUpdated: Date?

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.highHeartRateEvent),
            HKCategoryType(.irregularHeartRhythmEvent),
        ]
    }

    /// Shows Apple's Health permission sheet. Health doesn't tell apps which types were allowed;
    /// types the user turned off simply return no data.
    func requestAccess() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    func refresh(now: Date = .now) async {
        guard Self.isAvailable else { return }
        status = .loading
        do {
            var snapshot = HealthSnapshot()
            snapshot.hourlyHeartRate = try await averages(of: .heartRate, days: 7, interval: DateComponents(hour: 1), now: now)
            snapshot.dailyRestingHeartRate = try await averages(of: .restingHeartRate, days: 30, interval: DateComponents(day: 1), now: now)
            snapshot.nights = try await sleepNights(days: 15, now: now)
            snapshot.highHeartRateEvents = try await eventDates(.highHeartRateEvent, days: 14, now: now)
            snapshot.irregularRhythmEvents = try await eventDates(.irregularHeartRhythmEvent, days: 14, now: now)
            snapshot.latestWeightKg = try await latest(.bodyMass, unit: .gramUnit(with: .kilo))
            snapshot.latestHeightCm = try await latest(.height, unit: .meterUnit(with: .centi))
            self.snapshot = snapshot
            lastUpdated = now
            status = .loaded
        } catch {
            status = .failed
        }
    }

    func clear() {
        snapshot = nil
        lastUpdated = nil
        status = .idle
    }

    // MARK: Queries

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    private func averages(of identifier: HKQuantityTypeIdentifier, days: Int, interval: DateComponents, now: Date) async throws -> [HealthSnapshot.Reading] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: .discreteAverage,
            anchorDate: calendar.startOfDay(for: now),
            intervalComponents: interval
        )
        let collection = try await descriptor.result(for: store)
        return collection.statistics().compactMap { stats in
            guard let value = stats.averageQuantity()?.doubleValue(for: Self.bpm) else { return nil }
            return HealthSnapshot.Reading(time: stats.startDate, value: value)
        }
    }

    private func sleepNights(days: Int, now: Date) async throws -> [HealthSnapshot.Night] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let intervals = try await descriptor.result(for: store)
            .filter { asleepValues.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        return Self.nights(from: intervals, calendar: calendar)
    }

    /// Merges overlapping sleep from several sources (iPhone and Watch) and totals it per night.
    nonisolated static func nights(from intervals: [DateInterval], calendar: Calendar) -> [HealthSnapshot.Night] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        // Sleep starting before noon belongs to the previous evening.
        var totals: [Date: TimeInterval] = [:]
        for interval in merged {
            let evening = calendar.startOfDay(for: interval.start.addingTimeInterval(-12 * 3600))
            totals[evening, default: 0] += interval.duration
        }
        return totals.map { HealthSnapshot.Night(evening: $0.key, asleep: $0.value) }.sorted { $0.evening < $1.evening }
    }

    private func eventDates(_ identifier: HKCategoryTypeIdentifier, days: Int, now: Date) async throws -> [Date] {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map(\.startDate)
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first?.quantity.doubleValue(for: unit)
    }
}

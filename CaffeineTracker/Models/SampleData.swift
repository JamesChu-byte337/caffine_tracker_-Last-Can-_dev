#if DEBUG
import Foundation
import SwiftData

/// Fake history for demos and the student walkthroughs. Debug builds only.
/// Launching with `-seedDemoData` loads it automatically when the log is empty (used for screenshots).
enum SampleData {
    static let launchArgument = "-seedDemoData"

    static func insert(into context: ModelContext, days: Int = 30, now: Date = .now) {
        let calendar = Calendar.current
        let drinks: [(String, Double)] = [("Monster Energy", 160), ("Red Bull", 80), ("Coffee", 95), ("Celsius", 200)]
        var generator = SystemRandomNumberGenerator()
        for offset in 1...days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else { continue }
            let count = Int.random(in: 0...4, using: &generator)
            for _ in 0..<count {
                let (name, mg) = drinks.randomElement(using: &generator)!
                let minutes = Int.random(in: (8 * 60)...(23 * 60), using: &generator)
                context.insert(DrinkEntry(timestamp: day.addingTimeInterval(TimeInterval(minutes * 60)), name: name, mgPerServing: mg, quantity: 1, source: .manual))
            }
        }
        // Two drinks earlier today, so the Today curve has something to show.
        let startOfToday = calendar.startOfDay(for: now)
        for (name, mg, hoursAgo) in [("Monster Energy", 160.0, 7.5), ("Red Bull", 80.0, 2.25)] {
            let time = now.addingTimeInterval(-hoursAgo * 3600)
            if time > startOfToday {
                context.insert(DrinkEntry(timestamp: time, name: name, mgPerServing: mg, quantity: 1, source: .saved))
            }
        }
        let savedCount = (try? context.fetchCount(FetchDescriptor<SavedDrink>())) ?? 0
        if savedCount == 0 {
            for (name, mg) in drinks { context.insert(SavedDrink(name: name, mgPerServing: mg)) }
        }
        try? context.save()
    }
}
#endif

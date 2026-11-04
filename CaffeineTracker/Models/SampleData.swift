#if DEBUG
import Foundation
import SwiftData

/// Fake history for demos and the student walkthroughs. Debug builds only.
enum SampleData {
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
        try? context.save()
    }
}
#endif

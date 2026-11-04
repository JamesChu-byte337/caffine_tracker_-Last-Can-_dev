import Foundation
import SwiftData

enum DrinkSource: String, Codable, CaseIterable, Identifiable {
    case saved, scan, manual
    var id: String { rawValue }

    var label: String {
        switch self {
        case .saved: "My drinks"
        case .scan: "Scan label"
        case .manual: "Enter mg"
        }
    }
}

/// A logged drink. Editable after saving.
@Model
final class DrinkEntry {
    var timestamp: Date
    var name: String
    var mgPerServing: Double
    var quantity: Double
    var sourceRaw: String

    init(timestamp: Date, name: String, mgPerServing: Double, quantity: Double, source: DrinkSource) {
        self.timestamp = timestamp
        self.name = name
        self.mgPerServing = mgPerServing
        self.quantity = quantity
        self.sourceRaw = source.rawValue
    }

    var totalMg: Double { mgPerServing * quantity }
    var dose: CaffeineDose { CaffeineDose(time: timestamp, mg: totalMg) }
}

/// A drink the user can pick again without re-entering its caffeine.
@Model
final class SavedDrink {
    var name: String
    var mgPerServing: Double
    var servingML: Double?
    var createdAt: Date

    init(name: String, mgPerServing: Double, servingML: Double? = nil, createdAt: Date = .now) {
        self.name = name
        self.mgPerServing = mgPerServing
        self.servingML = servingML
        self.createdAt = createdAt
    }
}

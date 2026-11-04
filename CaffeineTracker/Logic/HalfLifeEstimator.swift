import Foundation

/// Estimates a personal caffeine half-life from factors reported in pharmacology research.
///
/// The starting point is the ~5 h average for healthy, non-smoking adults. Each factor scales it:
/// - Some medications (fluvoxamine, ciprofloxacin, others) strongly inhibit CYP1A2.
/// - Liver disease and pregnancy (especially late pregnancy) markedly slow clearance.
/// - Obesity and older age are associated with modest slowing.
/// Genetics (CYP1A2 variants) also matter but can't be estimated without testing.
/// Sources: Nehlig 2018, Pharmacol Rev (PMID 29514871); Grzegorzewski et al. 2021, Front Pharmacol (doi 10.3389/fphar.2021.752826).
enum HalfLifeEstimator {
    struct Adjustment: Equatable, Identifiable {
        let label: String
        let multiplier: Double
        var id: String { label }
        var effectText: String { multiplier < 1 ? "Shorter" : "Longer" }
    }

    struct Estimate: Equatable {
        let hours: Double
        let adjustments: [Adjustment]
    }

    static let baseHours = CaffeineModel.defaultHalfLifeHours

    static func estimate(for profile: UserProfile) -> Estimate {
        let factors = profile.bodyFactors
        var adjustments: [Adjustment] = []

        if factors.slowingMedication {
            adjustments.append(Adjustment(label: "Medication that slows caffeine breakdown", multiplier: 2.0))
        }
        if profile.healthFlags.contains(.liverCondition) {
            adjustments.append(Adjustment(label: "Liver condition", multiplier: 2.0))
        }
        if profile.healthFlags.contains(.pregnancyOrBreastfeeding) {
            adjustments.append(Adjustment(label: "Pregnancy or breastfeeding", multiplier: 1.8))
        }
        if profile.age >= 65 {
            adjustments.append(Adjustment(label: "Age 65 or over", multiplier: 1.2))
        }
        if let bmi = bmi(weightKg: factors.weightKg, heightCm: factors.heightCm), bmi >= 30 {
            adjustments.append(Adjustment(label: "Body mass index 30 or over", multiplier: 1.15))
        }

        let raw = adjustments.reduce(baseHours) { $0 * $1.multiplier }
        let clamped = min(max(raw, CaffeineModel.halfLifeRange.lowerBound), CaffeineModel.halfLifeRange.upperBound)
        // Rounded to the nearest quarter hour; more precision than that would be false confidence.
        return Estimate(hours: (clamped * 4).rounded() / 4, adjustments: adjustments)
    }

    static func bmi(weightKg: Double?, heightCm: Double?) -> Double? {
        guard let weightKg, let heightCm, weightKg > 0, heightCm > 0 else { return nil }
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }
}

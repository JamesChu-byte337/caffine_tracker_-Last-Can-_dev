import Foundation
import Observation

enum HealthFlag: String, Codable, CaseIterable, Identifiable {
    case hypertension, heartCondition, palpitations, anxiety, migraine, sleepProblems, acidReflux, seizureDisorder, liverCondition, kidneyCondition, pregnancyOrBreastfeeding, caffeineSensitivity
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hypertension: "High blood pressure (hypertension)"
        case .heartCondition: "A heart condition"
        case .palpitations: "Irregular or racing heartbeat (palpitations)"
        case .anxiety: "Anxiety or panic attacks"
        case .migraine: "Migraines or frequent headaches"
        case .sleepProblems: "Insomnia or other sleep problems"
        case .acidReflux: "Acid reflux or stomach ulcers"
        case .seizureDisorder: "Epilepsy or seizures"
        case .liverCondition: "A liver condition"
        case .kidneyCondition: "A kidney condition"
        case .pregnancyOrBreastfeeding: "Pregnant or breastfeeding"
        case .caffeineSensitivity: "Caffeine sensitivity"
        }
    }
}

/// Things known to change how fast caffeine leaves the body. Stored only on this device.
struct BodyFactors: Codable, Equatable {
    var weightKg: Double?
    var heightCm: Double?
    var slowingMedication = false
}

struct UserProfile: Codable, Equatable {
    static let minimumAge = 18

    var age: Int
    var usualDrinkName: String
    var usualDrinkMg: Double
    var usualDrinkServingML: Double?
    /// Minutes after midnight.
    var bedtimeMinutes: Int
    var healthFlags: Set<HealthFlag>
    /// Conditions the user typed in that aren't in the list.
    var customConditions: [String] = []
    var bodyFactors = BodyFactors()
    /// Set by `HalfLifeEstimator`, not by the user directly.
    var halfLifeHours: Double = CaffeineModel.defaultHalfLifeHours
    var halfLifeEvaluatedAt: Date?
    var thresholdMg: Double = 50
    var notificationsEnabled: Bool = false

    var hasFullAccess: Bool { age >= Self.minimumAge }
    var hasHealthFlags: Bool { !healthFlags.isEmpty || !customConditions.isEmpty }
    var conditionCount: Int { healthFlags.count + customConditions.count }

    init(age: Int, usualDrinkName: String, usualDrinkMg: Double, usualDrinkServingML: Double? = nil, bedtimeMinutes: Int, healthFlags: Set<HealthFlag>, customConditions: [String] = [], bodyFactors: BodyFactors = BodyFactors(), thresholdMg: Double = 50) {
        self.age = age
        self.usualDrinkName = usualDrinkName
        self.usualDrinkMg = usualDrinkMg
        self.usualDrinkServingML = usualDrinkServingML
        self.bedtimeMinutes = bedtimeMinutes
        self.healthFlags = healthFlags
        self.customConditions = customConditions
        self.bodyFactors = bodyFactors
        self.thresholdMg = thresholdMg
    }

    // Decoded by hand so profiles saved by older versions, missing newer fields, still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        age = try c.decode(Int.self, forKey: .age)
        usualDrinkName = try c.decode(String.self, forKey: .usualDrinkName)
        usualDrinkMg = try c.decode(Double.self, forKey: .usualDrinkMg)
        usualDrinkServingML = try c.decodeIfPresent(Double.self, forKey: .usualDrinkServingML)
        bedtimeMinutes = try c.decode(Int.self, forKey: .bedtimeMinutes)
        let rawFlags = try c.decodeIfPresent([String].self, forKey: .healthFlags) ?? []
        healthFlags = Set(rawFlags.compactMap(HealthFlag.init(rawValue:)))
        customConditions = try c.decodeIfPresent([String].self, forKey: .customConditions) ?? []
        bodyFactors = try c.decodeIfPresent(BodyFactors.self, forKey: .bodyFactors) ?? BodyFactors()
        halfLifeHours = try c.decodeIfPresent(Double.self, forKey: .halfLifeHours) ?? CaffeineModel.defaultHalfLifeHours
        halfLifeEvaluatedAt = try c.decodeIfPresent(Date.self, forKey: .halfLifeEvaluatedAt)
        thresholdMg = try c.decodeIfPresent(Double.self, forKey: .thresholdMg) ?? 50
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
    }

    /// Re-runs the half-life estimate from the current age, conditions and body factors.
    mutating func reevaluateHalfLife(now: Date = .now) {
        halfLifeHours = HalfLifeEstimator.estimate(for: self).hours
        halfLifeEvaluatedAt = now
    }
}

enum AppText {
    static let disclaimer = "This app provides estimates for tracking purposes only and isn't medical advice. Caffeine affects people differently. If you have a health condition or concern, consult a healthcare professional. If you have severe symptoms, seek medical care right away."

    static let healthFlagAdvice = "Please talk to your doctor about how much caffeine is right for you. Because you've listed a health condition, this app won't calculate a personal limit."

    static let guidelineNote = "400 mg is Health Canada's general daily maximum for healthy adults."

    static let onDeviceStorage = "Saved only on this device. It's never sent to our servers or shared."

    static let urgentCare = "This isn't a diagnosis. If you have chest pain, fainting, or trouble breathing, seek medical care right away."
}

/// Account, profile and disclaimer state, kept in on-device UserDefaults (not synced).
@Observable
final class ProfileStore {
    private static let profileKey = "userProfile.v1"
    private static let disclaimerKey = "disclaimerAcceptedAt.v1"
    private static let emailKey = "accountEmail.v1"
    private static let healthSharingKey = "healthSharingEnabled.v1"
    private static let greetingDayKey = "lastGreetingDay.v1"
    private let defaults: UserDefaults

    var profile: UserProfile? {
        didSet { saveProfile() }
    }

    var disclaimerAcceptedAt: Date? {
        didSet { defaults.set(disclaimerAcceptedAt, forKey: Self.disclaimerKey) }
    }

    var accountEmail: String? {
        didSet { defaults.set(accountEmail, forKey: Self.emailKey) }
    }

    /// The user agreed to let the app read Apple Health data.
    var healthSharingEnabled: Bool {
        didSet { defaults.set(healthSharingEnabled, forKey: Self.healthSharingKey) }
    }

    /// The day ("yyyy-MM-dd") the daily greeting was last shown.
    var lastGreetingDay: String? {
        didSet { defaults.set(lastGreetingDay, forKey: Self.greetingDayKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.profileKey) {
            profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        }
        disclaimerAcceptedAt = defaults.object(forKey: Self.disclaimerKey) as? Date
        accountEmail = defaults.string(forKey: Self.emailKey)
        healthSharingEnabled = defaults.bool(forKey: Self.healthSharingKey)
        lastGreetingDay = defaults.string(forKey: Self.greetingDayKey)
    }

    func signOut() {
        accountEmail = nil
    }

    func reset() {
        profile = nil
        disclaimerAcceptedAt = nil
        accountEmail = nil
        healthSharingEnabled = false
        lastGreetingDay = nil
    }

    private func saveProfile() {
        if let profile, let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        } else {
            defaults.removeObject(forKey: Self.profileKey)
        }
    }
}

enum Account {
    static let allowedDomain = "uwaterloo.ca"

    /// Only University of Waterloo addresses can use the app for now. Not verified; there's no SSO yet.
    static func isAllowed(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: #"^[A-Za-z0-9._%+-]+@uwaterloo\.ca$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

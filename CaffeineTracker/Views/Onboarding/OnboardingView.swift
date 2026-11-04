import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.modelContext) private var context

    private enum Step: Int, CaseIterable {
        case age, drink, bedtime, health, aboutYou, countdown

        var title: String {
            switch self {
            case .age: "Your age"
            case .drink: "Your usual drink"
            case .bedtime: "Your bedtime"
            case .health: "Health"
            case .aboutYou: "About you"
            case .countdown: "Countdown"
            }
        }
    }

    @State private var step: Step = .age
    @State private var ageText = ""
    @State private var drinkName = ""
    @State private var drinkMgText = ""
    @State private var servingMLText = ""
    @State private var bedtime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now
    @State private var healthFlags: Set<HealthFlag> = []
    @State private var customConditions: [String] = []
    @State private var bodyFactors = BodyFactors()
    @State private var thresholdMg: Double = 50
    @State private var wantsNotifications = true

    var body: some View {
        NavigationStack {
            Form { content }
                .keyboardDoneButton()
                .navigationTitle(step.title)
                .toolbar {
                    if step != .age {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .age }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button(action: advance) {
                        Text(step == .countdown ? "Start tracking" : "Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canContinue)
                    .padding()
                    .background(.bar)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .age:
            Section {
                TextField("Age", text: $ageText)
                    .keyboardType(.numberPad)
            } footer: {
                Text("Full access is limited to adults 18 and over.")
            }

        case .drink:
            Section {
                TextField("Drink name (e.g. Monster Energy)", text: $drinkName)
                LabeledContent("Caffeine per serving") {
                    TextField("mg", text: $drinkMgText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Serving size (optional)") {
                    TextField("mL", text: $servingMLText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("Check the can or bottle for the caffeine amount. You can add more drinks later, or scan a label.")
            }

        case .bedtime:
            Section {
                DatePicker("Typical bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
            } footer: {
                Text("The app shows how much caffeine it estimates will still be in your system at this time.")
            }

        case .health:
            Section {
                HealthConditionsRow(flags: $healthFlags, custom: $customConditions)
            } header: {
                Text("Do you have any health conditions? (Optional)")
            } footer: {
                Text("For example high blood pressure, a heart condition, migraines or anxiety. \(AppText.onDeviceStorage)")
            }
            if !healthFlags.isEmpty || !customConditions.isEmpty {
                Section {
                    Callout(systemImage: "stethoscope", text: AppText.healthFlagAdvice, color: .blue)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

        case .aboutYou:
            Section {
                Text("These help estimate how long caffeine stays in your body (its half-life). All are optional.")
                    .font(.subheadline)
            }
            BodyFactorsFields(factors: $bodyFactors)

        case .countdown:
            Section {
                Stepper(value: $thresholdMg, in: 10...200, step: 10) {
                    LabeledContent("Notify me below", value: thresholdMg.mgText)
                }
                Toggle("Send a notification", isOn: $wantsNotifications)
            } footer: {
                Text("The app counts down to when your estimated caffeine falls below this amount.")
            }
        }
    }

    private var age: Int? { Int(ageText.trimmingCharacters(in: .whitespaces)) }
    private var drinkMg: Double? { Double(drinkMgText.replacingOccurrences(of: ",", with: ".")) }
    private var servingML: Double? { Double(servingMLText.replacingOccurrences(of: ",", with: ".")) }

    private var canContinue: Bool {
        switch step {
        case .age: (1...120).contains(age ?? 0)
        case .drink: !drinkName.trimmingCharacters(in: .whitespaces).isEmpty && (drinkMg ?? 0) > 0
        case .bedtime, .health, .aboutYou, .countdown: true
        }
    }

    private var bedtimeMinutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        return (parts.hour ?? 23) * 60 + (parts.minute ?? 0)
    }

    private func advance() {
        if step == .age, let age, age < UserProfile.minimumAge {
            // Store only the age so the app stays restricted; nothing else is collected.
            store.profile = UserProfile(age: age, usualDrinkName: "", usualDrinkMg: 0, bedtimeMinutes: 23 * 60, healthFlags: [])
            return
        }
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        } else {
            finish()
        }
    }

    private func finish() {
        guard let age, let drinkMg else { return }
        let name = drinkName.trimmingCharacters(in: .whitespaces)
        context.insert(SavedDrink(name: name, mgPerServing: drinkMg, servingML: servingML))
        try? context.save()

        var profile = UserProfile(
            age: age,
            usualDrinkName: name,
            usualDrinkMg: drinkMg,
            usualDrinkServingML: servingML,
            bedtimeMinutes: bedtimeMinutes,
            healthFlags: healthFlags,
            customConditions: customConditions,
            bodyFactors: bodyFactors,
            thresholdMg: thresholdMg
        )
        profile.reevaluateHalfLife()
        store.profile = profile
        if wantsNotifications {
            Task {
                let granted = await CaffeineNotifier.requestAuthorization()
                store.profile?.notificationsEnabled = granted
            }
        }
    }
}

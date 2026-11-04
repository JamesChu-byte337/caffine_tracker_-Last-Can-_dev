import SwiftData
import SwiftUI

/// Pick a drink, see how it would change the estimate, then log it or cancel. Nothing is saved until "Log drink".
struct DrinkComposerView: View {
    let mode: ComposerMode
    let profile: UserProfile
    let drinks: [DrinkEntry]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedDrink.createdAt) private var savedDrinks: [SavedDrink]

    @State private var source: DrinkSource = .saved
    @State private var selectedSavedID: PersistentIdentifier?
    @State private var customName = ""
    @State private var customMgText = ""
    @State private var customServingML: Double?
    @State private var saveCustomDrink = false
    @State private var quantity: Double = 1
    @State private var usesCustomTime = false
    @State private var customTime = Date.now
    @State private var showScanner = false
    @State private var showChart = true
    @State private var confirmOverGuideline = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                form(now: timeline.date)
            }
            .keyboardDoneButton()
            .navigationTitle(mode == .preview ? "Preview a drink" : "Log a drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                LabelScanView { name, mg, servingML in
                    customName = name
                    customMgText = mg.quantityText
                    customServingML = servingML
                    saveCustomDrink = true
                }
            }
            .onAppear(perform: setInitialSelection)
        }
    }

    // MARK: Form

    private func form(now: Date) -> some View {
        let projection = candidate.map { Projection(drink: $0, quantity: quantity, time: drinkTime(now: now), now: now, drinks: drinks, profile: profile) }

        return Form {
            Section {
                Picker("Source", selection: $source) {
                    ForEach(DrinkSource.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            sourceSection

            Section {
                Stepper(value: $quantity, in: 0.5...10, step: 0.5) {
                    LabeledContent("Quantity", value: quantity == 1 ? "1 serving" : "\(quantity.quantityText) servings")
                }
                Toggle("Different time", isOn: $usesCustomTime.animation())
                if usesCustomTime {
                    DatePicker("Drink time", selection: $customTime, in: now.addingTimeInterval(-24 * 3600)...now.addingTimeInterval(18 * 3600), displayedComponents: [.date, .hourAndMinute])
                } else {
                    LabeledContent("Drink time", value: "Now")
                }
            }

            if let projection {
                projectionSection(projection)
            } else {
                Section {
                    Text("Choose or enter a drink to see how it would change your estimate.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    if projection?.isOverGuideline == true {
                        confirmOverGuideline = true
                    } else {
                        log(now: now)
                    }
                } label: {
                    Text("Log drink").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(projection == nil)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Button("Cancel", role: .cancel) { dismiss() }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            .alert("Above the daily guideline", isPresented: $confirmOverGuideline) {
                Button("Log anyway") { log(now: now) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Logging this would bring your estimated 24-hour total to \(projection?.totalAfter.mgText ?? ""), above Health Canada's 400 mg daily maximum for adults.")
            }
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        switch source {
        case .saved:
            Section {
                if savedDrinks.isEmpty {
                    Text("You don't have any saved drinks yet. Scan a label or enter the amount.")
                        .foregroundStyle(.secondary)
                }
                ForEach(savedDrinks) { drink in
                    Button {
                        selectedSavedID = drink.persistentModelID
                    } label: {
                        HStack {
                            Text(drink.name)
                            Spacer()
                            Text(drink.mgPerServing.mgText).foregroundStyle(.secondary)
                            Image(systemName: selectedSavedID == drink.persistentModelID ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedSavedID == drink.persistentModelID ? Theme.accent : Color.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("My drinks")
            }

        case .scan:
            Section {
                Button {
                    showScanner = true
                } label: {
                    Label(customMgText.isEmpty ? "Scan a drink label" : "Scan again", systemImage: "text.viewfinder")
                }
                if !customMgText.isEmpty {
                    customFields
                }
            } footer: {
                Text("Check the detected amount against the label before logging.")
            }

        case .manual:
            Section {
                customFields
            }
        }
    }

    @ViewBuilder
    private var customFields: some View {
        TextField("Drink name (optional)", text: $customName)
        LabeledContent("Caffeine per serving") {
            TextField("mg", text: $customMgText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        Toggle("Save to My drinks", isOn: $saveCustomDrink)
    }

    private func projectionSection(_ projection: Projection) -> some View {
        Section {
            Text(projection.sentence)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("24-hour total", value: "\(projection.totalBefore.mgText) → \(projection.totalAfter.mgText)")
                .monospacedDigit()

            switch CaffeineModel.guidelineLevel(for: projection.totalAfter) {
            case .above:
                Callout(systemImage: "exclamationmark.octagon.fill", text: "This would put your 24-hour total above Health Canada's 400 mg daily maximum for adults.", color: .red)
            case .approaching:
                Callout(systemImage: "exclamationmark.triangle.fill", text: "This would bring you close to Health Canada's 400 mg daily maximum for adults.", color: .orange)
            case .below:
                EmptyView()
            }

            DisclosureGroup("Projected curve", isExpanded: $showChart) {
                CaffeineCurveChart(
                    doses: projection.doses,
                    previewDose: projection.dose,
                    halfLifeHours: profile.halfLifeHours,
                    now: projection.now,
                    bedtime: projection.bedtime,
                    thresholdMg: profile.thresholdMg
                )
                .frame(height: 200)
                .padding(.vertical, 4)
            }
        } header: {
            Text("What if")
        } footer: {
            Text("Estimates only. Caffeine affects people differently.")
        }
    }

    // MARK: State

    private var candidate: (name: String, mgPerServing: Double)? {
        switch source {
        case .saved:
            guard let drink = savedDrinks.first(where: { $0.persistentModelID == selectedSavedID }) else { return nil }
            return (drink.name, drink.mgPerServing)
        case .scan, .manual:
            guard let mg = Double(customMgText.replacingOccurrences(of: ",", with: ".")), mg > 0 else { return nil }
            let name = customName.trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? "Custom drink" : name, mg)
        }
    }

    private func drinkTime(now: Date) -> Date {
        usesCustomTime ? customTime : now
    }

    private func setInitialSelection() {
        guard selectedSavedID == nil else { return }
        let usual = savedDrinks.first { $0.name == profile.usualDrinkName } ?? savedDrinks.first
        if let usual {
            selectedSavedID = usual.persistentModelID
        } else {
            source = .manual
        }
        showChart = mode == .preview
    }

    private func log(now: Date) {
        guard let candidate else { return }
        context.insert(DrinkEntry(timestamp: drinkTime(now: now), name: candidate.name, mgPerServing: candidate.mgPerServing, quantity: quantity, source: source))
        if source != .saved, saveCustomDrink {
            context.insert(SavedDrink(name: candidate.name, mgPerServing: candidate.mgPerServing, servingML: customServingML))
        }
        try? context.save()
        dismiss()
    }
}

/// How one extra drink would change the estimate. Information only: it never says whether a drink is OK.
struct Projection {
    let dose: CaffeineDose
    let doses: [CaffeineDose]
    let now: Date
    let bedtime: Date
    let bedtimeBefore: Double
    let bedtimeAfter: Double
    let totalBefore: Double
    let totalAfter: Double

    init(drink: (name: String, mgPerServing: Double), quantity: Double, time: Date, now: Date, drinks: [DrinkEntry], profile: UserProfile) {
        let cutoff = min(now, time).addingTimeInterval(-CaffeineModel.relevantWindow)
        doses = drinks.filter { $0.timestamp > cutoff }.map(\.dose)
        dose = CaffeineDose(time: time, mg: drink.mgPerServing * quantity)
        self.now = now
        // Look at the first bedtime after both now and the drink.
        let reference = max(now, time)
        bedtime = CaffeineModel.nextBedtime(after: reference, bedtimeMinutes: profile.bedtimeMinutes)
        bedtimeBefore = CaffeineModel.remaining(at: bedtime, doses: doses, halfLifeHours: profile.halfLifeHours)
        bedtimeAfter = CaffeineModel.remaining(at: bedtime, doses: doses + [dose], halfLifeHours: profile.halfLifeHours)
        totalBefore = CaffeineModel.rolling24hTotal(endingAt: reference, doses: doses)
        totalAfter = CaffeineModel.rolling24hTotal(endingAt: reference, doses: doses + [dose])
    }

    var isOverGuideline: Bool { totalAfter > CaffeineModel.dailyGuidelineMg }

    var sentence: String {
        let when = abs(dose.time.timeIntervalSince(now)) < 60 ? "now" : "at \(dose.time.shortTime)"
        var bedtimeText = bedtime.shortTime
        if !Calendar.current.isDate(bedtime, inSameDayAs: now), Calendar.current.component(.hour, from: bedtime) >= 12 {
            bedtimeText = "tomorrow's bedtime (\(bedtime.shortTime))"
        }
        return "If you drink this \(when), you'll have an estimated \(bedtimeAfter.mgText) in your system at \(bedtimeText), up from \(bedtimeBefore.mgText)."
    }
}

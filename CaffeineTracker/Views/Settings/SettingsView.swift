import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var showReevaluate = false
    @State private var showHealthConsent = false
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                if store.profile != nil {
                    profileSection
                    healthSection
                    estimateSection
                    appleHealthSection
                    countdownSection
                }
                displaySection
                aboutSection
                Section {
                    Button("Delete all data", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Removes your drink log, saved drinks and profile from this device.")
                }
                #if DEBUG
                Section("Developer") {
                    Button("Add 30 days of sample drinks") { SampleData.insert(into: context) }
                    Button("Send test notification in 5 seconds") {
                        Task { await CaffeineNotifier.sendTest(thresholdMg: store.profile?.thresholdMg ?? 50) }
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(isPresented: $showReevaluate) {
                if let profile = store.profile { ReevaluateHalfLifeView(profile: profile) }
            }
            .sheet(isPresented: $showHealthConsent) { HealthConsentView() }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { store.signOut() }
            } message: {
                Text("Your drinks and profile stay on this device.")
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive, action: deleteAll)
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section("Your profile") {
            if let email = store.accountEmail {
                LabeledContent("Signed in as", value: email)
            }
            LabeledContent("Age", value: "\(store.profile?.age ?? 0)")
            DatePicker("Typical bedtime", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
            NavigationLink("My drinks") { SavedDrinksView() }
            Button("Sign out") { confirmSignOut = true }
        }
    }

    private var healthSection: some View {
        Section {
            HealthConditionsRow(
                flags: Binding(get: { store.profile?.healthFlags ?? [] }, set: { store.profile?.healthFlags = $0 }),
                custom: Binding(get: { store.profile?.customConditions ?? [] }, set: { store.profile?.customConditions = $0 })
            )
        } header: {
            Text("Health")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if store.profile?.hasHealthFlags == true {
                    Text(AppText.healthFlagAdvice)
                }
                Text(AppText.onDeviceStorage)
            }
        }
    }

    private var estimateSection: some View {
        Section {
            LabeledContent("Your caffeine half-life", value: String(format: "%g h", store.profile?.halfLifeHours ?? CaffeineModel.defaultHalfLifeHours))
            if let evaluated = store.profile?.halfLifeEvaluatedAt {
                LabeledContent("Last evaluated", value: evaluated.formatted(date: .abbreviated, time: .omitted))
            }
            Button("Re-evaluate") { showReevaluate = true }
        } header: {
            Text("Estimate")
        } footer: {
            Text("Half-life is how long it takes for about half of the caffeine to leave your body. It's estimated for you from your age, health conditions and the factors you've entered, using published research. All amounts in this app are estimates.")
        }
    }

    private var appleHealthSection: some View {
        Section {
            if store.healthSharingEnabled {
                Toggle("Use Apple Health data", isOn: Binding(
                    get: { store.healthSharingEnabled },
                    set: { isOn in
                        if !isOn {
                            store.healthSharingEnabled = false
                            health.clear()
                        }
                    }
                ))
            } else {
                Button("Connect Apple Health") { showHealthConsent = true }
                    .disabled(!HealthDataStore.isAvailable)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text(store.healthSharingEnabled
                 ? "Heart rate, sleep, height and weight are read and analyzed on this iPhone only. To fully remove access, open the Health app → Sharing → Apps → Last Can."
                 : "Optional. With an Apple Watch or similar device, the app can look for patterns between your caffeine, heart rate and sleep. Data never leaves this iPhone.")
        }
    }

    private var countdownSection: some View {
        Section {
            Stepper(value: profile(\.thresholdMg), in: 10...200, step: 10) {
                LabeledContent("Countdown threshold", value: profile(\.thresholdMg).wrappedValue.mgText)
            }
            Toggle("Notify me when the countdown ends", isOn: Binding(
                get: { store.profile?.notificationsEnabled ?? false },
                set: { isOn in
                    guard isOn else {
                        store.profile?.notificationsEnabled = false
                        return
                    }
                    Task {
                        let granted = await CaffeineNotifier.requestAuthorization()
                        store.profile?.notificationsEnabled = granted
                        notificationsDenied = !granted
                    }
                }
            ))
        } header: {
            Text("Countdown")
        } footer: {
            if notificationsDenied {
                Text("Notifications are turned off for this app. You can allow them in the iPhone Settings app.")
            } else {
                Text("You'll get: \u{201C}Caffeine countdown ended. \(CaffeineNotifier.message(thresholdMg: profile(\.thresholdMg).wrappedValue))\u{201D}")
            }
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            NavigationLink("Disclaimer") { DisclaimerView(acceptedAt: store.disclaimerAcceptedAt) }
            LabeledContent("Daily guideline", value: "400 mg")
            Text(AppText.guidelineNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func profile(_ keyPath: WritableKeyPath<UserProfile, Double>) -> Binding<Double> {
        Binding(
            get: { store.profile?[keyPath: keyPath] ?? 0 },
            set: { store.profile?[keyPath: keyPath] = $0 }
        )
    }

    private var bedtimeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = store.profile?.bedtimeMinutes ?? 23 * 60
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.profile?.bedtimeMinutes = (parts.hour ?? 23) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func deleteAll() {
        try? context.delete(model: DrinkEntry.self)
        try? context.delete(model: SavedDrink.self)
        try? context.save()
        CaffeineNotifier.cancel()
        health.clear()
        store.reset()
    }
}

struct SavedDrinksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedDrink.createdAt) private var savedDrinks: [SavedDrink]
    @State private var editing: SavedDrink?
    @State private var addingNew = false

    var body: some View {
        List {
            ForEach(savedDrinks) { drink in
                Button { editing = drink } label: {
                    LabeledContent(drink.name, value: drink.mgPerServing.mgText)
                }
                .foregroundStyle(.primary)
            }
            .onDelete { offsets in
                offsets.map { savedDrinks[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .overlay {
            if savedDrinks.isEmpty {
                ContentUnavailableView("No saved drinks", systemImage: "cup.and.saucer", description: Text("Add drinks you have often so you can pick them quickly."))
            }
        }
        .navigationTitle("My drinks")
        .toolbar {
            Button("Add", systemImage: "plus") { addingNew = true }
        }
        .sheet(item: $editing) { drink in
            SavedDrinkForm(drink: drink)
        }
        .sheet(isPresented: $addingNew) {
            SavedDrinkForm(drink: nil)
        }
    }
}

struct SavedDrinkForm: View {
    let drink: SavedDrink?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mgText = ""
    @State private var servingText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                LabeledContent("Caffeine per serving") {
                    TextField("mg", text: $mgText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Serving size") {
                    TextField("mL (optional)", text: $servingText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .keyboardDoneButton()
            .navigationTitle(drink == nil ? "New drink" : "Edit drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.isEmpty || (mg ?? 0) <= 0)
                }
            }
            .onAppear {
                guard let drink else { return }
                name = drink.name
                mgText = drink.mgPerServing.quantityText
                servingText = drink.servingML.map(\.quantityText) ?? ""
            }
        }
    }

    private var mg: Double? { Double(mgText.replacingOccurrences(of: ",", with: ".")) }

    private func save() {
        guard let mg else { return }
        let serving = Double(servingText.replacingOccurrences(of: ",", with: "."))
        if let drink {
            drink.name = name
            drink.mgPerServing = mg
            drink.servingML = serving
        } else {
            context.insert(SavedDrink(name: name, mgPerServing: mg, servingML: serving))
        }
        try? context.save()
        dismiss()
    }
}

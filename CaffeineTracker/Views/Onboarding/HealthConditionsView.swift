import SwiftUI

/// One row that opens the full list of conditions, used in onboarding and Settings.
struct HealthConditionsRow: View {
    @Binding var flags: Set<HealthFlag>
    @Binding var custom: [String]

    var body: some View {
        NavigationLink {
            HealthConditionsView(flags: $flags, custom: $custom)
        } label: {
            LabeledContent("Health conditions", value: summary)
        }
    }

    private var summary: String {
        let count = flags.count + custom.count
        return count == 0 ? "None" : "\(count) selected"
    }
}

struct HealthConditionsView: View {
    @Binding var flags: Set<HealthFlag>
    @Binding var custom: [String]
    @State private var newCondition = ""

    var body: some View {
        Form {
            if !flags.isEmpty || !custom.isEmpty {
                Section {
                    Callout(systemImage: "stethoscope", text: AppText.healthFlagAdvice, color: .blue)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(HealthFlag.allCases) { flag in
                    Button {
                        if flags.contains(flag) { flags.remove(flag) } else { flags.insert(flag) }
                    } label: {
                        HStack {
                            Text(flag.label)
                            Spacer()
                            if flags.contains(flag) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                Text("Select any that apply")
            }

            Section {
                ForEach(custom, id: \.self) { condition in
                    Label(condition, systemImage: "tag")
                }
                .onDelete { custom.remove(atOffsets: $0) }
                HStack {
                    TextField("Add another condition", text: $newCondition)
                        .onSubmit(addCustom)
                    Button("Add", action: addCustom)
                        .disabled(newCondition.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Something else?")
            } footer: {
                Text(AppText.onDeviceStorage)
            }
        }
        .navigationTitle("Health conditions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addCustom() {
        let trimmed = newCondition.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !custom.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        custom.append(trimmed)
        newCondition = ""
    }
}

/// Inputs for the half-life estimate. Shared by onboarding and Re-evaluate.
struct BodyFactorsFields: View {
    @Binding var factors: BodyFactors

    var body: some View {
        Section {
            LabeledContent("Weight") {
                TextField("kg", value: $factors.weightKg, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Height") {
                TextField("cm", value: $factors.heightCm, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Body (optional)")
        } footer: {
            Text("Weight and height have only a small effect on half-life.")
        }

        Section {
            Toggle("I take a medication that slows caffeine breakdown", isOn: $factors.slowingMedication)
        } header: {
            Text("Things that change caffeine half-life")
        } footer: {
            Text("Examples of such medications: fluvoxamine, ciprofloxacin, some antidepressants. Ask a pharmacist if you're not sure.\n\n\(AppText.onDeviceStorage)")
        }
    }
}

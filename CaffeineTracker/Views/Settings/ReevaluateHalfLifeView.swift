import SwiftUI

/// Update the factors, run the estimate again (with a short progress screen), then confirm the result.
struct ReevaluateHalfLifeView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case editing, evaluating, result }

    @State private var draft: UserProfile
    @State private var phase: Phase = .editing
    @State private var completedSteps = 0
    @State private var result: HalfLifeEstimator.Estimate?

    init(profile: UserProfile) {
        _draft = State(initialValue: profile)
    }

    private var steps: [String] {
        var steps = ["Reading your profile"]
        if store.healthSharingEnabled { steps.append("Checking Apple Health for height and weight") }
        steps += ["Applying research-based factors", "Calculating your half-life"]
        return steps
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .editing: editor
                case .evaluating: progress
                case .result: resultView
                }
            }
            .navigationTitle("Re-evaluate half-life")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(phase == .evaluating)
    }

    private var editor: some View {
        Form {
            Section {
                LabeledContent("Current estimate", value: hoursText(draft.halfLifeHours))
                LabeledContent("Age", value: "\(draft.age)")
                HealthConditionsRow(flags: $draft.healthFlags, custom: $draft.customConditions)
            }
            BodyFactorsFields(factors: $draft.bodyFactors)
            Section {
                Button {
                    Task { await evaluate() }
                } label: {
                    Text("Re-evaluate").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .keyboardDoneButton()
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    Group {
                        if index < completedSteps {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if index == completedSteps {
                            ProgressView()
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 24)
                    Text(step).foregroundStyle(index <= completedSteps ? .primary : .secondary)
                }
            }
            Spacer()
        }
        .padding(32)
    }

    private var resultView: some View {
        Form {
            if let result {
                Section {
                    VStack(spacing: 6) {
                        Text("Your estimated half-life").font(.subheadline).foregroundStyle(.secondary)
                        Text(hoursText(result.hours)).font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("About half of a drink's caffeine is estimated to leave your body in this time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("What it's based on") {
                    LabeledContent("Average for healthy adults", value: hoursText(HalfLifeEstimator.baseHours))
                    if result.adjustments.isEmpty {
                        Text("None of the known factors apply, so the average is used.").foregroundStyle(.secondary)
                    }
                    ForEach(result.adjustments) { adjustment in
                        LabeledContent(adjustment.label, value: adjustment.effectText)
                    }
                }
                Section {
                    Button {
                        draft.halfLifeHours = result.hours
                        draft.halfLifeEvaluatedAt = .now
                        store.profile = draft
                        dismiss()
                    } label: {
                        Text("Use this estimate").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Genetics also affect half-life but can't be estimated here. This is an estimate, not a medical measurement.")
                }
            }
        }
    }

    private func evaluate() async {
        withAnimation { phase = .evaluating }
        completedSteps = 0
        if store.healthSharingEnabled {
            await health.refresh()
            if let weight = health.snapshot?.latestWeightKg { draft.bodyFactors.weightKg = (weight * 10).rounded() / 10 }
            if let height = health.snapshot?.latestHeightCm { draft.bodyFactors.heightCm = height.rounded() }
        }
        // The calculation is instant; the short pause per step lets people see what was considered.
        for index in steps.indices {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation { completedSteps = index + 1 }
        }
        result = HalfLifeEstimator.estimate(for: draft)
        withAnimation { phase = .result }
    }

    private func hoursText(_ hours: Double) -> String {
        String(format: "%g h", hours)
    }
}

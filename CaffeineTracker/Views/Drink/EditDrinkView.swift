import SwiftData
import SwiftUI

/// Edit or delete a logged drink. Changes apply only when saved.
struct EditDrinkView: View {
    let entry: DrinkEntry
    /// Every other logged drink, for the guideline check.
    let otherDoses: [CaffeineDose]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var mgText = ""
    @State private var quantity: Double = 1
    @State private var timestamp = Date.now
    @State private var confirmDelete = false
    @State private var confirmOverGuideline = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    LabeledContent("Caffeine per serving") {
                        TextField("mg", text: $mgText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Stepper(value: $quantity, in: 0.5...10, step: 0.5) {
                        LabeledContent("Quantity", value: quantity.quantityText)
                    }
                    DatePicker("Time", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text("Total: \(((mg ?? 0) * quantity).mgText)")
                }

                Section {
                    Button("Delete drink", role: .destructive) { confirmDelete = true }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Edit drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: attemptSave).disabled((mg ?? 0) <= 0)
                }
            }
            .confirmationDialog("Delete this drink?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                }
            }
            .alert("Above the daily guideline", isPresented: $confirmOverGuideline) {
                Button("Save anyway", action: save)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("With this change, your estimated 24-hour total would be \(editedTotal.mgText), above Health Canada's 400 mg daily maximum for adults.")
            }
            .onAppear {
                name = entry.name
                mgText = entry.mgPerServing.quantityText
                quantity = entry.quantity
                timestamp = entry.timestamp
            }
        }
    }

    private var mg: Double? { Double(mgText.replacingOccurrences(of: ",", with: ".")) }

    /// Rolling 24-hour total at the later of now and the drink's time, with the edits applied.
    private var editedTotal: Double {
        let reference = max(.now, timestamp)
        return CaffeineModel.rolling24hTotal(endingAt: reference, doses: otherDoses + [CaffeineDose(time: timestamp, mg: (mg ?? 0) * quantity)])
    }

    private func attemptSave() {
        let originalTotal = CaffeineModel.rolling24hTotal(endingAt: max(.now, entry.timestamp), doses: otherDoses + [entry.dose])
        if editedTotal > CaffeineModel.dailyGuidelineMg, editedTotal > originalTotal {
            confirmOverGuideline = true
        } else {
            save()
        }
    }

    private func save() {
        guard let mg else { return }
        entry.name = name.isEmpty ? entry.name : name
        entry.mgPerServing = mg
        entry.quantity = quantity
        entry.timestamp = timestamp
        try? context.save()
        dismiss()
    }
}

import PhotosUI
import SwiftUI

/// Reads caffeine and serving size from a label photo, then asks the user to confirm them.
struct LabelScanView: View {
    /// Called with the confirmed name, caffeine per serving (mg) and serving size (mL).
    var onConfirm: (String, Double, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var image: UIImage?
    @State private var isReading = false
    @State private var result: LabelScanResult?
    @State private var errorMessage: String?
    @State private var name = ""
    @State private var mgText = ""
    @State private var servingText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            Label("Take a photo of the label", systemImage: "camera")
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo")
                    }
                } footer: {
                    Text("Text is read on your device. Photos aren't saved.")
                }

                if let image {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .frame(maxWidth: .infinity)
                    }
                }

                if isReading {
                    Section { ProgressView("Reading label…") }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                if let result {
                    confirmSection(result)
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Scan label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        guard let mg else { return }
                        onConfirm(name.trimmingCharacters(in: .whitespaces), mg, serving)
                        dismiss()
                    }
                    .disabled(result == nil || (mg ?? 0) <= 0)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in Task { await read(image) } }
                    .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        await read(picked)
                    } else {
                        errorMessage = "Couldn't open that photo."
                    }
                }
            }
        }
    }

    private func confirmSection(_ result: LabelScanResult) -> some View {
        Section {
            TextField("Drink name", text: $name)
            LabeledContent("Caffeine per serving") {
                TextField("mg", text: $mgText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Serving size") {
                TextField("mL", text: $servingText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Confirm the details")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let matched = result.matchedText {
                    Text("Found on label: \u{201C}\(matched)\u{201D}")
                }
                if let per100 = result.per100mLMg {
                    Text("The label lists \(per100.mgText) per 100 mL. Caffeine per serving is calculated from the serving size; check it matches what you'll drink.")
                }
                if result.caffeineMg == nil && result.per100mLMg == nil {
                    Text("Couldn't find a caffeine amount. Enter it from the label.")
                }
            }
        }
    }

    private var mg: Double? { Double(mgText.replacingOccurrences(of: ",", with: ".")) }
    private var serving: Double? { Double(servingText.replacingOccurrences(of: ",", with: ".")) }

    @MainActor
    private func read(_ picked: UIImage) async {
        image = picked
        isReading = true
        errorMessage = nil
        defer { isReading = false }
        do {
            let lines = try await TextRecognizer.recognizeLines(in: picked)
            let parsed = LabelParser.parse(lines: lines)
            result = parsed
            mgText = parsed.caffeineMg?.quantityText ?? ""
            servingText = parsed.servingML?.quantityText ?? ""
            if name.isEmpty { name = lines.first(where: { $0.count > 2 && $0.rangeOfCharacter(from: .decimalDigits) == nil }) ?? "" }
        } catch {
            errorMessage = "Couldn't read text from that photo. Try again or enter the amount manually."
        }
    }
}

/// System camera for taking a single label photo.
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

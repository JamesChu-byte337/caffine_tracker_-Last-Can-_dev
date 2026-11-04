import SwiftUI

/// The user's choice in Settings; "System" follows the iPhone's own light/dark setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "appearanceMode"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.80, green: 0.42, blue: 0.16)
    static let preview = Color.indigo
    static let bedtime = Color.purple
}

extension Double {
    /// Rounded milligrams, e.g. "142 mg".
    var mgText: String { "\(Int(rounded())) mg" }

    /// Servings, e.g. "1", "1.5".
    var quantityText: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

extension TimeInterval {
    /// e.g. "3 h 12 min", "45 min", "under 1 min".
    var durationText: String {
        let totalMinutes = Int((self / 60).rounded(.up))
        guard totalMinutes > 0 else { return "under 1 min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }
}

/// A rounded card used for the main-screen sections.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A coloured note with an icon, used for guideline and health messages.
struct Callout: View {
    let systemImage: String
    let text: String
    var color: Color = .secondary

    var body: some View {
        Label {
            Text(text).font(.footnote).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    /// Adds a "Done" button above number pads, which have no return key, and lets scrolling dismiss the keyboard.
    func keyboardDoneButton() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
    }
}

import SwiftUI

/// Shown before first use (with `onAccept`) and from Settings (without it).
struct DisclaimerView: View {
    var acceptedAt: Date? = nil
    var onAccept: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                Text(onAccept == nil ? "Disclaimer" : "Before you start")
                    .font(.largeTitle.bold())
                Text(AppText.disclaimer)
                    .font(.body)
                if let acceptedAt {
                    Text("Accepted \(acceptedAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if let onAccept {
                Button(action: onAccept) {
                    Text("I understand and accept").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AgeRestrictedView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("This app is for adults 18 and over")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Caffeine guidance for people under 18 is different from the adult guidance this app is built around. If you have questions about caffeine, talk to a parent, guardian or healthcare professional.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("I entered my age incorrectly") { store.profile = nil }
                .padding(.bottom)
        }
        .padding(24)
    }
}

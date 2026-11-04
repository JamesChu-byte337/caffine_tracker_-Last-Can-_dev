import SwiftUI

/// Today's health check. Stays a small "nothing unusual" line until the analysis finds something,
/// then expands to the top of the screen.
struct HealthCheckCard: View {
    let findings: [HealthFinding]
    let hasData: Bool
    let status: HealthDataStore.Status
    let lastUpdated: Date?

    var body: some View {
        if findings.isEmpty {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: status == .loading ? "arrow.triangle.2.circlepath" : (hasData ? "checkmark.seal.fill" : "applewatch.slash"))
                        .font(.title2)
                        .foregroundStyle(hasData ? .green : .secondary)
                        .symbolEffect(.rotate, isActive: status == .loading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Health check").font(.headline)
                        Text(summary).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            let top = findings.map(\.level).max() ?? .notice
            let color = color(for: top)
            Card {
                Label("Health check", systemImage: top == .talkToDoctor ? "heart.text.square.fill" : "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(color)
                ForEach(findings) { finding in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.title).font(.subheadline.bold())
                        Text(finding.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.color(for: finding.level).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                Text(AppText.urgentCare).font(.caption).foregroundStyle(.secondary)
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.5), lineWidth: 1.5))
        }
    }

    private var summary: String {
        switch status {
        case .loading: return "Checking your Apple Health data…"
        case .failed: return "Couldn't read Apple Health data. It'll try again next time you open the app."
        case .idle, .loaded:
            guard hasData else {
                return "No heart rate or sleep data found in Apple Health. Insights need an Apple Watch or another device that records them."
            }
            let checked = lastUpdated.map { " Last checked \($0.shortTime)." } ?? ""
            return "Nothing unusual noticed in your heart rate or sleep.\(checked)"
        }
    }

    private func color(for level: HealthFinding.Level) -> Color {
        switch level {
        case .notice: .blue
        case .attention: .orange
        case .talkToDoctor: .red
        }
    }
}

/// Invitation shown on Today until the user connects Apple Health or says not now.
struct HealthInviteCard: View {
    var onConnect: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .top) {
                Label("Connect Apple Health", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.pink)
                Spacer()
                Button("Not now", action: onDismiss).font(.subheadline)
            }
            Text("If you wear an Apple Watch, the app can look for patterns between your caffeine, heart rate and sleep. Analysis happens on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Learn more and connect", action: onConnect)
                .buttonStyle(.bordered)
        }
    }
}

/// Explains exactly what's read before Apple's own permission sheet appears.
struct HealthConsentView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "heart.text.square.fill").font(.system(size: 48)).foregroundStyle(.pink)
                    Text("Connect Apple Health").font(.title.bold())
                    Text("With your permission, Last Can reads:")
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Heart rate and resting heart rate", systemImage: "heart")
                        Label("Apple Watch high heart rate and irregular rhythm notifications", systemImage: "applewatch")
                        Label("Sleep", systemImage: "bed.double")
                        Label("Height and weight (for your half-life estimate)", systemImage: "figure")
                    }
                    .font(.subheadline)
                    Callout(systemImage: "lock.fill", text: "Your Health data is analyzed on this iPhone only. It's never sent to our servers or anyone else, and the app never writes to Apple Health.", color: .green)
                    Text("You need a device that records heart rate or sleep, such as an Apple Watch. You can turn this off at any time in Settings, and remove access in the Health app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(AppText.urgentCare).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        isRequesting = true
                        if await health.requestAccess() {
                            store.healthSharingEnabled = true
                            await health.refresh()
                        }
                        isRequesting = false
                        dismiss()
                    }
                } label: {
                    Text("Continue to Apple Health").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)
                .padding()
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
    }
}

struct GreetingCard: View {
    let message: DailyGreeting.Message
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("Goose")
                .resizable()
                .scaledToFit()
                .frame(width: 72)
                .accessibilityHidden(true)
            Text(message.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .background((message.trend == .down ? Color.green : Theme.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Changelog.entries) { entry in
                Section {
                    ForEach(entry.changes, id: \.self) { change in
                        Text(change).font(.subheadline)
                    }
                } header: {
                    HStack {
                        Text("Version \(entry.version)")
                        Spacer()
                        Text(entry.date)
                    }
                }
            }
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

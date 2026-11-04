import SwiftData
import SwiftUI

enum ComposerMode: String, Identifiable {
    case preview, log
    var id: String { rawValue }
}

struct HomeView: View {
    let profile: UserProfile
    let drinks: [DrinkEntry]
    @Environment(ProfileStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var composerMode: ComposerMode?
    @State private var editing: DrinkEntry?
    @State private var showChangelog = false
    @State private var showHealthConsent = false
    @State private var greeting: DailyGreeting.Message?
    @AppStorage("healthInviteDismissed") private var healthInviteDismissed = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                content(now: timeline.date)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            // Puts the large title in the navigation bar row instead of a separate row below it.
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showChangelog = true } label: {
                        Text("v\(Changelog.currentVersion)")
                            .font(.caption.monospaced().weight(.medium))
                    }
                    .accessibilityLabel("Version \(Changelog.currentVersion), what's new")
                }
            }
            .sheet(isPresented: $showChangelog) { ChangelogView() }
            .sheet(isPresented: $showHealthConsent) { HealthConsentView() }
            .task { await onOpen() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await onOpen() } }
            }
            .sheet(item: $composerMode) { mode in
                DrinkComposerView(mode: mode, profile: profile, drinks: drinks)
            }
            .sheet(item: $editing) { entry in
                EditDrinkView(entry: entry, otherDoses: drinks.filter { $0 !== entry }.map(\.dose))
            }
        }
    }

    private func content(now: Date) -> some View {
        let cutoff = now.addingTimeInterval(-CaffeineModel.relevantWindow)
        let doses = drinks.filter { $0.timestamp > cutoff }.map(\.dose)
        let bedtime = CaffeineModel.nextBedtime(after: now, bedtimeMinutes: profile.bedtimeMinutes)
        let current = CaffeineModel.remaining(at: now, doses: doses, halfLifeHours: profile.halfLifeHours)
        let atBedtime = CaffeineModel.remaining(at: bedtime, doses: doses, halfLifeHours: profile.halfLifeHours)
        let total24h = CaffeineModel.rolling24hTotal(endingAt: now, doses: doses)
        let recentDrinks = drinks.filter { $0.timestamp > now.addingTimeInterval(-24 * 3600) }.reversed()
        let findings = health.snapshot.map {
            HealthAnalyzer.analyze($0, doses: drinks.filter { $0.timestamp > now.addingTimeInterval(-30 * 86_400) }.map(\.dose), profile: profile, now: now)
        } ?? []

        return ScrollView {
            VStack(spacing: 16) {
                if let greeting {
                    GreetingCard(message: greeting) { withAnimation { self.greeting = nil } }
                }
                // Anything the analysis flags moves to the top.
                if store.healthSharingEnabled, !findings.isEmpty {
                    healthCard(findings)
                }
                Card {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estimated now").font(.subheadline).foregroundStyle(.secondary)
                            Text(current.mgText).font(.system(size: 40, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Label("At bedtime \(bedtime.shortTime)", systemImage: "moon.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.bedtime)
                            Text("≈ \(atBedtime.mgText)").font(.title2.bold())
                        }
                    }
                    CaffeineCurveChart(
                        doses: doses,
                        halfLifeHours: profile.halfLifeHours,
                        now: now,
                        bedtime: bedtime,
                        thresholdMg: profile.thresholdMg
                    )
                    .frame(height: 220)
                    Text("Estimates use your estimated \(String(format: "%g", profile.halfLifeHours))-hour half-life and assume each drink is absorbed right away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button { composerMode = .preview } label: {
                        Label("Preview", systemImage: "wand.and.sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.preview)
                    Button { composerMode = .log } label: {
                        Label("Log drink", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)

                CountdownCard(now: now, current: current, doses: doses, profile: profile)
                GuidelineCard(total24h: total24h, profile: profile)

                if store.healthSharingEnabled {
                    if findings.isEmpty { healthCard(findings) }
                } else if HealthDataStore.isAvailable, !healthInviteDismissed {
                    HealthInviteCard(onConnect: { showHealthConsent = true }, onDismiss: { healthInviteDismissed = true })
                }

                Card {
                    Text("Recent drinks").font(.headline)
                    if recentDrinks.isEmpty {
                        Text("No drinks logged.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(recentDrinks)) { entry in
                        Button { editing = entry } label: {
                            DrinkRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        if entry !== recentDrinks.last { Divider() }
                    }
                    if !recentDrinks.isEmpty {
                        Text("Tap a drink to edit or delete it.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private func healthCard(_ findings: [HealthFinding]) -> some View {
        HealthCheckCard(findings: findings, hasData: health.snapshot?.hasHeartOrSleepData ?? false, status: health.status, lastUpdated: health.lastUpdated)
    }

    /// First open of a new day shows the greeting (if caffeine changed); every open refreshes Health data.
    private func onOpen() async {
        let today = DailyGreeting.dayKey(.now)
        if store.lastGreetingDay != today {
            store.lastGreetingDay = today
            greeting = DailyGreeting.message(doses: drinks.map(\.dose), now: .now)
        }
        if store.healthSharingEnabled, health.status != .loading {
            await health.refresh()
        }
    }
}

struct DrinkRow: View {
    let entry: DrinkEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.quantity == 1 ? entry.name : "\(entry.quantity.quantityText) × \(entry.name)")
                Text(entry.timestamp.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.totalMg.mgText).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct CountdownCard: View {
    let now: Date
    let current: Double
    let doses: [CaffeineDose]
    let profile: UserProfile

    var body: some View {
        Card {
            Label("Countdown to below \(profile.thresholdMg.mgText)", systemImage: "timer")
                .font(.headline)
            if let crossing = CaffeineModel.timeBelow(thresholdMg: profile.thresholdMg, after: now, doses: doses, halfLifeHours: profile.halfLifeHours) {
                Text(crossing.timeIntervalSince(now).durationText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Estimated to fall below \(profile.thresholdMg.mgText) around \(crossing.shortTime), if you don't have more caffeine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your estimated caffeine is below \(profile.thresholdMg.mgText).")
                    .font(.subheadline)
            }
            if !profile.notificationsEnabled {
                Text("Turn on notifications in Settings to be told when the countdown ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GuidelineCard: View {
    let total24h: Double
    let profile: UserProfile

    var body: some View {
        let level = CaffeineModel.guidelineLevel(for: total24h)
        let color: Color = switch level {
        case .below: Theme.accent
        case .approaching: .orange
        case .above: .red
        }

        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 24 hours").font(.headline)
                Spacer()
                Text("\(total24h.mgText) of 400 mg").monospacedDigit().foregroundStyle(color)
            }
            ProgressView(value: min(total24h / CaffeineModel.dailyGuidelineMg, 1))
                .tint(color)
            switch level {
            case .below:
                Text(AppText.guidelineNote).font(.caption).foregroundStyle(.secondary)
            case .approaching:
                Callout(systemImage: "exclamationmark.triangle.fill", text: "You're approaching Health Canada's 400 mg daily maximum for adults.", color: .orange)
            case .above:
                Callout(systemImage: "exclamationmark.octagon.fill", text: "You're above Health Canada's 400 mg daily maximum for adults.", color: .red)
            }
            if profile.hasHealthFlags {
                Callout(systemImage: "stethoscope", text: AppText.healthFlagAdvice, color: .blue)
            }
        }
    }
}

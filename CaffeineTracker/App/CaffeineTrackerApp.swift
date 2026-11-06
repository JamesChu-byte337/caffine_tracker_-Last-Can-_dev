import SwiftData
import SwiftUI
import UserNotifications

@main
struct CaffeineTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ProfileStore()
    @State private var health = HealthDataStore()
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system

    private let container: ModelContainer = {
        // Local only: drink logs are never synced to iCloud.
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: DrinkEntry.self, SavedDrink.self, configurations: configuration)
        } catch {
            fatalError("Could not open the on-device store: \(error)")
        }
    }()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(SampleData.launchArgument) {
            let context = ModelContext(container)
            if ((try? context.fetchCount(FetchDescriptor<DrinkEntry>())) ?? 0) == 0 {
                SampleData.insert(into: context)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(health)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show the countdown notification even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

struct RootView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        if store.accountEmail == nil {
            LoginView()
        } else if store.disclaimerAcceptedAt == nil {
            DisclaimerView { store.disclaimerAcceptedAt = .now }
        } else if let profile = store.profile {
            if profile.hasFullAccess {
                MainTabView(profile: profile)
            } else {
                AgeRestrictedView()
            }
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    let profile: UserProfile
    @Query(sort: \DrinkEntry.timestamp) private var drinks: [DrinkEntry]

    private struct NotificationInputs: Hashable {
        let doses: [CaffeineDose]
        let thresholdMg: Double
        let halfLifeHours: Double
        let enabled: Bool
    }

    var body: some View {
        TabView {
            Tab("Today", systemImage: "cup.and.saucer.fill") {
                HomeView(profile: profile, drinks: drinks)
            }
            Tab("History", systemImage: "chart.bar.xaxis") {
                HistoryView(profile: profile, drinks: drinks)
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        // Any change to drinks or countdown settings reschedules the notification right away.
        .task(id: notificationInputs) {
            await CaffeineNotifier.reschedule(doses: notificationInputs.doses, profile: profile)
        }
    }

    private var notificationInputs: NotificationInputs {
        let cutoff = Date.now.addingTimeInterval(-CaffeineModel.relevantWindow)
        return NotificationInputs(
            doses: drinks.filter { $0.timestamp > cutoff }.map(\.dose),
            thresholdMg: profile.thresholdMg,
            halfLifeHours: profile.halfLifeHours,
            enabled: profile.notificationsEnabled
        )
    }
}

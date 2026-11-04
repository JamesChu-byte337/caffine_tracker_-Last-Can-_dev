# Last Can (iOS, SwiftUI)

Helps students decide on their next energy drink by showing estimated caffeine now, at bedtime, and what one more drink would change.

## Run

Open `CaffeineTracker.xcodeproj` in Xcode (the project and target keep the internal name CaffeineTracker; the app shows as "Last Can") and run the **CaffeineTracker** scheme on an iPhone simulator (iOS 18+). Tests: `⌘U`, or

```bash
xcodebuild -project CaffeineTracker.xcodeproj -scheme CaffeineTracker -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

To try it with realistic history, debug builds have **Settings → Developer → Add 30 days of sample drinks**.

## Where things live

| Area | Files |
|---|---|
| Estimate math (half-life sum, 24 h total, countdown, bedtime) | `CaffeineTracker/Logic/CaffeineModel.swift` |
| History stats and insight sentences | `Logic/HistoryStats.swift` |
| Label OCR (Vision, on device) and caffeine/serving parsing | `Logic/TextRecognizer.swift`, `Logic/LabelParser.swift` |
| Countdown notification | `Logic/CaffeineNotifier.swift` |
| Profile, health flags, disclaimer state (UserDefaults, on device) | `Models/ProfileStore.swift` |
| Drink log and saved drinks (SwiftData, local only, no CloudKit) | `Models/DrinkModels.swift` |
| Disclaimer, 18+ gate, onboarding | `Views/Onboarding/` |
| Main screen, curve chart, countdown, guideline | `Views/Home/` |
| "What if" preview/log sheet, edit drink, label scan | `Views/Drink/` |
| Weekly/monthly charts | `Views/History/` |

## Version 1.0.1 additions

| Area | Files |
|---|---|
| uwaterloo.ca sign-in (format check only, no SSO) | `Views/Onboarding/LoginView.swift`, `Account` in `Models/ProfileStore.swift` |
| Health conditions list with custom entries | `Views/Onboarding/HealthConditionsView.swift` |
| Personal half-life estimate and Re-evaluate | `Logic/HalfLifeEstimator.swift`, `Views/Settings/ReevaluateHalfLifeView.swift` |
| Apple Health reading (opt-in, read-only) | `Logic/HealthDataStore.swift`, `CaffeineTracker.entitlements` |
| On-device heart rate / sleep pattern analysis | `Logic/HealthAnalyzer.swift`, `Views/Home/HealthCheckCard.swift` |
| Daily greeting, changelog, version badge | `Logic/DailyGreeting.swift` |

The half-life estimate starts at 5 h and applies multipliers from published research (Nehlig 2018, Pharmacol Rev; Grzegorzewski et al. 2021, Front Pharmacol): CYP1A2-inhibiting medication ×2, liver condition ×2, pregnancy ×1.8, age 65+ ×1.2, BMI 30+ ×1.15. The result is clamped to 2–8 h and rounded to 0.25 h.

When you add a release, add an entry at the top of `Changelog.entries` and bump `MARKETING_VERSION` in the project.

## Choices worth knowing

- "Late caffeine" counts drinks from 8 p.m. up to 4 a.m., on the calendar day the drink was logged.
- History "days over 400 mg" uses calendar-day totals; the main screen and the logging warning use the rolling 24-hour total.
- "Approaching the guideline" starts at 300 mg (75%).
- Bedtime is the next occurrence after now, so at 12:30 a.m. with an 11 p.m. bedtime, the app shows the following night.
- Health info is never synced or sent anywhere, including Apple Health data. The opt-in sync from the proposal isn't built.
- Health "analysis" is rule-based and runs on the device; findings are worded as observations and point to a doctor, never as a diagnosis.
- Bundle ID is the placeholder `com.example.CaffeineTracker`. Set your team and bundle ID before installing on a phone.

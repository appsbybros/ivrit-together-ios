# Ivrit Together / עברית ביחד for iPhone and iPad

An adult beginner's Hebrew companion for everyday life in Israel: a native SwiftUI port of
the Android app (`C:/Projects/IvritTogether`, Kotlin and Jetpack Compose, version 1.0.0).
Bundle ID `com.appsbybros.ivrittogether`, version 1.0.0, iOS 17 or later, iPhone and iPad,
portrait and landscape.

**Status: written without a Swift compiler and not compiled yet.** See
[BUILD_STATUS.md](BUILD_STATUS.md) for what was checked and what has to happen next.

## What the app does

- 18 everyday topics, 108 words and phrases, 22 letters with the five final forms.
- Learning cards, meaning and listening questions, right-to-left sentence construction,
  matching, a searchable phrasebook with saved phrases, and spaced review.
- Interface and meanings in English, Russian, Ukrainian, French, Spanish, Portuguese,
  Arabic, Amharic, German and Hebrew, with right-to-left layout for Arabic and Hebrew and
  no English fallback.
- Optional vowel marks and pronunciation guides, masculine or feminine examples.
- Hebrew speech with Apple's on-device voices at normal and slow speed; without a Hebrew
  voice the app explains this and Voice settings opens the app's page in Settings.
- A daily goal of five different phrases with a progress bar, practice-day streak and
  phrases practised.
- Rate, Share and Send feedback. The light palette stays readable in Dark Mode, text
  follows Dynamic Type (the bottom bar becomes a two-by-two grid at large sizes, as on
  Android) and controls have VoiceOver labels.

## Same content and rules as Android

`Resources/course.json` and `Resources/ui.json` are byte-identical copies of the Android
`app/src/main/assets` files (SHA-256 `b840a6fb…ab26953` and `7549cd5d…c3dba1a`) and are read
at runtime. To update content, copy the Android files again; nothing else needs to change.

The Swift code ports every rule of `Learning.kt`, `Data.kt`, `LearnViewModel.kt`,
`Speech.kt` and `MainActivity.kt`:

| Android | iOS |
| --- | --- |
| `Learning.kt` (Progress, Session, makeSession, plainHebrew) | `Sources/Learning.swift` (`LearnerProgress`, `Session`, `makeSession`, `plainHebrew`) |
| `Data.kt` Course | `Sources/Course.swift` |
| `Data.kt` LocalStore, SharedPreferences `ivrit-together` | `Sources/LocalStore.swift`, UserDefaults suite `ivrit-together`, same keys (`language`, `female`, `transliteration`, `vowels`, `progress`) and the same progress JSON (version 1, words, completed, saved, days, answered, dailyPhrases) |
| `LearnViewModel.kt` | `Sources/LearnViewModel.swift` |
| `Speech.kt` (TextToSpeech, rate 0.88 / 0.65) | `Sources/Speech.swift` (AVSpeechSynthesizer, 0.88 / 0.65 of the default rate) |
| `MainActivity.kt` screens | `Sources/RootView.swift`, `HomeViews.swift`, `LessonViews.swift`, `PracticeViews.swift`, `LibraryViews.swift`, `SettingsView.swift`, `Theme.swift` |

Spaced review keeps Android's intervals (20 minutes, 1, 3, 7, 14 and 30 days), early
repeats do not advance a stage, a wrong answer resets it, repeated taps on the same answer
count once, the daily goal counts five different correctly answered phrases per day, the
last 60 days and 600 attempt ids are kept, and unreadable saved progress is preserved
(saving is refused) until the learner resets it.

### Deliberate iOS differences

- **More Minik apps & games** is left out: it uses an Android-only shared module, and the
  developer's App Store page URL is not known yet.
- **Privacy note**: `ui.json` says "Android backups may include progress" in all ten
  languages. iOS shows the same sentence with "iCloud" in place of "Android"
  (`PlatformWording` in `Course.swift`); every other text is shown unchanged. A unit test
  checks both, so a changed Android text is noticed.
- **Voice settings**: iOS has no public link to its speech voice settings, so the button
  opens the app's page in Settings (as requested), one step from Accessibility.
- **Rate and Share** need the app's Apple ID for an App Store link. The TestFlight workflow
  reads it from App Store Connect and builds it in (`IVRIT_APP_STORE_ID`, Info.plist key
  `IvritAppStoreID`). Without it (local builds) Rate shows StoreKit's review prompt and
  Share sends the app name only. Feedback opens a `mailto:` to appsbybros.dev@gmail.com
  with the subject "Ivrit Together feedback", as on Android.
- **Welcome screen** uses the chosen language's direction at once (Android switches the
  layout direction after the language is chosen).
- **Saved phrases** use an outlined heart when not saved and a filled heart when saved, so
  the state does not rely on colour alone.
- **Audio** plays like media, also with the ring switch on silent (Android speaks on the
  media stream), and lowers other audio only while speaking.

## Project layout

```
project.yml                 XcodeGen spec: app target IvritTogether, unit tests IvritTogetherTests
Sources/                    SwiftUI app (14 files)
Resources/course.json       identical to Android
Resources/ui.json           identical to Android
Resources/Assets.xcassets   AppIcon (1024 px, no transparency), Neighborhood art, colours
Resources/Localization/     InfoPlist.strings for the ten languages
Resources/PrivacyInfo.xcprivacy  UserDefaults (CA92.1), no tracking, no collected data
Tests/                      XCTest: learning rules, daily goal, storage, content, flows
Scripts/validate.py         content, interface keys, assets and store texts (no Swift build)
Scripts/make_assets.py      renders the AppIcon from the Android launcher vector (Pillow)
Scripts/appstore.py         App Store Connect: App ID, pre-flight, build number, upload
.github/workflows/          verify.yml and testflight.yml (both started by hand only)
app-store/en-US, app-store/he   App Store texts; submission.json
docs/privacy.html, docs/privacy-he.html
```

## Build and verify

On a Mac with Xcode 15 or later and XcodeGen 2.38 or later:

```
xcodegen generate
open IvritTogether.xcodeproj
```

On GitHub, **Actions > Verify iOS build and tests > Run workflow** checks the resources,
generates the project, compiles the app and its tests for an iPhone simulator, runs the
unit tests, compiles Release for devices without signing, and lists every compiler error
and failed test in the run summary. It needs no secrets.

The unit tests (50) port `LearningTest.kt` and `DailyGoalTest.kt` and the content,
storage and flow checks of `LearningDeviceTest.kt`: every lesson solvable in both forms
and all ten languages, every interface key present in all ten languages (including each
key the iOS screens read), Android-format progress read correctly, corrupt progress kept
until reset, double submission ignored, matching, unpointed sentence building, daily
practice and reset.

## TestFlight

**Actions > TestFlight upload > Run workflow** (adapted from the Minik apps' workflow). It
needs the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (the full
`.p8` text of a Team key with the Admin role) and `APPLE_TEAM_ID`.

1. A Linux pre-flight checks the key and its signing access, registers the App ID
   `com.appsbybros.ivrittogether` if missing, and stops with instructions while the App
   Store Connect app record is missing. Create it once in App Store Connect (Apps > + >
   New App, iOS, bundle ID `com.appsbybros.ivrittogether`, SKU e.g. `ivrit-together-ios`)
   and run the workflow again.
2. It picks a build number above every build already uploaded.
3. A macOS job archives unsigned, exports with Apple's cloud-managed distribution
   certificate (`-allowProvisioningUpdates` with the API key) and uploads the .ipa through
   the App Store Connect API.

Neither workflow runs on push.

## Store and privacy

`app-store/en-US` and `app-store/he` hold the name, subtitle, keywords, description,
promotional text and what's new, adapted from the Play listing (no Android references,
within Apple's limits; `Scripts/validate.py` checks them). `docs/privacy.html` and
`docs/privacy-he.html` adapt the Android privacy policy to iOS and must be published on a
public HTTPS address before submission. App privacy details: Data Not Collected.

Copyright © 2026 Apps by Bros. All rights reserved.

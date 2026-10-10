# Ivrit Together iOS — build status

Date: 2026-10-10. Version 1.0.0 (build number set by the TestFlight workflow),
`com.appsbybros.ivrittogether`, iOS 17+, iPhone and iPad.

## Not compiled yet

The app and its tests were written on Windows, where no Swift compiler or Xcode exists.
**Nothing has been compiled, run, tested on a simulator or device, signed or uploaded.**
Expect the first verification run to report compiler errors that need fixing.

## What was checked without a compiler

- All 19 Swift files (14 app, 5 test) parse without errors in tree-sitter-swift, and their
  braces, parentheses and brackets balance (comments and strings excluded).
- Every API was chosen for iOS 17 and Swift 5 language mode and reviewed by reading,
  following patterns that already compile in the team's Minik and Easy Call iOS projects
  (for example `@MainActor` NSObject speech delegate with `nonisolated` callbacks,
  `@ScaledMetric(relativeTo:)`, custom `Layout`, `Binding(get:set:)` on a `@MainActor`
  model, `@MainActor` XCTestCase).
- `Resources/course.json` and `Resources/ui.json` are byte-identical to the Android assets
  (SHA-256 `b840a6fb60a6391dffd3539fcf090d2a99b23f9dc79fc9b696dd36215ab26953` and
  `7549cd5d992e50c9e24bc1ae6918fb7cc22afecd56c780ff3df7ee4fac3dba1a`); the neighbourhood
  art is the unchanged Android PNG.
- `python Scripts/validate.py` passes: 18 lessons, 108 phrases, 22 letters, all meanings
  and titles in ten languages, 88 interface keys in all ten languages, all 86 keys the
  Swift screens read exist, AppIcon 1024 x 1024 RGB without alpha, ten InfoPlist.strings,
  App Store texts within limits (en-US name 28, subtitle 30, keywords 95, description
  1246; he name 25, subtitle 26, keywords 96, description 1012 characters).
- The Hebrew string literals in the ported tests match the Kotlin tests code point for code
  point.
- `Scripts/appstore.py` passed a dry run of every command (check, register, next-build,
  app-id, upload) against a fake App Store Connect API.
- Both workflows parse as YAML, every shell step passes `bash -n`, and the verify summary
  parser and simulator chooser were run on sample `xcodebuild` and `simctl` output.

## Independent review (2026-10-10, still without a compiler)

- Parity: all five Android Kotlin files, both unit tests and the device test were compared
  with the Swift code: every screen and flow, Back rules, the spaced-review intervals and
  stage rules, the 5-phrase daily goal and its 60-day / 600-attempt limits, review order,
  question pattern, distractors, word bank, stored keys and JSON fields, all 88 interface
  keys and the ten languages. Nothing missing was found; the only differences are the
  deliberate iOS ones listed in README.md.
- Compile reading: every Swift file was re-read against the iOS 17 API surface and Swift 5
  language mode as built by Xcode 26 on `macos-latest`; every member, initializer label and
  call resolves; `course.json` and `ui.json` match the `Decodable` types field for field.
- Changes: `FlowRow` now calls its layout as a value (`layout { … }`, the form Minik's
  `CardsPageFillLayout` already compiles with) instead of a trailing closure on the
  layout's initializer, and its items keep the interface direction (in Arabic and Hebrew a
  chip's check mark sits on the right, as in Android's `FlowRow`). The verify workflow
  only picks a simulator runtime that the selected Xcode can run (not newer than its
  simulator SDK).

## Next steps

1. Put the folder in a GitHub repository (the orchestrator initialises and commits it).
2. Run **Verify iOS build and tests** by hand; fix any errors it lists in the run summary
   (compiler errors and failed tests are listed with file and line).
3. Add the four signing secrets, run **TestFlight upload**, create the App Store Connect
   app record when the pre-flight asks for it, and run it again.
4. On a physical iPhone and iPad: Hebrew speech (and the notice without a Hebrew voice),
   VoiceOver, the largest text sizes, Arabic and Hebrew right-to-left layout, landscape and
   iPad multitasking.
5. Capture App Store screenshots (6.9-inch iPhone, 13-inch iPad), publish
   `docs/privacy.html` and a support page, then complete App Review submission.

## Known limits

- "More Minik apps & games" is not on iOS (Android-only module; developer page URL unknown).
- Rate and Share link to the App Store only in builds made by the TestFlight workflow,
  which passes in the app's Apple ID.
- As on Android, native-language editorial review of the course is still recommended.

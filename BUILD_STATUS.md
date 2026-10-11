# Ivrit Together iOS — build status

Date: 2026-10-11. Version 1.0.0 (build number set by the TestFlight workflow),
`com.appsbybros.ivrittogether`, iOS 17+, iPhone and iPad.

## Current state

- **Version 1.0.0 as first committed (`bb4464c`)**: the owner reports that all steps are done
  and all builds are green; the TestFlight build was installed and tested on an iPad (QA
  report of 11 October 2026).
- **Practice change for QA ISSUE-001 (below)**: written on Windows, where no Swift compiler
  or Xcode exists. **Not compiled, run or tested yet.**

## QA ISSUE-001: immediate answer feedback with retry (not compiled yet)

The owner asked (iPad): check an answer as soon as it is selected, without a Check button;
mark a wrong answer without revealing the right one and let the learner choose again; keep a
Next button so the learner decides when to move on, as in Minik.

What changed:

- Meaning and listening questions: a tap checks the option at once. Right: the option is
  marked ✓, "That's right" shows the Hebrew and its meaning, and Next (Finish on the last
  question) moves on when the learner taps it. Wrong: only that option is marked ✗ and it
  cannot be chosen again; "Not quite. Try again." is shown, the right answer is not revealed
  and the other options stay available. Next is offered after a wrong answer too, in the
  secondary style, as Minik offers Next after a wrong attempt, so no question can block the
  learner. A listening question shows its Hebrew text on request or with the right answer.
- Sentence building: checked as soon as the last word is placed. A wrong sentence is marked
  but not corrected; tapping a placed word returns it to the bank (clearing the mark) and the
  rebuilt sentence is checked again. A right sentence is locked until Next.
- Matching already checked every pair at once; unchanged.
- Honest scoring: only the first answer to a question is saved. It alone decides the result
  score, the spaced review (a wrong first answer resets the phrase's stage, so it returns
  after 20 minutes) and the daily goal (a phrase found on a retry does not count). Later
  tries are not saved; an answer that cannot be saved is not shown as checked (the save
  error is shown, as before).
- VoiceOver: every checked answer is announced ("That's right" or "Not quite. Try again."),
  queued after VoiceOver's own speech (`.accessibilitySpeechQueueAnnouncement`, iOS 11), and
  each option reads its mark as its value ("That's right" or "Not correct"). Right-to-left
  layout is unchanged: marks lead the option text, the answer row still fills from the right.
- Texts: two new keys, `try_again` and `incorrect`, in all ten languages, in the new
  `Resources/ui-ios.json` (bundled by `project.yml`, merged by `Course`), so `ui.json` stays
  byte-identical to Android; Android's text wins if `ui.json` ever gains the same key. The
  screens no longer read Android's `check`, `continue` and `not_yet`; Next uses `next`.
- Files: `Sources/Learning.swift` (`Session.choose`, `toggleToken`, `submit`; `wrongChoices`,
  `tries`, `wrong`), `Sources/LearnViewModel.swift` (no `submit()`; the first check is saved
  in `show`), `Sources/PracticeViews.swift`, `Sources/Course.swift`, `Resources/ui-ios.json`,
  `project.yml`, `Scripts/validate.py`, the tests and README.md.
- Tests: 57 (was 50). Rewritten or new: tap-to-check with repeated taps counted once and
  Next unavailable before an answer; a wrong option marked, retried and not scored; Next after
  a wrong answer; a wrong sentence checked when complete and fixed; an unsaved answer not
  shown as checked; the Session rules; the iOS-only texts complete in ten languages. The
  Kotlin port `testRepeatedWordsRemainSeparateTokens` keeps its Hebrew literals and its
  assertion (removing token 1 from an unchecked answer [1, 0] leaves [0]); in the tapped flow
  it removes a word before the sentence is complete, because a complete sentence is now
  checked at once.

Checked without a compiler:

- All 19 Swift files parse without errors in tree-sitter-swift (WASM and Python bindings),
  and their braces, parentheses and brackets balance (comments and strings excluded).
- Every changed line was read against the iOS 17 API surface and Swift 5 language mode as
  Xcode 26 builds it. The new code uses forms this project already compiles (a `let` inside
  a view builder, two-parameter `onChange(of:)`, `background(_:in:)`, a String
  `accessibilityLabel`, a custom `ButtonStyle`) plus a String `accessibilityValue` (iOS 14)
  and an `NSAttributedString` with UIKit's `.accessibilitySpeechQueueAnnouncement` key
  (iOS 11) for the announcements.
- `python Scripts/validate.py` passes: 88 Android interface keys and 2 iOS-only keys in all ten
  languages, all 85 keys the Swift screens read exist, the three JSON resources are bundled.
- The new expectations were traced by hand against the course data (for example lesson
  `messages` question 3 is a three-word sentence whose reverse is wrong).
- Independent review (2026-10-11, still without a compiler): every changed line re-read for
  compile errors, and the flow checked against ISSUE-001 and Minik's Next after a wrong
  attempt; listening auto-play, matching, results and the leave confirmation are unchanged.
  No errors found; the new and changed test scenarios were replayed against `course.json` in
  a separate Python port of the rules. Only the Kotlin assertion above was restored.

## Version 1.0.0: checked without a compiler before its first build

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

1. Commit the ISSUE-001 change and push it when the owner asks.
2. The owner runs **Verify iOS build and tests** by hand; fix any errors it lists in the run
   summary (compiler errors and failed tests are listed with file and line).
3. The owner runs **TestFlight upload** and checks on the iPad (and an iPhone): a right tap
   shows "That's right" and waits for Next; a wrong tap is marked without the answer, another
   option can be tried, and Next still moves on; a sentence is checked when its last word is
   placed and can be fixed; the daily goal counts only first-try answers; VoiceOver
   announcements; Arabic and Hebrew layout.
4. Decide whether Android's Ivrit Together should get the same flow (the owner asked to
   compare the apps later).
5. If not yet done for 1.0.0: App Store screenshots (6.9-inch iPhone, 13-inch iPad), the
   public privacy and support pages, and App Review submission.

## Known limits

- "More Minik apps & games" is not on iOS (Android-only module; developer page URL unknown).
- Rate and Share link to the App Store only in builds made by the TestFlight workflow,
  which passes in the app's Apple ID.
- As on Android, native-language editorial review of the course is still recommended.

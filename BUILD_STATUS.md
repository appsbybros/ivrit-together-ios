# Ivrit Together iOS — build status

Date: 2026-10-12. Version 1.0.0 (build number set by the TestFlight workflow),
`com.appsbybros.ivrittogether`, iOS 17+, iPhone and iPad.

## Current state

- **Version 1.0.0 as first committed (`bb4464c`)**: the owner reports that all steps are done
  and all builds are green; the TestFlight build was installed and tested on an iPad (QA
  report of 11 October 2026).
- **Practice change for QA ISSUE-001 (`64553ab`), its follow-up (`1c7e36b`), the text review
  (`e1a5915`) and the owner's decisions of 12 October (below)**: written on Windows, where no
  Swift compiler or Xcode exists. **Not compiled, run or tested yet.**

## Owner's decisions of 12 October 2026 (not compiled yet)

- **"That's right" panel back.** Only the Check button was to go; the panel had been removed
  by mistake. After a right answer Android's panel shows again (mint, "✓ That's right", the
  Hebrew at 29 points and its meaning) during the success feedback; the page scrolls just
  enough to show it if it is below the screen (`Page(focus:)`, `ScrollViewReader`, no
  animation with Reduce Motion), and every question starts at the top of the page
  (`Page(start:)`), so the next one is not shown scrolled down. The pause is now 1.5 seconds
  (the longest of the owner's 1 to 1.5), so the panel can be read.
- **The chime respects silent mode.** `Speech.playSuccess()` plays `success.wav` as a system
  sound (`AudioServicesCreateSystemSoundID`, `AudioServicesPlaySystemSound`): not played
  while the device is silenced (ring/silent switch or Silent Mode), at the system sound
  volume, mixing with the speech and other apps' audio without lowering them; it no longer
  activates the app's audio session. Speech is unchanged (plays on silent, as Android).
- **Points.** The owner: a right answer after another try should earn less (1) than a right
  answer first time. A right answer now earns 2 points first time and 1 after another try;
  moving on with Next earns none (`Points`, `Session.score`, `Session.maxScore`). The result
  shows the points out of the most possible ("Points", 2 per question) and the rule. The
  daily goal is 10 points (`LearnerProgress.dailyGoalPoints`, `dailyPoints`): 2 for each
  phrase answered right first time that day, 1 for each phrase found only after another try,
  each phrase once a day with its best result. The first answer alone still decides the
  spaced review: a phrase found after another try comes back after 20 minutes. Phrases found
  after another try are saved by day in `dailyRetried`, kept 60 days and written to the
  progress JSON only once there is one, so older progress loads unchanged.
- Texts: four new iOS-only keys in all ten languages (`points`, `points_rule`,
  `daily_goal_points`, `daily_goal_points_done`), written in each language's existing voice
  (formal in Russian, Ukrainian, French and Amharic; informal in Spanish and German; plural in
  Hebrew). The screens no longer read Android's `score`, `daily_goal` and `daily_goal_done`.
- Tests: 69 (was 66): points first time and after another try in `LearningTests` and
  `LearnViewModelTests`, daily points and their 60-day history in `DailyGoalTests`, and
  `dailyRetried` saved and restored in `LocalStoreTests`.
- Checked without a compiler: all 21 Swift files parse in tree-sitter-swift and their
  delimiters balance; `python Scripts/validate.py` passes (6 iOS-only keys in ten languages,
  every key the Swift screens read exists, the chime shorter than the 1.5-second pause).

## QA ISSUE-001 follow-up: a right answer moves on by itself (not compiled yet)

Superseded in part by the owner's decisions above: the "That's right" panel is shown again,
the pause is 1.5 seconds, the chime is a system sound that respects silent mode, and answers
score points.

The owner's spec (12 October 2026): after a right answer, about 1 to 1.5 seconds of pleasant
success feedback, then the next item by itself, with no Next button; Next appears only after
a wrong answer; the scoring rules stay as they are.

What changed:

- Right answer (an option, or a sentence when its last word is placed): the option or the
  answer row turns green (`Palette.correct` #2E7D4A border, `Palette.correctFill` #DCF2E1)
  with ✓ (the answer row now has a mark slot leading its words, kept free while unmarked so
  the words never move) and bounces once (scale 1.05 and back, about half a second); a
  short two-note chime and a success haptic (`UINotificationFeedbackGenerator`, `.success`)
  play; after 1.2 seconds (`LiveAnswerFeedback.successSeconds`) the next question follows,
  or on the last one the result (the lesson is saved as completed, as Finish did). No Next
  is shown, and Next is refused by the model while a right answer is on screen.
- The "That's right" panel with the Hebrew and its meaning is no longer shown after a right
  answer: the success feedback is the green mark, the bounce, the chime and the haptic, as the
  spec lists them (a listening question still shows its Hebrew text with the right answer).
- Wrong answer: the option turns red (`Palette.wrongFill` #FBE3E1 with the `danger` #9F3030
  border) with its ✗, the right answer is not revealed, "Not quite. Try again." is shown, the
  other options stay available, and a secondary Next (Finish on the last question) is
  offered (`Session.offersNext`: a wrong answer checked and the question not solved). A
  wrong sentence turns red with ✗ the same way, keeps its words and offers Next; Next stays while
  the sentence is being fixed. Finding the right answer afterwards hides Next, plays the
  success feedback and moves on by itself.
- Scoring unchanged: only the first answer to a question is saved and scored.
- VoiceOver: every checked answer is announced as before ("That's right", "Not quite. Try
  again.", queued after VoiceOver's own speech). After a right answer the next question waits
  until VoiceOver reports that "That's right" has been spoken
  (`UIAccessibility.announcementDidFinishNotification`), and at least the 1.2 seconds; if the
  report never comes it moves on after at most 10 seconds more (checked every 0.1 seconds).
  Reduce Motion: no bounce; the pause stays.
- The chime: `Resources/success.wav`, 0.65 seconds, C6 then G6 0.1 seconds later, bell-like
  (two softer overtones), 44.1 kHz mono 16-bit, peak about -6 dBFS, rendered by
  `Scripts/make_sound.py` (standard library, same file on every run) and bundled by
  `project.yml`. `Speech.playSuccess()` plays it with `AVAudioPlayer` through the app's audio
  session (`.playback`, `.spokenAudio`, `.duckOthers`, which mixes with other apps' audio and
  lowers it while playing), so it also mixes with the Hebrew speech; the session is ended
  only when neither the speech nor the chime is playing. The player is not prepared at
  launch, so starting the app does not lower other audio.
- Speech stops when the practice ends by itself (`onDisappear`), as the Finish button did;
  moving to the next question already stopped it.
- Code: the new `Sources/AnswerFeedback.swift` (the `AnswerFeedback` protocol the model uses,
  `LiveAnswerFeedback`, and `announceForVoiceOver` moved from the practice screen);
  `LearnViewModel` (a third init parameter `feedback`; `present` announces and starts the
  pause; `moveOn` moves on only if the learner is still on that solved question; `abandon`
  cancels the pause); `Session.offersNext`; `PracticeView` (green and red marks, bounce,
  chime, haptic, Next only after a wrong answer); `Speech` (the chime); `Palette`;
  `project.yml`; `Scripts/validate.py` (checks the WAV and that it is bundled).
- Tests: 66 (was 57). The model tests use an `AnswerFeedback` whose pause the test ends
  itself: a right answer announced, with no Next and moving on only when the pause ends (also
  the result after the last question); Next only after a wrong answer, also Finish on the last
  question; a retry after a wrong answer moving on by itself; a fixed sentence moving on;
  leaving during the pause; an unsaved answer neither announced nor moved on. New
  `Tests/AnswerFeedbackTests.swift` runs `LiveAnswerFeedback` on an instant clock (nothing
  sleeps): the pause between 1 and 1.5 seconds, the wait for VoiceOver's announcement (another
  announcement does not end it), its 10-second limit, cancelling, and the bundled chime
  readable and shorter than the pause. `LearningTests` check `offersNext`.

Checked without a compiler:

- All 21 Swift files parse without errors in tree-sitter-swift (Python bindings), and their
  braces, parentheses and brackets balance (comments and strings excluded).
- Every changed line was read against the iOS 17 API surface and Swift 5 language mode as
  Xcode 26 builds it. New APIs: `AVAudioPlayer(contentsOf:)`, `play()`, `currentTime`,
  `isPlaying` and `AVAudioPlayerDelegate.audioPlayerDidFinishPlaying(_:successfully:)`
  (a `nonisolated` callback hopping to the main actor, like the speech delegate),
  `UINotificationFeedbackGenerator` (iOS 10), `UIAccessibility.isVoiceOverRunning`,
  `announcementDidFinishNotification` with `announcementStringValueUserInfoKey` (iOS 6),
  `@Environment(\.accessibilityReduceMotion)`, `withAnimation(_:_:)` with
  `.spring(response:dampingFraction:)`, `scaleEffect(_:)`, `Task.sleep(nanoseconds:)` (all
  iOS 13 or earlier), and `AVAudioFile(forReading:)` in a test.
- `python Scripts/validate.py` passes: 88 Android interface keys and 2 iOS-only keys in all
  ten languages, all 85 keys the Swift screens read exist (no new texts were needed: the
  announcements use `correct` and `try_again`, Next uses `next` and `finish`), the four
  bundled resources are listed in `project.yml`, and `success.wav` is 16-bit PCM, mono,
  44.1 kHz, 0.65 seconds.
- Every changed and new test was traced by hand against `course.json` (for example lesson
  `cafe` question 6 is the two-word sentence `cafe-6`, wrong in reverse order).

## QA ISSUE-001: immediate answer feedback with retry (not compiled yet)

Superseded in part by the follow-up above: a right answer no longer waits for Next and no
longer shows the "That's right" panel, and Next appears only after a wrong answer. The rest of
this section still holds.

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

1. The owner runs **Verify iOS build and tests** by hand; fix any errors it lists in the run
   summary (compiler errors and failed tests are listed with file and line).
2. The owner runs **TestFlight upload** and checks on the iPad (and an iPhone): a right tap
   turns green, bounces, shows "That's right" with the Hebrew and its meaning (scrolled into
   view on a small screen), chimes, gives a haptic and moves on by itself after 1.5 seconds,
   with no Next; with the device silenced there is no chime, and music from another app is
   not lowered by it; a wrong tap turns red without the answer, another option can be tried,
   and only then Next is offered; a right retry moves on by itself; a sentence is checked
   when its last word is placed, moves on when right and can be fixed when wrong; the result
   shows points (2 first time, 1 after another try) and the home card's daily goal counts to
   10 points; VoiceOver waits for "That's right" before moving on; Reduce Motion has no
   bounce; Arabic and Hebrew layout.
3. Decide whether Android's Ivrit Together should get the same flow (the owner asked to
   compare the apps later).
4. If not yet done for 1.0.0: App Store screenshots (6.9-inch iPhone, 13-inch iPad), the
   public privacy and support pages, and App Review submission.

## Known limits

- "More Minik apps & games" is not on iOS (Android-only module; developer page URL unknown).
- Rate and Share link to the App Store only in builds made by the TestFlight workflow,
  which passes in the app's Apple ID.
- As on Android, native-language editorial review of the course is still recommended.

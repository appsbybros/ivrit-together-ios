import XCTest
@testable import IvritTogether

/// The screen flows of LearningDeviceTest.kt, driven through the model the SwiftUI screens use.
@MainActor
final class LearnViewModelTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let model: LearnViewModel
        let defaults: UserDefaults
        let suite: String

        func reopen() throws -> LearnViewModel {
            LearnViewModel(course: try Course(bundle: Bundle(for: Course.self)), store: LocalStore(defaults: defaults))
        }

        func remove() {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    private func makeFixture(language: String = "en", configure: (UserDefaults) -> Void = { _ in }) throws -> Fixture {
        let suite = "ivrit-together-model-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(language, forKey: "language")
        configure(defaults)
        let course = try Course(bundle: Bundle(for: Course.self))
        return Fixture(model: LearnViewModel(course: course, store: LocalStore(defaults: defaults)), defaults: defaults, suite: suite)
    }

    /// No Check button: a tap checks the answer, a solved question ignores further taps and
    /// waits for Next, and each question is saved once.
    func testAnswersAreCheckedOnTapAndRepeatedTapsCountOnce() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.tab = "journey"
        vm.openLesson("understand")
        vm.beginCurrentLesson()
        for position in 0..<6 {
            let q = try XCTUnwrap(vm.session).question
            vm.next()
            XCTAssertEqual(vm.session?.index, position, "Next needs an answer first")
            if q.kind == .build {
                for index in q.tokens.indices.dropLast() { vm.token(index) }
                // Choosing a word again returns it to the bank.
                vm.token(0)
                XCTAssertFalse(try XCTUnwrap(vm.session).selectedTokens.contains(0))
                vm.token(0)
                XCTAssertEqual(try XCTUnwrap(vm.session).selectedTokens.last, 0)
                XCTAssertFalse(try XCTUnwrap(vm.session).checked, "An unfinished sentence is not checked")
                XCTAssertNil(vm.progress.words[q.phrase.id])
                // Rebuild in reading order after deliberately moving the first word to the end;
                // placing the last word checks the sentence.
                for index in try XCTUnwrap(vm.session).selectedTokens { vm.token(index) }
                XCTAssertTrue(try XCTUnwrap(vm.session).selectedTokens.isEmpty)
                for index in q.tokens.indices { vm.token(index) }
            } else {
                vm.select(q.phrase.id)
            }
            let solved = try XCTUnwrap(vm.session)
            XCTAssertTrue(solved.checked, "The answer is checked without a Check button")
            XCTAssertTrue(solved.correct)
            XCTAssertFalse(solved.wrong)
            XCTAssertEqual(solved.tries, 1)
            XCTAssertEqual(solved.index, position, "Next stays manual")
            XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
            // Further taps on a solved question change nothing and are not saved again.
            if q.kind == .build {
                vm.token(0)
            } else {
                vm.select(q.phrase.id)
                vm.select(try XCTUnwrap(q.choices.first { $0.id != q.phrase.id }).id)
            }
            XCTAssertEqual(vm.session, solved)
            XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
            vm.next()
        }
        XCTAssertNil(vm.session)
        XCTAssertEqual(vm.result?.score, 6)
        XCTAssertTrue(vm.progress.completed.contains("understand"))
        let before = vm.progress
        XCTAssertEqual(try fixture.reopen().progress, before)
    }

    func testMatchingMissesAndCompletes() throws {
        let fixture = try makeFixture(language: "he")
        defer { fixture.remove() }
        let vm = fixture.model
        vm.openLesson("hello")
        vm.toggleSaved("hello-1")
        XCTAssertTrue(vm.progress.saved.contains("hello-1"))
        vm.beginMatch()
        vm.selectMatch("hello-1", left: true)
        vm.selectMatch("hello-2", left: false)
        XCTAssertEqual(vm.match?.miss, true)
        XCTAssertEqual(vm.match?.matched.isEmpty, true)
        // Tapping a chosen item again deselects it.
        vm.selectMatch("hello-3", left: true)
        vm.selectMatch("hello-3", left: true)
        XCTAssertNil(vm.match?.left)
        let items = try XCTUnwrap(vm.match).leftItems
        XCTAssertEqual(items.map(\.id), ["hello-1", "hello-2", "hello-3", "hello-4"])
        XCTAssertEqual(Set(try XCTUnwrap(vm.match).rightItems.map(\.id)), Set(items.map(\.id)))
        for phrase in items {
            vm.selectMatch(phrase.id, left: true)
            vm.selectMatch(phrase.id, left: false)
        }
        XCTAssertEqual(vm.match?.matched.count, 4)
        XCTAssertEqual(vm.match?.complete, true)
        XCTAssertEqual(vm.match?.miss, false)
        // "Practice" after matching starts the lesson's practice.
        vm.abandon()
        vm.beginCurrentLesson()
        XCTAssertNil(vm.match)
        XCTAssertEqual(vm.session?.lessonId, "hello")
        XCTAssertTrue(try fixture.reopen().progress.saved.contains("hello-1"))
    }

    func testOnboardingAndLanguageChoicePersist() throws {
        let fixture = try makeFixture(language: "")
        defer { fixture.remove() }
        let vm = fixture.model
        XCTAssertEqual(vm.language, "")
        XCTAssertEqual(vm.t("start"), "Let’s begin", "Before a choice, texts are English")
        vm.chooseLanguage("uk")
        XCTAssertEqual(vm.language, "uk")
        XCTAssertFalse(vm.isRightToLeft)
        vm.chooseLanguage("ar")
        XCTAssertTrue(vm.isRightToLeft)
        vm.chooseLanguage("xx")
        XCTAssertEqual(vm.language, "ar", "Unknown languages are ignored")
        XCTAssertEqual(fixture.defaults.string(forKey: "language"), "ar")
        XCTAssertEqual(try fixture.reopen().language, "ar")
    }

    func testUnknownSavedLanguageShowsTheWelcomeAgain() throws {
        let fixture = try makeFixture(language: "zz")
        defer { fixture.remove() }
        XCTAssertEqual(fixture.model.language, "")
    }

    func testUnpointedSentenceUsesEverydaySpellingAndStillChecksCorrectly() throws {
        let fixture = try makeFixture(language: "he")
        defer { fixture.remove() }
        let vm = fixture.model
        vm.changeFemale(true)
        vm.changeVowels(false)
        vm.openLesson("messages")
        vm.beginCurrentLesson()
        for _ in 0..<2 {
            vm.select(try XCTUnwrap(vm.session).question.phrase.id)
            vm.next()
        }
        let q = try XCTUnwrap(vm.session).question
        XCTAssertEqual(q.kind, .build)
        XCTAssertEqual(q.phrase.id, "messages-3")
        XCTAssertEqual(vm.hebrew(q.phrase), "אני אחזור אלייך")
        for index in q.tokens.indices { vm.token(index) }
        XCTAssertTrue(try XCTUnwrap(vm.session).correct)
        let reopened = try fixture.reopen()
        XCTAssertTrue(reopened.female)
        XCTAssertFalse(reopened.vowels)
    }

    func testDailyPracticeUsesReviewPhrases() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.begin(nil)
        let session = try XCTUnwrap(vm.session)
        XCTAssertNil(session.lessonId)
        XCTAssertEqual(session.questions.map(\.phrase.id), Array(vm.course.phrases.prefix(10)).map(\.id))
        for _ in session.questions.indices {
            let q = try XCTUnwrap(vm.session).question
            if q.kind == .build {
                for index in q.tokens.indices { vm.token(index) }
            } else {
                vm.select(q.phrase.id)
            }
            vm.next()
        }
        XCTAssertEqual(vm.result?.score, 10)
        XCTAssertTrue(vm.progress.completed.isEmpty, "Daily practice completes no lesson")
        XCTAssertEqual(vm.progress.dailyCount(LocalDay.today()), 5)
        vm.home()
        XCTAssertNil(vm.result)
        XCTAssertEqual(vm.tab, "today")
    }

    func testLeavingKeepsCheckedAnswers() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.openLesson("cafe")
        vm.beginCurrentLesson()
        let q = try XCTUnwrap(vm.session).question
        vm.select(q.phrase.id)
        vm.abandon()
        XCTAssertNil(vm.session)
        XCTAssertEqual(vm.lessonId, "cafe")
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
        XCTAssertFalse(vm.progress.completed.contains("cafe"))
    }

    /// A wrong tap is marked without revealing the right answer and can be corrected, but the
    /// first answer decides the score, the spaced review and the daily goal.
    func testWrongTapIsMarkedWithoutTheAnswerAndCanBeRetried() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.openLesson("cafe")
        vm.beginCurrentLesson()
        let q = try XCTUnwrap(vm.session).question
        XCTAssertEqual(q.kind, .meaning)
        let wrongs = q.choices.filter { $0.id != q.phrase.id }
        XCTAssertEqual(wrongs.count, 3)
        vm.select(wrongs[0].id)
        var s = try XCTUnwrap(vm.session)
        XCTAssertTrue(s.checked, "A wrong tap is checked at once")
        XCTAssertTrue(s.wrong)
        XCTAssertFalse(s.correct, "The right answer is not revealed")
        XCTAssertEqual(s.wrongChoices, [wrongs[0].id])
        XCTAssertEqual(s.score, 0)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.stage, 0)
        // The same wrong option again changes nothing.
        vm.select(wrongs[0].id)
        XCTAssertEqual(vm.session, s)
        // Another wrong option is marked too; still nothing is revealed or saved again.
        vm.select(wrongs[1].id)
        s = try XCTUnwrap(vm.session)
        XCTAssertEqual(s.wrongChoices, [wrongs[0].id, wrongs[1].id])
        XCTAssertEqual(s.tries, 2)
        XCTAssertFalse(s.correct)
        XCTAssertEqual(s.index, 0, "A wrong answer does not move on by itself")
        // The right option is accepted on a retry...
        vm.select(q.phrase.id)
        s = try XCTUnwrap(vm.session)
        XCTAssertTrue(s.correct)
        XCTAssertFalse(s.wrong)
        XCTAssertEqual(s.tries, 3)
        XCTAssertEqual(s.index, 0, "Next stays manual")
        // ...but only the first answer counts: no score, no spaced progress, no daily goal.
        XCTAssertEqual(s.score, 0)
        let word = try XCTUnwrap(vm.progress.words[q.phrase.id])
        XCTAssertEqual(word.attempts, 1)
        XCTAssertEqual(word.correct, 0)
        XCTAssertEqual(word.stage, 0)
        XCTAssertEqual(vm.progress.dailyCount(LocalDay.today()), 0)
        // The solved question is locked.
        vm.select(wrongs[2].id)
        XCTAssertEqual(vm.session, s)
        XCTAssertEqual(try fixture.reopen().progress, vm.progress)
    }

    func testNextAfterAWrongAnswerMovesOnWithoutTheAnswer() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.openLesson("cafe")
        vm.beginCurrentLesson()
        let q = try XCTUnwrap(vm.session).question
        vm.select(try XCTUnwrap(q.choices.first { $0.id != q.phrase.id }).id)
        vm.next()
        let moved = try XCTUnwrap(vm.session)
        XCTAssertEqual(moved.index, 1)
        XCTAssertFalse(moved.checked)
        XCTAssertFalse(moved.wrong)
        XCTAssertNil(moved.selection)
        XCTAssertTrue(moved.wrongChoices.isEmpty)
        XCTAssertEqual(moved.score, 0)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.correct, 0)
    }

    /// Sentence building is checked when the last word is placed; a wrong sentence stays as
    /// built (it is not corrected for the learner) and can be fixed, without scoring.
    func testWrongSentenceIsCheckedWhenCompleteAndCanBeFixed() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.openLesson("messages")
        vm.beginCurrentLesson()
        for _ in 0..<2 {
            vm.select(try XCTUnwrap(vm.session).question.phrase.id)
            vm.next()
        }
        let q = try XCTUnwrap(vm.session).question
        XCTAssertEqual(q.kind, .build)
        XCTAssertEqual(q.tokens.count, 3)
        let reversed = Array(q.tokens.indices.reversed())
        XCTAssertNotEqual(reversed.map { q.tokens[$0] }, q.tokens)
        for index in reversed.dropLast() { vm.token(index) }
        XCTAssertFalse(try XCTUnwrap(vm.session).checked)
        vm.token(try XCTUnwrap(reversed.last))
        var s = try XCTUnwrap(vm.session)
        XCTAssertTrue(s.checked, "Placing the last word checks the sentence")
        XCTAssertTrue(s.wrong)
        XCTAssertFalse(s.correct)
        XCTAssertEqual(s.selectedTokens, reversed, "The words stay where the learner put them")
        XCTAssertEqual(s.score, 2)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.stage, 0)
        // Moving a word back clears the mark; the sentence can then be built again.
        vm.token(reversed[0])
        s = try XCTUnwrap(vm.session)
        XCTAssertFalse(s.wrong)
        XCTAssertEqual(s.tries, 1)
        for index in s.selectedTokens { vm.token(index) }
        XCTAssertTrue(try XCTUnwrap(vm.session).selectedTokens.isEmpty)
        for index in q.tokens.indices { vm.token(index) }
        s = try XCTUnwrap(vm.session)
        XCTAssertTrue(s.correct)
        XCTAssertEqual(s.tries, 2)
        XCTAssertEqual(s.score, 2, "A sentence fixed on a retry does not score")
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.correct, 0)
        vm.token(0)
        XCTAssertEqual(vm.session, s, "A solved sentence is locked")
    }

    func testAnAnswerThatCannotBeSavedIsNotShownAsChecked() throws {
        let fixture = try makeFixture { defaults in
            defaults.set("not valid progress", forKey: "progress")
        }
        defer { fixture.remove() }
        let vm = fixture.model
        vm.error = nil
        vm.openLesson("cafe")
        vm.beginCurrentLesson()
        let q = try XCTUnwrap(vm.session).question
        vm.select(q.phrase.id)
        XCTAssertEqual(vm.error, "save_error")
        XCTAssertFalse(try XCTUnwrap(vm.session).checked)
        XCTAssertNil(vm.progress.words[q.phrase.id])
        vm.next()
        XCTAssertEqual(vm.session?.index, 0)
    }

    func testCorruptStorageWarnsAndIsKeptUntilReset() throws {
        let fixture = try makeFixture { defaults in
            defaults.set("not valid progress", forKey: "progress")
        }
        defer { fixture.remove() }
        let vm = fixture.model
        XCTAssertEqual(vm.error, "storage_error")
        vm.error = nil
        vm.toggleSaved("hello-1")
        XCTAssertEqual(vm.error, "save_error")
        XCTAssertFalse(vm.progress.saved.contains("hello-1"))
        XCTAssertEqual(fixture.defaults.string(forKey: "progress"), "not valid progress")
        vm.reset()
        XCTAssertNil(vm.error)
        vm.toggleSaved("hello-1")
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.progress.saved.contains("hello-1"))
    }

    func testResetClearsProgressButKeepsPreferences() throws {
        let fixture = try makeFixture(language: "fr")
        defer { fixture.remove() }
        let vm = fixture.model
        vm.changeTransliteration(false)
        vm.toggleSaved("hello-2")
        vm.openLesson("hello")
        vm.reset()
        XCTAssertEqual(vm.progress, LearnerProgress())
        XCTAssertNil(vm.lessonId)
        XCTAssertEqual(vm.tab, "today")
        let reopened = try fixture.reopen()
        XCTAssertEqual(reopened.progress, LearnerProgress())
        XCTAssertEqual(reopened.language, "fr")
        XCTAssertFalse(reopened.transliteration)
    }

    func testInterfaceTextFollowsTheChosenLanguage() throws {
        let fixture = try makeFixture(language: "he")
        defer { fixture.remove() }
        let vm = fixture.model
        XCTAssertEqual(vm.t("brand"), "עברית ביחד")
        XCTAssertTrue(vm.isRightToLeft)
        vm.chooseLanguage("de")
        XCTAssertEqual(vm.t("brand"), "Hebräisch gemeinsam")
        XCTAssertFalse(vm.t("privacy_body").contains("Android"))
    }
}

import XCTest
@testable import IvritTogether

/// Answer feedback whose pause the test ends itself: after a right answer the model's move on
/// waits in `pending` until `endPause()`, so no test sleeps.
@MainActor
private final class ManualAnswerFeedback: AnswerFeedback {
    private(set) var announcements: [String] = []
    private(set) var pending: (@MainActor () -> Void)?

    /// A right answer is waiting for the end of its success feedback.
    var waiting: Bool { pending != nil }

    func right(announcement: String, then advance: @escaping @MainActor () -> Void) {
        announcements.append(announcement)
        pending = advance
    }

    func wrong(announcement: String) {
        announcements.append(announcement)
    }

    func cancel() {
        pending = nil
    }

    /// The success feedback has had its time: the model moves on.
    func endPause() {
        let advance = pending
        pending = nil
        advance?()
    }
}

/// The screen flows of LearningDeviceTest.kt, driven through the model the SwiftUI screens use.
@MainActor
final class LearnViewModelTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let model: LearnViewModel
        let feedback: ManualAnswerFeedback
        let defaults: UserDefaults
        let suite: String

        func reopen() throws -> LearnViewModel {
            LearnViewModel(course: try Course(bundle: Bundle(for: Course.self)),
                           store: LocalStore(defaults: defaults),
                           feedback: ManualAnswerFeedback())
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
        let feedback = ManualAnswerFeedback()
        return Fixture(model: LearnViewModel(course: course, store: LocalStore(defaults: defaults), feedback: feedback),
                       feedback: feedback, defaults: defaults, suite: suite)
    }

    /// No Check button and no Next after a right answer: a tap checks the answer, the success
    /// feedback is announced, a solved question ignores further taps and Next, and the next
    /// question follows by itself once the pause ends. Each question is saved once.
    func testRightAnswersAreCheckedOnTapAndMoveOnByThemselves() throws {
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
            XCTAssertFalse(solved.offersNext, "No Next after a right answer")
            XCTAssertEqual(solved.tries, 1)
            XCTAssertEqual(solved.index, position, "The success feedback plays before moving on")
            XCTAssertTrue(fixture.feedback.waiting, "A right answer moves on by itself")
            XCTAssertEqual(fixture.feedback.announcements.last, vm.t("correct"))
            XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
            // Further taps and Next change nothing on a solved question and save nothing again.
            if q.kind == .build {
                vm.token(0)
            } else {
                vm.select(q.phrase.id)
                vm.select(try XCTUnwrap(q.choices.first { $0.id != q.phrase.id }).id)
            }
            vm.next()
            XCTAssertEqual(vm.session, solved)
            XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
            XCTAssertEqual(fixture.feedback.announcements.count, position + 1, "Each answer is announced once")
            fixture.feedback.endPause()
            if position < 5 {
                let moved = try XCTUnwrap(vm.session)
                XCTAssertEqual(moved.index, position + 1, "The next question follows by itself")
                XCTAssertFalse(moved.checked)
            }
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
            fixture.feedback.endPause()
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
            fixture.feedback.endPause()
        }
        XCTAssertEqual(vm.result?.score, 10)
        XCTAssertTrue(vm.progress.completed.isEmpty, "Daily practice completes no lesson")
        XCTAssertEqual(vm.progress.dailyCount(LocalDay.today()), 5)
        vm.home()
        XCTAssertNil(vm.result)
        XCTAssertEqual(vm.tab, "today")
    }

    /// Leaving during the success feedback keeps the saved answer and cancels the move on; a
    /// late move on from the left practice changes nothing in a new one.
    func testLeavingKeepsCheckedAnswers() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.openLesson("cafe")
        vm.beginCurrentLesson()
        let q = try XCTUnwrap(vm.session).question
        vm.select(q.phrase.id)
        XCTAssertTrue(fixture.feedback.waiting)
        let late = fixture.feedback.pending
        vm.abandon()
        XCTAssertFalse(fixture.feedback.waiting, "Leaving cancels the move on")
        XCTAssertNil(vm.session)
        XCTAssertEqual(vm.lessonId, "cafe")
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
        XCTAssertFalse(vm.progress.completed.contains("cafe"))
        vm.beginCurrentLesson()
        let fresh = try XCTUnwrap(vm.session)
        late?()
        XCTAssertEqual(vm.session, fresh)
        XCTAssertNil(vm.result)
    }

    /// A wrong tap is marked without revealing the right answer, offers Next and can be
    /// corrected. The right answer found on a retry plays the success feedback and moves on by
    /// itself, but the first answer decides the score, the spaced review and the daily goal.
    func testWrongTapIsMarkedWithoutTheAnswerAndARetryMovesOnByItself() throws {
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
        XCTAssertTrue(s.offersNext, "Next is offered after a wrong answer")
        XCTAssertEqual(s.wrongChoices, [wrongs[0].id])
        XCTAssertEqual(s.score, 0)
        XCTAssertFalse(fixture.feedback.waiting, "A wrong answer does not move on by itself")
        XCTAssertEqual(fixture.feedback.announcements, [vm.t("try_again")])
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
        XCTAssertTrue(s.offersNext)
        XCTAssertEqual(s.index, 0, "A wrong answer does not move on by itself")
        XCTAssertFalse(fixture.feedback.waiting)
        // The right option is accepted on a retry: Next goes away, the success feedback is
        // announced, and the next question follows by itself...
        vm.select(q.phrase.id)
        s = try XCTUnwrap(vm.session)
        XCTAssertTrue(s.correct)
        XCTAssertFalse(s.wrong)
        XCTAssertFalse(s.offersNext, "No Next once the right answer is found")
        XCTAssertEqual(s.tries, 3)
        XCTAssertEqual(s.index, 0, "The success feedback plays before moving on")
        XCTAssertTrue(fixture.feedback.waiting)
        XCTAssertEqual(fixture.feedback.announcements, [vm.t("try_again"), vm.t("try_again"), vm.t("correct")])
        // ...but only the first answer counts: no score, no spaced progress, no daily goal.
        XCTAssertEqual(s.score, 0)
        let word = try XCTUnwrap(vm.progress.words[q.phrase.id])
        XCTAssertEqual(word.attempts, 1)
        XCTAssertEqual(word.correct, 0)
        XCTAssertEqual(word.stage, 0)
        XCTAssertEqual(vm.progress.dailyCount(LocalDay.today()), 0)
        // The solved question is locked, and Next is not offered.
        vm.select(wrongs[2].id)
        vm.next()
        XCTAssertEqual(vm.session, s)
        fixture.feedback.endPause()
        let moved = try XCTUnwrap(vm.session)
        XCTAssertEqual(moved.index, 1, "The next question follows by itself")
        XCTAssertFalse(moved.checked)
        XCTAssertTrue(moved.wrongChoices.isEmpty)
        XCTAssertEqual(moved.score, 0)
        XCTAssertEqual(try fixture.reopen().progress, vm.progress)
    }

    /// Next is offered only after a wrong answer: not before an answer and not after a right
    /// one. It moves on without showing the answer, and nothing moves on by itself.
    func testNextAfterAWrongAnswerMovesOnWithoutTheAnswer() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.openLesson("cafe")
        vm.beginCurrentLesson()
        let q = try XCTUnwrap(vm.session).question
        XCTAssertFalse(try XCTUnwrap(vm.session).offersNext, "No Next before an answer")
        vm.next()
        XCTAssertEqual(vm.session?.index, 0)
        vm.select(try XCTUnwrap(q.choices.first { $0.id != q.phrase.id }).id)
        XCTAssertTrue(try XCTUnwrap(vm.session).offersNext)
        vm.next()
        let moved = try XCTUnwrap(vm.session)
        XCTAssertEqual(moved.index, 1)
        XCTAssertFalse(moved.checked)
        XCTAssertFalse(moved.wrong)
        XCTAssertFalse(moved.offersNext, "The new question has no Next until it is answered wrongly")
        XCTAssertNil(moved.selection)
        XCTAssertTrue(moved.wrongChoices.isEmpty)
        XCTAssertEqual(moved.score, 0)
        XCTAssertFalse(fixture.feedback.waiting, "Nothing moves on by itself after a wrong answer")
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.correct, 0)
    }

    /// On the last question, Next after a wrong answer finishes the practice; the questions
    /// answered right before it moved on by themselves.
    func testNextOnTheLastQuestionAfterAWrongAnswerFinishes() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let vm = fixture.model
        vm.openLesson("cafe")
        vm.beginCurrentLesson()
        for _ in 0..<5 {
            let q = try XCTUnwrap(vm.session).question
            if q.kind == .build {
                for index in q.tokens.indices { vm.token(index) }
            } else {
                vm.select(q.phrase.id)
            }
            fixture.feedback.endPause()
        }
        let last = try XCTUnwrap(vm.session)
        XCTAssertTrue(last.isLast)
        XCTAssertEqual(last.question.kind, .build)
        XCTAssertEqual(last.question.phrase.id, "cafe-6")
        XCTAssertEqual(last.question.tokens.count, 2)
        // The two words in reverse order make a wrong sentence.
        vm.token(1)
        vm.token(0)
        XCTAssertTrue(try XCTUnwrap(vm.session).wrong)
        XCTAssertTrue(try XCTUnwrap(vm.session).offersNext)
        XCTAssertFalse(fixture.feedback.waiting)
        vm.next()
        XCTAssertNil(vm.session)
        XCTAssertEqual(vm.result?.score, 5)
        XCTAssertTrue(vm.progress.completed.contains("cafe"))
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
            fixture.feedback.endPause()
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
        XCTAssertTrue(s.offersNext, "Next is offered after a wrong sentence")
        XCTAssertFalse(fixture.feedback.waiting)
        XCTAssertEqual(fixture.feedback.announcements.last, vm.t("try_again"))
        XCTAssertEqual(s.selectedTokens, reversed, "The words stay where the learner put them")
        XCTAssertEqual(s.score, 2)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.stage, 0)
        // Moving a word back clears the mark (Next stays); the sentence can then be built again.
        vm.token(reversed[0])
        s = try XCTUnwrap(vm.session)
        XCTAssertFalse(s.wrong)
        XCTAssertTrue(s.offersNext)
        XCTAssertEqual(s.tries, 1)
        for index in s.selectedTokens { vm.token(index) }
        XCTAssertTrue(try XCTUnwrap(vm.session).selectedTokens.isEmpty)
        for index in q.tokens.indices { vm.token(index) }
        s = try XCTUnwrap(vm.session)
        XCTAssertTrue(s.correct)
        XCTAssertFalse(s.offersNext, "No Next once the sentence is right")
        XCTAssertEqual(s.tries, 2)
        XCTAssertEqual(s.score, 2, "A sentence fixed on a retry does not score")
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.attempts, 1)
        XCTAssertEqual(vm.progress.words[q.phrase.id]?.correct, 0)
        XCTAssertEqual(fixture.feedback.announcements.last, vm.t("correct"))
        vm.token(0)
        vm.next()
        XCTAssertEqual(vm.session, s, "A solved sentence is locked")
        // The fixed sentence moves on by itself, like a right first answer.
        fixture.feedback.endPause()
        XCTAssertEqual(vm.session?.index, 3)
        XCTAssertEqual(vm.session?.checked, false)
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
        XCTAssertFalse(fixture.feedback.waiting, "An unsaved answer does not move on")
        XCTAssertTrue(fixture.feedback.announcements.isEmpty, "An unsaved answer is not announced")
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

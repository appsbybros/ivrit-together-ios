import XCTest
@testable import IvritTogether

/// Port of app/src/test/.../LearningTest.kt, plus checks of the iOS date and review helpers.
final class LearningTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 8)

    func testWrongAnswerReturnsSoonAndIsNotMastery() {
        let p = LearnerProgress().answer(attemptId: "a", phraseId: "word", correct: false, now: 1000, date: day)
        XCTAssertEqual(p.words["word"]?.stage, 0)
        XCTAssertEqual(p.words["word"]?.due, 1_201_000)
    }

    func testRepeatedTapIsIdempotent() {
        let p = LearnerProgress().answer(attemptId: "a", phraseId: "word", correct: true, now: 1000, date: day)
        XCTAssertEqual(p, p.answer(attemptId: "a", phraseId: "word", correct: true, now: 1001, date: day))
    }

    func testEarlyRepeatDoesNotAdvanceSpacedMastery() {
        let p = LearnerProgress().answer(attemptId: "a", phraseId: "word", correct: true, now: 1000, date: day)
        let q = p.answer(attemptId: "b", phraseId: "word", correct: true, now: 2000, date: day)
        XCTAssertEqual(q.words["word"]?.stage, 1)
        XCTAssertEqual(p.words["word"]?.due, q.words["word"]?.due)
    }

    func testDueReviewAdvancesAndWrongResets() {
        let p = LearnerProgress().answer(attemptId: "a", phraseId: "word", correct: true, now: 1000, date: day)
        let q = p.answer(attemptId: "b", phraseId: "word", correct: true, now: 86_401_001, date: day.plusDays(1))
        XCTAssertEqual(q.words["word"]?.stage, 2)
        let r = q.answer(attemptId: "c", phraseId: "word", correct: false, now: 86_402_000, date: day.plusDays(1))
        XCTAssertEqual(r.words["word"]?.stage, 0)
    }

    func testStreakAllowsTodayNotYetPractised() {
        let p = LearnerProgress(days: [day.minusDays(1).iso, day.minusDays(2).iso])
        XCTAssertEqual(p.streak(day), 2)
        XCTAssertEqual(p.streak(day.plusDays(1)), 0)
    }

    func testStripVowelsKeepsLettersAndPunctuation() {
        XCTAssertEqual(plainHebrew("שָׁלוֹם!"), "שלום!")
        XCTAssertEqual(plainHebrew("תֵּל־אָבִיב"), "תל־אביב")
    }

    func testUnpointedSpellingIsIndependentOfPointedSpelling() {
        let p = Phrase(id: "p",
                       lessonId: "l",
                       hebrew: "אֶחְזֹר אֵלֶיךָ",
                       transliteration: "echzor elecha",
                       meanings: ["en": "I will return to you"],
                       feminine: "אֶחְזֹר אֵלַיִךְ",
                       unpointed: "אחזור אליך",
                       feminineUnpointed: "אחזור אלייך")
        XCTAssertEqual(p.withoutVowels(false), "אחזור אליך")
        XCTAssertEqual(p.withoutVowels(true), "אחזור אלייך")
        XCTAssertNotEqual(plainHebrew(p.text(false)), p.withoutVowels(false))
    }

    func testRepeatedWordsRemainSeparateTokens() {
        let p = Phrase(id: "p", lessonId: "l", hebrew: "טוב טוב", transliteration: "tov tov", meanings: ["en": "very good"])
        let q = Question(phrase: p, kind: .build, choices: [p], tokens: ["טוב", "טוב"], tokenOrder: [1, 0])
        // The Kotlin assertion, on an answer [1, 0] that is not checked yet: removing token 1
        // returns only that word, not the equal word at index 0.
        var unchecked = Session(questions: [q])
        unchecked.selectedTokens = [1, 0]
        XCTAssertEqual(unchecked.toggleToken(1).selectedTokens, [0])
        // iOS checks the sentence as soon as its last word is placed (Android on Check), so in
        // the tapped flow a word is removed before the sentence is complete.
        let s = Session(questions: [q]).toggleToken(1)
        XCTAssertEqual(s.selectedTokens, [1], "Only the tapped word moves, not every equal word")
        XCTAssertEqual(s.toggleToken(1).selectedTokens, [], "Tapping a chosen word returns just that word")
        XCTAssertFalse(s.checked)
        let built = s.toggleToken(0)
        XCTAssertEqual(built.selectedTokens, [1, 0])
        XCTAssertTrue(built.correct, "Equal words may stand in either order")
        XCTAssertTrue(built.submit().correct)
    }

    func testSessionContainsOnlyDistinctAnswers() {
        let ps = (0...5).map { index in
            Phrase(id: "\(index)", lessonId: "l", hebrew: "מילה \(index)", transliteration: "", meanings: ["en": "meaning \(index)"])
        }
        let s = makeSession(items: ps, all: ps, female: false, language: "en", seed: 3)
        XCTAssertEqual(s.questions.count, 6)
        for q in s.questions {
            XCTAssertEqual(q.choices.count, 4)
            XCTAssertEqual(q.choices.filter { $0.id == q.phrase.id }.count, 1)
        }
    }

    // iOS-specific checks of the helpers the port relies on.

    func testIntervalsMatchAndroid() {
        XCTAssertEqual(LearnerProgress.intervals, [1_200_000, 86_400_000, 259_200_000, 604_800_000, 1_209_600_000, 2_592_000_000])
    }

    func testStageStopsAtFive() {
        var p = LearnerProgress()
        var now: Int64 = 0
        for attempt in 0..<8 {
            p = p.answer(attemptId: "a\(attempt)", phraseId: "word", correct: true, now: now, date: day)
            now = (p.words["word"]?.due ?? 0) + 1
        }
        XCTAssertEqual(p.words["word"]?.stage, 5)
        XCTAssertEqual(p.words["word"]?.attempts, 8)
        XCTAssertEqual(p.words["word"]?.correct, 8)
    }

    func testLocalDayFormatsAndMovesLikeLocalDate() {
        XCTAssertEqual(day.iso, "2026-10-08")
        XCTAssertEqual(LocalDay(year: 2028, month: 2, day: 28).plusDays(1).iso, "2028-02-29")
        XCTAssertEqual(LocalDay(year: 2026, month: 12, day: 31).plusDays(1).iso, "2027-01-01")
        XCTAssertEqual(LocalDay(year: 2026, month: 3, day: 1).minusDays(1).iso, "2026-02-28")
        XCTAssertTrue(day < day.plusDays(1))
    }

    func testTodayIsAGregorianDateWhateverTheDeviceCalendar() {
        let noon = Date(timeIntervalSince1970: 1_791_460_800) // 2026-10-08 12:00 UTC
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        XCTAssertEqual(LocalDay.today(now: noon, timeZone: utc).iso, "2026-10-08")
        let kiritimati = TimeZone(secondsFromGMT: 14 * 3600) ?? .current
        XCTAssertEqual(LocalDay.today(now: noon, timeZone: kiritimati).iso, "2026-10-09")
    }

    func testReviewListsDuePhrasesFirstThenNewOnes() {
        let items = ["a", "b", "c", "d"].map { id in
            Phrase(id: id, lessonId: "l", hebrew: "א", transliteration: "", meanings: ["en": id])
        }
        var p = LearnerProgress()
        p.words["b"] = WordProgress(stage: 1, due: 100, last: 0, attempts: 1, correct: 1)
        p.words["c"] = WordProgress(stage: 1, due: 50, last: 0, attempts: 1, correct: 1)
        p.words["d"] = WordProgress(stage: 1, due: 9_999, last: 0, attempts: 1, correct: 1)
        XCTAssertEqual(p.review(items, now: 200).map(\.id), ["c", "b", "a"])
        XCTAssertEqual(p.review(items, now: 200, limit: 2).map(\.id), ["c", "b"])
    }

    func testQuestionKindsFollowTheAndroidPattern() {
        let ps = (0...5).map { index in
            Phrase(id: "\(index)", lessonId: "l", hebrew: "מילה מספר \(index)", transliteration: "", meanings: ["en": "meaning \(index)"])
        }
        let s = makeSession(items: ps, all: ps, female: false, language: "en", seed: 11)
        XCTAssertEqual(s.questions.map(\.kind), [.meaning, .listen, .build, .meaning, .listen, .build])
        let single = [Phrase(id: "x", lessonId: "l", hebrew: "שלום", transliteration: "", meanings: ["en": "hello"])]
        let three = single + Array(ps.prefix(2))
        XCTAssertEqual(makeSession(items: three, all: ps + single, female: false, language: "en", seed: 1).questions.map(\.kind),
                       [.meaning, .listen, .build])
        let wordLast = Array(ps.prefix(2)) + single
        XCTAssertEqual(makeSession(items: wordLast, all: ps + single, female: false, language: "en", seed: 1).questions.map(\.kind),
                       [.meaning, .listen, .meaning], "A one-word phrase is never a sentence to build")
    }

    func testWordBankNeverStartsSolved() {
        let p = Phrase(id: "p", lessonId: "l", hebrew: "אני לומד עברית", transliteration: "", meanings: ["en": "I learn Hebrew"])
        for seed in UInt64(0)..<200 {
            let q = makeSession(items: [p, p, p], all: [p], female: false, language: "en", seed: seed).questions[2]
            XCTAssertEqual(q.kind, .build)
            XCTAssertNotEqual(q.tokenOrder, [0, 1, 2])
            XCTAssertEqual(q.tokenOrder.sorted(), [0, 1, 2])
        }
    }

    func testPlainHebrewDecomposesPresentationForms() {
        // U+FB2A is SHIN WITH SHIN DOT; Android normalises to NFD before removing the dot.
        XCTAssertEqual(plainHebrew("\u{FB2A}לום"), "שלום")
        XCTAssertEqual(plainHebrew("abc 123"), "abc 123")
    }

    func testSearchMatchingIgnoresCaseAndAcceptsEmptyText() {
        XCTAssertTrue(containsIgnoringCase("Good Morning", "morning"))
        XCTAssertTrue(containsIgnoringCase("Доброе утро", "УТРО"))
        XCTAssertTrue(containsIgnoringCase("anything", ""))
        XCTAssertFalse(containsIgnoringCase("shalom", "boker"))
    }

    // The iOS answer flow (owner QA ISSUE-001): checked on the tap, retry after a wrong answer,
    // Next offered only after a wrong answer (a right one moves on by itself in the view model),
    // and only the first check scores.

    private func choiceSession() -> Session {
        let ps = (0...3).map { index in
            Phrase(id: "\(index)", lessonId: "l", hebrew: "מילה \(index)", transliteration: "", meanings: ["en": "meaning \(index)"])
        }
        let q = Question(phrase: ps[0], kind: .meaning, choices: ps, tokens: ["מילה", "0"], tokenOrder: [1, 0])
        return Session(questions: [q, q])
    }

    func testChoosingAnOptionChecksItAtOnce() {
        let fresh = choiceSession()
        XCTAssertFalse(fresh.checked)
        XCTAssertFalse(fresh.offersNext, "No Next before an answer")
        XCTAssertEqual(fresh.submit(), fresh, "Nothing is checked before an option is chosen")
        let s = fresh.choose("0")
        XCTAssertTrue(s.checked)
        XCTAssertTrue(s.correct)
        XCTAssertFalse(s.wrong)
        XCTAssertFalse(s.offersNext, "No Next after a right answer")
        XCTAssertEqual(s.selection, "0")
        XCTAssertEqual(s.tries, 1)
        XCTAssertEqual(s.score, 1)
        XCTAssertEqual(s.index, 0, "The session stays until the view model moves on")
        XCTAssertEqual(s.choose("1"), s, "A solved question is locked")
        XCTAssertEqual(s.toggleToken(0), s, "Words belong to sentence questions only")
        let next = s.next()
        XCTAssertEqual(next.index, 1)
        XCTAssertFalse(next.checked)
        XCTAssertFalse(next.correct)
        XCTAssertFalse(next.offersNext)
        XCTAssertNil(next.selection)
        XCTAssertEqual(next.tries, 0)
        XCTAssertEqual(next.score, 1)
    }

    func testWrongChoiceIsMarkedAndOnlyTheFirstTryScores() {
        var s = choiceSession().choose("2")
        XCTAssertTrue(s.checked)
        XCTAssertTrue(s.wrong)
        XCTAssertFalse(s.correct)
        XCTAssertTrue(s.offersNext, "Next after a wrong answer")
        XCTAssertEqual(s.wrongChoices, ["2"])
        XCTAssertEqual(s.score, 0)
        XCTAssertEqual(s.choose("2"), s, "An option found wrong is not checked again")
        XCTAssertEqual(s.choose("9"), s, "Only the question's options can be chosen")
        s = s.choose("3")
        XCTAssertEqual(s.wrongChoices, ["2", "3"])
        XCTAssertEqual(s.tries, 2)
        XCTAssertTrue(s.wrong)
        XCTAssertTrue(s.offersNext)
        s = s.choose("0")
        XCTAssertTrue(s.correct)
        XCTAssertFalse(s.wrong)
        XCTAssertFalse(s.offersNext, "No Next once the right answer is found")
        XCTAssertEqual(s.tries, 3)
        XCTAssertEqual(s.score, 0, "Only a right first answer scores")
        XCTAssertEqual(s.wrongChoices, ["2", "3"], "Options found wrong stay marked")
        let next = s.next()
        XCTAssertTrue(next.wrongChoices.isEmpty)
        XCTAssertFalse(next.wrong)
        XCTAssertEqual(next.choose("0").score, 1)
    }

    func testSentenceIsCheckedWhenItsLastWordIsPlacedAndCanBeFixed() {
        let p = Phrase(id: "p", lessonId: "l", hebrew: "אני לומד עברית", transliteration: "", meanings: ["en": "I learn Hebrew"])
        let q = Question(phrase: p, kind: .build, choices: [p], tokens: ["אני", "לומד", "עברית"], tokenOrder: [2, 0, 1])
        var s = Session(questions: [q]).toggleToken(1).toggleToken(0)
        XCTAssertFalse(s.checked, "An unfinished sentence is not checked")
        XCTAssertFalse(s.offersNext)
        XCTAssertEqual(s.submit(), s)
        XCTAssertEqual(s.choose("p"), s, "A sentence question has no options to choose")
        s = s.toggleToken(2)
        XCTAssertEqual(s.selectedTokens, [1, 0, 2])
        XCTAssertTrue(s.checked)
        XCTAssertTrue(s.wrong)
        XCTAssertFalse(s.correct)
        XCTAssertTrue(s.offersNext, "Next after a wrong sentence")
        XCTAssertEqual(s.tries, 1)
        XCTAssertEqual(s.submit(), s, "An unchanged wrong sentence is not checked again")
        s = s.toggleToken(1).toggleToken(2)
        XCTAssertEqual(s.selectedTokens, [0])
        XCTAssertFalse(s.wrong, "Moving a word clears the wrong mark")
        XCTAssertTrue(s.offersNext, "Next stays while the sentence is fixed")
        XCTAssertEqual(s.tries, 1)
        s = s.toggleToken(1).toggleToken(2)
        XCTAssertTrue(s.correct)
        XCTAssertFalse(s.offersNext, "No Next once the sentence is right")
        XCTAssertEqual(s.tries, 2)
        XCTAssertEqual(s.score, 0, "A sentence fixed on a retry does not score")
        XCTAssertEqual(s.toggleToken(0), s, "A solved sentence is locked")
    }
}

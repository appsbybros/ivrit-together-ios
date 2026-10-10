import XCTest
@testable import IvritTogether

/// Port of app/src/test/.../DailyGoalTest.kt, plus the history limits Android applies.
final class DailyGoalTests: XCTestCase {
    func testDailyGoalUsesDifferentCorrectPhrasesAndResetsByDate() {
        let d = LocalDay(year: 2026, month: 10, day: 9)
        var p = LearnerProgress()
        p = p.answer(attemptId: "a", phraseId: "one", correct: true, now: 0, date: d)
            .answer(attemptId: "b", phraseId: "one", correct: true, now: 1, date: d)
            .answer(attemptId: "c", phraseId: "two", correct: false, now: 2, date: d)
        XCTAssertEqual(p.dailyCount(d), 1)
        XCTAssertEqual(p.dailyCount(d.plusDays(1)), 0)
        for index in 0..<10 {
            p = p.answer(attemptId: "x\(index)", phraseId: "phrase\(index)", correct: true, now: 3 + Int64(index), date: d)
        }
        XCTAssertEqual(p.dailyCount(d), 5)
        XCTAssertEqual(p, p.answer(attemptId: "a", phraseId: "different", correct: true, now: 100, date: d))
    }

    func testDailyHistoryKeepsTheLatestSixtyDays() {
        let first = LocalDay(year: 2026, month: 1, day: 1)
        var p = LearnerProgress()
        for offset in 0..<70 {
            p = p.answer(attemptId: "d\(offset)", phraseId: "word", correct: true, now: Int64(offset), date: first.plusDays(offset))
        }
        XCTAssertEqual(p.dailyPhrases.count, 60)
        XCTAssertNil(p.dailyPhrases[first.iso])
        XCTAssertNil(p.dailyPhrases[first.plusDays(9).iso])
        XCTAssertEqual(p.dailyCount(first.plusDays(10)), 1)
        XCTAssertEqual(p.dailyCount(first.plusDays(69)), 1)
        XCTAssertEqual(p.days.count, 70, "Practice days for the streak are not trimmed")
    }

    func testAnsweredAttemptsKeepTheLatestSixHundred() {
        let d = LocalDay(year: 2026, month: 10, day: 9)
        var p = LearnerProgress()
        for index in 0..<605 {
            p = p.answer(attemptId: "attempt-\(index)", phraseId: "word", correct: false, now: Int64(index), date: d)
        }
        XCTAssertEqual(p.answered.count, 600)
        XCTAssertEqual(p.answered.first, "attempt-5")
        XCTAssertEqual(p.answered.last, "attempt-604")
        XCTAssertEqual(p.words["word"]?.attempts, 605)
    }

    func testWrongAnswersDoNotCountTowardsTheGoal() {
        let d = LocalDay(year: 2026, month: 10, day: 9)
        var p = LearnerProgress()
        for index in 0..<5 {
            p = p.answer(attemptId: "w\(index)", phraseId: "phrase\(index)", correct: false, now: Int64(index), date: d)
        }
        XCTAssertEqual(p.dailyCount(d), 0)
        XCTAssertTrue(p.days.contains(d.iso), "A practice day counts for the streak even without a correct answer")
    }
}

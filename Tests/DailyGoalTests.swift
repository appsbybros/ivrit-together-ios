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
        XCTAssertEqual(p.dailyPoints(d), 0)
    }

    /// iOS: the goal counts points, two for a phrase answered right first time and one for a
    /// phrase found after another try; each phrase counts once a day with its best result.
    func testDailyPointsGiveOnePointForAPhraseFoundAfterAnotherTry() {
        let d = LocalDay(year: 2026, month: 10, day: 9)
        XCTAssertEqual(LearnerProgress.dailyGoalPoints, 10)
        var p = LearnerProgress()
            .answer(attemptId: "a", phraseId: "one", correct: false, now: 0, date: d)
            .retried(phraseId: "one", date: d)
        XCTAssertEqual(p.dailyPoints(d), 1)
        XCTAssertEqual(p.dailyCount(d), 0, "Android's count of phrases right first time")
        XCTAssertEqual(p.words["one"]?.stage, 0, "The wrong first answer still decides the review")
        XCTAssertEqual(p.retried(phraseId: "one", date: d), p, "A phrase counts once a day")
        p = p.answer(attemptId: "b", phraseId: "one", correct: true, now: 1, date: d)
        XCTAssertEqual(p.dailyPoints(d), 2, "Right first time later that day: its best result, not both")
        p = p.answer(attemptId: "c", phraseId: "two", correct: true, now: 2, date: d)
        XCTAssertEqual(p.dailyPoints(d), 4)
        XCTAssertEqual(p.dailyPoints(d.plusDays(1)), 0, "Points start again every day")
        for index in 0..<10 {
            p = p.answer(attemptId: "w\(index)", phraseId: "phrase\(index)", correct: false, now: 3 + Int64(index), date: d)
                .retried(phraseId: "phrase\(index)", date: d)
        }
        XCTAssertEqual(p.dailyPoints(d), LearnerProgress.dailyGoalPoints, "The total stops at the goal")
    }

    func testRetriedHistoryKeepsTheLatestSixtyDays() {
        let first = LocalDay(year: 2026, month: 1, day: 1)
        var p = LearnerProgress()
        for offset in 0..<70 {
            p = p.retried(phraseId: "word", date: first.plusDays(offset))
        }
        XCTAssertEqual(p.dailyRetried.count, 60)
        XCTAssertNil(p.dailyRetried[first.plusDays(9).iso])
        XCTAssertEqual(p.dailyPoints(first.plusDays(10)), 1)
        XCTAssertEqual(p.dailyPoints(first.plusDays(69)), 1)
    }
}

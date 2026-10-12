import XCTest
@testable import IvritTogether

/// Progress storage, the daily goal and corrupt-data protection (ports of the storage checks
/// in LearningDeviceTest.kt). Each test uses its own UserDefaults suite.
final class LocalStoreTests: XCTestCase {
    private var suites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = "ivrit-together-tests-\(UUID().uuidString)"
        suites.append(name)
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Could not create the test defaults suite")
        }
        return defaults
    }

    override func tearDown() {
        for name in suites {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        suites.removeAll()
        super.tearDown()
    }

    private let day = LocalDay(year: 2026, month: 10, day: 9)

    func testDefaultsMatchAndroid() {
        let store = LocalStore(defaults: makeDefaults())
        XCTAssertEqual(store.language, "")
        XCTAssertFalse(store.female)
        XCTAssertTrue(store.transliteration)
        XCTAssertTrue(store.vowels)
        XCTAssertEqual(store.load(), LearnerProgress())
        XCTAssertFalse(store.loadFailed)
    }

    func testPreferencesPersist() {
        let defaults = makeDefaults()
        let store = LocalStore(defaults: defaults)
        store.language = "he"
        store.female = true
        store.transliteration = false
        store.vowels = false
        let reopened = LocalStore(defaults: defaults)
        XCTAssertEqual(reopened.language, "he")
        XCTAssertTrue(reopened.female)
        XCTAssertFalse(reopened.transliteration)
        XCTAssertFalse(reopened.vowels)
    }

    func testProgressRoundTripKeepsEveryField() {
        let defaults = makeDefaults()
        var progress = LearnerProgress()
        progress = progress.answer(attemptId: "s:0", phraseId: "hello-1", correct: true, now: 1_000, date: day)
        progress = progress.answer(attemptId: "s:1", phraseId: "hello-2", correct: false, now: 2_000, date: day)
        progress = progress.answer(attemptId: "s:2", phraseId: "hello-1", correct: true, now: 90_000_000, date: day.plusDays(1))
        progress.completed = ["hello", "cafe"]
        progress.saved = ["hello-1"]
        XCTAssertTrue(LocalStore(defaults: defaults).save(progress))
        let loaded = LocalStore(defaults: defaults).load()
        XCTAssertEqual(loaded, progress)
        XCTAssertEqual(loaded.answered, ["s:0", "s:1", "s:2"], "Attempt order survives saving")
    }

    func testDailyGoalIsDistinctSavedAndRestored() {
        let defaults = makeDefaults()
        let today = LocalDay.today()
        var progress = LearnerProgress()
        for index in 0..<5 {
            progress = progress.answer(attemptId: "daily-\(index)", phraseId: "hello-\(index + 1)", correct: true,
                                       now: currentMillis(), date: today)
        }
        progress = progress.answer(attemptId: "repeat", phraseId: "hello-1", correct: true, now: currentMillis(), date: today)
        XCTAssertEqual(progress.dailyCount(today), 5)
        let store = LocalStore(defaults: defaults)
        XCTAssertTrue(store.save(progress))
        XCTAssertEqual(store.load(), progress)
        XCTAssertEqual(LocalStore(defaults: defaults).load().dailyCount(today), 5)
    }

    func testCorruptProgressIsPreservedUntilExplicitReset() {
        let defaults = makeDefaults()
        defaults.set("not valid progress", forKey: "progress")
        let store = LocalStore(defaults: defaults)
        XCTAssertEqual(store.load(), LearnerProgress())
        XCTAssertTrue(store.loadFailed)
        XCTAssertFalse(store.save(LearnerProgress()))
        XCTAssertEqual(defaults.string(forKey: "progress"), "not valid progress")
        XCTAssertTrue(store.reset())
        XCTAssertNil(defaults.string(forKey: "progress"))
        XCTAssertTrue(store.save(LearnerProgress()))
    }

    func testInvalidWordProgressIsTreatedAsCorrupt() {
        let defaults = makeDefaults()
        defaults.set(#"{"version":1,"words":{"w":{"stage":7,"due":0,"last":0,"attempts":1,"correct":1}}}"#, forKey: "progress")
        let store = LocalStore(defaults: defaults)
        XCTAssertEqual(store.load(), LearnerProgress())
        XCTAssertTrue(store.loadFailed)

        let other = makeDefaults()
        other.set(#"{"version":1,"words":{"w":{"stage":1,"due":0,"last":0,"attempts":1,"correct":2}}}"#, forKey: "progress")
        let second = LocalStore(defaults: other)
        _ = second.load()
        XCTAssertTrue(second.loadFailed)

        let future = makeDefaults()
        future.set(#"{"version":2,"words":{}}"#, forKey: "progress")
        let third = LocalStore(defaults: future)
        _ = third.load()
        XCTAssertTrue(third.loadFailed)
    }

    func testReadsProgressWrittenByAndroid() {
        // The shape LocalStore.save writes on Android (org.json, insertion order).
        let android = #"{"dailyPhrases":{"2026-10-09":["hello-1"]},"version":1,"words":{"hello-1":{"stage":1,"due":86401000,"last":1000,"attempts":1,"correct":1}},"completed":["hello"],"saved":["hello-1","cafe-2"],"days":["2026-10-09"],"answered":["abc:0"]}"#
        let defaults = makeDefaults()
        defaults.set(android, forKey: "progress")
        let store = LocalStore(defaults: defaults)
        let progress = store.load()
        XCTAssertFalse(store.loadFailed)
        XCTAssertEqual(progress.words["hello-1"], WordProgress(stage: 1, due: 86_401_000, last: 1_000, attempts: 1, correct: 1))
        XCTAssertEqual(progress.completed, ["hello"])
        XCTAssertEqual(progress.saved, ["hello-1", "cafe-2"])
        XCTAssertEqual(progress.days, ["2026-10-09"])
        XCTAssertEqual(progress.answered, ["abc:0"])
        XCTAssertEqual(progress.dailyCount(day), 1)
    }

    /// iOS adds dailyRetried, only once there is a phrase found after another try.
    func testPointsFoundAfterAnotherTryAreSavedAndRestored() throws {
        let defaults = makeDefaults()
        let progress = LearnerProgress()
            .answer(attemptId: "a", phraseId: "hello-1", correct: false, now: 1, date: day)
            .retried(phraseId: "hello-1", date: day)
        XCTAssertTrue(LocalStore(defaults: defaults).save(progress))
        let loaded = LocalStore(defaults: defaults).load()
        XCTAssertEqual(loaded, progress)
        XCTAssertEqual(loaded.dailyPoints(day), 1)
        let text = try ProgressCodec.encode(progress)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(object["dailyRetried"] as? [String: [String]], [day.iso: ["hello-1"]])
    }

    func testOptionalListsMayBeMissing() throws {
        let progress = try ProgressCodec.decode(#"{"version":1,"words":{}}"#)
        XCTAssertEqual(progress, LearnerProgress())
    }

    func testSavedJSONUsesTheAndroidFieldNames() throws {
        let progress = LearnerProgress().answer(attemptId: "a", phraseId: "word", correct: true, now: 5, date: day)
        let text = try ProgressCodec.encode(progress)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["dailyPhrases", "version", "words", "completed", "saved", "days", "answered"])
        XCTAssertEqual(object["version"] as? Int, 1)
        let words = try XCTUnwrap(object["words"] as? [String: Any])
        let word = try XCTUnwrap(words["word"] as? [String: Any])
        XCTAssertEqual(Set(word.keys), ["stage", "due", "last", "attempts", "correct"])
    }
}

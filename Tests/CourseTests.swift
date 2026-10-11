import XCTest
@testable import IvritTogether

/// course.json and ui.json load from the app bundle, are complete in all ten languages, and
/// every lesson is solvable (port of the content checks in LearningDeviceTest.kt).
final class CourseTests: XCTestCase {
    private let codes = ["en", "ru", "uk", "fr", "es", "pt", "ar", "am", "de", "he"]

    /// Every interface key the iOS screens read (Sources/*.swift), including keys chosen at
    /// runtime: navigation labels, exercise headings, feedback and error messages. Android's
    /// "check", "continue" and "not_yet" are not read: iOS checks answers on the tap.
    private let keysUsedByTheApp: [String] = [
        "about", "again", "all", "all_topics", "alphabet", "back", "brand", "build", "build_hint",
        "cancel", "choose_language", "choose_meaning", "close", "complete",
        "continue_lesson", "correct", "daily_body", "daily_goal", "daily_goal_done", "daily_practice",
        "daily_title", "days", "delete", "empty", "everyday", "feminine", "finish", "forms", "forms_help",
        "home", "incorrect", "journey", "language", "learn", "learned", "leave", "leave_body", "letters_hint",
        "listen", "listen_choose", "masculine", "match", "match_hint", "match_miss", "matched", "next",
        "no_external_app", "ok", "practice", "previous", "privacy", "privacy_body", "rate_app",
        "reset", "reset_confirm", "result_tip", "review_due", "save", "save_error", "saved", "score",
        "search", "send_feedback", "settings", "share_app", "show_meaning", "show_text", "slow",
        "sound_hint", "start", "storage_error", "tab_words", "today", "transliteration", "try_again",
        "unsave", "up_to_date", "voice_missing", "voice_settings", "vowels", "welcome", "welcome_body",
        "well_done", "words", "your_answer"
    ]

    /// The texts only the iOS screens use (Resources/ui-ios.json).
    private let iosOnlyKeys: Set<String> = ["incorrect", "try_again"]

    private var bundle: Bundle { Bundle(for: Course.self) }

    private func loadCourse() throws -> Course {
        try Course(bundle: bundle)
    }

    private func rawInterfaceTexts() throws -> [String: [String: String]] {
        let url = try XCTUnwrap(bundle.url(forResource: "ui", withExtension: "json"))
        return try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
    }

    func testCourseLoadsWithTheAndroidContent() throws {
        let course = try loadCourse()
        XCTAssertEqual(course.lessons.count, 18)
        XCTAssertEqual(course.phrases.count, 108)
        XCTAssertEqual(course.alphabet.count, 22)
        XCTAssertEqual(course.alphabet.filter { $0.letter.contains(" ") }.count, 5, "Five letters show their final form")
        XCTAssertEqual(Set(course.phrases.map(\.id)).count, 108, "Phrase ids are unique")
        XCTAssertEqual(Set(course.lessons.map(\.id)).count, 18, "Lesson ids are unique")
        for lesson in course.lessons {
            XCTAssertEqual(lesson.phrases.count, 6, lesson.id)
            XCTAssertTrue(lesson.phrases.allSatisfy { $0.lessonId == lesson.id }, lesson.id)
        }
        XCTAssertEqual(course.lessons.first?.id, "hello")
        XCTAssertEqual(course.lessons.last?.id, "messages")
    }

    func testLanguageListMatchesAndroid() {
        XCTAssertEqual(Language.all.map(\.code), codes)
        XCTAssertEqual(Language.all.filter(\.rtl).map(\.code), ["ar", "he"])
        XCTAssertEqual(Language.all.map(\.name),
                       ["English", "Русский", "Українська", "Français", "Español", "Português", "العربية", "አማርኛ", "Deutsch", "עברית"])
    }

    func testEveryPhraseAndTitleHasAllTenLanguages() throws {
        let course = try loadCourse()
        for lesson in course.lessons {
            for code in codes {
                XCTAssertFalse(lesson.title(code).trimmingCharacters(in: .whitespaces).isEmpty, "\(lesson.id) title \(code)")
            }
        }
        for phrase in course.phrases {
            for code in codes {
                XCTAssertFalse(phrase.meaning(code).trimmingCharacters(in: .whitespaces).isEmpty, "\(phrase.id) meaning \(code)")
            }
            XCTAssertFalse(phrase.hebrew.isEmpty, phrase.id)
            XCTAssertFalse(phrase.transliteration.isEmpty, phrase.id)
            XCTAssertEqual(phrase.feminine == nil, phrase.feminineTransliteration == nil, phrase.id)
        }
    }

    func testEveryInterfaceKeyExistsInAllTenLanguages() throws {
        let texts = try rawInterfaceTexts()
        XCTAssertEqual(Set(texts.keys), Set(codes))
        let allKeys = texts.values.reduce(into: Set<String>()) { keys, values in keys.formUnion(values.keys) }
        XCTAssertEqual(allKeys.count, 88)
        for code in codes {
            let values = try XCTUnwrap(texts[code], code)
            XCTAssertEqual(Set(values.keys), allKeys, "Missing keys in \(code): \(allKeys.subtracting(values.keys).sorted())")
            for (key, value) in values {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(code).\(key) is empty")
            }
        }
    }

    func testEveryKeyTheAppReadsExistsInAllTenLanguages() throws {
        let course = try loadCourse()
        for code in codes {
            for key in keysUsedByTheApp {
                XCTAssertNotNil(course.interfaceTexts[code]?[key], "\(code).\(key)")
                XCTAssertNotEqual(course.text(code, key), key, "\(code).\(key) falls back to its key")
            }
        }
    }

    func testIOSOnlyTextsAreCompleteAndLeaveAndroidTextsAlone() throws {
        let url = try XCTUnwrap(bundle.url(forResource: "ui-ios", withExtension: "json"))
        let added = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
        let android = try rawInterfaceTexts()
        let course = try loadCourse()
        XCTAssertEqual(Set(added.keys), Set(codes))
        for code in codes {
            let values = try XCTUnwrap(added[code], code)
            XCTAssertEqual(Set(values.keys), iosOnlyKeys, code)
            for (key, value) in values {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(code).\(key) is empty")
                XCTAssertNil(android[code]?[key], "\(code).\(key) is now in Android's ui.json; remove it from ui-ios.json")
                XCTAssertEqual(course.text(code, key), value, "\(code).\(key)")
            }
        }
        XCTAssertTrue(iosOnlyKeys.isSubset(of: Set(keysUsedByTheApp)))
    }

    func testIOSWordingOnlyRenamesThePlatform() throws {
        let raw = try rawInterfaceTexts()
        let course = try loadCourse()
        for code in codes {
            for (key, value) in raw[code] ?? [:] {
                let shown = course.text(code, key)
                XCTAssertFalse(shown.contains("Android"), "\(code).\(key) names Android on iOS")
                if key == "privacy_body" {
                    XCTAssertTrue(value.contains("Android"), "\(code): Android's privacy note changed; review PlatformWording")
                    XCTAssertTrue(shown.contains("iCloud"), code)
                    XCTAssertEqual(shown, value.replacingOccurrences(of: "Android", with: "iCloud"), code)
                } else {
                    XCTAssertEqual(shown, value, "\(code).\(key) must stay identical to Android")
                }
            }
        }
    }

    func testEveryLessonHasSolvableExercisesInBothFormsAndAllLanguages() throws {
        let course = try loadCourse()
        for language in Language.all {
            for female in [false, true] {
                for lesson in course.lessons {
                    let session = makeSession(items: lesson.phrases, all: course.phrases, female: female,
                                              language: language.code, lessonId: lesson.id, seed: 42)
                    XCTAssertEqual(session.questions.count, 6)
                    for (index, q) in session.questions.enumerated() {
                        let label = "\(language.code)/\(lesson.id)/\(index)/\(female)"
                        let unpointed: [Substring] = q.phrase.withoutVowels(female)
                            .split(separator: " ", omittingEmptySubsequences: false)
                        XCTAssertEqual(q.tokens.count, unpointed.count, label)
                        XCTAssertEqual(q.phrase.withoutVowels(female), plainHebrew(q.phrase.withoutVowels(female)), label)
                        XCTAssertEqual(q.choices.count, 4, label)
                        XCTAssertEqual(Set(q.choices.map { $0.meaning(language.code) }).count, 4, label)
                        var answered = session
                        answered.index = index
                        answered.selection = q.phrase.id
                        answered.selectedTokens = Array(q.tokens.indices)
                        XCTAssertTrue(answered.submit().correct, label)
                    }
                }
            }
        }
    }

    func testFeminineFormsHaveTheirOwnEverydaySpelling() throws {
        let course = try loadCourse()
        let messages = try XCTUnwrap(course.lesson("messages"))
        let returnCall = try XCTUnwrap(messages.phrases.first { $0.id == "messages-3" })
        let words: [Substring] = returnCall.withoutVowels(true).split(separator: " ")
        XCTAssertTrue(words.contains("אחזור"))
        XCTAssertTrue(words.contains("אלייך"))
        XCTAssertNotEqual(returnCall.text(true), returnCall.text(false))
    }
}

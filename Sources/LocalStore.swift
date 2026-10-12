import Foundation

// Port of LocalStore (Data.kt). Android keeps everything in the SharedPreferences file
// "ivrit-together": language, female, transliteration, vowels and "progress", a JSON string
// with version 1, words, completed, saved, days, answered and dailyPhrases. iOS keeps the
// same keys and the same JSON in the UserDefaults suite "ivrit-together", plus dailyRetried
// (phrases answered right after another try, by day) once there is one: Android has no second
// try, and older progress without it loads as before.

final class LocalStore {
    static let preferenceName = "ivrit-together"

    let defaults: UserDefaults
    /// Set when saved progress cannot be read. Saving is then refused, so the unreadable data
    /// is preserved until the learner deliberately resets progress.
    private(set) var loadFailed = false

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: LocalStore.preferenceName) ?? .standard
    }

    var language: String {
        get { defaults.string(forKey: Keys.language) ?? "" }
        set { defaults.set(newValue, forKey: Keys.language) }
    }

    var female: Bool {
        get { (defaults.object(forKey: Keys.female) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Keys.female) }
    }

    var transliteration: Bool {
        get { (defaults.object(forKey: Keys.transliteration) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Keys.transliteration) }
    }

    var vowels: Bool {
        get { (defaults.object(forKey: Keys.vowels) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Keys.vowels) }
    }

    func load() -> LearnerProgress {
        guard let raw = defaults.string(forKey: Keys.progress) else { return LearnerProgress() }
        do {
            return try ProgressCodec.decode(raw)
        } catch {
            loadFailed = true
            return LearnerProgress()
        }
    }

    func save(_ progress: LearnerProgress) -> Bool {
        if loadFailed { return false }
        guard let text = try? ProgressCodec.encode(progress) else { return false }
        defaults.set(text, forKey: Keys.progress)
        return true
    }

    func reset() -> Bool {
        defaults.removeObject(forKey: Keys.progress)
        loadFailed = false
        return true
    }

    enum Keys {
        static let language = "language"
        static let female = "female"
        static let transliteration = "transliteration"
        static let vowels = "vowels"
        static let progress = "progress"
    }
}

/// The Android progress JSON, field for field.
enum ProgressCodec {
    enum Failure: Error {
        case unsupportedVersion
        case invalidWord
        case notText
    }

    struct StoredWord: Codable, Equatable {
        var stage: Int
        var due: Int64
        var last: Int64
        var attempts: Int
        var correct: Int
    }

    struct Stored: Codable {
        var dailyPhrases: [String: [String]]?
        var version: Int
        var words: [String: StoredWord]
        var completed: [String]?
        var saved: [String]?
        var days: [String]?
        var answered: [String]?
        /// iOS only; left out while empty, so the JSON stays Android's until then.
        var dailyRetried: [String: [String]]?
    }

    static func decode(_ text: String) throws -> LearnerProgress {
        let stored = try JSONDecoder().decode(Stored.self, from: Data(text.utf8))
        guard stored.version == 1 else { throw Failure.unsupportedVersion }
        var words: [String: WordProgress] = [:]
        for (id, word) in stored.words {
            guard word.stage >= 0, word.stage <= 5,
                  word.attempts >= 0, word.correct >= 0, word.correct <= word.attempts else {
                throw Failure.invalidWord
            }
            words[id] = WordProgress(stage: word.stage, due: word.due, last: word.last,
                                     attempts: word.attempts, correct: word.correct)
        }
        var daily: [String: Set<String>] = [:]
        for (day, ids) in stored.dailyPhrases ?? [:] {
            daily[day] = Set(ids)
        }
        var retried: [String: Set<String>] = [:]
        for (day, ids) in stored.dailyRetried ?? [:] {
            retried[day] = Set(ids)
        }
        return LearnerProgress(words: words,
                               completed: Set(stored.completed ?? []),
                               saved: Set(stored.saved ?? []),
                               days: Set(stored.days ?? []),
                               answered: unique(stored.answered ?? []),
                               dailyPhrases: daily,
                               dailyRetried: retried)
    }

    static func encode(_ progress: LearnerProgress) throws -> String {
        var words: [String: StoredWord] = [:]
        for (id, word) in progress.words {
            words[id] = StoredWord(stage: word.stage, due: word.due, last: word.last,
                                   attempts: word.attempts, correct: word.correct)
        }
        var daily: [String: [String]] = [:]
        for (day, ids) in progress.dailyPhrases {
            daily[day] = ids.sorted()
        }
        var retried: [String: [String]] = [:]
        for (day, ids) in progress.dailyRetried {
            retried[day] = ids.sorted()
        }
        let stored = Stored(dailyPhrases: daily,
                            version: 1,
                            words: words,
                            completed: progress.completed.sorted(),
                            saved: progress.saved.sorted(),
                            days: progress.days.sorted(),
                            answered: progress.answered,
                            dailyRetried: retried.isEmpty ? nil : retried)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(stored)
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.notText }
        return text
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}

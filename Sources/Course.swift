import Foundation

// Port of Course (Data.kt): course.json and ui.json are the Android files, copied unchanged
// and read at runtime, so lessons, meanings and interface texts stay identical.

enum CourseError: Error, CustomStringConvertible {
    case missingResource(String)

    var description: String {
        switch self {
        case .missingResource(let name):
            return "\(name) is missing from the app bundle"
        }
    }
}

final class Course {
    let lessons: [Lesson]
    let phrases: [Phrase]
    let alphabet: [Letter]
    /// ui.json by language and key, with iOS wording where Android names its own platform.
    let interfaceTexts: [String: [String: String]]

    init(bundle: Bundle = .main) throws {
        let file = try Course.read(CourseFile.self, named: "course", in: bundle)
        let texts = try Course.read([String: [String: String]].self, named: "ui", in: bundle)
        let builtLessons: [Lesson] = file.lessons.map { entry in
            Lesson(id: entry.id, titles: entry.titles, phrases: entry.phrases.map { item in
                Phrase(id: item.id,
                       lessonId: entry.id,
                       hebrew: item.he,
                       transliteration: item.translit,
                       meanings: item.meanings,
                       feminine: Course.nonBlank(item.female),
                       feminineTransliteration: Course.nonBlank(item.femaleTranslit),
                       unpointed: item.plain,
                       feminineUnpointed: Course.nonBlank(item.femalePlain))
            })
        }
        lessons = builtLessons
        phrases = builtLessons.flatMap { $0.phrases }
        alphabet = file.alphabet.map { Letter(letter: $0.letter, name: $0.name, sound: $0.sound) }
        var adapted: [String: [String: String]] = [:]
        for (language, values) in texts {
            var localized: [String: String] = [:]
            for (key, value) in values {
                localized[key] = PlatformWording.adapt(key: key, value: value)
            }
            adapted[language] = localized
        }
        interfaceTexts = adapted
    }

    /// Android throws for a missing key; every key is checked by the unit tests, so this
    /// fallback (the key itself, never English) only shows a development mistake.
    func text(_ language: String, _ key: String) -> String {
        interfaceTexts[language]?[key] ?? key
    }

    func lesson(_ id: String?) -> Lesson? {
        guard let id = id else { return nil }
        return lessons.first { $0.id == id }
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func read<T: Decodable>(_ type: T.Type, named name: String, in bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CourseError.missingResource("\(name).json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
}

/// ui.json is shared unchanged with Android. Its privacy note says that Android backups may
/// include progress; on iPhone and iPad the same sentence names iCloud backups, which include
/// this app's preferences and progress. Apple's guidelines also keep other platforms' names
/// out of iOS apps. Every language writes the platform as the Latin word "Android".
enum PlatformWording {
    static let adaptedKeys: Set<String> = ["privacy_body"]

    static func adapt(key: String, value: String) -> String {
        guard adaptedKeys.contains(key) else { return value }
        return value.replacingOccurrences(of: "Android", with: "iCloud")
    }
}

private struct CourseFile: Decodable {
    struct PhraseEntry: Decodable {
        let id: String
        let he: String
        let translit: String
        let meanings: [String: String]
        let plain: String
        let female: String?
        let femaleTranslit: String?
        let femalePlain: String?
    }

    struct LessonEntry: Decodable {
        let id: String
        let titles: [String: String]
        let phrases: [PhraseEntry]
    }

    struct LetterEntry: Decodable {
        let letter: String
        let name: String
        let sound: String
    }

    let lessons: [LessonEntry]
    let alphabet: [LetterEntry]
}

import Foundation

// Port of Learning.kt: languages, phrases, spaced review, daily goal, practice sessions.

struct Language: Equatable, Identifiable, Sendable {
    let code: String
    let name: String
    let rtl: Bool

    var id: String { code }

    init(_ code: String, _ name: String, rtl: Bool = false) {
        self.code = code
        self.name = name
        self.rtl = rtl
    }

    /// The ten interface and meaning languages, in the Android order.
    static let all: [Language] = [
        Language("en", "English"),
        Language("ru", "Русский"),
        Language("uk", "Українська"),
        Language("fr", "Français"),
        Language("es", "Español"),
        Language("pt", "Português"),
        Language("ar", "العربية", rtl: true),
        Language("am", "አማርኛ"),
        Language("de", "Deutsch"),
        Language("he", "עברית", rtl: true)
    ]

    static func isSupported(_ code: String) -> Bool {
        all.contains { $0.code == code }
    }

    static func isRightToLeft(_ code: String) -> Bool {
        all.first { $0.code == code }?.rtl == true
    }
}

struct Phrase: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let lessonId: String
    let hebrew: String
    let transliteration: String
    let meanings: [String: String]
    let feminine: String?
    let feminineTransliteration: String?
    let unpointed: String
    let feminineUnpointed: String?

    init(id: String,
         lessonId: String,
         hebrew: String,
         transliteration: String,
         meanings: [String: String],
         feminine: String? = nil,
         feminineTransliteration: String? = nil,
         unpointed: String? = nil,
         feminineUnpointed: String? = nil) {
        self.id = id
        self.lessonId = lessonId
        self.hebrew = hebrew
        self.transliteration = transliteration
        self.meanings = meanings
        self.feminine = feminine
        self.feminineTransliteration = feminineTransliteration
        self.unpointed = unpointed ?? plainHebrew(hebrew)
        self.feminineUnpointed = feminineUnpointed
    }

    func text(_ female: Bool) -> String {
        female ? (feminine ?? hebrew) : hebrew
    }

    func sound(_ female: Bool) -> String {
        female ? (feminineTransliteration ?? transliteration) : transliteration
    }

    func withoutVowels(_ female: Bool) -> String {
        female ? (feminineUnpointed ?? unpointed) : unpointed
    }

    func meaning(_ language: String) -> String {
        meanings[language] ?? ""
    }
}

struct Lesson: Equatable, Identifiable, Sendable {
    let id: String
    let titles: [String: String]
    let phrases: [Phrase]

    func title(_ language: String) -> String {
        titles[language] ?? ""
    }
}

struct Letter: Equatable, Identifiable, Sendable {
    let letter: String
    let name: String
    let sound: String

    var id: String { letter }
}

struct WordProgress: Equatable, Sendable {
    var stage: Int = 0
    var due: Int64 = 0
    var last: Int64 = 0
    var attempts: Int = 0
    var correct: Int = 0
}

/// A calendar day in the Gregorian (ISO) calendar, like java.time.LocalDate. Its text is
/// "yyyy-MM-dd", the key Android stores, whatever calendar the device displays.
struct LocalDay: Equatable, Hashable, Comparable, CustomStringConvertible, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static func today(now: Date = Date(), timeZone: TimeZone = .current) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return LocalDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    func plusDays(_ count: Int) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              let moved = calendar.date(byAdding: .day, value: count, to: start) else {
            return self
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        return LocalDay(year: parts.year ?? year, month: parts.month ?? month, day: parts.day ?? day)
    }

    func minusDays(_ count: Int) -> LocalDay {
        plusDays(-count)
    }

    var iso: String {
        "\(LocalDay.padded(year, 4))-\(LocalDay.padded(month, 2))-\(LocalDay.padded(day, 2))"
    }

    var description: String { iso }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

/// Android's Progress: spaced review, completed lessons, saved phrases, practice days and
/// the daily goal. `answered` keeps insertion order, like Kotlin's LinkedHashSet, so the
/// oldest attempt ids are the ones dropped beyond 600.
struct LearnerProgress: Equatable, Sendable {
    var words: [String: WordProgress] = [:]
    var completed: Set<String> = []
    var saved: Set<String> = []
    var days: Set<String> = []
    var answered: [String] = []
    var dailyPhrases: [String: Set<String>] = [:]

    static let intervals: [Int64] = [
        20 * 60_000,
        86_400_000,
        3 * 86_400_000,
        7 * 86_400_000,
        14 * 86_400_000,
        30 * 86_400_000
    ]
    static let dailyGoal = 5
    static let keptDays = 60
    static let keptAttempts = 600

    func dailyCount(_ date: LocalDay) -> Int {
        min(dailyPhrases[date.iso]?.count ?? 0, LearnerProgress.dailyGoal)
    }

    func answer(attemptId: String, phraseId: String, correct: Bool, now: Int64, date: LocalDay) -> LearnerProgress {
        if answered.contains(attemptId) { return self }
        let previous = words[phraseId] ?? WordProgress()
        // Early repeats can improve recall, but cannot manufacture spaced mastery.
        let nextStage: Int
        if !correct {
            nextStage = 0
        } else if previous.attempts == 0 || now >= previous.due {
            nextStage = min(previous.stage + 1, 5)
        } else {
            nextStage = previous.stage
        }
        let nextDue: Int64
        if correct && previous.attempts > 0 && now < previous.due {
            nextDue = previous.due
        } else {
            nextDue = now + LearnerProgress.intervals[min(max(nextStage, 0), 5)]
        }
        var daily = dailyPhrases
        if correct {
            daily[date.iso, default: []].insert(phraseId)
        }
        var kept: [String: Set<String>] = [:]
        for key in daily.keys.sorted().suffix(LearnerProgress.keptDays) {
            kept[key] = daily[key]
        }
        var next = self
        next.dailyPhrases = kept
        next.words[phraseId] = WordProgress(
            stage: nextStage,
            due: nextDue,
            last: now,
            attempts: previous.attempts + 1,
            correct: previous.correct + (correct ? 1 : 0)
        )
        next.days.insert(date.iso)
        next.answered.append(attemptId)
        if next.answered.count > LearnerProgress.keptAttempts {
            next.answered.removeFirst(next.answered.count - LearnerProgress.keptAttempts)
        }
        return next
    }

    func streak(_ today: LocalDay) -> Int {
        var day = days.contains(today.iso) ? today : today.minusDays(1)
        var count = 0
        while days.contains(day.iso) {
            count += 1
            day = day.minusDays(1)
        }
        return count
    }

    func review(_ items: [Phrase], now: Int64, limit: Int = 10) -> [Phrase] {
        let due = items
            .filter { item in
                guard let word = words[item.id] else { return false }
                return word.due <= now
            }
            .sorted { (words[$0.id]?.due ?? 0) < (words[$1.id]?.due ?? 0) }
        let fresh = items.filter { words[$0.id] == nil }
        return Array((due + fresh).prefix(limit))
    }
}

enum Exercise: Equatable, Sendable {
    case meaning
    case listen
    case build
}

struct Question: Equatable, Sendable {
    let phrase: Phrase
    let kind: Exercise
    let choices: [Phrase]
    let tokens: [String]
    let tokenOrder: [Int]
}

/// A practice session. iOS checks every answer as soon as it is given (owner QA ISSUE-001;
/// Android checks with a Check button): a chosen option at once, a built sentence when its
/// last word is placed. A right answer locks the question, and the view model moves on by
/// itself after the success feedback. A wrong one is marked without showing the right answer,
/// and the learner may try again or move on with Next. Only the first check of a question
/// counts: it alone scores, and the view model saves it alone to the spaced review and the
/// daily goal.
struct Session: Equatable, Sendable {
    var id: String = UUID().uuidString.lowercased()
    var lessonId: String? = nil
    var questions: [Question]
    var index: Int = 0
    /// The option chosen last (meaning and listening questions).
    var selection: String? = nil
    var selectedTokens: [Int] = []
    /// This question's options already chosen and found wrong, in the order they were tried.
    var wrongChoices: [String] = []
    /// How many answers to this question have been checked.
    var tries: Int = 0
    /// The last checked answer is right: the question is solved and locked until the view
    /// model moves on.
    var correct: Bool = false
    /// The last checked answer is wrong and still unchanged (moving a word clears it).
    var wrong: Bool = false
    var score: Int = 0

    var question: Question { questions[index] }
    var attemptId: String { "\(id):\(index)" }
    var isLast: Bool { index == questions.count - 1 }
    /// The first answer to this question has been checked (and saved).
    var checked: Bool { tries > 0 }
    /// A wrong answer has been checked and the question is not solved: Next lets the learner
    /// move on without being shown the answer. A right answer moves on by itself, so it never
    /// offers Next.
    var offersNext: Bool { checked && !correct }
    /// Every word of the sentence is in the answer.
    var sentenceComplete: Bool { selectedTokens.count == question.tokens.count }

    /// Chooses an option and checks it at once. Ignored once the question is solved, for an
    /// option already found wrong, for an id that is not one of the choices, and in a
    /// sentence question.
    func choose(_ choice: String) -> Session {
        if correct || question.kind == .build || wrongChoices.contains(choice) { return self }
        if !question.choices.contains(where: { $0.id == choice }) { return self }
        var updated = self
        updated.selection = choice
        return updated.submit()
    }

    /// Puts a word into the answer, or a chosen word back into the word bank. Placing the
    /// last word checks the sentence at once; after a wrong sentence the words can be moved
    /// and the sentence built again. A solved sentence is locked.
    func toggleToken(_ token: Int) -> Session {
        if correct || question.kind != .build || !question.tokens.indices.contains(token) { return self }
        var updated = self
        if let position = selectedTokens.firstIndex(of: token) {
            updated.selectedTokens.remove(at: position)
        } else {
            updated.selectedTokens.append(token)
        }
        updated.wrong = false
        if updated.sentenceComplete {
            return updated.submit()
        }
        return updated
    }

    /// Checks the current answer: the chosen option, or the sentence once all its words are
    /// placed. Nothing is checked twice: a solved question, an option already found wrong and
    /// a wrong sentence that has not been changed are ignored. Only a right first check
    /// scores.
    func submit() -> Session {
        if correct { return self }
        let current = question
        var updated = self
        let ok: Bool
        if current.kind == .build {
            if wrong || !sentenceComplete { return self }
            ok = selectedTokens.map { current.tokens[$0] } == current.tokens
        } else {
            guard let chosen = selection, !wrongChoices.contains(chosen) else { return self }
            ok = chosen == current.phrase.id
            if !ok {
                updated.wrongChoices.append(chosen)
            }
        }
        updated.tries = tries + 1
        updated.correct = ok
        updated.wrong = !ok
        if ok && tries == 0 {
            updated.score = score + 1
        }
        return updated
    }

    func next() -> Session {
        var updated = self
        updated.index = index + 1
        updated.selection = nil
        updated.selectedTokens = []
        updated.wrongChoices = []
        updated.tries = 0
        updated.correct = false
        updated.wrong = false
        return updated
    }
}

struct MatchState: Equatable, Sendable {
    var leftItems: [Phrase]
    var rightItems: [Phrase]
    var left: String? = nil
    var right: String? = nil
    var matched: Set<String> = []
    var miss: Bool = false

    var complete: Bool { matched.count == leftItems.count }
}

/// Removes Hebrew points and cantillation (U+0591-U+05C7) after canonical decomposition,
/// keeping maqaf, paseq, sof pasuq and nun hafukha, exactly like Android's plainHebrew.
func plainHebrew(_ text: String) -> String {
    let kept: [UInt32] = [0x05BE, 0x05C0, 0x05C3, 0x05C6]
    var scalars = String.UnicodeScalarView()
    for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
        let value = scalar.value
        if value >= 0x0591 && value <= 0x05C7 && !kept.contains(value) {
            continue
        }
        scalars.append(scalar)
    }
    return String(scalars)
}

/// Milliseconds since 1970, like System.currentTimeMillis().
func currentMillis(_ date: Date = Date()) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
}

/// Kotlin's contains(other, ignoreCase = true): an empty search always matches.
func containsIgnoringCase(_ text: String, _ part: String) -> Bool {
    part.isEmpty || text.range(of: part, options: .caseInsensitive) != nil
}

/// A small deterministic generator (SplitMix64) for reproducible sessions in tests.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var mixed: UInt64 = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// Every third question builds the sentence (when it has more than one word), every
/// third listens, the rest choose the meaning; three distinct distractors per question.
func makeSession(items: [Phrase],
                 all: [Phrase],
                 female: Bool,
                 language: String,
                 lessonId: String? = nil,
                 seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) -> Session {
    precondition(!items.isEmpty, "A session needs at least one phrase")
    var random = SeededRandom(seed: seed)
    var questions: [Question] = []
    for (position, phrase) in items.enumerated() {
        let parts: [Substring] = phrase.text(female).split(separator: " ")
        let tokens: [String] = parts
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let kind: Exercise
        if position % 3 == 2 && tokens.count > 1 {
            kind = .build
        } else if position % 3 == 1 {
            kind = .listen
        } else {
            kind = .meaning
        }
        let meaning = phrase.meaning(language)
        let plain = plainHebrew(phrase.text(female))
        var seenMeanings = Set<String>()
        var candidates: [Phrase] = []
        for other in all where other.id != phrase.id
            && other.meaning(language) != meaning
            && plainHebrew(other.text(female)) != plain {
            if seenMeanings.insert(other.meaning(language)).inserted {
                candidates.append(other)
            }
        }
        let others: [Phrase] = Array(candidates.shuffled(using: &random).prefix(3))
        let natural: [Int] = Array(tokens.indices)
        var order: [Int] = natural.shuffled(using: &random)
        if order == natural && tokens.count > 1 {
            order = Array(order.dropFirst()) + [order[0]]
        }
        let choices: [Phrase] = (others + [phrase]).shuffled(using: &random)
        questions.append(Question(phrase: phrase, kind: kind, choices: choices, tokens: tokens, tokenOrder: order))
    }
    return Session(lessonId: lessonId, questions: questions)
}

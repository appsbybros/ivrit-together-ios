import Combine
import Foundation

// Port of LearnViewModel.kt. Saving is synchronous on iOS (UserDefaults), so `busy` is only
// set while a save runs; the same guards still make repeated taps harmless.

@MainActor
final class LearnViewModel: ObservableObject {
    let course: Course
    private let store: LocalStore

    @Published private(set) var language: String
    @Published private(set) var female: Bool
    @Published private(set) var transliteration: Bool
    @Published private(set) var vowels: Bool
    @Published private(set) var progress: LearnerProgress
    @Published var error: String? = nil
    @Published var tab: String = "today"
    @Published var lessonId: String? = nil
    @Published var learning: Bool = false
    @Published var cardIndex: Int = 0
    @Published private(set) var session: Session? = nil
    @Published private(set) var result: Session? = nil
    @Published private(set) var match: MatchState? = nil
    @Published private(set) var busy: Bool = false

    init(course: Course, store: LocalStore) {
        self.course = course
        self.store = store
        let savedLanguage = store.language
        language = Language.isSupported(savedLanguage) ? savedLanguage : ""
        female = store.female
        transliteration = store.transliteration
        vowels = store.vowels
        progress = store.load()
        if store.loadFailed {
            error = "storage_error"
        }
    }

    convenience init() {
        let course: Course
        do {
            course = try Course()
        } catch {
            fatalError("The bundled course could not be read: \(error)")
        }
        self.init(course: course, store: LocalStore())
    }

    var isRightToLeft: Bool { Language.isRightToLeft(language) }

    var currentLesson: Lesson? { course.lesson(lessonId) }

    func t(_ key: String) -> String {
        course.text(language.isEmpty ? "en" : language, key)
    }

    func hebrew(_ phrase: Phrase) -> String {
        vowels ? phrase.text(female) : phrase.withoutVowels(female)
    }

    func chooseLanguage(_ code: String) {
        guard Language.isSupported(code) else { return }
        language = code
        store.language = code
    }

    func changeFemale(_ value: Bool) {
        female = value
        store.female = value
    }

    func changeTransliteration(_ value: Bool) {
        transliteration = value
        store.transliteration = value
    }

    func changeVowels(_ value: Bool) {
        vowels = value
        store.vowels = value
    }

    func openLesson(_ id: String) {
        lessonId = id
        learning = false
        cardIndex = 0
        result = nil
    }

    /// A lesson's phrases, or with nil the daily review (due phrases first, then new ones).
    func begin(_ id: String?) {
        let items: [Phrase]
        if let id = id {
            guard let lesson = course.lesson(id) else { return }
            items = lesson.phrases
        } else {
            items = progress.review(course.phrases, now: currentMillis())
        }
        if items.isEmpty { return }
        result = nil
        match = nil
        learning = false
        session = makeSession(items: items, all: course.phrases, female: female, language: language, lessonId: id)
    }

    /// Android's begin() with its default argument, the open lesson.
    func beginCurrentLesson() {
        begin(lessonId)
    }

    func select(_ id: String) {
        guard var current = session, !current.checked else { return }
        current.selection = id
        session = current
    }

    func token(_ index: Int) {
        guard let current = session else { return }
        session = current.toggleToken(index)
    }

    func submit() {
        guard let current = session, !current.checked, !busy else { return }
        if current.question.kind != .build && current.selection == nil { return }
        if current.question.kind == .build && current.selectedTokens.isEmpty { return }
        let checked = current.submit()
        let next = progress.answer(attemptId: current.attemptId,
                                   phraseId: current.question.phrase.id,
                                   correct: checked.correct,
                                   now: currentMillis(),
                                   date: LocalDay.today())
        update(next) {
            if session?.attemptId == current.attemptId {
                session = checked
            }
        }
    }

    func next() {
        guard let current = session, current.checked, !busy else { return }
        if current.isLast {
            var finished = progress
            if let lesson = current.lessonId {
                finished.completed.insert(lesson)
            }
            update(finished) {
                if session?.attemptId == current.attemptId {
                    result = current
                    session = nil
                }
            }
        } else {
            session = current.next()
        }
    }

    func abandon() {
        session = nil
        match = nil
        result = nil
        learning = false
    }

    func home() {
        abandon()
        lessonId = nil
        tab = "today"
    }

    func toggleSaved(_ id: String) {
        guard !busy else { return }
        var next = progress
        if next.saved.contains(id) {
            next.saved.remove(id)
        } else {
            next.saved.insert(id)
        }
        update(next)
    }

    func reset() {
        guard !busy else { return }
        busy = true
        if store.reset() {
            progress = LearnerProgress()
            error = nil
            home()
        } else {
            error = "save_error"
        }
        busy = false
    }

    func beginMatch() {
        guard let lesson = currentLesson else { return }
        let items = Array(lesson.phrases.prefix(4))
        match = MatchState(leftItems: items, rightItems: items.shuffled())
    }

    func selectMatch(_ id: String, left: Bool) {
        guard let current = match, !current.matched.contains(id) else { return }
        var next = current
        next.miss = false
        if left {
            next.left = current.left == id ? nil : id
        } else {
            next.right = current.right == id ? nil : id
        }
        if let chosenLeft = next.left, let chosenRight = next.right {
            if chosenLeft == chosenRight {
                next.matched.insert(id)
            } else {
                next.miss = true
            }
            next.left = nil
            next.right = nil
        }
        match = next
    }

    @discardableResult
    private func update(_ next: LearnerProgress, after: () -> Void = {}) -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        guard store.save(next) else {
            error = "save_error"
            return false
        }
        progress = next
        after()
        return true
    }
}

import Combine
import Foundation

// Port of LearnViewModel.kt. Saving is synchronous on iOS (UserDefaults), so `busy` is only
// set while a save runs; the same guards still make repeated taps harmless. Unlike Android, a
// right answer moves on by itself after its success feedback (owner QA ISSUE-001), Next is
// offered only after a wrong answer, and a right answer after another try earns one point
// (two first time; see Points).

@MainActor
final class LearnViewModel: ObservableObject {
    let course: Course
    private let store: LocalStore
    /// VoiceOver's announcements and the pause before a right answer moves on.
    private let feedback: AnswerFeedback

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

    init(course: Course, store: LocalStore, feedback: AnswerFeedback) {
        self.course = course
        self.store = store
        self.feedback = feedback
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
        self.init(course: course, store: LocalStore(), feedback: LiveAnswerFeedback())
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

    /// Choosing an option checks it at once; there is no Check button (Session.choose).
    func select(_ id: String) {
        guard let current = session, !busy else { return }
        show(current.choose(id), replacing: current)
    }

    /// Placing or removing a word; placing the last word checks the sentence at once
    /// (Session.toggleToken).
    func token(_ index: Int) {
        guard let current = session, !busy else { return }
        show(current.toggleToken(index), replacing: current)
    }

    /// Next, offered only after a wrong answer: moves on without revealing the right answer. A
    /// right answer moves on by itself (moveOn).
    func next() {
        guard let current = session, current.offersNext, !busy else { return }
        advance(from: current)
    }

    /// The next question, or on the last one the result (saving the lesson as completed).
    private func advance(from current: Session) {
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
        feedback.cancel()
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

    /// Shows the session after a tap. The first checked answer of a question is saved before
    /// it is shown, as Android's submit() does: it alone decides the spaced review (a phrase
    /// found only on a later try is not known yet and comes back soon) and, when right, gives
    /// the phrase two points toward the daily goal. A right answer after another try is saved
    /// as one point toward the goal. Other taps change the screen only. If saving fails, the
    /// tap is not applied and the error is shown.
    private func show(_ updated: Session, replacing current: Session) {
        if updated == current { return }
        let phraseId = current.question.phrase.id
        let next: LearnerProgress
        if !current.checked && updated.checked {
            next = progress.answer(attemptId: current.attemptId,
                                   phraseId: phraseId,
                                   correct: updated.correct,
                                   now: currentMillis(),
                                   date: LocalDay.today())
        } else if current.checked && !current.correct && updated.correct {
            next = progress.retried(phraseId: phraseId, date: LocalDay.today())
        } else {
            present(updated, replacing: current)
            return
        }
        update(next) {
            if session?.attemptId == current.attemptId {
                present(updated, replacing: current)
            }
        }
    }

    /// Puts the session on screen. Every newly checked answer is announced; a right one then
    /// moves on by itself after its success feedback, a wrong one waits for another try or Next.
    private func present(_ updated: Session, replacing current: Session) {
        session = updated
        guard updated.tries > current.tries else { return }
        if updated.correct {
            let attemptId = updated.attemptId
            feedback.right(announcement: t("correct")) { [weak self] in
                self?.moveOn(after: attemptId)
            }
        } else {
            feedback.wrong(announcement: t("try_again"))
        }
    }

    /// The move on after a right answer, unless the learner has left the practice meanwhile.
    private func moveOn(after attemptId: String) {
        guard let current = session, current.attemptId == attemptId, current.correct else { return }
        advance(from: current)
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

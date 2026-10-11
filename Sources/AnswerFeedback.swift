import UIKit

// What a checked practice answer does beyond the screen (owner QA ISSUE-001): VoiceOver hears
// whether it is right, and a right answer moves on by itself once its success feedback has
// played. PracticeView plays that feedback (the green mark, the bounce, the chime and the
// success haptic); this file decides when the next question comes.

/// A VoiceOver announcement, queued after what VoiceOver is saying (such as the tapped
/// option's new state) so that it is not cut off; Android uses a polite live region.
@MainActor
func announceForVoiceOver(_ text: String) {
    let announcement = NSAttributedString(string: text,
                                          attributes: [.accessibilitySpeechQueueAnnouncement: true])
    UIAccessibility.post(notification: .announcement, argument: announcement)
}

/// The answer feedback the model uses. Tests replace it with one whose pause they end
/// themselves, so no test waits.
@MainActor
protocol AnswerFeedback: AnyObject {
    /// A right answer: announced, then `advance` is called once the success feedback has
    /// played (with VoiceOver running, not before the announcement has been spoken); always
    /// later, never from within this call, because the model may still be saving.
    func right(announcement: String, then advance: @escaping @MainActor () -> Void)
    /// A wrong answer: announced. The learner tries again or moves on with Next.
    func wrong(announcement: String)
    /// Drops a pending move on (the learner left the practice).
    func cancel()
}

/// The app's answer feedback. After a right answer the success feedback stays on screen for
/// `successSeconds` (the owner asked for 1 to 1.5 seconds), then the next question follows. With
/// VoiceOver running it also waits until the announcement has been spoken, checking every
/// `pollSeconds` at most `maxPolls` times (10 seconds more), so a lost notification cannot keep
/// a solved question on screen. Reduce Motion changes nothing here: the pause stays.
@MainActor
final class LiveAnswerFeedback: AnswerFeedback {
    static let successSeconds: Double = 1.2
    static let pollSeconds: Double = 0.1
    static let maxPolls = 100

    /// Waits the given number of seconds; tests pass one that returns at once.
    private let pause: @Sendable (Double) async -> Void
    private let voiceOverRunning: @MainActor () -> Bool
    /// The move on after a right answer, while it is pending.
    private(set) var pending: Task<Void, Never>?
    /// A right answer's announcement, until VoiceOver has finished speaking it.
    private(set) var unspoken: String?
    private var observer: NSObjectProtocol?

    convenience init() {
        self.init(pause: { seconds in
            _ = try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }, voiceOverRunning: {
            UIAccessibility.isVoiceOverRunning
        })
    }

    init(pause: @escaping @Sendable (Double) async -> Void, voiceOverRunning: @escaping @MainActor () -> Bool) {
        self.pause = pause
        self.voiceOverRunning = voiceOverRunning
        // Read here, on the main actor; the observer block below is a nonisolated Sendable
        // closure, so it uses only this String copy and no UIKit symbol.
        let textKey: String = UIAccessibility.announcementStringValueUserInfoKey
        observer = NotificationCenter.default.addObserver(forName: UIAccessibility.announcementDidFinishNotification,
                                                          object: nil,
                                                          queue: .main) { [weak self] notification in
            let text = notification.userInfo?[textKey] as? String
            Task { @MainActor [weak self] in
                self?.announcementFinished(text)
            }
        }
    }

    func right(announcement: String, then advance: @escaping @MainActor () -> Void) {
        cancel()
        unspoken = voiceOverRunning() ? announcement : nil
        announceForVoiceOver(announcement)
        let pause = self.pause
        pending = Task { @MainActor [weak self] in
            await pause(LiveAnswerFeedback.successSeconds)
            var polls = 0
            while !Task.isCancelled, self?.waitsForAnnouncement == true, polls < LiveAnswerFeedback.maxPolls {
                await pause(LiveAnswerFeedback.pollSeconds)
                polls += 1
            }
            if Task.isCancelled { return }
            self?.pending = nil
            self?.unspoken = nil
            advance()
        }
    }

    func wrong(announcement: String) {
        announceForVoiceOver(announcement)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        unspoken = nil
    }

    /// VoiceOver finished speaking an announcement, or it was interrupted: the right answer's
    /// own announcement ends the wait (a notification without its text is taken as that one).
    func announcementFinished(_ text: String?) {
        guard let waiting = unspoken else { return }
        if text == nil || text == waiting {
            unspoken = nil
        }
    }

    private var waitsForAnnouncement: Bool {
        unspoken != nil && voiceOverRunning()
    }
}

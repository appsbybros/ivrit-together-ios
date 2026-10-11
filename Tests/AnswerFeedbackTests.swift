import AVFoundation
import XCTest
@testable import IvritTogether

/// Records every pause LiveAnswerFeedback asks for and returns at once, so no test sleeps.
/// `onPause` runs after each pause with the number of pauses so far.
@MainActor
private final class InstantClock {
    private(set) var pauses: [Double] = []
    var onPause: (@MainActor (Int) -> Void)?

    func pause(_ seconds: Double) {
        pauses.append(seconds)
        onPause?(pauses.count)
    }
}

/// Counts how often the feedback moved on.
@MainActor
private final class MoveCounter {
    private(set) var count = 0

    func moved() {
        count += 1
    }
}

/// The app's answer feedback (LiveAnswerFeedback) on an instant clock: the pause before a right
/// answer moves on, the wait for VoiceOver's announcement and its limit; and the bundled chime.
@MainActor
final class AnswerFeedbackTests: XCTestCase {
    private func makeFeedback(_ clock: InstantClock, voiceOver: Bool) -> LiveAnswerFeedback {
        LiveAnswerFeedback(pause: { seconds in await clock.pause(seconds) },
                           voiceOverRunning: { voiceOver })
    }

    func testTheSuccessFeedbackLastsBetweenOneAndOneAndAHalfSeconds() {
        XCTAssertGreaterThanOrEqual(LiveAnswerFeedback.successSeconds, 1.0)
        XCTAssertLessThanOrEqual(LiveAnswerFeedback.successSeconds, 1.5)
    }

    func testARightAnswerMovesOnAfterTheSuccessPause() async {
        let clock = InstantClock()
        let moves = MoveCounter()
        let feedback = makeFeedback(clock, voiceOver: false)
        feedback.right(announcement: "That’s right") { moves.moved() }
        XCTAssertEqual(moves.count, 0, "Not before the pause")
        XCTAssertNil(feedback.unspoken, "Without VoiceOver nothing waits for the announcement")
        _ = await feedback.pending?.value
        XCTAssertEqual(clock.pauses, [LiveAnswerFeedback.successSeconds])
        XCTAssertEqual(moves.count, 1)
        XCTAssertNil(feedback.pending)
    }

    func testAWrongAnswerIsOnlyAnnounced() {
        let clock = InstantClock()
        let feedback = makeFeedback(clock, voiceOver: true)
        feedback.wrong(announcement: "Not quite. Try again.")
        XCTAssertNil(feedback.pending, "A wrong answer does not move on")
        XCTAssertNil(feedback.unspoken)
        XCTAssertTrue(clock.pauses.isEmpty)
    }

    /// With VoiceOver the next question waits until "That’s right" has been spoken; another
    /// announcement finishing first does not end the wait.
    func testWithVoiceOverItWaitsUntilTheAnnouncementHasBeenSpoken() async {
        let clock = InstantClock()
        let moves = MoveCounter()
        let feedback = makeFeedback(clock, voiceOver: true)
        clock.onPause = { [weak feedback] count in
            if count == 2 {
                feedback?.announcementFinished("Not quite. Try again.")
            }
            if count == 4 {
                feedback?.announcementFinished("That’s right")
            }
        }
        feedback.right(announcement: "That’s right") { moves.moved() }
        XCTAssertEqual(feedback.unspoken, "That’s right")
        _ = await feedback.pending?.value
        XCTAssertEqual(clock.pauses, [LiveAnswerFeedback.successSeconds,
                                      LiveAnswerFeedback.pollSeconds,
                                      LiveAnswerFeedback.pollSeconds,
                                      LiveAnswerFeedback.pollSeconds])
        XCTAssertEqual(moves.count, 1)
        XCTAssertNil(feedback.unspoken)
    }

    /// An announcement VoiceOver finished during the success pause adds no wait.
    func testWithVoiceOverAnAnnouncementSpokenDuringThePauseAddsNoWait() async {
        let clock = InstantClock()
        let moves = MoveCounter()
        let feedback = makeFeedback(clock, voiceOver: true)
        feedback.right(announcement: "That’s right") { moves.moved() }
        feedback.announcementFinished("That’s right")
        _ = await feedback.pending?.value
        XCTAssertEqual(clock.pauses, [LiveAnswerFeedback.successSeconds])
        XCTAssertEqual(moves.count, 1)
    }

    /// If VoiceOver never reports the announcement, the question still moves on after the limit.
    func testWithVoiceOverALostAnnouncementStillMovesOnAfterTheLimit() async {
        let clock = InstantClock()
        let moves = MoveCounter()
        let feedback = makeFeedback(clock, voiceOver: true)
        feedback.right(announcement: "That’s right") { moves.moved() }
        _ = await feedback.pending?.value
        XCTAssertEqual(clock.pauses.count, 1 + LiveAnswerFeedback.maxPolls)
        XCTAssertEqual(clock.pauses.dropFirst().reduce(0, +), 10, accuracy: 0.001)
        XCTAssertEqual(moves.count, 1)
    }

    func testCancelKeepsTheQuestion() async {
        let clock = InstantClock()
        let moves = MoveCounter()
        let feedback = makeFeedback(clock, voiceOver: false)
        feedback.right(announcement: "That’s right") { moves.moved() }
        let pending = feedback.pending
        feedback.cancel()
        XCTAssertNil(feedback.pending)
        _ = await pending?.value
        XCTAssertEqual(moves.count, 0)
    }

    func testTheSuccessChimeIsBundledAndEndsWithinThePause() throws {
        let url = try XCTUnwrap(Bundle(for: Course.self).url(forResource: "success", withExtension: "wav"))
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertGreaterThan(seconds, 0.2)
        XCTAssertLessThan(seconds, LiveAnswerFeedback.successSeconds, "The chime ends before the next question")
    }
}

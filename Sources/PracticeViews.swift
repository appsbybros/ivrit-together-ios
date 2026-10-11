import SwiftUI
import UIKit

// Port of Practice, Token, ResultPage and MatchPage (MainActivity.kt). Unlike Android, an
// answer is checked as soon as it is tapped, with no Check button (owner QA ISSUE-001). A right
// answer turns green with a check mark, bounces, plays a chime and a success haptic, and the
// next question follows by itself after about 1.2 seconds (LiveAnswerFeedback). A wrong answer
// is marked red with a cross, without showing the right one, and can be corrected; only then is
// Next offered, so the learner can also move on without the answer.

struct PracticeView: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Android's `remember(session.attemptId) { showText }`.
    @State private var shownTextFor: String? = nil
    /// The right answer's short bounce: 1 at rest, a little larger for a moment after a right
    /// answer (never with Reduce Motion).
    @State private var bounce: CGFloat = 1

    var body: some View {
        if let session = vm.session {
            let question = session.question
            Page { _ in
                HStack(alignment: .firstTextBaseline) {
                    BodyText(text: vm.t("practice"), color: Palette.muted)
                    Spacer(minLength: 12)
                    BodyText(text: isolatedLTR("\(session.index + 1) / \(session.questions.count)"), weight: .bold, color: Palette.teal)
                }
                ProgressBar(value: Double(session.index) / Double(max(session.questions.count, 1)), track: Palette.mint)
                Heading(title: vm.t(PracticeView.headingKey(question.kind)))
                CardPanel(color: Palette.mint) {
                    prompt(session: session, question: question)
                }
                if question.kind == .build {
                    buildArea(session: session, question: question)
                } else {
                    // A tap checks the option at once. An option found wrong keeps its mark and
                    // cannot be chosen again; the others stay open until the right one is found.
                    ForEach(question.choices) { choice in
                        let mark = PracticeView.mark(session, choice.id)
                        ChoiceButton(text: choice.meaning(vm.language),
                                     mark: mark,
                                     markDescription: markDescription(mark),
                                     enabled: !session.correct && mark != .wrong,
                                     identifier: "choice-\(choice.id)") {
                            vm.select(choice.id)
                        }
                        .scaleEffect(mark == .right ? bounce : 1)
                    }
                }
                if session.wrong {
                    tryAgain()
                }
                // Next only after a wrong answer, to move on without being shown the answer, in
                // the secondary style so that trying again stays the obvious step. A right
                // answer moves on by itself.
                if session.offersNext {
                    ActionButton(title: vm.t(session.isLast ? "finish" : "next"),
                                 identifier: "next-question",
                                 enabled: !vm.busy,
                                 secondary: true) {
                        speech.stop()
                        vm.next()
                    }
                }
            }
            // Android's LaunchedEffect(session.attemptId, speech.ready): stop, then play a
            // listening question automatically once a voice is ready.
            .onAppear { playListeningQuestion() }
            .onChange(of: session.attemptId) { _, _ in playListeningQuestion() }
            .onChange(of: speech.ready) { _, _ in playListeningQuestion() }
            // The success feedback of a right answer. The model announces every checked answer
            // to VoiceOver and moves on after the pause.
            .onChange(of: session.correct) { _, solved in
                if solved {
                    celebrate()
                }
            }
            // Questions move on by themselves, so speech stops when the practice ends, as the
            // Finish button did.
            .onDisappear { speech.stop() }
        }
    }

    static func headingKey(_ kind: Exercise) -> String {
        switch kind {
        case .meaning: return "choose_meaning"
        case .listen: return "listen_choose"
        case .build: return "build"
        }
    }

    /// Options found wrong keep their mark; the right one is marked once it is chosen.
    static func mark(_ session: Session, _ choice: String) -> ChoiceMark {
        if session.wrongChoices.contains(choice) { return .wrong }
        if session.correct && session.selection == choice { return .right }
        return .unmarked
    }

    /// What VoiceOver says about a marked option.
    private func markDescription(_ mark: ChoiceMark) -> String {
        switch mark {
        case .unmarked: return ""
        case .right: return vm.t("correct")
        case .wrong: return vm.t("incorrect")
        }
    }

    /// A right answer's success feedback: the chime, a success haptic and a short bounce of the
    /// answer, which Reduce Motion leaves out.
    private func celebrate() {
        speech.playSuccess()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if reduceMotion { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            bounce = 1.05
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                bounce = 1
            }
        }
    }

    private func playListeningQuestion() {
        speech.stop()
        guard let current = vm.session, current.question.kind == .listen, speech.ready else { return }
        speech.say(current.question.phrase.text(vm.female))
    }

    @ViewBuilder
    private func prompt(session: Session, question: Question) -> some View {
        switch question.kind {
        case .meaning:
            HebrewText(text: vm.hebrew(question.phrase), size: 35)
            if vm.transliteration {
                BodyText(text: isolatedLTR(question.phrase.sound(vm.female)), color: Palette.muted)
            }
        case .listen:
            ActionButton(title: vm.t("listen"), identifier: "listen") {
                speech.say(question.phrase.text(vm.female))
            }
            ActionButton(title: vm.t("slow"), identifier: "slow", secondary: true) {
                speech.say(question.phrase.text(vm.female), slow: true)
            }
            if speech.failed {
                VoiceNotice()
            }
            Button {
                shownTextFor = session.attemptId
            } label: {
                Text(vm.t("show_text"))
                    .appFont(18, .semibold)
                    .foregroundStyle(Palette.teal)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("show-text")
            // Shown on request, or with the right answer; a wrong try leaves listening open.
            if shownTextFor == session.attemptId || session.correct {
                HebrewText(text: vm.hebrew(question.phrase), size: 32)
            }
        case .build:
            BodyText(text: question.phrase.meaning(vm.language), size: 26, weight: .medium)
        }
    }

    /// Right-to-left sentence construction: the answer row and the word bank both fill from
    /// the right, as Android forces LayoutDirection.Rtl here. The sentence is checked when its
    /// last word is placed and marked like an option: a wrong one red with ✗ (not corrected),
    /// its words still movable so it can be fixed; a right one green with ✓, locked, bouncing
    /// like a right option and moving on by itself.
    @ViewBuilder
    private func buildArea(session: Session, question: Question) -> some View {
        BodyText(text: vm.t("build_hint"), size: 16, color: Palette.muted)
        BodyText(text: vm.t("your_answer"), weight: .bold)
        HStack(alignment: .top, spacing: 8) {
            // The mark leads the words, as on an option; its slot stays free while the sentence
            // is unmarked, so the words do not move when it appears.
            Text(verbatim: answerMark(session))
                .appFont(19)
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 22, minHeight: 54)
                .accessibilityHidden(true)
            FlowRow(rightToLeft: true) {
                ForEach(session.selectedTokens, id: \.self) { index in
                    TokenButton(text: tokenText(question, index),
                                identifier: "chosen-\(index)",
                                enabled: !session.correct) {
                        vm.token(index)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(answerFill(session), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(answerBorder(session), lineWidth: 2)
        )
        .scaleEffect(session.correct ? bounce : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(vm.t("your_answer"))
        .accessibilityIdentifier("answer-tokens")
        FlowRow(rightToLeft: true) {
            ForEach(question.tokenOrder.filter { !session.selectedTokens.contains($0) }, id: \.self) { index in
                TokenButton(text: tokenText(question, index),
                            identifier: "token-\(index)",
                            enabled: !session.correct) {
                    vm.token(index)
                }
            }
        }
    }

    /// The answer row is marked like an option: green with ✓ when right, red with ✗ while a
    /// wrong sentence is unchanged.
    private func answerMark(_ session: Session) -> String {
        if session.correct { return "✓" }
        if session.wrong { return "✗" }
        return ""
    }

    private func answerFill(_ session: Session) -> Color {
        if session.correct { return Palette.correctFill }
        if session.wrong { return Palette.wrongFill }
        return Color.clear
    }

    private func answerBorder(_ session: Session) -> Color {
        if session.correct { return Palette.correct }
        if session.wrong { return Palette.danger }
        return Palette.teal.opacity(0.3)
    }

    /// With vowel marks off, a word shows its everyday unpointed spelling (Android splits the
    /// unpointed phrase on single spaces and takes the same position).
    private func tokenText(_ question: Question, _ index: Int) -> String {
        if vm.vowels { return question.tokens[index] }
        let plain: [Substring] = question.phrase.withoutVowels(vm.female)
            .split(separator: " ", omittingEmptySubsequences: false)
        return plain.indices.contains(index) ? String(plain[index]) : question.tokens[index]
    }

    /// After a wrong answer, the invitation to try again: the right answer is not revealed. A
    /// right answer has no panel; its success feedback is on the answer itself.
    private func tryAgain() -> some View {
        CardPanel(color: Palette.retry) {
            BodyText(text: "↺ " + vm.t("try_again"), size: 23, weight: .bold)
                .accessibilityIdentifier("feedback")
        }
    }
}

/// How a checked option is shown.
enum ChoiceMark: Equatable {
    case unmarked
    case right
    case wrong
}

struct ChoiceButton: View {
    let text: String
    let mark: ChoiceMark
    /// What VoiceOver says about the mark ("That’s right", "Not correct"); empty if unmarked.
    let markDescription: String
    let enabled: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(markSymbol + text)
                .appFont(19)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(minHeight: 60)
                .background(fillColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: mark == .unmarked ? 1 : 2)
                )
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                // Once the right answer is found the other options fade; marked ones keep
                // their colours.
                .opacity(mark == .unmarked && !enabled ? 0.55 : 1)
        }
        .buttonStyle(ChoiceStyle())
        .disabled(!enabled)
        .accessibilityLabel(text)
        .accessibilityValue(markDescription)
        .accessibilityAddTraits(mark == .right ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var markSymbol: String {
        switch mark {
        case .unmarked: return ""
        case .right: return "✓  "
        case .wrong: return "✗  "
        }
    }

    private var fillColor: Color {
        switch mark {
        case .unmarked: return Color.white
        case .right: return Palette.correctFill
        case .wrong: return Palette.wrongFill
        }
    }

    private var borderColor: Color {
        switch mark {
        case .unmarked: return Palette.ink.opacity(0.16)
        case .right: return Palette.correct
        case .wrong: return Palette.danger
        }
    }
}

/// Shows the press only. Unlike the plain style, a disabled option is not dimmed, so a
/// checked option keeps the colours of its mark.
private struct ChoiceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct TokenButton: View {
    let text: String
    let identifier: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .appFont(25)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 54)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(enabled ? 0.35 : 0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .environment(\.layoutDirection, .rightToLeft)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}

struct ResultView: View {
    @EnvironmentObject private var vm: LearnViewModel

    var body: some View {
        if let result = vm.result {
            Page { _ in
                CardPanel(color: Palette.ink) {
                    Text(verbatim: "✦")
                        .appFont(70)
                        .foregroundStyle(Palette.gold)
                        .accessibilityHidden(true)
                    BodyText(text: vm.t("well_done"), size: 31, weight: .bold, color: Color.white)
                    BodyText(text: isolatedLTR("\(result.score) / \(result.questions.count)"),
                             size: 48, weight: .bold, color: Palette.gold)
                    BodyText(text: vm.t("score"), color: Color.white)
                }
                BodyText(text: vm.t("result_tip"), color: Palette.muted)
                ActionButton(title: vm.t("home"), identifier: "result-home") {
                    vm.home()
                }
                ActionButton(title: vm.t("again"), identifier: "again", secondary: true) {
                    vm.begin(result.lessonId)
                }
            }
        }
    }
}

struct MatchView: View {
    @EnvironmentObject private var vm: LearnViewModel

    var body: some View {
        if let match = vm.match {
            Page { _ in
                Heading(title: vm.t("match"), subtitle: vm.t("match_hint"))
                BodyText(text: isolatedLTR("\(match.matched.count) / \(match.leftItems.count)") + " · " + vm.t("matched"),
                         weight: .bold, color: Palette.teal)
                // Columns have fixed semantic roles, independent of the interface direction.
                HStack(alignment: .top, spacing: 12) {
                    column(match, left: true)
                    column(match, left: false)
                }
                .environment(\.layoutDirection, .leftToRight)
                if match.miss {
                    BodyText(text: vm.t("match_miss"))
                }
                if match.complete {
                    Heading(title: vm.t("well_done"))
                    ActionButton(title: vm.t("practice"), identifier: "match-finish") {
                        vm.abandon()
                        vm.beginCurrentLesson()
                    }
                }
            }
            // Android's live region on the "not this pair" text.
            .onChange(of: match.miss) { _, miss in
                if miss {
                    announceForVoiceOver(vm.t("match_miss"))
                }
            }
        }
    }

    private func column(_ match: MatchState, left: Bool) -> some View {
        VStack(spacing: 14) {
            ForEach(left ? match.leftItems : match.rightItems) { phrase in
                MatchButton(text: left ? vm.hebrew(phrase) : phrase.meaning(vm.language),
                            hebrew: left,
                            chosen: (left ? match.left : match.right) == phrase.id,
                            matched: match.matched.contains(phrase.id),
                            rightToLeft: left || vm.isRightToLeft,
                            identifier: "match-\(left ? "he" : "meaning")-\(phrase.id)") {
                    vm.selectMatch(phrase.id, left: left)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct MatchButton: View {
    let text: String
    let hebrew: Bool
    let chosen: Bool
    let matched: Bool
    let rightToLeft: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text((matched ? "✓ " : "") + text)
                .appFont(hebrew ? 24 : 18)
                .foregroundStyle(matched ? Palette.teal : Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 96)
                .background((chosen || matched) ? Palette.mint : Color.white,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(chosen ? Palette.teal : Palette.ink.opacity(0.16), lineWidth: chosen ? 2 : 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        }
        .buttonStyle(.plain)
        .disabled(matched)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

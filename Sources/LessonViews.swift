import SwiftUI

// Port of LessonPage, PhraseTile, VoiceNotice and LearnPage (MainActivity.kt).

struct LessonView: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech

    var body: some View {
        if let lesson = vm.currentLesson {
            Page { _ in
                Heading(title: lesson.title(vm.language))
                ActionButton(title: vm.t("learn"), identifier: "learn") {
                    vm.learning = true
                    vm.cardIndex = 0
                }
                HStack(alignment: .top, spacing: 12) {
                    ActionButton(title: vm.t("practice"), identifier: "practice", secondary: true) {
                        vm.beginCurrentLesson()
                    }
                    ActionButton(title: vm.t("match"), identifier: "match", secondary: true) {
                        vm.beginMatch()
                    }
                }
                if speech.failed {
                    VoiceNotice()
                }
                ForEach(lesson.phrases) { phrase in
                    PhraseTile(phrase: phrase)
                }
            }
        }
    }
}

struct PhraseTile: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech
    let phrase: Phrase

    var body: some View {
        let saved = vm.progress.saved.contains(phrase.id)
        CardPanel {
            HebrewText(text: vm.hebrew(phrase), size: 27)
            if vm.transliteration {
                BodyText(text: isolatedLTR(phrase.sound(vm.female)), color: Palette.muted)
            }
            BodyText(text: phrase.meaning(vm.language), weight: .medium)
            HStack(spacing: 12) {
                Button {
                    speech.say(phrase.text(vm.female))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .appFont(18)
                            .accessibilityHidden(true)
                        Text(vm.t("listen"))
                            .appFont(18, .semibold)
                    }
                    .foregroundStyle(Palette.teal)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 12)
                Button {
                    vm.toggleSaved(phrase.id)
                } label: {
                    Image(systemName: saved ? "heart.fill" : "heart")
                        .appFont(24)
                        .foregroundStyle(saved ? Palette.teal : Palette.muted.opacity(0.55))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(vm.busy)
                .accessibilityLabel(vm.t(saved ? "unsave" : "save"))
                .accessibilityIdentifier("save-\(phrase.id)")
            }
        }
    }
}

struct VoiceNotice: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BodyText(text: vm.t("voice_missing"), size: 15, color: Palette.muted)
            Button {
                speech.openSettings()
            } label: {
                Text(vm.t("voice_settings"))
                    .appFont(16, .semibold)
                    .foregroundStyle(Palette.teal)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LearnView: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech
    /// Android's `remember(p.id) { reveal }`: the meaning shows for the card it was opened on.
    @State private var revealed: String? = nil

    var body: some View {
        if let lesson = vm.currentLesson, lesson.phrases.indices.contains(vm.cardIndex) {
            let phrase = lesson.phrases[vm.cardIndex]
            let last = vm.cardIndex == lesson.phrases.count - 1
            Page { _ in
                BodyText(text: isolatedLTR("\(vm.cardIndex + 1) / \(lesson.phrases.count)"), weight: .bold, color: Palette.teal)
                Heading(title: lesson.title(vm.language))
                CardPanel {
                    HebrewText(text: vm.hebrew(phrase), size: 42)
                    if vm.transliteration {
                        BodyText(text: isolatedLTR(phrase.sound(vm.female)), size: 21, color: Palette.muted)
                    }
                    ActionButton(title: vm.t("listen"), identifier: "listen") {
                        speech.say(phrase.text(vm.female))
                    }
                    ActionButton(title: vm.t("slow"), identifier: "slow", secondary: true) {
                        speech.say(phrase.text(vm.female), slow: true)
                    }
                    if speech.failed {
                        VoiceNotice()
                    }
                    if revealed == phrase.id {
                        BodyText(text: phrase.meaning(vm.language), size: 24)
                            .accessibilityIdentifier("meaning")
                    } else {
                        ActionButton(title: vm.t("show_meaning"), identifier: "reveal", secondary: true) {
                            revealed = phrase.id
                        }
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    ActionButton(title: vm.t("previous"), enabled: vm.cardIndex > 0, secondary: true) {
                        speech.stop()
                        vm.cardIndex -= 1
                    }
                    ActionButton(title: vm.t(last ? "practice" : "next"), identifier: "next-card") {
                        speech.stop()
                        if last {
                            vm.beginCurrentLesson()
                        } else {
                            vm.cardIndex += 1
                        }
                    }
                }
            }
            .onChange(of: vm.cardIndex) { _, _ in
                revealed = nil
            }
        }
    }
}

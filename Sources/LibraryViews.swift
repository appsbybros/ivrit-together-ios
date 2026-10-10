import SwiftUI

// Port of Phrasebook and Alphabet (MainActivity.kt).

struct PhrasebookView: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech
    @State private var query = ""
    @State private var savedOnly = false

    var body: some View {
        let items = filtered
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Heading(title: vm.t("words"))
                if speech.failed {
                    VoiceNotice()
                }
                searchField
                HStack(spacing: 12) {
                    ChipButton(title: vm.t("all"), selected: !savedOnly) {
                        savedOnly = false
                    }
                    ChipButton(title: vm.t("saved"), selected: savedOnly, identifier: "saved-filter") {
                        savedOnly = true
                    }
                }
                if items.isEmpty {
                    BodyText(text: vm.t("empty"))
                }
                ForEach(items) { phrase in
                    PhraseTile(phrase: phrase)
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Android: Hebrew is compared without vowel marks (pointed and everyday spellings),
    /// meanings and pronunciation guides case-insensitively; a blank search shows all.
    private var filtered: [Phrase] {
        let blank = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let plainQuery = plainHebrew(query)
        return vm.course.phrases.filter { phrase in
            if savedOnly && !vm.progress.saved.contains(phrase.id) { return false }
            if blank { return true }
            return containsIgnoringCase(plainHebrew(phrase.text(vm.female)), plainQuery)
                || containsIgnoringCase(phrase.withoutVowels(vm.female), plainQuery)
                || containsIgnoringCase(phrase.meaning(vm.language), query)
                || containsIgnoringCase(phrase.sound(vm.female), query)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(18)
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            TextField(vm.t("search"), text: $query)
                .appFont(18)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("search")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.25), lineWidth: 1)
        )
    }
}

struct AlphabetView: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech

    var body: some View {
        Page { width in
            Heading(title: vm.t("alphabet"), subtitle: vm.t("letters_hint"))
            if speech.failed {
                VoiceNotice()
            }
            BodyText(text: vm.t("sound_hint"), size: 16, color: Palette.muted)
            GridRows(items: vm.course.alphabet, columns: AlphabetView.columns(for: width), spacing: 12) { letter in
                LetterCard(letter: letter)
            }
        }
    }

    static func columns(for width: CGFloat) -> Int {
        if width > 700 { return 4 }
        if width > 430 { return 3 }
        return 2
    }
}

struct LetterCard: View {
    @EnvironmentObject private var speech: Speech
    let letter: Letter

    var body: some View {
        Button {
            speech.say(letter.name)
        } label: {
            CardPanel {
                HebrewText(text: letter.letter, size: 42)
                HebrewText(text: letter.name, size: 21)
                BodyText(text: isolatedLTR(letter.sound), color: Palette.muted)
            }
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("letter-" + String(letter.letter.prefix(1)))
    }
}

import StoreKit
import SwiftUI

// Port of Settings (MainActivity.kt). The "More Minik apps & games" button uses an
// Android-only shared module and is left out on iOS.

struct SettingsView: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var confirmReset = false

    var body: some View {
        Page { _ in
            Heading(title: vm.t("language"))
            LanguageChoices(selected: vm.language, rightToLeft: vm.isRightToLeft) { code in
                vm.chooseLanguage(code)
            }
            CardPanel {
                BodyText(text: vm.t("forms"), size: 22, weight: .bold)
                FormChoice(title: vm.t("masculine"), selected: !vm.female) {
                    vm.changeFemale(false)
                }
                FormChoice(title: vm.t("feminine"), selected: vm.female) {
                    vm.changeFemale(true)
                }
                BodyText(text: vm.t("forms_help"), size: 16, color: Palette.muted)
            }
            CardPanel {
                PreferenceToggle(title: vm.t("transliteration"),
                                 isOn: Binding(get: { vm.transliteration }, set: { vm.changeTransliteration($0) }))
                PreferenceToggle(title: vm.t("vowels"),
                                 isOn: Binding(get: { vm.vowels }, set: { vm.changeVowels($0) }))
                ActionButton(title: vm.t("voice_settings"), secondary: true) {
                    speech.openSettings()
                }
            }
            CardPanel {
                ActionButton(title: vm.t("rate_app"), identifier: "rate-app", secondary: true) {
                    rate()
                }
                ShareLink(item: AppLinks.shareText) {
                    Text(vm.t("share_app"))
                        .appFont(18, .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(ActionStyle(secondary: true))
                .accessibilityIdentifier("share-app")
                ActionButton(title: vm.t("send_feedback"), identifier: "send-feedback", secondary: true) {
                    sendFeedback()
                }
            }
            CardPanel {
                Heading(title: vm.t("privacy"))
                BodyText(text: vm.t("privacy_body"))
            }
            BodyText(text: vm.t("about"), color: Palette.muted)
            BodyText(text: "© 2026 Apps by Bros · " + AppLinks.version, size: 14, color: Palette.muted)
            Button {
                confirmReset = true
            } label: {
                Text(vm.t("reset"))
                    .appFont(18, .semibold)
                    .foregroundStyle(Palette.danger)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reset")
        }
        .alert(vm.t("reset"), isPresented: $confirmReset) {
            Button(vm.t("delete"), role: .destructive) {
                vm.reset()
            }
            .disabled(vm.busy)
            Button(vm.t("cancel"), role: .cancel) {}
        } message: {
            Text(vm.t("reset_confirm"))
        }
    }

    /// The App Store's write-review page when the app's Apple ID is known, otherwise
    /// StoreKit's review prompt (which the system may choose not to show).
    private func rate() {
        if let url = AppLinks.reviewURL {
            openLink(url)
        } else {
            requestReview()
        }
    }

    private func sendFeedback() {
        guard let url = AppLinks.feedbackURL else { return }
        openLink(url)
    }

    /// Android shows "No suitable app is installed" when nothing can open the link.
    private func openLink(_ url: URL) {
        let model = vm
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in model.error = "no_external_app" }
            }
        }
    }
}

/// Android's RadioButton row.
struct FormChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .appFont(22)
                    .foregroundStyle(selected ? Palette.teal : Palette.muted)
                    .accessibilityHidden(true)
                Text(title)
                    .appFont(18)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Android's Preference: a label and a switch.
struct PreferenceToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .appFont(18)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Palette.teal)
        .frame(minHeight: 60)
    }
}

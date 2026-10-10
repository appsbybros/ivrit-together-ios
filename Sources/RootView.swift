import SwiftUI

// Port of IvritApp, Header and Navigation (MainActivity.kt): one screen at a time, chosen by
// the same state as Android, a top bar with Back (nested screens) or Settings (main tabs),
// and the bottom navigation on the four main tabs only.

struct RootView: View {
    @EnvironmentObject private var vm: LearnViewModel
    @EnvironmentObject private var speech: Speech
    @State private var settings = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            Palette.sand.ignoresSafeArea()
            if vm.language.isEmpty {
                WelcomeView()
            } else {
                mainScreen
            }
        }
        .environment(\.layoutDirection, vm.isRightToLeft ? .rightToLeft : .leftToRight)
        .alert(vm.t("brand"), isPresented: errorShown) {
            Button(vm.t("ok")) { vm.error = nil }
        } message: {
            Text(vm.t(vm.error ?? ""))
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { vm.error != nil }, set: { shown in
            if !shown { vm.error = nil }
        })
    }

    /// Android's `nested`: screens with a Back button instead of Settings.
    private var nested: Bool {
        settings || vm.lessonId != nil || vm.session != nil || vm.result != nil
    }

    private var showsNavigation: Bool {
        vm.lessonId == nil && vm.session == nil && vm.result == nil && !settings
    }

    private var title: String {
        settings ? vm.t("settings") : vm.t("brand")
    }

    /// Android's Scaffold: the top bar, the current screen and, on the four main tabs, the
    /// bottom navigation. A SwiftUI bar (not a UIKit navigation bar) follows the interface
    /// direction exactly, as Android's TopAppBar does.
    private var mainScreen: some View {
        VStack(spacing: 0) {
            HeaderBar(title: title, nested: nested, back: back, openSettings: { settings = true })
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsNavigation {
                BottomNavigation()
            }
        }
        .background(Palette.sand.ignoresSafeArea())
        .alert(vm.t("leave"), isPresented: $leaving) {
            Button(vm.t("close"), role: .destructive) {
                leaving = false
                vm.abandon()
                speech.stop()
            }
            Button(vm.t("cancel"), role: .cancel) {
                leaving = false
            }
        } message: {
            Text(vm.t("leave_body"))
        }
    }

    @ViewBuilder
    private var screen: some View {
        if settings {
            SettingsView()
        } else if vm.session != nil {
            PracticeView()
        } else if vm.result != nil {
            ResultView()
        } else if vm.match != nil {
            MatchView()
        } else if vm.learning {
            LearnView()
        } else if vm.lessonId != nil {
            LessonView()
        } else if vm.tab == "journey" {
            JourneyView()
        } else if vm.tab == "words" {
            PhrasebookView()
        } else if vm.tab == "alphabet" {
            AlphabetView()
        } else {
            TodayView()
        }
    }

    /// Android's Header back action (and BackHandler).
    private func back() {
        if settings {
            settings = false
        } else if vm.session != nil || vm.match != nil {
            leaving = true
        } else if vm.learning {
            vm.learning = false
        } else {
            vm.lessonId = nil
            vm.abandon()
        }
        speech.stop()
    }
}

/// Android's TopAppBar: Back on nested screens, the title, Settings on the main tabs.
struct HeaderBar: View {
    @EnvironmentObject private var vm: LearnViewModel
    let title: String
    let nested: Bool
    let back: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if nested {
                Button(action: back) {
                    Image(systemName: "chevron.backward")
                        .appFont(22, .semibold)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.t("back"))
                .accessibilityIdentifier("back")
            }
            Text(title)
                .appFont(22, .bold)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, nested ? 0 : 14)
                .accessibilityAddTraits(.isHeader)
            if !nested {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .appFont(22, .semibold)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.t("settings"))
                .accessibilityIdentifier("settings")
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minHeight: 56)
        .background(Palette.sand)
    }
}

struct TabDestination: Identifiable {
    let id: String
    let icon: String
    let selectedIcon: String

    var labelKey: String { id == "words" ? "tab_words" : id }

    static let all: [TabDestination] = [
        TabDestination(id: "today", icon: "house", selectedIcon: "house.fill"),
        TabDestination(id: "journey", icon: "list.bullet.rectangle", selectedIcon: "list.bullet.rectangle.fill"),
        TabDestination(id: "words", icon: "heart", selectedIcon: "heart.fill"),
        TabDestination(id: "alphabet", icon: "character.book.closed", selectedIcon: "character.book.closed.fill")
    ]
}

/// Android's NavigationBar; with large text (font scale above 1.3) a two-by-two grid of
/// wide buttons, as on Android.
struct BottomNavigation: View {
    @EnvironmentObject private var vm: LearnViewModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize > .xxLarge {
                VStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(TabDestination.all[(row * 2)..<(row * 2 + 2)]) { item in
                                TabButton(item: item, wide: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 0) {
                    ForEach(TabDestination.all) { item in
                        TabButton(item: item, wide: false)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
        }
    }
}

private struct TabButton: View {
    @EnvironmentObject private var vm: LearnViewModel
    let item: TabDestination
    let wide: Bool

    var body: some View {
        let current = vm.tab == item.id
        Button {
            vm.tab = item.id
        } label: {
            if wide {
                HStack(spacing: 8) {
                    Image(systemName: current ? item.selectedIcon : item.icon)
                        .appFont(20)
                        .accessibilityHidden(true)
                    Text(vm.t(item.labelKey))
                        .appFont(16, current ? .semibold : .regular)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(current ? Palette.mint : Color.white,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: current ? item.selectedIcon : item.icon)
                        .appFont(19)
                        .frame(width: 60, height: 30)
                        .background(current ? Palette.mint : Color.clear, in: Capsule())
                        .accessibilityHidden(true)
                    Text(vm.t(item.labelKey))
                        .appFont(13, current ? .semibold : .medium)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("nav-\(item.id)")
    }
}

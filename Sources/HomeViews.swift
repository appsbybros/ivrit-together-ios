import SwiftUI

// Port of Welcome, Today (Daily, Stats, NextLesson) and Journey (MainActivity.kt).

struct WelcomeView: View {
    @EnvironmentObject private var vm: LearnViewModel
    @State private var code = "en"

    var body: some View {
        let rightToLeft = Language.isRightToLeft(code)
        Page { _ in
            NeighborhoodImage(height: 210, radius: 28)
            Heading(title: text("welcome"), subtitle: text("welcome_body"))
            BodyText(text: text("choose_language"), weight: .bold)
            LanguageChoices(selected: code, rightToLeft: rightToLeft) { chosen in
                code = chosen
            }
            ActionButton(title: text("start"), identifier: "start") {
                vm.chooseLanguage(code)
            }
        }
        // Android keeps the welcome layout left-to-right until a language is chosen and
        // aligns Arabic and Hebrew text by its content; here the chosen language's own
        // direction is used for the whole screen.
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    }

    private func text(_ key: String) -> String {
        vm.course.text(code, key)
    }
}

struct TodayView: View {
    @EnvironmentObject private var vm: LearnViewModel

    var body: some View {
        let now = currentMillis()
        let next = vm.course.lessons.first { !vm.progress.completed.contains($0.id) } ?? vm.course.lessons.first
        let due = vm.progress.words.values.filter { $0.due <= now }.count
        let reviewReady = !vm.progress.review(vm.course.phrases, now: now).isEmpty
        Page { width in
            CardPanel(color: Palette.ink) {
                BodyText(text: vm.t("welcome"), size: 27, weight: .bold, color: Color.white)
                NeighborhoodImage(height: min(max((width - 44) / 2.6, 105), 200), radius: 18)
                if reviewReady {
                    ActionButton(title: vm.t("daily_practice"), identifier: "daily-practice", secondary: true) {
                        vm.begin(nil)
                    }
                } else {
                    BodyText(text: vm.t("up_to_date"), color: Color.white)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home-hero")
            if width > 650 {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) {
                        DailyCard(due: due)
                        StatsRow()
                    }
                    .frame(maxWidth: .infinity)
                    VStack {
                        if let lesson = next {
                            NextLessonCard(lesson: lesson)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                DailyCard(due: due)
                StatsRow()
                if let lesson = next {
                    NextLessonCard(lesson: lesson)
                }
            }
        }
    }
}

struct DailyCard: View {
    @EnvironmentObject private var vm: LearnViewModel
    let due: Int

    var body: some View {
        let goal = LearnerProgress.dailyGoal
        let count = vm.progress.dailyCount(LocalDay.today())
        CardPanel(color: Palette.mint) {
            Heading(title: vm.t("daily_title"))
            BodyText(text: "\(due) · \(vm.t("review_due"))", weight: .bold, color: Palette.teal)
            BodyText(text: vm.t(count >= goal ? "daily_goal_done" : "daily_goal"), weight: .bold)
            BodyText(text: isolatedLTR("\(count) / \(goal)"), color: Palette.teal)
                .accessibilityIdentifier("daily-count")
            ProgressBar(value: Double(count) / Double(goal), track: Color.white)
            BodyText(text: vm.t("daily_body"), color: Palette.muted)
        }
    }
}

struct StatsRow: View {
    @EnvironmentObject private var vm: LearnViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StatBox(value: vm.progress.words.count, label: vm.t("learned"))
            StatBox(value: vm.progress.streak(LocalDay.today()), label: vm.t("days"))
        }
    }
}

struct StatBox: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(value))
                .appFont(32, .bold)
                .foregroundStyle(Palette.teal)
            BodyText(text: label, size: 15, color: Palette.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct NextLessonCard: View {
    @EnvironmentObject private var vm: LearnViewModel
    let lesson: Lesson

    var body: some View {
        CardPanel {
            BodyText(text: vm.t("continue_lesson"), color: Palette.muted)
            BodyText(text: lesson.title(vm.language), size: 25, weight: .bold)
            if let first = lesson.phrases.first {
                HebrewText(text: first.text(vm.female), size: 28)
            }
            ActionButton(title: vm.t("learn"), identifier: "continue-lesson", secondary: true) {
                vm.openLesson(lesson.id)
            }
        }
    }
}

struct JourneyView: View {
    @EnvironmentObject private var vm: LearnViewModel

    var body: some View {
        Page { width in
            Heading(title: vm.t("everyday"), subtitle: vm.t("all_topics"))
            GridRows(items: vm.course.lessons, columns: JourneyView.columns(for: width), spacing: 14) { lesson in
                LessonCard(lesson: lesson)
            }
        }
    }

    static func columns(for width: CGFloat) -> Int {
        if width > 850 { return 3 }
        if width > 570 { return 2 }
        return 1
    }
}

struct LessonCard: View {
    @EnvironmentObject private var vm: LearnViewModel
    let lesson: Lesson

    var body: some View {
        let lessons = vm.course.lessons
        let number = (lessons.firstIndex { $0.id == lesson.id } ?? 0) + 1
        let numberText = number < 10 ? "0\(number)" : "\(number)"
        Button {
            vm.openLesson(lesson.id)
        } label: {
            CardPanel {
                BodyText(text: isolatedLTR("\(numberText) / \(lessons.count)"), weight: .bold, color: Palette.teal)
                BodyText(text: lesson.title(vm.language), size: 22, weight: .semibold)
                if vm.progress.completed.contains(lesson.id) {
                    BodyText(text: "✓ " + vm.t("complete"), color: Palette.teal)
                } else if let first = lesson.phrases.first {
                    HebrewText(text: first.withoutVowels(vm.female), size: 23)
                }
            }
            .multilineTextAlignment(.leading)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lesson-\(lesson.id)")
    }
}

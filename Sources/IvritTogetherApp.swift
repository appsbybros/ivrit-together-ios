import SwiftUI

// Port of MainActivity: one model and one speech engine for the app's lifetime. Speech is
// refreshed when the app becomes active (Android onResume) and stopped in the background
// (Android onStop).

@main
struct IvritTogetherApp: App {
    @StateObject private var model = LearnViewModel()
    @StateObject private var speech = Speech()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(speech)
                .tint(Palette.teal)
                // The app's light palette is independent of the device's Dark Mode.
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        speech.refresh()
                    case .background:
                        speech.stop()
                    default:
                        break
                    }
                }
        }
    }
}

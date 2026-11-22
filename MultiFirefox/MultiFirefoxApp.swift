import SwiftUI
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Publishes whether Sparkle can currently start an update check, so the menu item
/// is disabled while a check is already running.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

@main
struct MultiFirefoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Feed and public key come from Info.plist (`SUFeedURL`, `SUPublicEDKey`).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 480, height: 300)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

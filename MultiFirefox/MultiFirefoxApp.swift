import SwiftUI
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MultiFirefoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController

    /// Sparkle updates are switched off until the fork has its own signed appcast.
    /// To enable: set this to `true` and add `SUFeedURL` plus `SUPublicEDKey` to Info.plist.
    private static let updatesEnabled = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: Self.updatesEnabled,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 480, height: 300)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                if Self.updatesEnabled {
                    Button("Check for Updates…") {
                        updaterController.updater.checkForUpdates()
                    }
                }
            }
        }
    }
}

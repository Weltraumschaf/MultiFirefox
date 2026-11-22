import SwiftUI

struct ContentView: View {
    @StateObject private var manager = FirefoxManager()
    @State private var selectedVersion: String?
    @State private var selectedProfile: String?
    @State private var activeAlert: AppAlert?
    @State private var needsProfileReload = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 1) {
                versionList
                Divider()
                profileList
            }
            Divider()
            buttonBar
        }
        .frame(minWidth: 440, minHeight: 270)
        .onAppear {
            restoreSelection()
            checkProfiles()
        }
        .onChange(of: selectedVersion) { newVersion in
            guard newVersion != nil else { return }
            selectedProfile = FirefoxManager.profileToSelect(
                preferred: selectedProfile, in: manager.profiles)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            guard needsProfileReload else { return }
            manager.reloadProfiles()
            selectedProfile = FirefoxManager.profileToSelect(
                preferred: selectedProfile, in: manager.profiles)
            needsProfileReload = false
            if let error = manager.profileLoadError { activeAlert = .unreadable(reason: error) }
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { if !$0 { activeAlert = nil } }
            ),
            presenting: activeAlert
        ) { alert in
            switch alert {
            case .tooFewProfiles:
                Button("Open Profile Manager") { openProfileManager() }
                Button("Cancel", role: .cancel) {}
            case .unreadable:
                Button("Open Privacy & Security") { openPrivacySettings() }
                Button("Cancel", role: .cancel) {}
            case let .appExists(version, profile, _):
                Button("Replace", role: .destructive) {
                    // Run after this alert is dismissed, so the result alert is not cleared with it.
                    Task { createApp(version, profile: profile, replacing: true) }
                }
                Button("Cancel", role: .cancel) {}
            case let .appCreated(bundle):
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([bundle])
                }
                Button("OK", role: .cancel) {}
            case .launchFailed, .profileManagerFailed, .createAppFailed:
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    private var versionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Firefox Version")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .top], 8)
            List(manager.versions, selection: $selectedVersion) { version in
                Text(version.name)
                    .help(version.url.path)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let version = firefox(for: ids) {
                    Button("Launch") { launch(version) }
                        .disabled(selectedProfile == nil)
                }
            } primaryAction: { ids in
                // Double-click (or Return) on a row launches it with the selected profile.
                guard let version = firefox(for: ids) else { return }
                launch(version)
            }
        }
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Profile")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .top], 8)
            List(manager.profiles, id: \.self, selection: $selectedProfile) { profile in
                Text(profile)
            }
        }
    }

    private var buttonBar: some View {
        HStack {
            Button("Launch Firefox") { launch() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(selectedVersion == nil || selectedProfile == nil)
            Spacer()
            Button("Profile Manager") { openProfileManager() }
                .disabled(selectedVersion == nil)
            Button("Create App") { createApp() }
                .disabled(selectedVersion == nil || selectedProfile == nil)
        }
        .padding(12)
    }

    /// The version selected in the list, resolved to the bundle it stands for.
    private var selectedFirefox: FirefoxVersion? {
        selectedVersion.flatMap { id in manager.versions.first { $0.id == id } }
    }

    private func launch() {
        guard let version = selectedFirefox, let profile = selectedProfile else { return }
        launch(version, profile: profile)
    }

    /// Launches `version` with the selected profile, if one is selected.
    private func launch(_ version: FirefoxVersion) {
        guard let profile = selectedProfile else { return }
        launch(version, profile: profile)
    }

    /// The version a context menu or double-click acts on: exactly one row, resolved to its bundle.
    private func firefox(for ids: Set<String>) -> FirefoxVersion? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return manager.versions.first { $0.id == id }
    }

    private func launch(_ version: FirefoxVersion, profile: String) {
        UserDefaults.standard.set(version.name, forKey: "lastVersion")
        UserDefaults.standard.set(profile, forKey: "lastProfile")
        Task {
            do {
                try await manager.launch(version: version, profile: profile)
            } catch {
                NSLog("MultiFirefoxNG: cannot launch %@: %@", version.url.path, String(describing: error))
                activeAlert = .launchFailed(
                    version: version.name, profile: profile, reason: error.localizedDescription
                )
            }
        }
    }

    private func openProfileManager() {
        guard let version = selectedFirefox else { return }
        needsProfileReload = true
        Task {
            do {
                try await manager.openProfileManager(version: version)
            } catch {
                needsProfileReload = false
                NSLog("MultiFirefoxNG: cannot open Profile Manager of %@: %@", version.url.path, String(describing: error))
                activeAlert = .profileManagerFailed(
                    version: version.name, reason: error.localizedDescription
                )
            }
        }
    }

    private func createApp() {
        guard let version = selectedFirefox, let profile = selectedProfile else { return }
        createApp(version, profile: profile, replacing: false)
    }

    /// Creates the shortcut app and reports the outcome; an existing app is only replaced after
    /// the user confirmed it.
    private func createApp(_ version: FirefoxVersion, profile: String, replacing: Bool) {
        do {
            let bundle = try manager.createApplication(
                version: version, profile: profile, replacing: replacing)
            activeAlert = .appCreated(bundle: bundle)
        } catch let CreateAppError.alreadyExists(bundle) {
            activeAlert = .appExists(version: version, profile: profile, bundle: bundle)
        } catch {
            NSLog("MultiFirefoxNG: cannot create app for %@ / %@: %@", version.name, profile, String(describing: error))
            activeAlert = .createAppFailed(
                version: version.name, profile: profile, reason: error.localizedDescription
            )
        }
    }

    private func checkProfiles() {
        if let error = manager.profileLoadError {
            activeAlert = .unreadable(reason: error)
        } else if manager.profiles.count < 2, !manager.versions.isEmpty {
            activeAlert = .tooFewProfiles
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func restoreSelection() {
        let lastVersion = UserDefaults.standard.string(forKey: "lastVersion")
        let lastProfile = UserDefaults.standard.string(forKey: "lastProfile")
        selectedVersion = lastVersion.flatMap { name in manager.versions.contains { $0.id == name } ? name : nil }
            ?? manager.versions.first?.id
        selectedProfile = FirefoxManager.profileToSelect(preferred: lastProfile, in: manager.profiles)
    }
}

/// An alert shown by `ContentView`; failures carry what the user needs to know.
enum AppAlert: Identifiable, Hashable {
    case tooFewProfiles
    case unreadable(reason: String)
    case launchFailed(version: String, profile: String, reason: String)
    case profileManagerFailed(version: String, reason: String)
    case appExists(version: FirefoxVersion, profile: String, bundle: URL)
    case appCreated(bundle: URL)
    case createAppFailed(version: String, profile: String, reason: String)

    var id: Self { self }

    var title: String {
        switch self {
        case .tooFewProfiles: "You need to create a profile!"
        case .unreadable: "Cannot read Firefox profiles"
        case .launchFailed: "Cannot launch Firefox"
        case .profileManagerFailed: "Cannot open Profile Manager"
        case .appExists: "App already exists"
        case .appCreated: "App created"
        case .createAppFailed: "Cannot create app"
        }
    }

    var message: String {
        switch self {
        case .tooFewProfiles:
            "You have fewer than two Firefox profiles. To run multiple versions side by side, you must have multiple profiles defined."
        case let .unreadable(reason):
            "MultiFirefoxNG is not allowed to read your Firefox profiles (\(reason)).\n\nmacOS protects data of other apps. Grant MultiFirefoxNG access in System Settings › Privacy & Security, then restart it."
        case let .launchFailed(version, profile, reason):
            "\(version) could not be started with the profile \"\(profile)\".\n\n\(reason)"
        case let .profileManagerFailed(version, reason):
            "The Profile Manager of \(version) could not be opened.\n\n\(reason)"
        case let .appExists(_, _, bundle):
            "\"\(bundle.lastPathComponent)\" already exists in \(bundle.deletingLastPathComponent().path). Replace it? The old app is moved to the Trash."
        case let .appCreated(bundle):
            "\"\(bundle.lastPathComponent)\" was created in \(bundle.deletingLastPathComponent().path)."
        case let .createAppFailed(version, profile, reason):
            "The app for \(version) with the profile \"\(profile)\" could not be created.\n\n\(reason)"
        }
    }
}

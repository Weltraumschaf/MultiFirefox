import SwiftUI

struct ContentView: View {
    @StateObject private var manager = FirefoxManager()
    @State private var selectedVersion: String?
    @State private var selectedProfile: String?
    @State private var activeAlert: ProfileAlert?
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
            guard let newVersion else { return }
            autoSelectProfile(for: newVersion)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            guard needsProfileReload else { return }
            let previous = selectedProfile
            manager.reloadProfiles()
            selectedProfile = (previous.flatMap { manager.profiles.contains($0) ? $0 : nil })
                ?? manager.profiles.first
            needsProfileReload = false
            if manager.profileLoadError != nil { activeAlert = .unreadable }
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
            }
        } message: { alert in
            switch alert {
            case .tooFewProfiles:
                Text("You have fewer than two Firefox profiles. To run multiple versions side by side, you must have multiple profiles defined.")
            case .unreadable:
                Text("MultiFirefoxNG is not allowed to read your Firefox profiles (\(manager.profileLoadError ?? "unknown error")).\n\nmacOS protects data of other apps. Grant MultiFirefoxNG access in System Settings › Privacy & Security, then restart it.")
            }
        }
    }

    private var versionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Firefox Version")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .top], 8)
            List(manager.versions, id: \.self, selection: $selectedVersion) { version in
                Text(version)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        selectedVersion = version
                        guard let profile = selectedProfile else { return }
                        UserDefaults.standard.set(version, forKey: "lastVersion")
                        UserDefaults.standard.set(profile, forKey: "lastProfile")
                        manager.launch(version: version, profile: profile)
                    }
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

    private func launch() {
        guard let version = selectedVersion, let profile = selectedProfile else { return }
        UserDefaults.standard.set(version, forKey: "lastVersion")
        UserDefaults.standard.set(profile, forKey: "lastProfile")
        manager.launch(version: version, profile: profile)
    }

    private func openProfileManager() {
        guard let version = selectedVersion else { return }
        needsProfileReload = true
        manager.openProfileManager(version: version)
    }

    private func createApp() {
        guard let version = selectedVersion, let profile = selectedProfile else { return }
        manager.createApplication(version: version, profile: profile)
    }

    private func checkProfiles() {
        if manager.profileLoadError != nil {
            activeAlert = .unreadable
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
        selectedVersion = lastVersion.flatMap { manager.versions.contains($0) ? $0 : nil }
            ?? manager.versions.first
        selectedProfile = lastProfile.flatMap { manager.profiles.contains($0) ? $0 : nil }
            ?? manager.profiles.first
    }

    private func autoSelectProfile(for version: String) {
        let isPlain = version.lowercased() == "firefox"
        if isPlain, let def = manager.profiles.first(where: { $0 == "default" }) {
            selectedProfile = def
            return
        }
        selectedProfile = manager.profiles.first
    }
}

private enum ProfileAlert: Identifiable {
    case tooFewProfiles
    case unreadable

    var id: Self { self }

    var title: String {
        switch self {
        case .tooFewProfiles: "You need to create a profile!"
        case .unreadable: "Cannot read Firefox profiles"
        }
    }
}

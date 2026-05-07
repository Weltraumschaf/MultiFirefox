import SwiftUI

struct ContentView: View {
    @StateObject private var manager = FirefoxManager()
    @State private var selectedVersion: String?
    @State private var selectedProfile: String?
    @State private var showingProfileWarning = false
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
}

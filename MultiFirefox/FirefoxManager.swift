import Foundation
import AppKit

@MainActor
final class FirefoxManager: ObservableObject {
    @Published var versions: [String] = []
    @Published var profiles: [String] = []
    /// Set when `profiles.ini` exists but could not be read (e.g. macOS privacy protection).
    @Published var profileLoadError: String?

    private static let applicationsPath = "/Applications"
    nonisolated static let profilesIniURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Firefox/profiles.ini")

    nonisolated static func isFirefoxApp(_ name: String) -> Bool {
        let lower = name.lowercased()
        return (lower.hasPrefix("firefox") || lower.hasPrefix("minefield"))
            && name.hasSuffix(".app")
    }

    /// Turns paths relative to the applications folder into sorted version names.
    ///
    /// Entries that are not Firefox app bundles are dropped. For nested paths such as
    /// `Firefox Versions/Firefox 90.app` the name is taken from the last path component.
    nonisolated static func filterVersions(from names: [String]) -> [String] {
        names
            .filter { isFirefoxApp($0) }
            .map { String(($0 as NSString).lastPathComponent.dropLast(4)) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Extracts profile names from `profiles.ini`, reading `Name=` only inside `[ProfileN]` sections.
    ///
    /// The default profile comes first, the rest are sorted alphabetically. The default is, in order
    /// of preference: the profile whose `Path=` matches `Default=` of an `[Install…]` section (what
    /// modern Firefox actually uses), the `[ProfileN]` flagged `Default=1`, a profile named "default".
    nonisolated static func parseProfiles(from iniContent: String) -> [String] {
        var names: [String] = []
        var pathToName: [String: String] = [:]
        var installDefaults: [String] = []
        var flaggedDefault: String?

        enum Section { case profile, install, other }
        var section = Section.other
        var name: String?
        var path: String?
        var isFlagged = false

        func finishProfile() {
            if section == .profile, let name, !name.isEmpty {
                if !names.contains(name) { names.append(name) }
                if let path, pathToName[path] == nil { pathToName[path] = name }
                if isFlagged, flaggedDefault == nil { flaggedDefault = name }
            }
            name = nil
            path = nil
            isFlagged = false
        }

        for line in iniContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                finishProfile()
                let header = trimmed.dropFirst().dropLast()
                let suffix = header.dropFirst("Profile".count)
                if header.hasPrefix("Profile") && !suffix.isEmpty && suffix.allSatisfy(\.isNumber) {
                    section = .profile
                } else if header.hasPrefix("Install") {
                    section = .install
                } else {
                    section = .other
                }
            } else if section == .profile {
                if trimmed.hasPrefix("Name=") {
                    name = String(trimmed.dropFirst(5))
                } else if trimmed.hasPrefix("Path=") {
                    path = String(trimmed.dropFirst(5))
                } else if trimmed == "Default=1" {
                    isFlagged = true
                }
            } else if section == .install, trimmed.hasPrefix("Default=") {
                installDefaults.append(String(trimmed.dropFirst(8)))
            }
        }
        finishProfile()

        let defaultName = installDefaults.lazy.compactMap { pathToName[$0] }.first
            ?? flaggedDefault
            ?? (names.contains("default") ? "default" : nil)
        let others = names
            .filter { $0 != defaultName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return defaultName.map { [$0] + others } ?? others
    }

    nonisolated static func buildAppBundle(version: String, profile: String, in directory: URL) {
        let appDir = directory.appendingPathComponent("\(version)-\(profile).app")
        let macosDir = appDir.appendingPathComponent("Contents/MacOS")
        let launcher = macosDir.appendingPathComponent("launcher")
        let infoPlist = appDir.appendingPathComponent("Contents/Info.plist")

        let fm = FileManager.default
        try? fm.createDirectory(at: macosDir, withIntermediateDirectories: true)

        let script = """
#!/bin/bash
open -na "/Applications/\(version).app" --args -no-remote -P "\(profile)"
"""
        try? script.write(to: launcher, atomically: true, encoding: .utf8)

        let bundleId = "com.multifirefox.shortcut.\(version.lowercased().replacingOccurrences(of: " ", with: "-"))-\(profile.lowercased())"
        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleName</key>
    <string>\(version)-\(profile)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIdentifier</key>
    <string>\(bundleId)</string>
</dict>
</plist>
"""
        try? plist.write(to: infoPlist, atomically: true, encoding: .utf8)

        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcher.path
        )
    }

    func createApplication(version: String, profile: String) {
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        Self.buildAppBundle(version: version, profile: profile, in: desktop)
    }

    // MARK: - Init and loading

    init() { load() }

    func load() {
        versions = Self.loadVersions()
        reloadProfiles()
    }

    func reloadProfiles() {
        do {
            profiles = try Self.loadProfiles(from: Self.profilesIniURL)
            profileLoadError = nil
        } catch {
            NSLog("MultiFirefoxNG: cannot read %@: %@", Self.profilesIniURL.path, String(describing: error))
            profiles = []
            profileLoadError = error.localizedDescription
        }
    }

    /// Scans `directory` for Firefox app bundles, descending only into Firefox-named folders.
    nonisolated static func loadVersions(in directory: String = applicationsPath) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else {
            return []
        }
        var candidates: [String] = []
        while let name = enumerator.nextObject() as? String {
            let lower = name.lowercased()
            if isFirefoxApp(name) {
                candidates.append(name)
                enumerator.skipDescendants()
            } else if !(lower.hasPrefix("firefox") || lower.hasPrefix("minefield")) {
                enumerator.skipDescendants()
            }
        }
        return filterVersions(from: candidates)
    }

    /// Reads profile names from the given `profiles.ini`.
    ///
    /// A missing file (Firefox never started) yields an empty list. Any other read failure —
    /// most notably macOS denying access to another app's data — is thrown so the UI can
    /// tell "no profiles" apart from "not allowed to look".
    nonisolated static func loadProfiles(from url: URL) throws -> [String] {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        return parseProfiles(from: content)
    }

    // MARK: - Launching

    func launch(version: String, profile: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [
            "-na", "\(Self.applicationsPath)/\(version).app",
            "--args", "-no-remote", "-P", profile
        ]
        try? p.run()
        NSApplication.shared.terminate(nil)
    }

    func openProfileManager(version: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [
            "-n", "\(Self.applicationsPath)/\(version).app",
            "--args", "--profilemanager"
        ]
        try? p.run()
    }
}

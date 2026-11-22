import Foundation
import AppKit

/// A Firefox app bundle found on disk.
///
/// `name` is the bundle name without `.app` and is unique in a version list, so it serves as the
/// identity. `url` is where the bundle actually is and is used to launch it.
struct FirefoxVersion: Identifiable, Hashable, Sendable {
    let name: String
    let url: URL

    var id: String { name }
}

/// Why Create App could not make a shortcut app.
enum CreateAppError: LocalizedError, Equatable {
    /// An app with the same name already exists at this URL.
    case alreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case let .alreadyExists(url): "\"\(url.lastPathComponent)\" already exists."
        }
    }
}

@MainActor
final class FirefoxManager: ObservableObject {
    @Published var versions: [FirefoxVersion] = []
    @Published var profiles: [String] = []
    /// Set when `profiles.ini` exists but could not be read (e.g. macOS privacy protection).
    @Published var profileLoadError: String?

    /// Folders searched for Firefox, in order of preference: a version name found in an earlier
    /// folder wins over the same name in a later one.
    nonisolated static let applicationsDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    ]
    nonisolated static let profilesIniURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Firefox/profiles.ini")

    nonisolated static func isFirefoxApp(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("firefox") && name.hasSuffix(".app")
    }

    /// Turns found bundle URLs into versions sorted by name.
    ///
    /// URLs whose last path component is not a Firefox app bundle are dropped. The name is the
    /// bundle name without `.app`, so `Firefox Versions/Firefox 90.app` becomes `Firefox 90`.
    /// When several bundles have the same name, the first one in `urls` is kept.
    nonisolated static func filterVersions(from urls: [URL]) -> [FirefoxVersion] {
        var seen: Set<String> = []
        return urls
            .filter { isFirefoxApp($0.lastPathComponent) }
            .map { FirefoxVersion(name: String($0.lastPathComponent.dropLast(4)), url: $0) }
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    /// Quotes `value` as one POSIX shell word: wrapped in single quotes, with each `'` written as
    /// `'\''`. Nothing inside single quotes is expanded, so the value is passed through verbatim.
    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The launcher script of a shortcut app: opens a new instance of the Firefox at `appURL` with
    /// `profile`, the same way the main window launches it.
    nonisolated static func launcherScript(appURL: URL, profile: String) -> String {
        let arguments = launchArguments(profile: profile).map(shellQuote).joined(separator: " ")
        return "#!/bin/bash\nexec /usr/bin/open -n -a \(shellQuote(appURL.path)) --args \(arguments)\n"
    }

    /// Turns `value` into a bundle identifier component: lowercased, every run of characters other
    /// than ASCII letters and digits replaced by one `-`, and `-` trimmed from the ends. Never empty.
    nonisolated static func bundleIdentifierComponent(_ value: String) -> String {
        var result = ""
        for scalar in value.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty, !result.hasSuffix("-") {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "unnamed" : result
    }

    nonisolated static func bundleIdentifier(version: String, profile: String) -> String {
        "com.multifirefox.shortcut.\(bundleIdentifierComponent(version))-\(bundleIdentifierComponent(profile))"
    }

    /// The Info.plist of a shortcut app, serialized as XML so any characters in the names are escaped.
    nonisolated static func infoPlistData(version: String, profile: String) throws -> Data {
        let plist: [String: Any] = [
            "CFBundleExecutable": "launcher",
            "CFBundleName": "\(version)-\(profile)",
            "CFBundlePackageType": "APPL",
            "CFBundleIdentifier": bundleIdentifier(version: version, profile: profile),
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Where the shortcut app for `version` and `profile` goes inside `directory`.
    nonisolated static func appBundleURL(version: String, profile: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(version)-\(profile).app")
    }

    /// Moves an existing shortcut app to the Trash, so replacing it can be undone.
    nonisolated static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Builds the shortcut app for `version` and `profile` in `directory` and returns its URL.
    ///
    /// The bundle is assembled in a temporary folder first and only moved into place when it is
    /// complete, so a failure leaves no half-built app behind. If the app already exists,
    /// `CreateAppError.alreadyExists` is thrown unless `replacing` is set; then the old app is handed
    /// to `removeExisting` (the Trash by default) before the new one is moved in.
    @discardableResult
    nonisolated static func buildAppBundle(
        version: String, appURL: URL, profile: String, in directory: URL,
        replacing: Bool = false,
        removeExisting: (URL) throws -> Void = moveToTrash
    ) throws -> URL {
        let fm = FileManager.default
        let appDir = appBundleURL(version: version, profile: profile, in: directory)
        let exists = (try? appDir.checkResourceIsReachable()) == true
        if exists, !replacing { throw CreateAppError.alreadyExists(appDir) }

        let staging = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: directory, create: true)
        defer { try? fm.removeItem(at: staging) }

        let stagedApp = staging.appendingPathComponent(appDir.lastPathComponent)
        let macosDir = stagedApp.appendingPathComponent("Contents/MacOS")
        let launcher = macosDir.appendingPathComponent("launcher")
        let infoPlist = stagedApp.appendingPathComponent("Contents/Info.plist")

        try fm.createDirectory(at: macosDir, withIntermediateDirectories: true)
        try launcherScript(appURL: appURL, profile: profile)
            .write(to: launcher, atomically: true, encoding: .utf8)
        try infoPlistData(version: version, profile: profile).write(to: infoPlist, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        if exists { try removeExisting(appDir) }
        try fm.moveItem(at: stagedApp, to: appDir)
        return appDir
    }

    nonisolated static var desktopDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    /// Creates the shortcut app on the Desktop and returns its URL; see `buildAppBundle`.
    func createApplication(
        version: FirefoxVersion, profile: String, replacing: Bool = false
    ) throws -> URL {
        try Self.buildAppBundle(
            version: version.name, appURL: version.url, profile: profile,
            in: Self.desktopDirectory, replacing: replacing)
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

    /// Scans `directories` for Firefox app bundles, descending only into Firefox-named folders.
    ///
    /// Directories are searched in the given order, and within one directory paths are taken in
    /// sorted order, so which bundle wins a name clash is deterministic (see `filterVersions`).
    nonisolated static func loadVersions(
        in directories: [URL] = applicationsDirectories
    ) -> [FirefoxVersion] {
        var candidates: [URL] = []
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
                continue
            }
            var found: [String] = []
            while let path = enumerator.nextObject() as? String {
                if isFirefoxApp((path as NSString).lastPathComponent) {
                    found.append(path)
                    enumerator.skipDescendants()
                } else if !path.lowercased().hasPrefix("firefox") {
                    enumerator.skipDescendants()
                }
            }
            candidates += found.sorted().map { directory.appendingPathComponent($0) }
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

    /// Command line arguments that start Firefox with `profile` as an instance of its own.
    nonisolated static func launchArguments(profile: String) -> [String] {
        ["-no-remote", "-P", profile]
    }

    /// Command line arguments that open Firefox's Profile Manager.
    nonisolated static let profileManagerArguments = ["--profilemanager"]

    /// How to open a Firefox bundle: always as a new instance, so it runs beside any Firefox
    /// that is already open, with the given command line arguments.
    nonisolated static func openConfiguration(arguments: [String]) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        return configuration
    }

    /// Starts `version` with `profile` and quits this app once Firefox has been launched.
    ///
    /// If the launch fails the error is thrown and this app keeps running.
    func launch(version: FirefoxVersion, profile: String) async throws {
        try await open(version, arguments: Self.launchArguments(profile: profile))
        NSApplication.shared.terminate(nil)
    }

    /// Opens the Profile Manager of `version`; a failed launch is thrown.
    func openProfileManager(version: FirefoxVersion) async throws {
        try await open(version, arguments: Self.profileManagerArguments)
    }

    private func open(_ version: FirefoxVersion, arguments: [String]) async throws {
        _ = try await NSWorkspace.shared.openApplication(
            at: version.url,
            configuration: Self.openConfiguration(arguments: arguments)
        )
    }
}

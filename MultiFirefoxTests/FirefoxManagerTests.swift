import XCTest
@testable import MultiFirefoxNG

final class FirefoxManagerTests: XCTestCase {

    func testParseProfilesExtractsNames() {
        let ini = "[Install]\nDefault=Profiles/xyz.default\n[Profile0]\nName=default\nIsRelative=1\nPath=Profiles/xyz.default\n[Profile1]\nName=Work\nIsRelative=1\nPath=Profiles/abc.work"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["default", "Work"])
    }

    func testParseProfilesPutsDefaultFirst() {
        let ini = "[Profile0]\nName=Work\n[Profile1]\nName=default"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini).first, "default")
    }

    func testParseProfilesSortsNonDefaultAlphabetically() {
        let ini = "[Profile0]\nName=Zebra\n[Profile1]\nName=Alpha\n[Profile2]\nName=default"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["default", "Alpha", "Zebra"])
    }

    func testParseProfilesReturnsEmptyForEmptyInput() {
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ""), [])
    }

    func testParseProfilesIgnoresNameOutsideProfileSections() {
        let ini = "[General]\nName=bogus\n[Install123]\nName=alsobogus\n[Profile0]\nName=Work\n[BackgroundTasksProfiles]\nName=bg"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["Work"])
    }

    func testParseProfilesHandlesUnorderedSectionsAndCRLF() {
        let ini = "[General]\r\nVersion=2\r\n\r\n[Profile3]\r\nName=proxy\r\n\r\n[Install2656]\r\nDefault=Profiles/x\r\n\r\n[Profile0]\r\nName=default\r\nDefault=1\r\n"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["default", "proxy"])
    }

    func testParseProfilesPutsProfileFlaggedDefaultFirst() {
        let ini = "[Profile0]\nName=default\n[Profile1]\nName=Work\nDefault=1\n[Profile2]\nName=Alpha"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["Work", "Alpha", "default"])
    }

    func testParseProfilesPrefersInstallDefaultOverProfileFlag() {
        let ini = "[Install4F96D1932A9F858E]\nDefault=Profiles/b.work\nLocked=1\n[Profile0]\nName=default\nPath=Profiles/a.default\nDefault=1\n[Profile1]\nName=Work\nPath=Profiles/b.work"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["Work", "default"])
    }

    func testParseProfilesMatchesInstallDefaultWhenInstallSectionComesLast() {
        let ini = "[Profile0]\nName=Alpha\nPath=Profiles/a.alpha\n[Profile1]\nName=Zebra\nPath=Profiles/z.zebra\n[Install123]\nDefault=Profiles/z.zebra"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["Zebra", "Alpha"])
    }

    func testParseProfilesFallsBackToProfileFlagWhenInstallDefaultUnknown() {
        let ini = "[Install123]\nDefault=Profiles/gone\n[Profile0]\nName=Alpha\nPath=Profiles/a\n[Profile1]\nName=Work\nPath=Profiles/w\nDefault=1"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["Work", "Alpha"])
    }

    func testParseProfilesIgnoresDefaultFlagOutsideProfileSections() {
        let ini = "[General]\nDefault=1\n[Profile0]\nName=Zebra\n[Profile1]\nName=Alpha"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["Alpha", "Zebra"])
    }

    func testParseProfilesRemovesDuplicates() {
        let ini = "[Profile0]\nName=Work\n[Profile1]\nName=Work"
        XCTAssertEqual(FirefoxManager.parseProfiles(from: ini), ["Work"])
    }

    func testLoadProfilesReturnsEmptyWhenFileMissing() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("profiles.ini")
        XCTAssertEqual(try FirefoxManager.loadProfiles(from: missing), [])
    }

    func testLoadProfilesThrowsWhenFileUnreadable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let ini = tempDir.appendingPathComponent("profiles.ini")
        try "[Profile0]\nName=Work\n".write(to: ini, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ini.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ini.path) }

        XCTAssertThrowsError(try FirefoxManager.loadProfiles(from: ini))
    }

    func testLoadProfilesReadsFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let ini = tempDir.appendingPathComponent("profiles.ini")
        try "[Profile0]\nName=Work\n[Profile1]\nName=default\n".write(to: ini, atomically: true, encoding: .utf8)

        XCTAssertEqual(try FirefoxManager.loadProfiles(from: ini), ["default", "Work"])
    }

    func testIsFirefoxAppAcceptsFirefoxVariants() {
        XCTAssertTrue(FirefoxManager.isFirefoxApp("Firefox 120.app"))
        XCTAssertTrue(FirefoxManager.isFirefoxApp("Firefox.app"))
        XCTAssertTrue(FirefoxManager.isFirefoxApp("firefox.app"))
        XCTAssertTrue(FirefoxManager.isFirefoxApp("Firefox Nightly.app"))
    }

    func testIsFirefoxAppRejectsNonFirefox() {
        XCTAssertFalse(FirefoxManager.isFirefoxApp("Safari.app"))
        XCTAssertFalse(FirefoxManager.isFirefoxApp("Firefox Folder"))
        XCTAssertFalse(FirefoxManager.isFirefoxApp("NotFirefox.app"))
        XCTAssertFalse(FirefoxManager.isFirefoxApp("Minefield.app"))
    }

    private func names(_ versions: [FirefoxVersion]) -> [String] { versions.map(\.name) }

    private func urls(_ paths: [String]) -> [URL] { paths.map { URL(fileURLWithPath: $0) } }

    func testFilterVersionsStripsAppSuffixAndFilters() {
        let input = urls(["/Applications/Firefox 120.app", "/Applications/Safari.app",
                          "/Applications/Firefox.app", "/Applications/Chrome.app"])
        XCTAssertEqual(names(FirefoxManager.filterVersions(from: input)), ["Firefox", "Firefox 120"])
    }

    func testFilterVersionsSortsCaseInsensitively() {
        let input = urls(["/A/Firefox 90.app", "/A/Firefox 120.app", "/A/firefox Beta.app"])
        XCTAssertEqual(names(FirefoxManager.filterVersions(from: input)),
                       ["Firefox 120", "Firefox 90", "firefox Beta"])
    }

    func testFilterVersionsKeepsRealBundleURL() {
        let input = urls(["/A/Firefox Versions/Firefox 90.app", "/A/Firefox 120.app"])
        XCTAssertEqual(FirefoxManager.filterVersions(from: input), [
            FirefoxVersion(name: "Firefox 120", url: URL(fileURLWithPath: "/A/Firefox 120.app")),
            FirefoxVersion(name: "Firefox 90", url: URL(fileURLWithPath: "/A/Firefox Versions/Firefox 90.app"))
        ])
    }

    func testFilterVersionsKeepsFirstOfDuplicateNames() {
        let input = urls(["/Applications/Firefox.app", "/Users/me/Applications/Firefox.app"])
        XCTAssertEqual(FirefoxManager.filterVersions(from: input),
                       [FirefoxVersion(name: "Firefox", url: URL(fileURLWithPath: "/Applications/Firefox.app"))])
    }

    func testApplicationsDirectoriesSearchSystemThenUserFolder() {
        XCTAssertEqual(FirefoxManager.applicationsDirectories.map(\.path), [
            "/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ])
    }

    private func makeTree(_ paths: [String]) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for path in paths {
            try fm.createDirectory(at: dir.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        addTeardownBlock { try? fm.removeItem(at: dir) }
        return dir
    }

    func testLoadVersionsScansDirectory() throws {
        let dir = try makeTree(["Firefox.app/Contents", "Firefox Versions/Firefox 90.app/Contents",
                                "Firefox Versions/Safari.app/Contents",
                                "Safari.app/Contents", "Utilities/Firefox 80.app/Contents"])
        let versions = FirefoxManager.loadVersions(in: [dir])
        XCTAssertEqual(names(versions), ["Firefox", "Firefox 90"])
        XCTAssertEqual(versions.last?.url.standardizedFileURL,
                       dir.appendingPathComponent("Firefox Versions/Firefox 90.app").standardizedFileURL)
    }

    func testLoadVersionsSearchesAllDirectoriesAndPrefersEarlierOne() throws {
        let system = try makeTree(["Firefox.app/Contents"])
        let user = try makeTree(["Firefox.app/Contents", "Firefox Nightly.app/Contents"])
        let versions = FirefoxManager.loadVersions(in: [system, user])
        XCTAssertEqual(names(versions), ["Firefox", "Firefox Nightly"])
        XCTAssertEqual(versions.first?.url.standardizedFileURL,
                       system.appendingPathComponent("Firefox.app").standardizedFileURL)
        XCTAssertEqual(versions.last?.url.standardizedFileURL,
                       user.appendingPathComponent("Firefox Nightly.app").standardizedFileURL)
    }

    func testLoadVersionsSkipsMissingDirectory() throws {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        XCTAssertEqual(FirefoxManager.loadVersions(in: [missing]), [])
        let dir = try makeTree(["Firefox.app/Contents"])
        XCTAssertEqual(names(FirefoxManager.loadVersions(in: [missing, dir])), ["Firefox"])
    }

    func testBuildAppBundleCreatesExpectedFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FirefoxManager.buildAppBundle(
            version: "Firefox 120", appURL: URL(fileURLWithPath: "/Users/me/Applications/Firefox 120.app"),
            profile: "Work", in: tempDir)

        let appDir = tempDir.appendingPathComponent("Firefox 120-Work.app")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: appDir.appendingPathComponent("Contents/MacOS/launcher").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: appDir.appendingPathComponent("Contents/Info.plist").path))
    }

    func testBuildAppBundleLauncherContainsVersionAndProfile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FirefoxManager.buildAppBundle(
            version: "Firefox 120", appURL: URL(fileURLWithPath: "/Users/me/Applications/Firefox 120.app"),
            profile: "Work", in: tempDir)

        let launcherURL = tempDir
            .appendingPathComponent("Firefox 120-Work.app/Contents/MacOS/launcher")
        let content = try String(contentsOf: launcherURL)
        XCTAssertTrue(content.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(content.contains("'/Users/me/Applications/Firefox 120.app'"))
        XCTAssertTrue(content.contains("'Work'"))
    }

    private let nastyNames = [
        "Work", "with space", "quote\"d", "$(touch /tmp/pwned)", "`id`", "it's", "a&b", "<x>",
        "under_score", "$HOME", "back\\slash", "'", "''", "", "new\nline",
    ]

    /// Runs `/bin/sh -c "printf %s <word>"` and returns what the shell printed.
    private func shellRoundTrip(_ word: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s \(word)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: data, as: UTF8.self)
    }

    func testShellQuoteWrapsInSingleQuotes() {
        XCTAssertEqual(FirefoxManager.shellQuote("Work"), "'Work'")
        XCTAssertEqual(FirefoxManager.shellQuote("it's"), "'it'\\''s'")
        XCTAssertEqual(FirefoxManager.shellQuote(""), "''")
    }

    func testShellQuoteRoundTripsThroughShell() throws {
        for name in nastyNames {
            XCTAssertEqual(try shellRoundTrip(FirefoxManager.shellQuote(name)), name, name)
        }
    }

    func testLauncherScriptQuotesPathAndProfile() {
        let script = FirefoxManager.launcherScript(
            appURL: URL(fileURLWithPath: "/Users/me/Applications/Fire'fox $1.app"), profile: "$(rm -rf ~)")
        XCTAssertEqual(script, """
            #!/bin/bash
            exec /usr/bin/open -n -a '/Users/me/Applications/Fire'\\''fox $1.app' --args '-no-remote' '-P' '$(rm -rf ~)'

            """)
    }

    func testLauncherScriptArgumentsRoundTripThroughShell() throws {
        for name in nastyNames {
            let script = FirefoxManager.launcherScript(
                appURL: URL(fileURLWithPath: "/Applications/\(name.isEmpty ? "x" : name).app"), profile: name)
            let prefix = "#!/bin/bash\nexec /usr/bin/open "
            XCTAssertTrue(script.hasPrefix(prefix))
            // Print each word the shell would pass to `open`, NUL-terminated, instead of running it.
            let words = String(script.dropFirst(prefix.count))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "printf '%s\\0' \(words)"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let printed = String(decoding: data, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
                .dropLast().map(String.init)
            XCTAssertEqual(printed, ["-n", "-a", "/Applications/\(name.isEmpty ? "x" : name).app",
                                     "--args", "-no-remote", "-P", name], name)
        }
    }

    func testBundleIdentifierComponentSanitizes() {
        XCTAssertEqual(FirefoxManager.bundleIdentifierComponent("Firefox Nightly"), "firefox-nightly")
        XCTAssertEqual(FirefoxManager.bundleIdentifierComponent("under_score"), "under-score")
        XCTAssertEqual(FirefoxManager.bundleIdentifierComponent("  a__b..c  "), "a-b-c")
        XCTAssertEqual(FirefoxManager.bundleIdentifierComponent("Grüße"), "gr-e")
        XCTAssertEqual(FirefoxManager.bundleIdentifierComponent("$(x)"), "x")
        XCTAssertEqual(FirefoxManager.bundleIdentifierComponent(""), "unnamed")
        XCTAssertEqual(FirefoxManager.bundleIdentifierComponent("___"), "unnamed")
    }

    func testBundleIdentifierIsValidForNastyNames() {
        XCTAssertEqual(FirefoxManager.bundleIdentifier(version: "Firefox 120", profile: "My_Work"),
                       "com.multifirefox.shortcut.firefox-120-my-work")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        for name in nastyNames {
            let id = FirefoxManager.bundleIdentifier(version: "Firefox Developer Edition", profile: name)
            XCTAssertTrue(id.unicodeScalars.allSatisfy(allowed.contains), id)
            XCTAssertFalse(id.contains(".."), id)
            XCTAssertFalse(id.hasSuffix("-") || id.hasSuffix("."), id)
        }
    }

    func testInfoPlistRoundTripsExactNames() throws {
        for name in nastyNames {
            let data = try FirefoxManager.infoPlistData(version: "Firefox <&> 120", profile: name)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertEqual(plist["CFBundleName"], "Firefox <&> 120-\(name)")
            XCTAssertEqual(plist["CFBundleExecutable"], "launcher")
            XCTAssertEqual(plist["CFBundlePackageType"], "APPL")
            XCTAssertEqual(plist["CFBundleIdentifier"],
                           FirefoxManager.bundleIdentifier(version: "Firefox <&> 120", profile: name))
        }
    }

    func testBuildAppBundleWritesParsableFilesForNastyProfile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let profile = "a&b <\"$(id)\"> `x` it's"

        try FirefoxManager.buildAppBundle(
            version: "Firefox", appURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            profile: profile, in: tempDir)

        let appDir = tempDir.appendingPathComponent("Firefox-\(profile).app")
        let data = try Data(contentsOf: appDir.appendingPathComponent("Contents/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        XCTAssertEqual(plist["CFBundleName"], "Firefox-\(profile)")
        let script = try String(contentsOf: appDir.appendingPathComponent("Contents/MacOS/launcher"))
        XCTAssertEqual(script, FirefoxManager.launcherScript(
            appURL: URL(fileURLWithPath: "/Applications/Firefox.app"), profile: profile))
    }

    func testLaunchArgumentsStartProfileWithoutRemote() {
        XCTAssertEqual(FirefoxManager.launchArguments(profile: "Work \"x\" $y"),
                       ["-no-remote", "-P", "Work \"x\" $y"])
    }

    func testProfileManagerArguments() {
        XCTAssertEqual(FirefoxManager.profileManagerArguments, ["--profilemanager"])
    }

    func testOpenConfigurationCreatesNewInstanceWithArguments() {
        let configuration = FirefoxManager.openConfiguration(arguments: ["-P", "Work"])
        XCTAssertTrue(configuration.createsNewApplicationInstance)
        XCTAssertEqual(configuration.arguments, ["-P", "Work"])
    }

    func testLaunchFailedAlertNamesVersionProfileAndReason() {
        let alert = AppAlert.launchFailed(version: "Firefox Nightly", profile: "Work", reason: "The file is damaged.")
        XCTAssertEqual(alert.title, "Cannot launch Firefox")
        XCTAssertEqual(alert.message, "Firefox Nightly could not be started with the profile \"Work\".\n\nThe file is damaged.")
    }

    func testProfileManagerFailedAlertNamesVersionAndReason() {
        let alert = AppAlert.profileManagerFailed(version: "Firefox", reason: "The file is damaged.")
        XCTAssertEqual(alert.title, "Cannot open Profile Manager")
        XCTAssertEqual(alert.message, "The Profile Manager of Firefox could not be opened.\n\nThe file is damaged.")
    }

    func testUnreadableAlertIncludesReason() {
        XCTAssertTrue(AppAlert.unreadable(reason: "Operation not permitted").message.contains("(Operation not permitted)"))
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }

    private let firefoxURL = URL(fileURLWithPath: "/Applications/Firefox.app")

    func testBuildAppBundleReturnsBundleURL() throws {
        let dir = try makeTempDir()
        let bundle = try FirefoxManager.buildAppBundle(
            version: "Firefox", appURL: firefoxURL, profile: "Work", in: dir)
        XCTAssertEqual(bundle.path, dir.appendingPathComponent("Firefox-Work.app").path)
        XCTAssertEqual(bundle.path, FirefoxManager.appBundleURL(version: "Firefox", profile: "Work", in: dir).path)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: bundle.appendingPathComponent("Contents/MacOS/launcher").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testBuildAppBundleThrowsWhenAppExistsAndKeepsIt() throws {
        let dir = try makeTempDir()
        let bundle = dir.appendingPathComponent("Firefox-Work.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let marker = bundle.appendingPathComponent("marker")
        try Data("old".utf8).write(to: marker)

        XCTAssertThrowsError(try FirefoxManager.buildAppBundle(
            version: "Firefox", appURL: firefoxURL, profile: "Work", in: dir,
            removeExisting: { _ in XCTFail("must not remove without replacing") })
        ) { error in
            guard case let .alreadyExists(url)? = error as? CreateAppError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(url.path, bundle.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: bundle.appendingPathComponent("Contents").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["Firefox-Work.app"])
    }

    func testBuildAppBundleReplacesExistingAppWhenAsked() throws {
        let dir = try makeTempDir()
        let bundle = dir.appendingPathComponent("Firefox-Work.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: bundle.appendingPathComponent("marker"))
        var removed: [URL] = []

        try FirefoxManager.buildAppBundle(
            version: "Firefox", appURL: firefoxURL, profile: "Work", in: dir, replacing: true,
            removeExisting: { url in
                removed.append(url)
                try FileManager.default.removeItem(at: url)
            })

        XCTAssertEqual(removed.map(\.path), [bundle.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("marker").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: bundle.appendingPathComponent("Contents/MacOS/launcher").path))
    }

    func testBuildAppBundleKeepsExistingAppWhenRemovalFails() throws {
        let dir = try makeTempDir()
        let bundle = dir.appendingPathComponent("Firefox-Work.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        struct RemovalFailed: Error {}

        XCTAssertThrowsError(try FirefoxManager.buildAppBundle(
            version: "Firefox", appURL: firefoxURL, profile: "Work", in: dir, replacing: true,
            removeExisting: { _ in throw RemovalFailed() })
        ) { error in
            XCTAssertTrue(error is RemovalFailed)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: bundle.path), [])
    }

    func testBuildAppBundlePropagatesErrorAndLeavesNothingBehind() throws {
        let dir = try makeTempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        XCTAssertThrowsError(try FirefoxManager.buildAppBundle(
            version: "Firefox", appURL: firefoxURL, profile: "Work", in: dir))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
    }

    func testBuildAppBundleThrowsForMissingDestination() throws {
        let missing = try makeTempDir().appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(try FirefoxManager.buildAppBundle(
            version: "Firefox", appURL: firefoxURL, profile: "Work", in: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testAlreadyExistsErrorNamesTheApp() {
        let error = CreateAppError.alreadyExists(URL(fileURLWithPath: "/Users/me/Desktop/Firefox-Work.app"))
        XCTAssertEqual(error.localizedDescription, "\"Firefox-Work.app\" already exists.")
    }

    func testCreateAppAlerts() {
        let bundle = URL(fileURLWithPath: "/Users/me/Desktop/Firefox-Work.app")
        let created = AppAlert.appCreated(bundle: bundle)
        XCTAssertEqual(created.title, "App created")
        XCTAssertEqual(created.message, "\"Firefox-Work.app\" was created in /Users/me/Desktop.")

        let exists = AppAlert.appExists(
            version: FirefoxVersion(name: "Firefox", url: firefoxURL), profile: "Work", bundle: bundle)
        XCTAssertEqual(exists.title, "App already exists")
        XCTAssertTrue(exists.message.contains("\"Firefox-Work.app\" already exists in /Users/me/Desktop."))
        XCTAssertTrue(exists.message.contains("Trash"))

        let failed = AppAlert.createAppFailed(version: "Firefox", profile: "Work", reason: "Disk full.")
        XCTAssertEqual(failed.title, "Cannot create app")
        XCTAssertEqual(failed.message,
                       "The app for Firefox with the profile \"Work\" could not be created.\n\nDisk full.")
    }
}

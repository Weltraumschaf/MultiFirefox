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

        FirefoxManager.buildAppBundle(
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

        FirefoxManager.buildAppBundle(
            version: "Firefox 120", appURL: URL(fileURLWithPath: "/Users/me/Applications/Firefox 120.app"),
            profile: "Work", in: tempDir)

        let launcherURL = tempDir
            .appendingPathComponent("Firefox 120-Work.app/Contents/MacOS/launcher")
        let content = try String(contentsOf: launcherURL)
        XCTAssertTrue(content.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(content.contains("\"/Users/me/Applications/Firefox 120.app\""))
        XCTAssertTrue(content.contains("Work"))
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
}

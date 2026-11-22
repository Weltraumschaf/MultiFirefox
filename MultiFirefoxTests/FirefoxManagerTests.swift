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
        XCTAssertTrue(FirefoxManager.isFirefoxApp("Minefield.app"))
    }

    func testIsFirefoxAppRejectsNonFirefox() {
        XCTAssertFalse(FirefoxManager.isFirefoxApp("Safari.app"))
        XCTAssertFalse(FirefoxManager.isFirefoxApp("Firefox Folder"))
        XCTAssertFalse(FirefoxManager.isFirefoxApp("NotFirefox.app"))
    }

    func testFilterVersionsStripsAppSuffixAndFilters() {
        let input = ["Firefox 120.app", "Safari.app", "Firefox.app", "Chrome.app"]
        XCTAssertEqual(FirefoxManager.filterVersions(from: input), ["Firefox", "Firefox 120"])
    }

    func testFilterVersionsSortsCaseInsensitively() {
        let input = ["Firefox 90.app", "Firefox 120.app", "Minefield.app"]
        XCTAssertEqual(FirefoxManager.filterVersions(from: input), ["Firefox 120", "Firefox 90", "Minefield"])
    }

    func testBuildAppBundleCreatesExpectedFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        FirefoxManager.buildAppBundle(version: "Firefox 120", profile: "Work", in: tempDir)

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

        FirefoxManager.buildAppBundle(version: "Firefox 120", profile: "Work", in: tempDir)

        let launcherURL = tempDir
            .appendingPathComponent("Firefox 120-Work.app/Contents/MacOS/launcher")
        let content = try String(contentsOf: launcherURL)
        XCTAssertTrue(content.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(content.contains("Firefox 120"))
        XCTAssertTrue(content.contains("Work"))
    }
}

import XCTest
@testable import MultiFirefox

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
}

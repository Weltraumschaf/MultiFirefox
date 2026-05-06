# MultiFirefox Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate MultiFirefox from Objective-C/NIB to Swift + SwiftUI in the existing Xcode project, restoring all three features and adding Sparkle 2.x auto-update.

**Architecture:** `FirefoxManager` (ObservableObject) holds all logic as static pure functions plus instance actions. `ContentView` (SwiftUI) provides a two-column List layout. `MultiFirefoxApp` (@main) is the entry point and hosts Sparkle. The ObjC files are removed atomically in Task 8 when the SwiftUI entry point takes over.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSApplication.terminate), Sparkle 2.x (already added via SPM), XCTest

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `MultiFirefox/FirefoxManager.swift` | ObservableObject: parse profiles, scan versions, launch Firefox, open profile manager, create app bundle |
| Create | `MultiFirefox/ContentView.swift` | SwiftUI two-column List UI, buttons, selection logic, persistence |
| Create | `MultiFirefox/MultiFirefoxApp.swift` | `@main` App entry point, AppDelegate (quit-on-close), Sparkle controller |
| Create | `MultiFirefoxTests/FirefoxManagerTests.swift` | Unit tests for all pure static functions |
| Modify | `Info.plist` | Remove `NSMainNibFile` and `NSPrincipalClass` keys |
| Modify | `.gitignore` | Add `.superpowers/` |
| Delete | `main.m`, `MFF.h`, `MFF.m`, `MainWindow.h`, `MainWindow.m`, `MultiFirefox_Prefix.pch` | Replaced by Swift |
| Delete | `English.lproj/MainMenu.nib`, `English.lproj/InfoPlist.strings` | Replaced by SwiftUI |
| Delete | `Sparkle.framework/` | Replaced by SPM package |

---

### Task 1: Add unit test target

**Files:**
- Create: `MultiFirefoxTests/FirefoxManagerTests.swift`

- [ ] **Step 1: Add test target in Xcode**

In Xcode: **File → New → Target**, choose **macOS → Unit Testing Bundle**. Set:
- Product Name: `MultiFirefoxTests`
- Target to be Tested: `MultiFirefox`
- Language: Swift

Click Finish. Xcode creates `MultiFirefoxTests/MultiFirefoxTests.swift`.

- [ ] **Step 2: Replace the generated file**

In Xcode, select `MultiFirefoxTests/MultiFirefoxTests.swift`, press **Delete → Move to Trash**.
Then **File → New → File → Swift File**, name it `FirefoxManagerTests.swift`, ensure target is `MultiFirefoxTests`.

```swift
import XCTest
@testable import MultiFirefox

final class FirefoxManagerTests: XCTestCase {
}
```

- [ ] **Step 3: Run tests to verify the target works**

Press **Cmd+U**. Expected output in the Test Navigator: 0 tests, 0 failures. Console shows:
```
Test Suite 'All tests' passed at ...
```

- [ ] **Step 4: Commit**

```bash
git add MultiFirefoxTests/
git commit -m "Add unit test target"
```

---

### Task 2: FirefoxManager skeleton + profile parsing (TDD)

**Files:**
- Create: `MultiFirefox/FirefoxManager.swift`
- Modify: `MultiFirefoxTests/FirefoxManagerTests.swift`

- [ ] **Step 1: Create FirefoxManager.swift with skeleton**

In Xcode: **File → New → File → Swift File**, name it `FirefoxManager.swift`, target `MultiFirefox`.

```swift
import Foundation
import AppKit

@MainActor
final class FirefoxManager: ObservableObject {
    @Published var versions: [String] = []
    @Published var profiles: [String] = []

    private static let applicationsPath = "/Applications"
    private static let profilesIniPath =
        ("~/Library/Application Support/Firefox/profiles.ini" as NSString)
            .expandingTildeInPath
}
```

- [ ] **Step 2: Build to confirm it compiles**

Press **Cmd+B**. Expected: no errors (ObjC warnings are fine — old code is still in the project).

- [ ] **Step 3: Write failing tests for parseProfiles**

Add to `FirefoxManagerTests.swift`:

```swift
func testParseProfilesExtractsNames() {
    let ini = """
    [Install]
    Default=Profiles/xyz.default
    [Profile0]
    Name=default
    IsRelative=1
    Path=Profiles/xyz.default
    [Profile1]
    Name=Work
    IsRelative=1
    Path=Profiles/abc.work
    """
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
```

- [ ] **Step 4: Run tests — expect failure**

Press **Cmd+U**. Expected: 4 failures, all saying `'FirefoxManager' has no member 'parseProfiles'`.

- [ ] **Step 5: Implement parseProfiles**

Add inside `FirefoxManager` (before the closing `}`):

```swift
static func parseProfiles(from iniContent: String) -> [String] {
    var names: [String] = []
    for line in iniContent.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("Name=") {
            names.append(String(trimmed.dropFirst(5)))
        }
    }
    let others = names
        .filter { $0 != "default" }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    return names.contains("default") ? ["default"] + others : others
}
```

- [ ] **Step 6: Run tests — expect pass**

Press **Cmd+U**. Expected: 4 tests pass, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add MultiFirefox/FirefoxManager.swift MultiFirefoxTests/FirefoxManagerTests.swift
git commit -m "Add FirefoxManager with profile parsing"
```

---

### Task 3: FirefoxManager — version filtering (TDD)

**Files:**
- Modify: `MultiFirefox/FirefoxManager.swift`
- Modify: `MultiFirefoxTests/FirefoxManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `FirefoxManagerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests — expect failure**

Press **Cmd+U**. Expected: 4 failures saying `'FirefoxManager' has no member 'isFirefoxApp'`.

- [ ] **Step 3: Implement isFirefoxApp and filterVersions**

Add inside `FirefoxManager`:

```swift
static func isFirefoxApp(_ name: String) -> Bool {
    let lower = name.lowercased()
    return (lower.hasPrefix("firefox") || lower.hasPrefix("minefield"))
        && name.hasSuffix(".app")
}

static func filterVersions(from names: [String]) -> [String] {
    names
        .filter { isFirefoxApp($0) }
        .map { String($0.dropLast(4)) }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}
```

- [ ] **Step 4: Run tests — expect pass**

Press **Cmd+U**. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add MultiFirefox/FirefoxManager.swift MultiFirefoxTests/FirefoxManagerTests.swift
git commit -m "Add version filtering to FirefoxManager"
```

---

### Task 4: FirefoxManager — createApplication (TDD)

**Files:**
- Modify: `MultiFirefox/FirefoxManager.swift`
- Modify: `MultiFirefoxTests/FirefoxManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `FirefoxManagerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests — expect failure**

Press **Cmd+U**. Expected: 2 failures saying `'FirefoxManager' has no member 'buildAppBundle'`.

- [ ] **Step 3: Implement buildAppBundle and createApplication**

Add inside `FirefoxManager`:

```swift
static func buildAppBundle(version: String, profile: String, in directory: URL) {
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

    let chmod = Process()
    chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
    chmod.arguments = ["+x", launcher.path]
    try? chmod.run()
    chmod.waitUntilExit()
}

func createApplication(version: String, profile: String) {
    let desktop = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
    Self.buildAppBundle(version: version, profile: profile, in: desktop)
}
```

- [ ] **Step 4: Run tests — expect pass**

Press **Cmd+U**. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add MultiFirefox/FirefoxManager.swift MultiFirefoxTests/FirefoxManagerTests.swift
git commit -m "Add createApplication to FirefoxManager"
```

---

### Task 5: FirefoxManager — filesystem loading and launching

**Files:**
- Modify: `MultiFirefox/FirefoxManager.swift`

- [ ] **Step 1: Add init, load, reloadProfiles, loadVersions, loadProfiles**

Add inside `FirefoxManager`:

```swift
init() { load() }

func load() {
    versions = Self.loadVersions()
    profiles = Self.loadProfiles()
}

func reloadProfiles() {
    profiles = Self.loadProfiles()
}

static func loadVersions() -> [String] {
    guard let enumerator = FileManager.default.enumerator(atPath: applicationsPath) else {
        return []
    }
    var result: [String] = []
    while let name = enumerator.nextObject() as? String {
        let lower = name.lowercased()
        if isFirefoxApp(name) {
            result.append(String((name as NSString).lastPathComponent.dropLast(4)))
            enumerator.skipDescendants()
        } else if !(lower.hasPrefix("firefox") || lower.hasPrefix("minefield")) {
            enumerator.skipDescendants()
        }
    }
    return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

static func loadProfiles() -> [String] {
    guard let content = try? String(contentsOfFile: profilesIniPath, encoding: .utf8) else {
        return []
    }
    return parseProfiles(from: content)
}
```

- [ ] **Step 2: Add launch and openProfileManager**

Add inside `FirefoxManager`:

```swift
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
```

- [ ] **Step 3: Build**

Press **Cmd+B**. Expected: builds without errors.

- [ ] **Step 4: Commit**

```bash
git add MultiFirefox/FirefoxManager.swift
git commit -m "Add filesystem loading and Firefox launching to FirefoxManager"
```

---

### Task 6: ContentView — two-column layout

**Files:**
- Create: `MultiFirefox/ContentView.swift`

- [ ] **Step 1: Create ContentView.swift**

In Xcode: **File → New → File → Swift File**, name it `ContentView.swift`, target `MultiFirefox`.

- [ ] **Step 2: Write the full view**

```swift
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
                        launch()
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
```

- [ ] **Step 3: Build (do not run yet)**

Press **Cmd+B**. Expected: builds without errors. The app still launches via the ObjC NIB — that's expected at this stage.

- [ ] **Step 4: Commit**

```bash
git add MultiFirefox/ContentView.swift
git commit -m "Add ContentView with two-column SwiftUI layout"
```

---

### Task 7: ContentView — selection, persistence, profile reload, and warning

**Files:**
- Modify: `MultiFirefox/ContentView.swift`

- [ ] **Step 1: Replace the body property**

In `ContentView.swift`, replace the entire `body` computed property with:

```swift
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
        if manager.profiles.count < 2 {
            showingProfileWarning = true
        }
    }
    .onChange(of: selectedVersion) { _, newVersion in
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
    }
    .alert("You need to create a profile!", isPresented: $showingProfileWarning) {
        Button("Open Profile Manager") { openProfileManager() }
        Button("Cancel", role: .cancel) {}
    } message: {
        Text("You only have one profile set up for Firefox. To run multiple versions side by side, you must have multiple profiles defined.")
    }
}
```

- [ ] **Step 2: Add helper methods**

Add inside `ContentView`, after the `createApp()` function:

```swift
private func restoreSelection() {
    let lastVersion = UserDefaults.standard.string(forKey: "lastVersion")
    let lastProfile = UserDefaults.standard.string(forKey: "lastProfile")
    selectedVersion = lastVersion.flatMap { manager.versions.contains($0) ? $0 : nil }
        ?? manager.versions.first
    selectedProfile = lastProfile.flatMap { manager.profiles.contains($0) ? $0 : nil }
        ?? manager.profiles.first
}

private func autoSelectProfile(for version: String) {
    let base = (version as NSString).lastPathComponent
    let isPlain = base.lowercased() == "firefox"
    selectedProfile = manager.profiles.first { profile in
        (isPlain && profile == "default") || profile.hasPrefix(base)
    } ?? manager.profiles.first
}
```

- [ ] **Step 3: Build**

Press **Cmd+B**. Expected: builds without errors.

- [ ] **Step 4: Commit**

```bash
git add MultiFirefox/ContentView.swift
git commit -m "Add selection persistence, auto-select, profile reload, and one-profile warning"
```

---

### Task 8: MultiFirefoxApp entry point + atomic swap from ObjC

**Files:**
- Create: `MultiFirefox/MultiFirefoxApp.swift`
- Modify: `Info.plist`
- Delete from project + disk: `main.m`, `MainWindow.h`, `MainWindow.m`, `MFF.h`, `MFF.m`, `MultiFirefox_Prefix.pch`, `English.lproj/MainMenu.nib`, `English.lproj/InfoPlist.strings`

> **Important:** Steps 2–4 must all be done before building. Having `@main` in a Swift file while `main.m` is still in the project causes a linker error (two `main` symbols).

- [ ] **Step 1: Create MultiFirefoxApp.swift**

In Xcode: **File → New → File → Swift File**, name it `MultiFirefoxApp.swift`, target `MultiFirefox`.

```swift
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

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.updater.checkForUpdates()
                }
            }
        }
    }
}
```

- [ ] **Step 2: Update Info.plist**

Open `Info.plist` in Xcode. Delete these two keys (select the row, click the minus button):
- `NSMainNibFile`
- `NSPrincipalClass`

Leave all other keys (`SUFeedURL`, `CFBundleVersion`, `CFBundleIconFile`, etc.) untouched.

- [ ] **Step 3: Remove ObjC files from project**

In the Xcode navigator, select each file below, press **Delete**, choose **Move to Trash**:
- `main.m`
- `MainWindow.h`
- `MainWindow.m`
- `MFF.h`
- `MFF.m`
- `MultiFirefox_Prefix.pch`
- `English.lproj/MainMenu.nib`
- `English.lproj/InfoPlist.strings`

- [ ] **Step 4: Build and run**

Press **Cmd+R**. Expected: the app launches showing the SwiftUI two-column window. Firefox versions appear in the left list if you have any installed in `/Applications`. Profiles appear in the right list. The app menu contains **Check for Updates…** after **About MultiFirefox**.

- [ ] **Step 5: Commit**

```bash
git add MultiFirefox/MultiFirefoxApp.swift Info.plist
git commit -m "Switch to SwiftUI entry point, wire Sparkle, remove ObjC files"
```

---

### Task 9: Final cleanup

**Files:**
- Modify: `.gitignore`
- Delete from disk: `Sparkle.framework/`
- Modify: Xcode project build settings (deployment target, prefix header)

- [ ] **Step 1: Delete Sparkle.framework from disk and project**

```bash
rm -rf /Users/sst/src/private/MultiFirefox/Sparkle.framework
```

If `Sparkle.framework` still appears in the Xcode navigator under Linked Frameworks or the project tree, select it and press **Delete → Remove Reference**.

- [ ] **Step 2: Clear obsolete prefix header build settings**

In Xcode: click **MultiFirefox** project → **MultiFirefox** target → **Build Settings** tab. Search for `prefix`. Set:
- `Precompile Prefix Header` → **No**
- `Prefix Header` → *(clear the value, leave empty)*

- [ ] **Step 3: Set deployment target**

Still in **Build Settings**, search for `deployment`. Set `macOS Deployment Target` to **13.0**.

- [ ] **Step 4: Update .gitignore**

```bash
echo ".superpowers/" >> /Users/sst/src/private/MultiFirefox/.gitignore
```

- [ ] **Step 5: Build — verify clean**

Press **Cmd+B**. Expected: 0 errors, 0 warnings.

- [ ] **Step 6: Commit**

```bash
git add .gitignore
git commit -m "Clean up: remove Sparkle.framework, clear prefix header settings, set deployment target 13.0"
```

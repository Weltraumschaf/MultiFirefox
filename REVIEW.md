# Code Review 

## Bugs

1. **The saved profile is never restored.** `restoreSelection()` sets `selectedVersion`, which
   triggers `onChange(of: selectedVersion)` → `autoSelectProfile(for:)`. That overwrites the restored
   `lastProfile` with "default" or the first profile. (`ContentView.swift`, `onAppear` / `onChange`)
2. **A failed launch quits silently.** `launch(version:profile:)` runs `try? p.run()` and then always
   calls `NSApplication.shared.terminate(nil)`. If the launch fails, the app just exits with no
   message. (`FirefoxManager.swift`, `launch`)
3. **Shell injection in Create App.** `buildAppBundle` puts `version` and `profile` straight into a
   bash script inside double quotes. A profile name containing `"`, `$` or a backtick runs as shell
   code. The same values go unescaped into the Info.plist XML (`&` or `<` breaks it) and into
   `CFBundleIdentifier` (spaces and underscores make an invalid ID). Quote properly for the shell and
   build the plist with `PropertyListSerialization`.
4. **Create App fails silently.** Every file operation uses `try?`, an existing bundle on the Desktop
   is overwritten, and the user gets no feedback on success or failure.
5. ✅ **`parseProfiles` takes `Name=` from any section**, not only `[ProfileN]`, and doesn't remove
   duplicates. Duplicate names break `List(id: \.self)`. It also picks the default profile by the name
   "default" rather than the `Default=1` flag in the file. *Fixed: sections are filtered, duplicates
   removed, and the default comes from `[Install…] Default=<path>`, then a `[ProfileN]` with
   `Default=1`, then the name "default". It is listed first and auto-selected.*

## Security / distribution

6. ✅ **The Sparkle update feed is upstream's S3 bucket**
   (`https://s3.amazonaws.com/mff_sparkle/MultiFirefoxAppcast2.xml`), and there's no `SUPublicEDKey`.
   If that abandoned bucket name is ever re-registered by someone else, they control what your users
   get as updates. Point it at your own feed and sign updates (EdDSA), or turn the updater off for now.
   *Mitigated: the upstream `SUFeedURL` is removed and the updater is switched off via
   `MultiFirefoxApp.updatesEnabled` (Sparkle stays linked). Before enabling it again, add an own
   `SUFeedURL` and `SUPublicEDKey`.*
7. **Hardened runtime isn't enabled** (`ENABLE_HARDENED_RUNTIME`), and notarization requires it.
   `Info.plist` also has outdated entries: `CFBundleSignature`, `CFBundleDevelopmentRegion = English`
   (should be `en`), and no `CFBundleShortVersionString`.

## Code quality

8. ✅ **The version-filter tests don't test the real code.** `filterVersions(from:)` is only used by
   tests; the app uses `loadVersions()`, which repeats the logic separately.
   *Fixed: `loadVersions(in:)` now only walks the folder and hands the found paths to
   `filterVersions(from:)`; tests also run `loadVersions(in:)` on a temporary folder.*
9. **Firefox is only looked for in `/Applications`**; `~/Applications` is ignored. The `Minefield`
   prefix is long obsolete.
10. **Launching goes through `/usr/bin/open`.** `NSWorkspace.openApplication(at:configuration:)` with
    `createsNewApplicationInstance = true` and `arguments` would report errors properly.
11. **Double-click to launch is attached to the row text** with `onTapGesture(count: 2)`, which can
    delay single-click selection. `.contextMenu(forSelectionType:primaryAction:)` (macOS 13+) is the
    intended API for this.
12. **Possible gap with Firefox's new profiles (unverified):** Firefox's newer profile switcher keeps
    data under `Profile Groups/`. Profiles made through it may not be listed in `profiles.ini`, so this
    app wouldn't show them.

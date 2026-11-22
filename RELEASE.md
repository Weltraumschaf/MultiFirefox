# Releasing MultiFirefox

MultiFirefox is distributed **without a paid Apple Developer account**:

- signed with a free **self-signed code-signing certificate** (not notarized),
- published as a zip on **GitHub Releases**,
- installed via the Homebrew tap
  [Weltraumschaf/homebrew-tap](https://github.com/Weltraumschaf/homebrew-tap),
- updated in place by **Sparkle** (EdDSA-signed appcast on GitHub Pages).

## Current State

- Sparkle 2.9.x is added as a Swift package (`Package.resolved` is committed).
- `SPUStandardUpdaterController` is wired up in
  `MultiFirefox/MultiFirefoxApp.swift`, but disabled via
  `updatesEnabled = false`.
- The app is not sandboxed, so Sparkle needs no extra XPC services or
  entitlements.
- Hardened runtime is enabled for Release builds; the app has its own bundle
  ID (`de.weltraumschaf.MultiFirefox`).

## Gatekeeper Without Notarization

Downloaded apps carry the `com.apple.quarantine` extended attribute. A
non-notarized app with that attribute is blocked on first launch. Since macOS
15 the Control-click → Open bypass is gone; users must either:

- go to **System Settings → Privacy & Security → "Open Anyway"**, or
- run `xattr -dr com.apple.quarantine /Applications/MultiFirefoxNG.app`.

The Homebrew cask removes the quarantine attribute in `postflight`, so tap
users are not affected. Sparkle strips quarantine from updates it installs,
so only the very first manual install needs approval.

Homebrew 5.0 deprecated `--no-quarantine`, and casks failing Gatekeeper are
removed from the *official* `homebrew/cask` repo (since September 2026).
This does not apply to a personal tap, which is why the cask lives there.
References: [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks),
[Deprecating, Disabling and Removing Casks](https://docs.brew.sh/Deprecating-Disabling-and-Removing-Casks).

## One-Time Setup

### 1. Self-Signed Code-Signing Certificate

Ad-hoc signatures (`codesign -s -`) change with every build, so macOS treats
each update as a different app and re-prompts for permissions (e.g. the App
Data / TCC access to Firefox's `profiles.ini`). A self-signed certificate gives
a stable identity across releases.

1. Keychain Access → Certificate Assistant → **Create a Certificate…**
   - Name: `MultiFirefox Signing` (any name; used as the signing identity)
   - Identity Type: Self-Signed Root
   - Certificate Type: **Code Signing**
   - Validity: tick "Let me override defaults" and pick a long period
     (e.g. 3650 days).
2. Export certificate + private key as `.p12` and **back it up** (password
   manager). Losing it means the next release looks like a different app.
3. Verify: `security find-identity -v -p codesigning` lists it.
4. In Xcode, Release configuration of the `MultiFirefox` target:
   - `CODE_SIGN_STYLE = Manual`
   - `CODE_SIGN_IDENTITY = "MultiFirefox Signing"`
   - `DEVELOPMENT_TEAM` empty (no team for self-signed)
   - keep `ENABLE_HARDENED_RUNTIME = YES`

   Debug can stay on automatic signing with the Apple Development identity.

### 2. Sparkle EdDSA Keys

1. Run Sparkle's `generate_keys` once (in the SwiftPM artifacts:
   `…/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`, or from the
   Sparkle release tarball). The private key is stored in the login keychain.
2. Back up the private key: `generate_keys -x sparkle_private_key` → store it
   in a password manager (and later as a GitHub secret). Delete the file.
3. Add the printed public key to `Info.plist` as `SUPublicEDKey`.

### 3. Feed URL and App Changes

- Enable GitHub Pages for the MultiFirefox repo (branch `gh-pages`, root).
- Add to `Info.plist`:
  - `SUFeedURL` = `https://weltraumschaf.github.io/MultiFirefox/appcast.xml`
  - `SUEnableAutomaticChecks` = `true` (optional; otherwise Sparkle asks on
    second launch)
- Remove the `updatesEnabled` flag in `MultiFirefoxApp.swift`, or derive it
  from the presence of `SUFeedURL` in the bundle.

### 4. Versioning

Sparkle compares `CFBundleVersion`. It is currently `2.5.0`, identical to the
marketing version. Switch `CURRENT_PROJECT_VERSION` to a monotonically
increasing integer build number (1, 2, 3, …) and bump it on every release.
`MARKETING_VERSION` stays the human-readable version (`2.5.0`).

### 5. Homebrew Cask

Casks in a tap must live in a `Casks/` directory. Create
`Casks/multifirefox.rb` in `Weltraumschaf/homebrew-tap`:

```ruby
cask "multifirefox" do
  version "2.5.0"
  sha256 "<sha256 of the release zip>"

  url "https://github.com/Weltraumschaf/MultiFirefox/releases/download/v#{version}/MultiFirefoxNG-#{version}.zip"
  name "MultiFirefox"
  desc "Launch different Firefox versions with different profiles"
  homepage "https://github.com/Weltraumschaf/MultiFirefox"

  livecheck do
    url "https://weltraumschaf.github.io/MultiFirefox/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "MultiFirefoxNG.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/MultiFirefoxNG.app"]
  end

  zap trash: [
    "~/Library/Preferences/de.weltraumschaf.MultiFirefox.plist",
    "~/Library/Caches/de.weltraumschaf.MultiFirefox",
  ]

  caveats <<~EOS
    MultiFirefox is not notarized by Apple. The quarantine attribute is
    removed on install so Gatekeeper does not block it.
  EOS
end
```

Also update the tap's `README.md` (it currently only lists formulas):

```sh
brew install --cask weltraumschaf/tap/multifirefox
```

Check the cask with `brew audit --cask --tap weltraumschaf/tap multifirefox`
and `brew style weltraumschaf/tap`.

## Release Steps

To be automated in `scripts/release.sh`, later in CI.

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, commit.
2. Archive:
   ```sh
   xcodebuild archive -scheme MultiFirefox -configuration Release \
     -archivePath build/MultiFirefox.xcarchive
   ```
3. Export the app from the archive (no notarization; `developer-id` export
   requires a paid account, so copy the app directly):
   ```sh
   ditto build/MultiFirefox.xcarchive/Products/Applications/MultiFirefoxNG.app \
     build/release/MultiFirefoxNG.app
   ```
4. Verify the signature:
   ```sh
   codesign --verify --deep --strict --verbose=2 build/release/MultiFirefoxNG.app
   codesign -dvv build/release/MultiFirefoxNG.app   # Authority=MultiFirefox Signing
   ```
5. Package (Sparkle prefers zip or dmg):
   ```sh
   cd build/release
   ditto -c -k --keepParent MultiFirefoxNG.app MultiFirefoxNG-<version>.zip
   ```
6. Release notes: put `MultiFirefoxNG-<version>.md` (or `.html`) next to the
   zip.
7. Generate the appcast (signs the zip with the EdDSA key from the keychain):
   ```sh
   generate_appcast \
     --download-url-prefix https://github.com/Weltraumschaf/MultiFirefox/releases/download/v<version>/ \
     build/release
   ```
   Keep previous `appcast.xml` in `build/release` before running so older
   entries are preserved (check it out from `gh-pages` first).
8. Publish the GitHub release:
   ```sh
   git tag v<version> && git push origin v<version>
   gh release create v<version> build/release/MultiFirefoxNG-<version>.zip \
     --notes-file build/release/MultiFirefoxNG-<version>.md
   ```
9. Deploy `appcast.xml` to the `gh-pages` branch.
10. Update the cask in `homebrew-tap`: set `version` and
    `sha256` (`shasum -a 256 MultiFirefoxNG-<version>.zip`), commit, push.

## GitHub Actions (optional)

macOS runner with these secrets:

- self-signed certificate `.p12` and its password (imported into a temporary
  keychain)
- Sparkle EdDSA private key (passed to `generate_appcast --ed-key-file -`)
- a token with push access to `homebrew-tap` to bump the cask

Check that the runner's Xcode can build the project — local development uses
Xcode 27.1, and GitHub runners often lag behind.

## Repository Housekeeping

- `README` is still the upstream text (mentions Objective-C, changelog stops at
  2.4.0) — update it, including install instructions (Homebrew + manual
  "Open Anyway") and a note that the app is not notarized.
- Rename `MITLicense.txt` to `LICENSE` so GitHub detects it; keep Dave
  Martorana's copyright line as required by the MIT license.
- The product is named `MultiFirefoxNG`, the repo and bundle use
  "MultiFirefox". Settle on a name before the first release — renaming the
  `.app` later complicates Sparkle updates and the cask.

## Suggested Order

1. Create and back up the self-signed certificate; switch Release signing.
2. Generate and back up Sparkle keys.
3. Add `SUFeedURL`/`SUPublicEDKey`, enable the updater, fix versioning.
4. Write `scripts/release.sh` and do one manual release (2.5.0).
5. Add the cask to the tap and install it via `brew`.
6. Release 2.5.1 and verify the Sparkle update works without a permission
   re-prompt.
7. Move the pipeline to CI.

# Upstream build log (macOS) — 2026-10-01

Goal: build and run unmodified upstream Codenotch (commit `f295939`, MARKETING_VERSION 1.20.0) before changing code.

## Procedure per README.md / CONTRIBUTING.md / Makefile

```sh
brew install xcodegen create-dmg   # once (NOT run: no system installs allowed)
make build                         # = xcodegen generate + xcodebuild ... Debug build
make run                           # build + launch
make test                          # unit tests
```

`make build` runs `gen` first (`xcodegen generate`, then copies `Package.resolved`), then `xcodebuild -project Codenotch.xcodeproj -scheme Codenotch -destination platform=macOS,arch=arm64 -configuration Debug <DEV_SIGN> build`. The Makefile picks ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) when no Developer ID / Apple Development identity exists, so no Apple account is needed.

## Toolchain on this Mac

| Item | Result |
|---|---|
| macOS | 26.6.2 (25G83), arm64 |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` |
| `/Applications/Xcode*.app` | none |
| `xcodebuild -version` | `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance` |
| `swift --version` | swift-driver 1.148.6, Apple Swift 6.3 (swiftlang-6.3.0.123.5), target arm64-apple-macosx26.0 (Command Line Tools) |
| `xcodegen` | not installed (`which xcodegen` empty) |
| `create-dmg` | not checked (only needed for dmg targets) |
| Code-signing identities | `security find-identity -v -p codesigning`: 0 valid identities (ad-hoc fallback applies) |
| brew / make | `/opt/homebrew/bin/brew`, `/usr/bin/make` present |
| cargo / rustc / node | cargo 1.97.1, node v26.0.0 (relevant for `windows/`) |

## Result: BLOCKED at step 1 (`make build`)

```
$ make build
xcodegen generate
make: xcodegen: No such file or directory
make: *** [gen] Error 1
```

Nothing was built or launched, so there was no app to quit. `make build` left no files behind (git status shows only pre-existing untracked agent files).

## Missing, precisely

1. **xcodegen** — `brew install xcodegen` (README step). Blocks `make gen`, hence every build target.
2. **Full Xcode** — only Command Line Tools are installed. `xcodebuild` refuses to run without Xcode.app, and the project needs the macOS SDK app targets, SwiftUI/AppKit build tooling and XCTest via Xcode. Deployment target is macOS 15.0; an Xcode with the macOS 26 SDK era toolchain is expected (exact minimum Xcode version is not stated upstream; UNVERIFIED).
3. Not blocking for local Debug: signing identity (ad-hoc is automatic), notarisation profile (`UsageNotch`, only for `make release`), `create-dmg` (only `dmg`/`release`).

Not done on purpose: no brew installs, no Xcode install, no `xcode-select -s`, no signing or keychain changes.

## Unblock steps for Tim

```sh
# install Xcode from the App Store / developer.apple.com, launch once to accept the license
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
brew install xcodegen
cd ~/dev/agents/bdb-ao-codenotch && make run && make test
```

The Makefile also exports `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` automatically if that path exists, so `xcode-select -s` is optional.

## Windows port (not attempted here)

`windows/` is Rust/Tauri 2 (`cargo test --locked`, `node --test test-codex-headline.cjs` per windows/README.md). cargo is installed on this Mac, but the crate targets Windows/WebView2 (a `tauri.linux.conf.json` and `scripts/run-linux.sh` exist; macOS not documented), so a Windows build is not verifiable on this machine. UNVERIFIED whether `cargo test` runs on macOS.

## Decision 2026-10-01: build in CI

No local Xcode install. `.github/workflows/bdb-build.yml` runs `make test-ci` and `make build-ci` on `macos-26` (xcodegen via brew), uploads `Codenotch-adhoc.zip`, and builds/tests `windows/` on `windows-latest`. Not yet run: a first run needs the repo pushed to the private origin and Actions enabled. Check in its log: the Xcode version on the runner, `brew install xcodegen` success, and `make test-ci` results.

## SwiftPM build with Command Line Tools only (no Xcode) — works, 2026-10-01

Tim rejected the 15 GB Xcode install, so a BDB-only SwiftPM path exists beside upstream's xcodegen one (`project.yml` and the Makefile's upstream targets are untouched).

```sh
swift build                 # debug; ~130 s cold, fetches Sparkle + SwiftNIO from GitHub
make bdb-build              # = Scripts/bdb-bundle.sh: release build, app bundle, ad-hoc sign, dmg
open build/bdb/Codenotch.app
```

Results on this Mac (CLT only, Swift 6.3, SDK MacOSX26.4):

| Step | Result |
|---|---|
| `swift build` | OK, first try, 0 errors |
| `Scripts/bdb-bundle.sh` | OK. `build/bdb/Codenotch.app` (ad-hoc signed, `codesign --verify --deep --strict` passes) and `build/bdb/Codenotch.dmg` (9,996,328 bytes) |
| Launch | `open` started it, process alive after 8 s, quit cleanly via AppleScript, no crash report in `~/Library/Logs/DiagnosticReports` |
| `swift build --build-tests` / `swift test` | **FAILS: `error: no such module 'XCTest'`** in every test file. CLT ships Swift Testing (`Testing.framework`) but no XCTest, and the suite is XCTest. Tests only run via Xcode (`make test`, or the CI `macos` job). |

What the SwiftPM path needed:
- `Package.swift` mirrors `project.yml` (macOS 15, Sparkle >= 2.6.0, NIOHTTP1/NIOPosix; the pins in `Package.resolved` apply: Sparkle 2.9.6, swift-nio 2.102.0). Swift language mode 5.
- The vendored zstd C decoder became its own target `CZstd` (SwiftPM has no bridging header); one upstream edit: `#if SWIFT_PACKAGE import CZstd #endif` in `Sources/Providers/ClaudeDesktopUsageCache.swift`.
- Asset catalog (needs `actool`): `AppIcon` converted to `AppIcon.icns` with `iconutil`; `MenuBarIcon` and `glyph-*` SVGs copied to `Resources/` as plain files, which `NSImage(named:)` can find. UNVERIFIED: whether SVG files load that way and the menu bar / provider glyphs render; the code falls back when `NSImage(named:)` returns nil, but glyph appearance was not inspected visually.
- `Localizable.xcstrings` (needs Xcode's compiler): `Scripts/bdb-xcstrings.py` writes `<lang>.lproj/Localizable.strings` (plain JSON conversion; the catalog only has simple string units). Not verified in the running UI.
- `Info.plist` template variables filled by `sed` from `project.yml` versions; `CFBundleIconFile` added.
- Sparkle.framework copied from `.build/artifacts` into `Contents/Frameworks` with an `@executable_path/../Frameworks` rpath.

Limits of this path:
- Ad-hoc signed, no hardened runtime, no notarisation: quarantined downloads need `xattr -dr com.apple.quarantine`. Keychain "Always Allow" does not persist across rebuilds (as upstream warns for ad-hoc builds).
- Sparkle auto-update points at upstream's feed (`hivinz.com/appcast.xml`, upstream EdDSA key). A BDB build must not self-update from it; disable or repoint before distributing (not done here).
- No unit tests locally (above). The hardened-runtime `disable-library-validation` entitlement from `make build-ci` is not needed because the runtime is off.
- Not exercised beyond launch: usage providers, notch rendering, settings, localisation.

CI: `.github/workflows/bdb-build.yml` gained a `swiftpm` job (`make bdb-build`, uploads `Codenotch-swiftpm-dmg`) next to the xcodegen `macos` job, which still runs the XCTest suite.

## BDB branding and updates off (2026-10-01)

`make bdb-build` now produces `build/bdb/BDB AO Codenotch.app` and `build/bdb/BDB-AO-Codenotch.dmg` (volume name "BDB AO Codenotch"). The upstream `project.yml` path is unchanged and still builds the stock Codenotch.

- **Identity**: bundle id `dev.bdb.ao-codenotch` (own prefs domain and caches, no collision with an installed upstream `com.vinz.codenotch`), `CFBundleDisplayName`/`CFBundleName` = "BDB AO Codenotch". Executable inside stays `Codenotch`. Logger subsystems and a few internal strings still say `com.vinz.codenotch` / "Codenotch" (not worth merge conflicts).
- **Icon**: BDB variant in `Brand/AppIcon.iconset` (paper squircle, ink notch, green ring; oklch palette converted to sRGB), generated by `Scripts/bdb-icon.py` (Pillow), turned into `.icns` by `iconutil` at bundle time.
- **Attribution**: `NSHumanReadableCopyright` "Based on Codenotch by vinzdg (MIT)", `Credits.rtf` for the About panel, and the MIT text copied to `Resources/LICENSE-Codenotch-MIT.txt`. Repo `LICENSE` untouched. Whether the About panel shows the credits was not checked visually.
- **Updates off**: the bundle script deletes `SUFeedURL`, `SUPublicEDKey`, `SUScheduledCheckInterval` and sets `SUEnableAutomaticChecks=false`. In code, `Sources/BDB/BDBBrand.swift` exposes `updatesAvailable` (true only when `SUFeedURL` exists), and `Updater` ignores `start()`, `checkNow()` and the automatic setting when it is false; Settings hides the "Check for updates", Preview and Check now controls. Upstream builds still have a feed, so they are unaffected. To add a BDB feed later: set `SUFeedURL`/`SUPublicEDKey` in the script.
- **Verified**: `codesign --verify --deep --strict` OK (ad-hoc); PlistBuddy shows `dev.bdb.ao-codenotch`, "BDB AO Codenotch", `SUFeedURL`/`SUPublicEDKey` absent, no "hivinz" in the Info.plist; app launched, alive 12 s, quit via AppleScript, 0 crash reports. Settings pane and the hidden update controls were not inspected visually. `build/bdb/` may still hold older `Codenotch.app`/`Codenotch.dmg` from before the rebrand (ignored by git).

## P1 keep-awake and P2 versions implemented (2026-10-01)

Code: `Sources/BDB/` (`BDBKeepAwakeCore.swift` pure logic, `BDBVersions.swift`, `BDBHub.swift` I/O + IOPMAssertion, `BDBViews.swift` Settings pane "BDB" and the floating panel, `BDBSelfTest.swift`). Upstream touch points: `SettingsView.swift` (new `.bdb` section, `bdb.settingsStart` default for screenshots), `AppDelegate.swift` (start/shutdown, `--bdb-selftest`). Everything is off until "Enable BDB features" is switched on (`bdb.enabled`).

- **Busy heuristic**: processes found via `ps -axo pid,ppid,time,command`; matches executable basename `claude|agy|opencode|codex` and node wrappers for `@anthropic-ai/claude-code`, `@openai/codex`, `opencode`; anything inside `.app/Contents` is ignored (Claude Desktop). Busy = CPU time of the process plus all descendants grew by more than 3 % of a core since the last 5 s scan. No transcript-write signal (not implemented).
- **Modes**: off, auto (5 min grace after last busy agent), always, timer (30 min, 1 h, 2 h, until a clock time; falls back to the previous mode when it ends). Assertion `PreventUserIdleSystemSleep` is held in-process and released on mode change, disable and quit.
- **Versions**: installed from `/opt/homebrew/lib/node_modules/@hybridlabor-api/{aos,bdb-agent-orchestrator}/package.json` (AO row hidden when absent), latest from `registry.npmjs.org/<pkg>/latest` at most every 6 h; `aos` is never executed.
- **Self-test**: `make bdb-selftest` (`Codenotch --bdb-selftest`), 35 asserts, ALL PASSED. XCTest remains unavailable.

Verified on this Mac (CLT only):
- `pmset -g assertions`: mode off -> no BDB assertion; mode always -> `PreventUserIdleSystemSleep named: "BDB AO Codenotch: coding agent active"`; after quitting the app 0 assertions.
- Fake agent: a copy of `/usr/bin/yes` (ad-hoc re-signed) renamed `claude` in a temp dir raised "Claude Code" from 6 running / 1 busy to 7 / 2 busy and "Awake: 1 agent busy" to "2 agents busy". Real agent sessions on this machine are also counted (they cannot be excluded), so the assertion in auto mode was held by them too; the grace period timing (5 min) and the timer modes were NOT exercised live, only in the self-test.
- Panel shows `AOS 4.12.1 · update 4.13.2 available` (real registry data). AO row not shown (package not installed here).
- Screenshots: `docs/bdb/screens/settings-bdb-pane.png`, `panel-grouped.png`, `panel-fake-claude-added.png`.
- Note: the Bash tool sandbox hides other processes and blocks screen capture; process tests and screenshots ran through the computer-use script tool instead. Windows equivalent (P1/P2) is not implemented.

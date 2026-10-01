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

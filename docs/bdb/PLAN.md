# BDB AO Codenotch — phased plan

Status date 2026-10-01. Baseline: upstream `f295939` (1.20.0). **Nothing below has been run**: the upstream macOS app could not be built on this machine (see `BUILD.md`: no Xcode, no xcodegen). Every claim about upstream code is from reading source; build and test steps are therefore UNVERIFIED until Xcode is installed.

## Principles

- **One repo, two ports**: macOS Swift in `Sources/`, Windows Rust/Tauri in `windows/codenotch/src/`. Each feature ships in both, behind the same on-disk contract (file formats, setting names), so the two stay in sync.
- **AOS alone must work; AO is optional.** AOS signals come from files and processes (agenttrail, `production_artifacts/state.json`, process table). The AO daemon is an additive source that never gates a feature.
- **No hooks written into other tools' config.** (Rejected: agents-sleep-preventer writes into `~/.claude/settings.json`.) Detect by process and files only. Note upstream's Windows `hooks_install.rs` does install Claude hooks on explicit user action — leave as is, do not extend to BDB features.
- Isolate BDB code in new files/folders (`Sources/BDB/`, `windows/codenotch/src/bdb/`) to keep upstream merges (`git fetch upstream`) cheap. Hook points in upstream files stay to a few lines.
- **Colours (decided 2026-10-01)**: ignore the old purple BDB CI. New UI follows the light green-beige of the AOS Store UI (`~/dev/bdb-dev/bdb-dev-optimized-agent-skills/lib/store-ui/index.html`): `--paper oklch(0.97 0.012 95)`, `--paper-2 oklch(0.93 0.018 95)`, `--green oklch(0.72 0.17 145)`, `--green-deep oklch(0.40 0.12 145)`, ink `oklch(0.18 0.025 265)`. Green for done / merge-ready is fine and matches upstream's green. (Values taken from Tim's message, file not re-read here.)
- **Upstream sync: merge, not rebase** (`git fetch upstream && git merge upstream/main`). **All BDB features are off by default.**
- **Build via GitHub Actions, not local Xcode**: `.github/workflows/bdb-build.yml` (see Phase 0).
- Private repo only; license MIT and attribution stay.

## Upstream architecture relevant to us (read, not run)

- macOS: `Sources/Sessions/` has one `AgentActivityMonitor` per tool (protocol: `sessions`, `sessionsPublisher`, `start()`, `stop()`), merged by `ActivityCoordinator` (`isBusy`, `activeIDs`, `setEnabled`) into `AgentSession` (`state`: busy/waiting/success/idle, `pid`, `since`, `waitingFor`). `ActivitySummary` reduces sessions to working/waiting/success/idle. `ProcessLiveness` checks pid + start time. Existing monitors: Claude, Codex, Cursor, Antigravity, Grok, Kimi, Gemini, Pi, Ollama, LM Studio. OpenCode has only `OpenCodeGeminiActivity.swift` and a usage provider (`Providers/OpenCodeProvider.swift`) — **no generic OpenCode session monitor found on macOS (UNVERIFIED beyond file names)**.
- macOS UI: `Sources/Notch/` (panel, layout, view model, root view), `Sources/Features/TooltipCard.swift` (hover card), `Sources/App/` (AppDelegate, StatusItemController, SessionChime, Updater), `Sources/Settings/` (Preferences, SettingsView), `Sources/Model/UsageStore.swift`, `NotificationChannel.swift`, `ThresholdNotifier.swift`. Extra: `Sources/PhoneLink/` (local server for the phone app; `PhoneLinkSnapshotBuilder` defines what the phone sees).
- Windows: `windows/codenotch/src/activity.rs` (`Activity{provider,state,name,detail,since}`; Claude, Codex, Cursor, Antigravity), `watcher.rs`, `state.rs`, `config.rs`, `usage.rs`, `server.rs`, `opencode.rs`, `agy_cli.rs`, `tray.rs`/`traymenu.rs`, `i18n.rs`; UI in `windows/codenotch/ui/*.html` (notch.html = pill + hover card); helper `windows/codenotch-hook`.
- Tests: macOS `Tests/*Tests.swift` (XCTest, `make test`); Windows `cargo test --locked` plus `node --test` scripts in `windows/`.
- Localisation: five-plus languages (`Sources/Localizable.xcstrings`, `i18n.rs`); new strings need en/de at minimum, others fall back to English (check `LocalizationTests`/`CatalogCoverageTests` — they may fail on missing keys; UNVERIFIED).

## Phase 0 — Unblock and baseline (before any code)

1. **No local Xcode** (Tim's decision). Builds and tests run in GitHub Actions: `.github/workflows/bdb-build.yml` has a `macos` job (runner `macos-26`, `brew install xcodegen`, `make test-ci`, `make build-ci`, uploads ad-hoc signed `Codenotch-adhoc.zip`) and a `windows` job (`windows-latest`, `cargo build/test --locked`, UI node checks, uploads debug exes). No secrets, no notarisation, no release. Upstream's `ci.yml`, `package.yml`, `windows.yml` are guarded by `github.repository == 'vinzdg/codenotch'` and are skipped in the fork; `windows-package.yml` also runs on manual `workflow_dispatch` only (and is harmless without the signing secret). The BDB jobs are guarded the other way round, so they never run upstream.
2. Create the private GitHub repo and push `main` (needs Tim's GO; master session does it). First CI run is the first real build (UNVERIFIED until it runs).
3. Windows: validated in CI only; this Mac cannot run the Windows port.

## P1 — Keep-awake for all coding agents

**Behaviour (decided)**: three modes, default off. (1) **Auto**: hold a no-idle-sleep assertion while a detected coding agent is *working* (busy), release when none is busy. (2) **Always on**: held until switched off. (3) **Timer**: held for a chosen duration or until a chosen clock time, then falls back to the previous mode. Mode picker in Settings and in the menu/tray; the timer's remaining time is shown. Mode and timer deadline persist across restarts (deadline in the past = expired). Covers Claude Code, agy (Antigravity CLI), OpenCode, Codex; AO-spawned sessions are covered because they are ordinary child processes of those CLIs (AO PID list is a bonus, not required).

**macOS design**
- Primitive: `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, ...)` held in-process (no child process to leak); release on state change and on quit. Alternative `caffeinate -i -w <pid>` per agent PID (self-cleaning when the agent dies) — simpler to test, one child per agent. Recommended: IOPMAssertion in-process, with `pmset -g assertions` as the verification tool.
- Detection by process: scan the process table (`sysctl`/`proc_listpids`, or reuse `ProcessLiveness` for pid validation) for names/argv: `claude`, `agy`, `opencode`, `codex`. Exact executable names and how npm/node wrappers appear in `ps` are UNVERIFIED — must be sampled on a live machine first.
- Hook-in: new `Sources/BDB/KeepAwake/` (`AgentProcessScanner`, `KeepAwakeController`); `ActivityCoordinator.isBusy` exists already and covers monitors upstream knows (Claude, Codex, Cursor, Antigravity...), so use it as an extra signal, but the scanner makes OpenCode/agy independent of upstream monitors. Wire in `Sources/App/AppDelegate.swift` (start/stop), setting in `Sources/Settings/Preferences.swift` + `SettingsView.swift`, status in `StatusItemController.swift`.
- Test locally: (a) XCTest for the pure decision logic (mode, timer deadline, busy agents -> hold/release; injectable clock) with fixtures, new `Tests/KeepAwakeTests.swift`; (b) manual: start `sleep 600` stand-in named like an agent, check `pmset -g assertions` shows the Codenotch assertion, kill it, assertion gone in under the poll interval; (c) real run with each CLI that is installed. Must not use `caffeinate` binary tests on a machine where the user relies on it elsewhere.

**Windows design**
- Primitive: `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)` via the `windows` crate (check whether it is already a dependency in `windows/codenotch/Cargo.toml`; UNVERIFIED). Must be called repeatedly from the same thread that set it, so run on a dedicated thread. PowerToys Awake is an optional external user choice, not a dependency.
- Detection: process enumeration (Toolhelp snapshot or `sysinfo` if already present — UNVERIFIED); `focus.rs`/`ProcMaps` and `activity.rs` already do process work for Claude; reuse.
- Hook-in: new `windows/codenotch/src/bdb/keepawake.rs`, spawned from `main.rs`, toggle in `traymenu.rs`/`settings.html`.
- Test: `cargo test` for the decision logic (pure function over mode, deadline, busy list); manual on Windows: `powercfg /requests` shows the request while a fake `claude.exe` runs. UNVERIFIED (no Windows machine here).

**Shared contract**: settings `bdb.keepAwake.mode` (`off|auto|always|timer`), `bdb.keepAwake.until` (ISO-8601 timestamp, timer only), agent name patterns in one list kept identical on both ports.

## P2 — AOS / AO installed version + npm update indicator

**Behaviour**: show installed AOS version and AO version; show a green dot/badge when the npm registry has a newer one. Packages: `@hybridlabor-api/aos`, `@hybridlabor-api/bdb-agent-orchestrator`. AO line only if AO is installed.

**Design**
- Installed version (decided): read `/opt/homebrew/lib/node_modules/@hybridlabor-api/aos/package.json` (`version`). **Never run `aos`** — `aos --version` runs the full installer and rewrites harness configs (known issue). Read versions from files instead: the npm global `package.json` (`$(npm root -g)/@hybridlabor-api/aos/package.json`, resolved without executing aos, e.g. via known prefixes such as `/opt/homebrew/lib/node_modules`), AO likewise from `/opt/homebrew/lib/node_modules/@hybridlabor-api/bdb-agent-orchestrator/package.json` (path assumed from the AOS pattern, UNVERIFIED). Intel/other prefixes (`npm root -g`) as fallback; Windows path is `%APPDATA%\npm\node_modules\...` (UNVERIFIED).
- Latest version: HTTPS GET `https://registry.npmjs.org/@hybridlabor-api%2Faos/latest` (scoped-package URL form; packages are public, so no token and no `~/.npmrc` access). Poll every few hours, cache with ETag; compare semver.
- Hook-in macOS: new `Sources/BDB/Versions/` + a row in `TooltipCard.swift` and `UpdateCard.swift` pattern (upstream already has an update card for Sparkle — follow its look); settings in `Preferences.swift`. Windows: `windows/codenotch/src/bdb/versions.rs` (the crate set already has HTTP in `updater.rs`/`usage.rs`), row in `notch.html`.
- Test: unit tests for semver compare and `package.json` parsing with fixtures; HTTP stubbed (upstream tests use fixtures, see `Tests/UpdaterOutcomeTests.swift` for the pattern); manual: lower the version in a temp copy of package.json (never edit the real install) and confirm the badge. Registry response shape UNVERIFIED until first run.

## P3 — Multi-agent workflow progress and done/needs-you notifications (AOS first, AO optional)

**Behaviour**: show whether a workflow (startcycle, startcycle-graph, swarms) is running and how far; raise working / done / needs-you signals for it like the existing Claude/agy signals.

**Sources, in priority order**
1. **AOS file sources (required)**: `<repo>/production_artifacts/state.json` per project (location confirmed by Tim) and the agenttrail live map data. Exact schema and how to discover active projects are **UNVERIFIED** — `~/.agents` is empty here, this repo's `production_artifacts/` is empty, and the schema lives in `.agents/graph.md` / agenttrail, which are not in this checkout. First task in P3: capture real `state.json` samples from a running `/startcycle-graph` and write a schema doc. Project discovery: watch a configured list of project roots, plus roots of detected agent processes' cwd.
2. **AO daemon (optional)**: `127.0.0.1:3101` (confirmed by Tim); if reachable, enrich with per-project task counts and PR "merge ready". API shape UNVERIFIED (no AO source read). Failure or absence must be silent.

**Design**
- Map to upstream's model: each workflow becomes an `AgentSession` (`name`=project/workflow, `detail`=node or phase, `state` busy/waiting/success/idle, `waitingFor` for needs-you e.g. GO gate or escalation) so existing `ActivitySummary`, chime (`SessionChime.swift`) and notification channel (`NotificationChannel.swift`) work unchanged. Progress (done/total) is an extra field on a BDB wrapper, shown in the hover card.
- macOS: new `Sources/BDB/Workflow/WorkflowActivityMonitor.swift` conforming to `AgentActivityMonitor`, registered where the other monitors are created (`Runtime.swift`/`AppDelegate.swift` — UNVERIFIED which). File watching via FSEvents/DispatchSource on state.json.
- Windows: new `bdb/workflow.rs` producing `Activity` entries from `activity.rs`' structure; `watcher.rs` for file notifications (check if reusable).
- Notification colour: green for done (upstream and BDB palette agree).
- Test: fixtures of `state.json` for each state (running, waiting on GO, done, failed/escalated, malformed, missing) -> XCTest/`cargo test` on the parser and state mapping; manual: run a real throwaway `/startcycle-graph-user` in a scratch dir and watch the notch; no-AO test = AO not installed/daemon down (must pass). AO test only once the API is known.

## P4 — Hover panel from the mockup

Reference: `docs/bdb/mockup-sidebar-2026-10-01.png`. Panel beside the existing gauges with an "AO Orchestrator / BDB Endpoints" block: rows per AO project (`id — x/100 % done`, green `Merge ready` badge) and per-endpoint usage rows (`BDB LLM Endpoint — GLM 5.3 flash`, `Seedance 2.0`, `BDB Creator Extension — Weekly`).

- The task-progress rows are fed by P3 (AOS-only fallback: workflow rows from state.json; AO rows appear only when AO is present). Endpoint usage rows depend on the BDB cloud API (later phase), so P4 ships with the progress block plus P1/P2 status, and endpoint rows render only when their provider exists. Green `Merge ready` badge uses `--green`/`--green-deep`; panel surface uses `--paper`/`--paper-2` with ink text.
- macOS: extend `Sources/Features/TooltipCard.swift` (+ `Notch/NotchRootView.swift`/`NotchLayout.swift` for sizing); new `Sources/BDB/Panel/BDBPanelView.swift`. Windows: new section in `windows/codenotch/ui/notch.html` fed through the existing state channel.
- Test: snapshot tests exist upstream (`Tests/SnapshotTests.swift`, `TooltipRenderTests.swift`, `NotchRenderTests.swift`); add a fixture-driven render test for the panel; compare visually to the mockup. Windows: `scripts/check-ui-scripts.mjs`-style node tests (UNVERIFIED how they run).

## Later (not scheduled)

- **BDB cloud plan usage**: new `UsageProvider` (macOS `Sources/Providers/UsageProvider.swift` protocol, e.g. like `GLMProvider`/`KiloProvider`), Windows `usage.rs` equivalent; needs the RCentry/fucksaas plan API (not defined; UNVERIFIED). Each provider gets a ring for free from upstream.
- **GO gateway approvals**: poll `https://gateway.rcentry.pro/approvals` (read-only list first; auth scheme UNVERIFIED), show a needs-you state; approving from the notch only after a security review (4-eyes semantics belong to the gateway, never auto-approve). Feeds the same needs-you channel as P3.
- **Server stats**: Uptime-Kuma style minimal host stats (inspiration exelban/stats); SSH or small agent endpoint; design open.
- **AO HANDS+**: separate standalone window per memory notes, not a tab in AO; out of scope for this repo until specified.

## Open questions

1. Keep-awake auto mode: grace period after an agent goes idle before releasing? Default timer presets (30 min, 1 h, 2 h, until time)?
2. P3: state.json schema and how to discover active projects (watch list vs agent-process cwd); AO daemon endpoints on `127.0.0.1:3101`.
3. Does the first CI run pass on `macos-26` (Xcode version it ships is unknown until the log)? Does `test-ci` need extra setup in the fork?
4. Windows machine for manual keep-awake and tray testing (CI only covers build/tests).

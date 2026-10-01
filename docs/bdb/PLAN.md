# BDB AO Codenotch — phased plan

Status date 2026-10-01. Baseline: upstream `f295939` (1.20.0). **Nothing below has been run**: the upstream macOS app could not be built on this machine (see `BUILD.md`: no Xcode, no xcodegen). Every claim about upstream code is from reading source; build and test steps are therefore UNVERIFIED until Xcode is installed.

## Principles

- **One repo, two ports**: macOS Swift in `Sources/`, Windows Rust/Tauri in `windows/codenotch/src/`. Each feature ships in both, behind the same on-disk contract (file formats, setting names), so the two stay in sync.
- **AOS alone must work; AO is optional.** AOS signals come from files and processes (agenttrail, `production_artifacts/state.json`, process table). The AO daemon is an additive source that never gates a feature.
- **No hooks written into other tools' config.** (Rejected: agents-sleep-preventer writes into `~/.claude/settings.json`.) Detect by process and files only. Note upstream's Windows `hooks_install.rs` does install Claude hooks on explicit user action — leave as is, do not extend to BDB features.
- Isolate BDB code in new files/folders (`Sources/BDB/`, `windows/codenotch/src/bdb/`) to keep upstream merges (`git fetch upstream`) cheap. Hook points in upstream files stay to a few lines.
- BDB CI colours: black `#0a0a0a`, white, purple `#9b30c4`; no mint/cyan (applies to new UI; upstream green notification is existing behaviour, decide in P3).
- Private repo only; license MIT and attribution stay.

## Upstream architecture relevant to us (read, not run)

- macOS: `Sources/Sessions/` has one `AgentActivityMonitor` per tool (protocol: `sessions`, `sessionsPublisher`, `start()`, `stop()`), merged by `ActivityCoordinator` (`isBusy`, `activeIDs`, `setEnabled`) into `AgentSession` (`state`: busy/waiting/success/idle, `pid`, `since`, `waitingFor`). `ActivitySummary` reduces sessions to working/waiting/success/idle. `ProcessLiveness` checks pid + start time. Existing monitors: Claude, Codex, Cursor, Antigravity, Grok, Kimi, Gemini, Pi, Ollama, LM Studio. OpenCode has only `OpenCodeGeminiActivity.swift` and a usage provider (`Providers/OpenCodeProvider.swift`) — **no generic OpenCode session monitor found on macOS (UNVERIFIED beyond file names)**.
- macOS UI: `Sources/Notch/` (panel, layout, view model, root view), `Sources/Features/TooltipCard.swift` (hover card), `Sources/App/` (AppDelegate, StatusItemController, SessionChime, Updater), `Sources/Settings/` (Preferences, SettingsView), `Sources/Model/UsageStore.swift`, `NotificationChannel.swift`, `ThresholdNotifier.swift`. Extra: `Sources/PhoneLink/` (local server for the phone app; `PhoneLinkSnapshotBuilder` defines what the phone sees).
- Windows: `windows/codenotch/src/activity.rs` (`Activity{provider,state,name,detail,since}`; Claude, Codex, Cursor, Antigravity), `watcher.rs`, `state.rs`, `config.rs`, `usage.rs`, `server.rs`, `opencode.rs`, `agy_cli.rs`, `tray.rs`/`traymenu.rs`, `i18n.rs`; UI in `windows/codenotch/ui/*.html` (notch.html = pill + hover card); helper `windows/codenotch-hook`.
- Tests: macOS `Tests/*Tests.swift` (XCTest, `make test`); Windows `cargo test --locked` plus `node --test` scripts in `windows/`.
- Localisation: five-plus languages (`Sources/Localizable.xcstrings`, `i18n.rs`); new strings need en/de at minimum, others fall back to English (check `LocalizationTests`/`CatalogCoverageTests` — they may fail on missing keys; UNVERIFIED).

## Phase 0 — Unblock and baseline (before any code)

1. Install Xcode + `brew install xcodegen` (Tim, system software), then `make run`, `make test` and record in `BUILD.md`.
2. Decide Windows verification route (Windows machine/VM or CI); this Mac cannot run the Windows port (UNVERIFIED).
3. Create the private GitHub repo, push `main` (needs Tim's GO).

## P1 — Keep-awake for all coding agents

**Behaviour**: while any detected coding agent process is active (busy, or alive — see open question), hold a no-idle-sleep power assertion; release when none remain. Menu/Settings toggle, default off until Tim decides. Covers Claude Code, agy (Antigravity CLI), OpenCode, Codex; AO-spawned sessions are covered because they are ordinary child processes of those CLIs (AO PID list is a bonus, not required).

**macOS design**
- Primitive: `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, ...)` held in-process (no child process to leak); release on state change and on quit. Alternative `caffeinate -i -w <pid>` per agent PID (self-cleaning when the agent dies) — simpler to test, one child per agent. Recommended: IOPMAssertion in-process, with `pmset -g assertions` as the verification tool.
- Detection by process: scan the process table (`sysctl`/`proc_listpids`, or reuse `ProcessLiveness` for pid validation) for names/argv: `claude`, `agy`, `opencode`, `codex`. Exact executable names and how npm/node wrappers appear in `ps` are UNVERIFIED — must be sampled on a live machine first.
- Hook-in: new `Sources/BDB/KeepAwake/` (`AgentProcessScanner`, `KeepAwakeController`); `ActivityCoordinator.isBusy` exists already and covers monitors upstream knows (Claude, Codex, Cursor, Antigravity...), so use it as an extra signal, but the scanner makes OpenCode/agy independent of upstream monitors. Wire in `Sources/App/AppDelegate.swift` (start/stop), setting in `Sources/Settings/Preferences.swift` + `SettingsView.swift`, status in `StatusItemController.swift`.
- Test locally: (a) XCTest for the pure decision logic (process list -> hold/release) with fixtures, new `Tests/KeepAwakeTests.swift`; (b) manual: start `sleep 600` stand-in named like an agent, check `pmset -g assertions` shows the Codenotch assertion, kill it, assertion gone in under the poll interval; (c) real run with each CLI that is installed. Must not use `caffeinate` binary tests on a machine where the user relies on it elsewhere.

**Windows design**
- Primitive: `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)` via the `windows` crate (check whether it is already a dependency in `windows/codenotch/Cargo.toml`; UNVERIFIED). Must be called repeatedly from the same thread that set it, so run on a dedicated thread. PowerToys Awake is an optional external user choice, not a dependency.
- Detection: process enumeration (Toolhelp snapshot or `sysinfo` if already present — UNVERIFIED); `focus.rs`/`ProcMaps` and `activity.rs` already do process work for Claude; reuse.
- Hook-in: new `windows/codenotch/src/bdb/keepawake.rs`, spawned from `main.rs`, toggle in `traymenu.rs`/`settings.html`.
- Test: `cargo test` for the decision logic (pure function over a process list); manual on Windows: `powercfg /requests` shows the request while a fake `claude.exe` runs. UNVERIFIED (no Windows machine here).

**Shared contract**: setting `bdb.keepAwake` (bool), agent name patterns in one list kept identical on both ports.

## P2 — AOS / AO installed version + npm update indicator

**Behaviour**: show installed AOS version and AO version; show a purple dot/badge when the npm registry has a newer one. Packages: `@hybridlabor-api/aos`, `@hybridlabor-api/bdb-agent-orchestrator`. AO line only if AO is installed.

**Design**
- Installed version: **do not run `aos`** — `aos --version` runs the full installer and rewrites harness configs (known issue). Read versions from files instead: the npm global `package.json` (`$(npm root -g)/@hybridlabor-api/aos/package.json`, resolved without executing aos, e.g. via known prefixes such as `/opt/homebrew/lib/node_modules`), or an AOS-written version marker if one exists (UNVERIFIED which). AO: `package.json` of the global package, or `ao --version` only after verifying it is side-effect free (UNVERIFIED).
- Latest version: HTTPS GET `https://registry.npmjs.org/@hybridlabor-api%2Faos/latest` (scoped-package URL form; auth required if the packages are private — UNVERIFIED, may need a token from `~/.npmrc`, which must be read-only and never logged). Poll every few hours, cache with ETag; compare semver.
- Hook-in macOS: new `Sources/BDB/Versions/` + a row in `TooltipCard.swift` and `UpdateCard.swift` pattern (upstream already has an update card for Sparkle — follow its look); settings in `Preferences.swift`. Windows: `windows/codenotch/src/bdb/versions.rs` (the crate set already has HTTP in `updater.rs`/`usage.rs`), row in `notch.html`.
- Test: unit tests for semver compare and `package.json` parsing with fixtures; HTTP stubbed (upstream tests use fixtures, see `Tests/UpdaterOutcomeTests.swift` for the pattern); manual: lower the version in a temp copy of package.json (never edit the real install) and confirm the badge. Registry reachability for private scope UNVERIFIED.

## P3 — Multi-agent workflow progress and done/needs-you notifications (AOS first, AO optional)

**Behaviour**: show whether a workflow (startcycle, startcycle-graph, swarms) is running and how far; raise working / done / needs-you signals for it like the existing Claude/agy signals.

**Sources, in priority order**
1. **AOS file sources (required)**: `production_artifacts/state.json` per project and the agenttrail live map data. Exact schemas, file locations and how to discover active projects are **UNVERIFIED** — `~/.agents` is empty here, this repo's `production_artifacts/` is empty, and the schema lives in `.agents/graph.md` / agenttrail, which are not in this checkout. First task in P3: capture real `state.json` samples from a running `/startcycle-graph` and write a schema doc. Project discovery: watch a configured list of project roots, plus roots of detected agent processes' cwd.
2. **AO daemon (optional)**: if reachable, enrich with per-project task counts and PR "merge ready". API shape UNVERIFIED (no AO source read). Failure or absence must be silent.

**Design**
- Map to upstream's model: each workflow becomes an `AgentSession` (`name`=project/workflow, `detail`=node or phase, `state` busy/waiting/success/idle, `waitingFor` for needs-you e.g. GO gate or escalation) so existing `ActivitySummary`, chime (`SessionChime.swift`) and notification channel (`NotificationChannel.swift`) work unchanged. Progress (done/total) is an extra field on a BDB wrapper, shown in the hover card.
- macOS: new `Sources/BDB/Workflow/WorkflowActivityMonitor.swift` conforming to `AgentActivityMonitor`, registered where the other monitors are created (`Runtime.swift`/`AppDelegate.swift` — UNVERIFIED which). File watching via FSEvents/DispatchSource on state.json.
- Windows: new `bdb/workflow.rs` producing `Activity` entries from `activity.rs`' structure; `watcher.rs` for file notifications (check if reusable).
- Notification colour: upstream "done" is green. BDB CI says no mint/cyan: decide whether BDB-sourced done uses purple; ask Tim.
- Test: fixtures of `state.json` for each state (running, waiting on GO, done, failed/escalated, malformed, missing) -> XCTest/`cargo test` on the parser and state mapping; manual: run a real throwaway `/startcycle-graph-user` in a scratch dir and watch the notch; no-AO test = AO not installed/daemon down (must pass). AO test only once the API is known.

## P4 — Hover panel from the mockup

Reference: `docs/bdb/mockup-sidebar-2026-10-01.png`. Panel beside the existing gauges with an "AO Orchestrator / BDB Endpoints" block: rows per AO project (`id — x/100 % done`, green `Merge ready` badge) and per-endpoint usage rows (`BDB LLM Endpoint — GLM 5.3 flash`, `Seedance 2.0`, `BDB Creator Extension — Weekly`).

- The task-progress rows are fed by P3 (AOS-only fallback: workflow rows from state.json; AO rows appear only when AO is present). Endpoint usage rows depend on the BDB cloud API (later phase), so P4 ships with the progress block plus P1/P2 status, and endpoint rows render only when their provider exists. Mockup says "green" badge — conflicts with BDB CI; flag to Tim.
- macOS: extend `Sources/Features/TooltipCard.swift` (+ `Notch/NotchRootView.swift`/`NotchLayout.swift` for sizing); new `Sources/BDB/Panel/BDBPanelView.swift`. Windows: new section in `windows/codenotch/ui/notch.html` fed through the existing state channel.
- Test: snapshot tests exist upstream (`Tests/SnapshotTests.swift`, `TooltipRenderTests.swift`, `NotchRenderTests.swift`); add a fixture-driven render test for the panel; compare visually to the mockup. Windows: `scripts/check-ui-scripts.mjs`-style node tests (UNVERIFIED how they run).

## Later (not scheduled)

- **BDB cloud plan usage**: new `UsageProvider` (macOS `Sources/Providers/UsageProvider.swift` protocol, e.g. like `GLMProvider`/`KiloProvider`), Windows `usage.rs` equivalent; needs the RCentry/fucksaas plan API (not defined; UNVERIFIED). Each provider gets a ring for free from upstream.
- **GO gateway approvals**: poll `https://gateway.rcentry.pro/approvals` (read-only list first; auth scheme UNVERIFIED), show a needs-you state; approving from the notch only after a security review (4-eyes semantics belong to the gateway, never auto-approve). Feeds the same needs-you channel as P3.
- **Server stats**: Uptime-Kuma style minimal host stats (inspiration exelban/stats); SSH or small agent endpoint; design open.
- **AO HANDS+**: separate standalone window per memory notes, not a tab in AO; out of scope for this repo until specified.

## Open questions

1. Keep-awake trigger: only while an agent is *busy*, or while any agent process is alive (idle CLI sessions would then block sleep all day)? Grace period after done?
2. P2: are `@hybridlabor-api/*` public or private on npm, and where may the app read a token? How may it read the installed AOS version without running `aos`?
3. P3: authoritative schema and location of `state.json` / agenttrail data; how to discover active projects; AO daemon address/API.
4. Colour of BDB done/merge-ready badges: mockup green vs BDB CI (purple, no mint).
5. Xcode install go-ahead on this Mac; Windows test machine?
6. Rebase policy against upstream (merge vs rebase), and whether BDB features should be toggled off by default.

# BDB AO Codenotch — project idea

Fork of [vinzdg/codenotch](https://github.com/vinzdg/codenotch) (MIT, Swift, macOS + Windows port in `windows/`).
Goal: one repo with both ports, extended into the BDB desktop companion for AOS and AO.

## What upstream Codenotch already does
- Pins usage limits from Claude Code, Cursor, Codex and Antigravity to a screen edge (notch / sidebar / hover).
- Shows when an agent is working and raises a green notification when an agent signals it is done.

## What BDB AO Codenotch adds
1. **Keep-awake for all agents** (macOS + Windows): prevent sleep while any coding agent is active.
   Native primitives: `caffeinate -w <pid>` on macOS; PowerToys Awake / `caffeinate-windows` / `caffeineOSS` on Windows.
   Must cover Claude Code, Antigravity (agy), OpenCode, Codex and AO-spawned sessions (AO knows every PID).
2. **AOS / AO version and update indicator**: installed AOS version, new AOS or AO release on npm.
3. **Workflow progress**: show whether a multi-agent workflow (startcycle, startcycle-graph, swarms) is running and how far it is, via AO orchestrator first, generic AOS later (agenttrail / state.json).
4. **AO orchestrator notifications**: working / done / needs-you signals for bdb-agent-orchestrator sessions, same as for Claude Code and agy today.
5. **BDB AOS Cloud plan usage** (later, with the RCentry / fucksaas subscription): how much of the plan is used.
6. **Cloud GO gateway**: pending approvals from `https://gateway.rcentry.pro/approvals` (BDB CBS, later customer servers).
7. **Server stats** (later): minimal host stats for an Ubuntu server, Uptime-Kuma style, inspired by [exelban/stats](https://github.com/exelban/stats).
8. **AO HANDS+** (later): extension of AO for workflows, deployment and automations.

In short: agent stats and usage counter + AOS/AO desktop plugin with update hints + light monitoring of cloud services and servers.

## Sidebar mockup (from the screenshot)
Hover panel next to the existing Codenotch gauges (Claude 19 %, Antigravity 3 %, Codex, Cursor 0.5 %):

- **AO Orchestrator / BDB Endpoints** block
  - one row per AO project: `AO Project ID — 0/100 % done of tasks`, with a green `Merge ready` badge when a PR is ready
  - `BDB LLM Endpoint — 0/100 % Usage / GLM 5.3 flash`
  - `BDB LLM Endpoint — 0/100 % Usage / Seedance 2.0`
  - `BDB Creator Extension — 0/100 % Usage / Weekly`

So the panel mixes AO task progress per project with per-endpoint usage quotas from BDB cloud services.

## Research links
- PowerToys Awake: https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/powertoys/awake.md
- caffeinate-windows: https://github.com/dincertekin/caffeinate-windows
- caffeineOSS: https://github.com/Kuberwastaken/caffeineOSS
- macOS caffeinate: https://adamj.eu/tech/2026/09/20/macos-caffeinate/
- Evaluated and rejected for BDB: agents-sleep-preventer (Claude Code, Codex, Hermes only; writes hooks into `~/.claude/settings.json`).

## Constraints
- Keep upstream MIT license and attribution. Upstream remote is `upstream`; sync regularly.
- GitHub repo must be private (a GitHub fork of a public repo cannot be private, so push as a fresh private repo).
- Colours (decided 2026-10-01): the old purple BDB CI is dropped for Codenotch. The new CI for BDB AOS/AO cloud products is the light green-beige of the AOS Store UI (`lib/store-ui/index.html` in bdb-dev-optimized-agent-skills): `--paper oklch(0.97 0.012 95)`, `--paper-2 oklch(0.93 0.018 95)`, `--green oklch(0.72 0.17 145)`, `--green-deep oklch(0.40 0.12 145)`, ink `oklch(0.18 0.025 265)`. Green for done / merge-ready is fine.
- Upstream sync is by merge (not rebase). BDB features are off by default.
- Builds run in GitHub Actions (`.github/workflows/bdb-build.yml`); no local Xcode.
- Keep-awake modes: auto (while an agent is working), always on, timer (duration or until a time).
- Reference mockup: `docs/bdb/mockup-sidebar-2026-10-01.png` (the second screenshot from the notes is irrelevant).

## Source
Tim's original notes (German, 2026-10-01) are in `docs/bdb/notes-2026-10-01.de.md`.

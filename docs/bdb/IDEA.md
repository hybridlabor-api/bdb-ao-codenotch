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

## Research links
- PowerToys Awake: https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/powertoys/awake.md
- caffeinate-windows: https://github.com/dincertekin/caffeinate-windows
- caffeineOSS: https://github.com/Kuberwastaken/caffeineOSS
- macOS caffeinate: https://adamj.eu/tech/2026/09/20/macos-caffeinate/
- Evaluated and rejected for BDB: agents-sleep-preventer (Claude Code, Codex, Hermes only; writes hooks into `~/.claude/settings.json`).

## Constraints
- Keep upstream MIT license and attribution. Upstream remote is `upstream`; sync regularly.
- GitHub repo must be private (a GitHub fork of a public repo cannot be private, so push as a fresh private repo).
- BDB CI: black #0a0a0a, white, accent purple #9b30c4; no mint/cyan.
- Two reference screenshots from the original notes were not found in Downloads; add them here when available.

## Source
Tim's original notes (German, 2026-10-01) are in `docs/bdb/notes-2026-10-01.de.md`.

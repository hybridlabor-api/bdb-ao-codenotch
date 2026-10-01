import Foundation

/// `Codenotch --bdb-selftest`: plain asserts for the BDB decision logic.
/// XCTest is not available with only the Command Line Tools.
enum BDBSelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "ok   " : "FAIL ", what)
            if !ok { failures += 1 }
        }
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        // Agent matching
        let a = BDBProcessTable.agent(for:)
        check(a("/usr/local/bin/claude --resume") == .claude, "claude binary")
        check(a("/tmp/x/claude 600") == .claude, "renamed test binary")
        check(a("node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js") == .claude, "claude npm wrapper")
        check(a("node /opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js") == .codex, "codex npm wrapper")
        check(a("/Users/me/.local/bin/agy chat") == .agy, "agy")
        check(a("/opt/homebrew/bin/opencode") == .opencode, "opencode")
        check(a("/Applications/Claude.app/Contents/MacOS/Claude") == nil, "Claude Desktop is not Claude Code")
        check(a("/bin/zsh -l") == nil, "unrelated process")
        check(a("grep claude") == nil, "grep claude is not an agent")

        // ps parsing
        let parsed = BDBProcessTable.parse("  12  1   1:02.50 /tmp/claude 600\n  13 12 0:00.10 sleep 1\nbad line\n")
        check(parsed.count == 2 && parsed[0].cpuSeconds == 62.5 && parsed[1].ppid == 12, "ps parsing")
        check(BDBProcessTable.cpuSeconds("1-02:00:00") == 93_600, "cpu time with days")

        // Busy detection incl. children
        let t1 = [BDBProcess(pid: 10, ppid: 1, cpuSeconds: 5, command: "/tmp/claude"),
                  BDBProcess(pid: 11, ppid: 10, cpuSeconds: 1, command: "bash")]
        let first = BDBBusyDetector.evaluate(table: t1, previous: [:], interval: 0)
        check(first.activities.count == 1 && !first.activities[0].busy, "first scan is never busy")
        let idle = BDBBusyDetector.evaluate(table: t1, previous: first.snapshot, interval: 5)
        check(!idle.activities[0].busy, "no cpu growth is idle")
        let t2 = [BDBProcess(pid: 10, ppid: 1, cpuSeconds: 5, command: "/tmp/claude"),
                  BDBProcess(pid: 11, ppid: 10, cpuSeconds: 3, command: "bash")]
        check(BDBBusyDetector.evaluate(table: t2, previous: first.snapshot, interval: 5).activities[0].busy,
              "child process cpu makes the agent busy")

        // Modes
        func hold(_ m: BDBKeepAwakeMode, busy: Int = 0, last: Date? = nil, until: Date? = nil, at: TimeInterval = 0) -> Bool {
            BDBKeepAwake.shouldHold(.init(mode: m, now: t0.addingTimeInterval(at), busyCount: busy, lastBusy: last, timerUntil: until))
        }
        check(!hold(.off, busy: 3), "off never holds")
        check(hold(.always), "always holds")
        check(hold(.auto, busy: 1), "auto holds while busy")
        check(!hold(.auto), "auto idle with no history releases")
        check(hold(.auto, last: t0, at: 299), "auto holds inside 5 min grace")
        check(!hold(.auto, last: t0, at: 300), "auto releases after 5 min grace")
        check(hold(.timer, until: t0.addingTimeInterval(60)), "timer holds before deadline")
        check(!hold(.timer, until: t0), "timer releases at deadline")
        check(!hold(.timer), "timer without deadline releases")

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_699_963_200) // 2023-11-14 12:00 UTC
        let next = BDBKeepAwake.nextOccurrence(hour: 9, minute: 30, after: noon, calendar: cal)!
        check(next.timeIntervalSince(noon) == 21.5 * 3600, "until-time rolls to tomorrow")
        check(BDBKeepAwake.summary(mode: .auto, holding: true, busyCount: 2, timerUntil: nil, now: t0, inGrace: false) == "Awake: 2 agents busy", "summary text")

        // Versions
        check(BDBVersionLogic.isNewer("4.14.0", than: "4.13.2"), "minor newer")
        check(!BDBVersionLogic.isNewer("4.13.2", than: "4.13.2"), "equal is not newer")
        check(!BDBVersionLogic.isNewer("4.9.0", than: "4.13.2"), "numeric not lexical")
        check(!BDBVersionLogic.isNewer("4.13.3-beta.1", than: "4.13.3"), "prerelease not newer")
        check(BDBVersionLogic.line(name: "AOS", installed: "4.13.2", latest: "4.14.0") == "AOS 4.13.2 · update 4.14.0 available", "row text")
        check(BDBVersionLogic.version(fromJSON: Data(#"{"name":"x","version":"1.2.3"}"#.utf8)) == "1.2.3", "package.json version")
        check(BDBVersionLogic.due(lastFetch: nil, now: t0), "fetch due when never fetched")
        check(!BDBVersionLogic.due(lastFetch: t0, now: t0.addingTimeInterval(5 * 3600)), "not due within 6 h")
        check(BDBVersionLogic.due(lastFetch: t0, now: t0.addingTimeInterval(6 * 3600)), "due after 6 h")

        // Snapshot for the notch gauge and hover card
        let acts = [BDBAgentActivity(agent: .claude, pid: 1, busy: true), BDBAgentActivity(agent: .claude, pid: 2, busy: false),
                    BDBAgentActivity(agent: .opencode, pid: 3, busy: false)]
        let st = BDBState(mode: .auto, holding: true, statusLine: "Awake: 1 agent busy", timerUntil: nil, graceEnds: nil,
                          agents: BDBState.from(acts),
                          versions: [BDBVersionRow(title: "AOS", installed: "4.12.1", latest: "4.13.2")])
        let snap = BDBSnapshot.make(st)
        check(snap.displayName == "BDB AOS CLOUD" && snap.headlineText == "1", "gauge label is the busy-agent count")
        check(abs((snap.usedFraction ?? -1) - 1.0 / 3.0) < 1e-9, "ring arc is busy/running")
        check(snap.windows.first { $0.id == "agent-claude" }?.detail == "2 running · 1 busy", "agent row text")
        check(snap.windows.first { $0.id == "ver-AOS" }?.detail == "4.12.1 · 4.13.2 available", "version row text")
        check(BDBSnapshot.make(BDBState()).headlineText == "0", "idle gauge shows 0")

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        return failures == 0 ? 0 : 1
    }
}

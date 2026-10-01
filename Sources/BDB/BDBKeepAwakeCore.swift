import Foundation

// Pure decision logic for BDB keep-awake. No I/O here, so BDBSelfTest can
// exercise it with fixtures.

enum BDBAgent: String, CaseIterable {
    case claude, agy, opencode, codex

    var title: String {
        switch self {
        case .claude:   return "Claude Code"
        case .agy:      return "Antigravity (agy)"
        case .opencode: return "OpenCode"
        case .codex:    return "Codex"
        }
    }
}

/// One row of the process table.
struct BDBProcess: Equatable {
    let pid: Int32
    let ppid: Int32
    /// Cumulative CPU seconds (user + system), from `ps -o time`.
    let cpuSeconds: Double
    let command: String
}

enum BDBProcessTable {
    /// Which agent a command line belongs to, or nil.
    ///
    /// Matches the basename of the executable (`claude`, `agy`, `opencode`,
    /// `codex`) and the npm wrappers that run under node. Anything inside an
    /// `.app` bundle is skipped on purpose: Claude Desktop and the Codex app are
    /// not the CLI agents and would otherwise match by name.
    static func agent(for command: String) -> BDBAgent? {
        if command.contains(".app/Contents/") { return nil }
        let words = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = words.first else { return nil }
        let base = { (s: String) in (s as NSString).lastPathComponent.lowercased() }
        if let hit = BDBAgent.allCases.first(where: { $0.rawValue == base(first) }) { return hit }
        let runner = base(first)
        guard ["node", "bun", "deno"].contains(runner) else { return nil }
        for word in words.dropFirst().prefix(3) where !word.hasPrefix("-") {
            if word.contains("/@anthropic-ai/claude-code/") { return .claude }
            if word.contains("/@openai/codex/") { return .codex }
            if word.contains("/opencode-ai/") || word.contains("/opencode/") { return .opencode }
            if let hit = BDBAgent.allCases.first(where: { $0.rawValue == base(word) }) { return hit }
        }
        return nil
    }

    /// Parse `ps -axo pid=,ppid=,time=,command=`.
    static func parse(_ output: String) -> [BDBProcess] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]),
                  let cpu = cpuSeconds(String(parts[2])) else { return nil }
            return BDBProcess(pid: pid, ppid: ppid, cpuSeconds: cpu,
                              command: String(parts[3]).trimmingCharacters(in: .whitespaces))
        }
    }

    /// `[dd-][hh:]mm:ss[.ss]` as macOS `ps` prints CPU time.
    static func cpuSeconds(_ text: String) -> Double? {
        var rest = text
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Double(rest[..<dash]) else { return nil }
            days = d
            rest = String(rest[rest.index(after: dash)...])
        }
        var total = 0.0
        for part in rest.split(separator: ":") {
            guard let v = Double(part) else { return nil }
            total = total * 60 + v
        }
        return total + days * 86_400
    }
}

struct BDBAgentActivity: Equatable {
    let agent: BDBAgent
    let pid: Int32
    let busy: Bool
}

enum BDBBusyDetector {
    /// An agent counts as busy when its process, **plus all its descendants**
    /// (agents run their tools as child processes), used more than
    /// `threshold` CPU seconds per wall second since the previous scan.
    /// Idle agents waiting for input sit near 0 %. The first scan of a process
    /// has no baseline and counts as not busy.
    static let threshold = 0.03

    static func evaluate(table: [BDBProcess], previous: [Int32: Double], interval: TimeInterval)
        -> (activities: [BDBAgentActivity], snapshot: [Int32: Double]) {
        var children: [Int32: [BDBProcess]] = [:]
        for p in table { children[p.ppid, default: []].append(p) }
        func treeCPU(_ pid: Int32, _ seen: inout Set<Int32>) -> Double {
            guard seen.insert(pid).inserted else { return 0 }
            let own = table.first { $0.pid == pid }?.cpuSeconds ?? 0
            return own + (children[pid] ?? []).reduce(0) { $0 + treeCPU($1.pid, &seen) }
        }
        var snapshot: [Int32: Double] = [:]
        var result: [BDBAgentActivity] = []
        for p in table {
            guard let agent = BDBProcessTable.agent(for: p.command) else { continue }
            var seen = Set<Int32>()
            let cpu = treeCPU(p.pid, &seen)
            snapshot[p.pid] = cpu
            var busy = false
            if let before = previous[p.pid], interval > 0 {
                busy = (cpu - before) / interval > threshold
            }
            result.append(BDBAgentActivity(agent: agent, pid: p.pid, busy: busy))
        }
        return (result, snapshot)
    }
}

enum BDBKeepAwakeMode: String, CaseIterable {
    case off, auto, always, timer
}

struct BDBKeepAwakeInput {
    var mode: BDBKeepAwakeMode
    var now: Date
    var busyCount: Int
    var lastBusy: Date?
    var timerUntil: Date?
    var grace: TimeInterval = 300
}

enum BDBKeepAwake {
    static func shouldHold(_ i: BDBKeepAwakeInput) -> Bool {
        switch i.mode {
        case .off:    return false
        case .always: return true
        case .timer:  return (i.timerUntil ?? .distantPast) > i.now
        case .auto:
            if i.busyCount > 0 { return true }
            guard let last = i.lastBusy else { return false }
            return i.now.timeIntervalSince(last) < i.grace
        }
    }

    /// Next occurrence of a clock time (hour, minute) strictly after `now`.
    static func nextOccurrence(hour: Int, minute: Int, after now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                          matchingPolicy: .nextTime)
    }

    static func summary(mode: BDBKeepAwakeMode, holding: Bool, busyCount: Int,
                        timerUntil: Date?, now: Date, inGrace: Bool) -> String {
        switch mode {
        case .off:    return "Keep-awake off"
        case .always: return "Awake: always on"
        case .timer:
            guard holding, let until = timerUntil else { return "Keep-awake timer ended" }
            let m = max(1, Int(until.timeIntervalSince(now) / 60.0 + 0.999))
            return "Awake: timer, \(m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min") left"
        case .auto:
            if busyCount > 0 { return "Awake: \(busyCount) agent\(busyCount == 1 ? "" : "s") busy" }
            return holding && inGrace ? "Awake: grace period after last agent" : "Auto: no agent busy"
        }
    }
}

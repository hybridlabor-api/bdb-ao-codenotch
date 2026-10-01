import Foundation

/// Everything the BDB AOS CLOUD gauge and its hover card show, as plain data.
struct BDBState: Equatable {
    var mode: BDBKeepAwakeMode = .off
    var holding = false
    var statusLine = ""
    var timerUntil: Date?
    var graceEnds: Date?
    var agents: [(agent: BDBAgent, running: Int, busy: Int)] = []
    var versions: [BDBVersionRow] = []

    static func == (a: BDBState, b: BDBState) -> Bool {
        a.mode == b.mode && a.holding == b.holding && a.statusLine == b.statusLine
            && a.timerUntil == b.timerUntil && a.graceEnds == b.graceEnds && a.versions == b.versions
            && a.agents.map { "\($0.agent)\($0.running)\($0.busy)" } == b.agents.map { "\($0.agent)\($0.running)\($0.busy)" }
    }

    var running: Int { agents.reduce(0) { $0 + $1.running } }
    var busy: Int { agents.reduce(0) { $0 + $1.busy } }

    static func from(_ activities: [BDBAgentActivity]) -> [(agent: BDBAgent, running: Int, busy: Int)] {
        BDBAgent.allCases.compactMap { kind in
            let mine = activities.filter { $0.agent == kind }
            return mine.isEmpty ? nil : (kind, mine.count, mine.filter(\.busy).count)
        }
    }
}

enum BDBSnapshot {
    /// The notch ring shows the number of busy agents; the arc is busy / running.
    /// Rows reuse the stock card: a bar row for keep-awake, count rows for the rest.
    static func make(_ s: BDBState, now: Date = Date()) -> ProviderSnapshot {
        var windows: [LimitWindow] = []

        let modeName: String
        switch s.mode {
        case .off: modeName = "off"
        case .auto: modeName = "auto"
        case .always: modeName = "always on"
        case .timer: modeName = "timer"
        }
        windows.append(LimitWindow(
            id: "awake", label: "Keep awake · \(modeName)",
            usedFraction: s.holding ? 1 : 0, detail: s.statusLine,
            resetsAt: s.timerUntil ?? s.graceEnds, bandOverride: .ample))

        windows.append(LimitWindow(
            id: "agents", label: "Agents busy",
            usedFraction: s.running == 0 ? 0 : Double(s.busy) / Double(s.running),
            usedText: "\(s.busy)",
            detail: s.running == 0 ? "No agent running" : "\(s.busy) busy of \(s.running) running",
            bandOverride: .ample, prefersUsedText: true))

        for a in s.agents {
            windows.append(LimitWindow(
                id: "agent-\(a.agent.rawValue)", group: "Agents", label: a.agent.title,
                detail: "\(a.running) running · \(a.busy) busy"))
        }
        for v in s.versions {
            let n = v.note(now: now)
            windows.append(LimitWindow(id: "ver-\(v.title)", group: "Versions", label: v.title, detail: v.detail,
                                       note: n?.text, noteAccent: n?.accent ?? false))
        }

        return ProviderSnapshot(
            id: BDBProvider.providerID, displayName: BDBProvider.title, glyph: .bdb,
            fidelity: .official, status: .ok, windows: windows, headlineID: "agents")
    }
}

/// The BDB entry in the notch's provider stack. Connected = BDB features on
/// (Settings > Accounts or Settings > BDB AOS CLOUD).
struct BDBProvider: UsageProvider {
    static let providerID = "bdb-aos-cloud"
    static let title = "BDB AOS CLOUD"

    var id: String { Self.providerID }
    var displayName: String { Self.title }
    var glyph: ProviderGlyph { .bdb }
    var signInRoute: SignInRoute {
        .guidance("Switch on to show keep-awake, running agents and AOS/AO versions in the notch.")
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        await MainActor.run { BDBSnapshot.make(BDBHub.shared.state) }
    }

    func account() -> ProviderAccount? {
        ProviderAccount(label: nil, plan: nil, source: "AOS", manageURL: nil)
    }
    func signOut() async {}
    func presentSignIn() {}
}

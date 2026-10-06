import Foundation
import IOKit.pwr_mgt
import Combine

/// Holds one "prevent idle system sleep" assertion in this process.
final class BDBPowerAssertion {
    private var id: IOPMAssertionID = 0
    private(set) var isHeld = false

    func set(_ hold: Bool, reason: String) {
        if hold, !isHeld {
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                reason as CFString, &id)
            isHeld = (r == kIOReturnSuccess)
        } else if !hold, isHeld {
            IOPMAssertionRelease(id)
            isHeld = false
        }
    }

    deinit { set(false, reason: "") }
}

struct BDBVersionRow: Identifiable, Equatable {
    let title: String
    let installed: String?
    let latest: String?
    var checked: Date? = nil
    var id: String { title }
    var updateAvailable: Bool {
        guard let installed, let latest else { return false }
        return BDBVersionLogic.isNewer(latest, than: installed)
    }
    var detail: String { installed ?? "not installed" }
    func note(now: Date) -> (text: String, accent: Bool)? {
        BDBVersionLogic.note(installed: installed, latest: latest, checked: checked, now: now)
    }
}

/// Everything BDB-specific that runs in the app. Off until the user enables
/// it in Settings > BDB; while off it scans nothing and makes no requests.
@MainActor
final class BDBHub: ObservableObject {
    static let shared = BDBHub()

    private enum Key {
        static let mode = "bdb.keepAwake.mode"
        static let base = "bdb.keepAwake.base"
        static let until = "bdb.keepAwake.until"
        static let latest = "bdb.versions.latest."
        static let fetched = "bdb.versions.fetched"
    }

    private let defaults = UserDefaults.standard
    private let power = BDBPowerAssertion()
    private var timer: Timer?
    private var previousCPU: [Int32: Double] = [:]
    private var lastScan: Date?
    private var lastBusy: Date?
    private var fetching = false
    private var lastState: BDBState?

    /// Mirrors "connected" for the BDB AOS CLOUD entry in Accounts; set from
    /// the app delegate, never persisted here.
    @Published var enabled = false { didSet { if enabled != oldValue { apply() } } }
    /// Called whenever what the notch shows has changed.
    var onChange: (() -> Void)?
    @Published private(set) var mode: BDBKeepAwakeMode
    @Published private(set) var timerUntil: Date?
    @Published private(set) var activities: [BDBAgentActivity] = []
    @Published private(set) var holding = false
    @Published private(set) var versionRows: [BDBVersionRow] = []

    var state: BDBState {
        BDBState(mode: mode, holding: holding, statusLine: statusLine, timerUntil: timerUntil,
                 graceEnds: graceEnds, agents: BDBState.from(activities), versions: versionRows)
    }

    var busyCount: Int { activities.filter(\.busy).count }

    private init() {
        mode = BDBKeepAwakeMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .off
        let until = defaults.double(forKey: Key.until)
        timerUntil = until > 0 ? Date(timeIntervalSince1970: until) : nil
    }

    /// Called once from the app delegate.
    func start() { apply() }

    func shutdown() {
        timer?.invalidate()
        power.set(false, reason: "")
    }

    // MARK: Modes

    func setMode(_ new: BDBKeepAwakeMode) {
        if new != .timer { defaults.set(new.rawValue, forKey: Key.base) }
        mode = new
        defaults.set(new.rawValue, forKey: Key.mode)
        if new != .timer { timerUntil = nil; defaults.removeObject(forKey: Key.until) }
        evaluate()
        notify()
    }

    func startTimer(minutes: Int) { startTimer(until: Date().addingTimeInterval(Double(minutes) * 60)) }

    func startTimer(until: Date) {
        if mode != .timer { defaults.set(mode.rawValue, forKey: Key.base) }
        mode = .timer
        timerUntil = until
        defaults.set(BDBKeepAwakeMode.timer.rawValue, forKey: Key.mode)
        defaults.set(until.timeIntervalSince1970, forKey: Key.until)
        evaluate()
        notify()
    }

    // MARK: Loop

    private func apply() {
        timer?.invalidate()
        timer = nil
        guard enabled else {
            power.set(false, reason: "")
            holding = false
            activities = []
            previousCPU = [:]
            lastScan = nil
            return
        }
        refreshVersionsIfDue()
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        let started = Date()
        let interval = lastScan.map { started.timeIntervalSince($0) } ?? 0
        let previous = previousCPU
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let out = Self.psOutput()
            let result = BDBBusyDetector.evaluate(table: BDBProcessTable.parse(out), previous: previous, interval: interval)
            DispatchQueue.main.async {
                guard let self, self.enabled else { return }
                self.previousCPU = result.snapshot
                self.lastScan = started
                self.activities = result.activities
                if result.activities.contains(where: \.busy) { self.lastBusy = Date() }
                self.evaluate()
                self.fetchVersionsIfDue()
                self.notify()
            }
        }
    }

    private func evaluate() {
        let now = Date()
        if mode == .timer, (timerUntil ?? .distantPast) <= now {
            let base = BDBKeepAwakeMode(rawValue: defaults.string(forKey: Key.base) ?? "") ?? .off
            setMode(base == .timer ? .off : base)
            return
        }
        guard enabled else { return }
        let hold = BDBKeepAwake.shouldHold(.init(mode: mode, now: now, busyCount: busyCount,
                                                 lastBusy: lastBusy, timerUntil: timerUntil))
        power.set(hold, reason: "BDB AO Codenotch: coding agent active")
        holding = power.isHeld
    }

    private func notify() {
        let s = state
        guard s != lastState else { return }
        lastState = s
        onChange?()
    }

    var graceEnds: Date? {
        guard mode == .auto, busyCount == 0, holding, let lastBusy else { return nil }
        return lastBusy.addingTimeInterval(300)
    }

    var statusLine: String {
        guard enabled else { return "BDB features off" }
        let grace = mode == .auto && busyCount == 0 && holding
        return BDBKeepAwake.summary(mode: mode, holding: holding, busyCount: busyCount,
                                    timerUntil: timerUntil, now: Date(), inGrace: grace)
    }

    nonisolated private static func psOutput() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,time=,command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Versions

    private var npmRoot: String?
    private var resolvedTools = false
    private var lastAttempt: Date?

    private var aosPath: String {
        BDBVersionLogic.packagePath(npmRoot: npmRoot, npmName: BDBPackage.aos.npmName) ?? BDBPackage.aos.fallbackPath
    }

    /// One-off at launch: where global npm packages live. Never runs `aos`.
    private func resolveToolsOnce() {
        guard !resolvedTools else { return }
        resolvedTools = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let npm = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"].first { FileManager.default.isExecutableFile(atPath: $0) }
            let root = npm.flatMap { Self.run($0, ["root", "-g"]) }
            DispatchQueue.main.async {
                self?.npmRoot = root
                self?.rebuildRows()
            }
        }
    }

    nonisolated private static func run(_ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory()]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    /// Reads one small file; only called at launch, on fetch and on card open, never per tick.
    private func rebuildRows() {
        let installed = FileManager.default.contents(atPath: aosPath).flatMap(BDBVersionLogic.version(fromJSON:))
        let rows = [BDBVersionRow(title: "AOS", installed: installed,
                                  latest: defaults.string(forKey: Key.latest + BDBPackage.aos.npmName),
                                  checked: defaults.object(forKey: Key.fetched) as? Date)]
        guard rows != versionRows else { return }
        versionRows = rows
        notify()
    }

    func refreshVersionsIfDue(force: Bool = false) {
        resolveToolsOnce()
        rebuildRows()
        fetchVersionsIfDue(force: force)
    }

    /// Hover card opened: re-read the install, refetch when the last fetch is over 10 min old.
    func cardOpened() {
        guard enabled else { return }
        rebuildRows()
        fetchVersionsIfDue(every: BDBVersionLogic.cardOpenInterval)
    }

    private func fetchVersionsIfDue(force: Bool = false, every: TimeInterval = BDBVersionLogic.fetchInterval) {
        let last = defaults.object(forKey: Key.fetched) as? Date
        let now = Date()
        guard enabled, !fetching, force || BDBVersionLogic.due(lastFetch: last, now: now, every: every),
              force || BDBVersionLogic.due(lastFetch: lastAttempt, now: now, every: 300) else { return }
        fetching = true
        lastAttempt = now
        Task.detached(priority: .utility) { [weak self] in
            var req = URLRequest(url: BDBPackage.aos.latestURL, timeoutInterval: 10)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let fetched: String?
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                fetched = BDBVersionLogic.version(fromJSON: data)
            } else {
                fetched = nil
            }
            await MainActor.run {
                if let fetched {
                    UserDefaults.standard.set(fetched, forKey: Key.latest + BDBPackage.aos.npmName)
                    UserDefaults.standard.set(Date(), forKey: Key.fetched)
                }
                self?.fetching = false
                self?.rebuildRows()
            }
        }
    }
}

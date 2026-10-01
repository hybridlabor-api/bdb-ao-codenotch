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
    let id: String
    let text: String
    let updateAvailable: Bool
}

/// Everything BDB-specific that runs in the app. Off until the user enables
/// it in Settings > BDB; while off it scans nothing and makes no requests.
@MainActor
final class BDBHub: ObservableObject {
    static let shared = BDBHub()

    private enum Key {
        static let enabled = "bdb.enabled"
        static let mode = "bdb.keepAwake.mode"
        static let base = "bdb.keepAwake.base"
        static let until = "bdb.keepAwake.until"
        static let panel = "bdb.panel"
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

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled); apply() } }
    @Published var showPanel: Bool { didSet { defaults.set(showPanel, forKey: Key.panel); BDBPanelController.shared.update() } }
    @Published private(set) var mode: BDBKeepAwakeMode
    @Published private(set) var timerUntil: Date?
    @Published private(set) var activities: [BDBAgentActivity] = []
    @Published private(set) var holding = false
    @Published private(set) var versionRows: [BDBVersionRow] = []

    var busyCount: Int { activities.filter(\.busy).count }

    private init() {
        enabled = defaults.bool(forKey: Key.enabled)
        showPanel = defaults.object(forKey: Key.panel) as? Bool ?? true
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
    }

    func startTimer(minutes: Int) { startTimer(until: Date().addingTimeInterval(Double(minutes) * 60)) }

    func startTimer(until: Date) {
        if mode != .timer { defaults.set(mode.rawValue, forKey: Key.base) }
        mode = .timer
        timerUntil = until
        defaults.set(BDBKeepAwakeMode.timer.rawValue, forKey: Key.mode)
        defaults.set(until.timeIntervalSince1970, forKey: Key.until)
        evaluate()
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
            BDBPanelController.shared.update()
            return
        }
        refreshVersionsIfDue()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
        BDBPanelController.shared.update()
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
                self.refreshVersionsIfDue()
                BDBPanelController.shared.refit()
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

    private func installedVersion(_ pkg: BDBPackage) -> String? {
        guard let data = FileManager.default.contents(atPath: pkg.installedPath) else { return nil }
        return BDBVersionLogic.version(fromJSON: data)
    }

    private func rebuildRows() {
        var rows: [BDBVersionRow] = []
        for pkg in [BDBPackage.aos, .ao] {
            let installed = installedVersion(pkg)
            // AO is optional: no row at all when it is not installed.
            if installed == nil, pkg == .ao { continue }
            let latest = defaults.string(forKey: Key.latest + pkg.npmName)
            let newer = installed != nil && latest != nil && BDBVersionLogic.isNewer(latest!, than: installed!)
            rows.append(BDBVersionRow(id: pkg.npmName,
                                      text: BDBVersionLogic.line(name: pkg.title, installed: installed, latest: latest),
                                      updateAvailable: newer))
        }
        versionRows = rows
        BDBPanelController.shared.refit()
    }

    func refreshVersionsIfDue(force: Bool = false) {
        rebuildRows()
        let last = defaults.object(forKey: Key.fetched) as? Date
        guard enabled, !fetching, force || BDBVersionLogic.due(lastFetch: last, now: Date()) else { return }
        fetching = true
        Task { [weak self] in
            var any = false
            for pkg in [BDBPackage.aos, .ao] {
                var req = URLRequest(url: pkg.latestURL, timeoutInterval: 10)
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let v = BDBVersionLogic.version(fromJSON: data) {
                    UserDefaults.standard.set(v, forKey: Key.latest + pkg.npmName)
                    any = true
                }
            }
            await MainActor.run {
                if any { UserDefaults.standard.set(Date(), forKey: Key.fetched) }
                self?.fetching = false
                self?.rebuildRows()
            }
        }
    }
}

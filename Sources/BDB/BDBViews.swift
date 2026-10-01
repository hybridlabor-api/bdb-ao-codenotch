import AppKit
import SwiftUI

/// AOS cloud palette (oklch values converted to sRGB; see Scripts/bdb-icon.py).
enum BDBPalette {
    static let paper = Color(red: 247 / 255, green: 245 / 255, blue: 236 / 255)
    static let paper2 = Color(red: 235 / 255, green: 232 / 255, blue: 219 / 255)
    static let green = Color(red: 84 / 255, green: 191 / 255, blue: 92 / 255)
    static let greenDeep = Color(red: 9 / 255, green: 87 / 255, blue: 23 / 255)
    static let ink = Color(red: 12 / 255, green: 17 / 255, blue: 29 / 255)
}

/// The BDB hover panel: keep-awake state, agents seen, versions.
struct BDBPanelView: View {
    @ObservedObject var hub: BDBHub

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(hub.holding ? BDBPalette.green : BDBPalette.paper2)
                    .overlay(Circle().stroke(BDBPalette.greenDeep.opacity(0.5), lineWidth: 1))
                    .frame(width: 9, height: 9)
                Text("BDB AO").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            Text(hub.statusLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hub.holding ? BDBPalette.greenDeep : BDBPalette.ink.opacity(0.7))
            if !hub.activities.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(BDBAgent.allCases.filter { k in hub.activities.contains { $0.agent == k } }, id: \.self) { k in
                        let mine = hub.activities.filter { $0.agent == k }
                        let busy = mine.filter(\.busy).count
                        Text("\(k.title) · \(mine.count) running\(busy > 0 ? ", \(busy) busy" : ", idle")")
                            .font(.system(size: 11))
                            .foregroundStyle(BDBPalette.ink.opacity(busy > 0 ? 0.9 : 0.5))
                    }
                }
            }
            if !hub.versionRows.isEmpty {
                Divider().overlay(BDBPalette.paper2)
                ForEach(hub.versionRows) { row in
                    Text(row.text)
                        .font(.system(size: 11))
                        .foregroundStyle(row.updateAvailable ? BDBPalette.greenDeep : BDBPalette.ink.opacity(0.65))
                        .fontWeight(row.updateAvailable ? .semibold : .regular)
                }
            }
        }
        .foregroundStyle(BDBPalette.ink)
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(BDBPalette.paper))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BDBPalette.paper2, lineWidth: 1))
        .padding(1)
    }
}

/// A small floating window for the panel. Draggable by its background; never
/// takes focus.
@MainActor
final class BDBPanelController {
    static let shared = BDBPanelController()
    private var panel: NSPanel?

    func update() {
        let hub = BDBHub.shared
        guard hub.enabled, hub.showPanel else { panel?.orderOut(nil); return }
        if panel == nil {
            let host = NSHostingView(rootView: BDBPanelView(hub: hub))
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 244, height: 150),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.contentView = host
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.isMovableByWindowBackground = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameTopLeftPoint(NSPoint(x: f.maxX - 244 - 90, y: f.maxY - 24))
            }
        }
        if let host = panel?.contentView as? NSHostingView<BDBPanelView> {
            let size = host.fittingSize
            panel?.setContentSize(size)
        }
        panel?.orderFrontRegardless()
    }

    /// Re-fit after content changed.
    func refit() { if panel != nil { update() } }
}

struct BDBSettingsPane: View {
    @ObservedObject var hub: BDBHub = .shared
    @State private var untilTime = Date().addingTimeInterval(3600)

    var body: some View {
        Form {
            Section {
                Toggle("Enable BDB features", isOn: $hub.enabled)
                Text("Off by default. When on, the app lists running processes every 5 s to find coding agents and checks the npm registry for AOS/AO releases at most every 6 h.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show the BDB panel", isOn: $hub.showPanel).disabled(!hub.enabled)
            }
            Section("Keep awake") {
                Picker("Mode", selection: Binding(
                    get: { hub.mode == .timer ? BDBKeepAwakeMode.timer : hub.mode },
                    set: { new in if new != .timer { hub.setMode(new) } else if hub.mode != .timer { hub.startTimer(minutes: 60) } }
                )) {
                    Text("Off").tag(BDBKeepAwakeMode.off)
                    Text("Auto (while an agent is busy)").tag(BDBKeepAwakeMode.auto)
                    Text("Always on").tag(BDBKeepAwakeMode.always)
                    Text("Timer").tag(BDBKeepAwakeMode.timer)
                }
                .disabled(!hub.enabled)
                HStack {
                    Text("Timer")
                    Button("30 min") { hub.startTimer(minutes: 30) }
                    Button("1 h") { hub.startTimer(minutes: 60) }
                    Button("2 h") { hub.startTimer(minutes: 120) }
                    DatePicker("", selection: $untilTime, displayedComponents: .hourAndMinute).labelsHidden()
                    Button("Until") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: untilTime)
                        if let d = BDBKeepAwake.nextOccurrence(hour: c.hour ?? 0, minute: c.minute ?? 0, after: Date()) {
                            hub.startTimer(until: d)
                        }
                    }
                }
                .disabled(!hub.enabled)
                Text(hub.statusLine).font(.callout)
                Text("Auto: an agent (claude, agy, opencode, codex) is busy when it, or any child process, used more than 3 % of a CPU core since the last 5 s scan. Sleep stays blocked for 5 minutes after the last busy agent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Versions") {
                if hub.versionRows.isEmpty {
                    Text(hub.enabled ? "Checking…" : "Enable BDB features to check.").foregroundStyle(.secondary)
                }
                ForEach(hub.versionRows) { Text($0.text) }
                Button("Check now") { hub.refreshVersionsIfDue(force: true) }.disabled(!hub.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

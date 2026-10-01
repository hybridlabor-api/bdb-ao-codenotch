import AppKit
import SwiftUI

struct BDBSettingsPane: View {
    @ObservedObject var hub: BDBHub = .shared
    @ObservedObject var preferences: Preferences
    @State private var untilTime = Date().addingTimeInterval(3600)

    var body: some View {
        Form {
            Section {
                Toggle("Enable BDB AOS CLOUD", isOn: Binding(
                    get: { preferences.isConnected(BDBProvider.providerID) },
                    set: { preferences.setConnected($0, for: BDBProvider.providerID) }
                ))
                Text("Off by default. Shows as a gauge in the notch, like any provider. When on, the app lists running processes every 5 s to find coding agents and checks the npm registry for AOS/AO releases at most every 6 h.")
                    .font(.caption).foregroundStyle(.secondary)
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
                    Text(hub.enabled ? "Checking…" : "Enable BDB AOS CLOUD to check.").foregroundStyle(.secondary)
                }
                ForEach(hub.versionRows) { Text($0.text) }
                Button("Check now") { hub.refreshVersionsIfDue(force: true) }.disabled(!hub.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

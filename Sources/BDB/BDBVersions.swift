import Foundation

/// Installed vs. latest npm version for the BDB packages. Never executes
/// `aos`: versions come from the installed package.json and the public
/// registry.
enum BDBVersionLogic {
    static func parse(_ v: String) -> [Int]? {
        let core = v.split(separator: "-", maxSplits: 1)[0].split(separator: "+")[0]
        let nums = core.split(separator: ".").map { Int($0) }
        guard !nums.isEmpty, !nums.contains(where: { $0 == nil }) else { return nil }
        return nums.map { $0! }
    }

    /// True when `latest` is a strictly higher release than `installed`.
    /// A pre-release of the same core (4.13.0-beta) counts as not newer.
    static func isNewer(_ latest: String, than installed: String) -> Bool {
        guard let a = parse(latest), let b = parse(installed) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func version(fromJSON data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? String
    }

    static func line(name: String, installed: String?, latest: String?) -> String {
        guard let installed else { return "\(name) not installed" }
        if let latest, isNewer(latest, than: installed) {
            return "\(name) \(installed) · update \(latest) available"
        }
        return "\(name) \(installed)" + (latest == nil ? "" : " · up to date")
    }

    static func due(lastFetch: Date?, now: Date, every: TimeInterval = 6 * 3600) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= every
    }
}

struct BDBPackage: Equatable {
    let title: String
    let npmName: String          // @hybridlabor-api/aos
    var installedPath: String { "/opt/homebrew/lib/node_modules/\(npmName)/package.json" }
    var latestURL: URL { URL(string: "https://registry.npmjs.org/\(npmName)/latest")! }

    static let aos = BDBPackage(title: "AOS", npmName: "@hybridlabor-api/aos")
    static let ao = BDBPackage(title: "AO", npmName: "@hybridlabor-api/bdb-agent-orchestrator")
}

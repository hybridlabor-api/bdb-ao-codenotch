import Foundation

/// Installed vs. latest npm version for the BDB packages. Never executes
/// `aos`: versions come from the installed package.json (path from `npm root -g`)
/// and the public registry.
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

    static let fetchInterval: TimeInterval = 3600
    static let cardOpenInterval: TimeInterval = 600

    static func due(lastFetch: Date?, now: Date, every: TimeInterval = fetchInterval) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= every
    }

    /// `<root>/@hybridlabor-api/aos/package.json` for the root `npm root -g` printed.
    static func packagePath(npmRoot output: String?, npmName: String) -> String? {
        guard let root = output?.trimmingCharacters(in: .whitespacesAndNewlines), root.hasPrefix("/") else { return nil }
        return "\(root)/\(npmName)/package.json"
    }

    /// Second line of a version row and whether it takes the accent colour.
    static func note(installed: String?, latest: String?, checked: Date?, now: Date,
                     fallback: String = "not checked yet") -> (text: String, accent: Bool)? {
        guard let installed else { return nil }
        if let latest, isNewer(latest, than: installed) { return ("update available: \(latest)", true) }
        if latest != nil, let checked { return ("up to date \u{00B7} checked \(ElapsedCopy.ago(since: checked, now: now))", false) }
        return (fallback, false)
    }
}

struct BDBPackage: Equatable {
    let title: String
    let npmName: String          // @hybridlabor-api/aos
    var fallbackPath: String { "/opt/homebrew/lib/node_modules/\(npmName)/package.json" }
    var latestURL: URL { URL(string: "https://registry.npmjs.org/\(npmName)/latest")! }

    static let aos = BDBPackage(title: "AOS", npmName: "@hybridlabor-api/aos")
}

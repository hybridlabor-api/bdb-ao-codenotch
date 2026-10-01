import Foundation

/// What differs in the BDB fork. Everything is read from the bundle's
/// Info.plist, so upstream's build (project.yml) behaves exactly as before and
/// the BDB bundle script only has to change plist keys.
enum BDBBrand {
    /// "Codenotch" upstream, "BDB AO Codenotch" in the BDB bundle.
    static let displayName: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Codenotch"

    /// Sparkle can only run with a feed. The BDB bundle ships without
    /// `SUFeedURL`, which switches every update path off (see `Updater`).
    static let updatesAvailable: Bool = {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        return !(feed ?? "").isEmpty
    }()
}

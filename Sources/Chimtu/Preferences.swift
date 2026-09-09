import Foundation

/// One place for every user preference. Same UserDefaults keys as v1, so
/// existing users keep their settings. Posts `.chimtuPreferencesChanged` on writes.
final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard
    private init() {}

    var scale: Double { get { let v = d.double(forKey: "petScale"); return v == 0 ? 1 : v } set { d.set(newValue, forKey: "petScale"); changed() } }
    var hat: String { get { d.string(forKey: "hat") ?? "none" } set { d.set(newValue, forKey: "hat"); changed() } }
    var typingReactions: Bool { get { d.object(forKey: "typingReactions") as? Bool ?? true } set { d.set(newValue, forKey: "typingReactions"); changed() } }
    var skin: String { get { d.string(forKey: "skin") ?? "shiba" } set { d.set(newValue, forKey: "skin"); changed() } }
    var soundsEnabled: Bool { get { d.bool(forKey: "soundsEnabled") } set { d.set(newValue, forKey: "soundsEnabled"); changed() } }
    var soundVolume: Double { get { d.object(forKey: "soundVolume") as? Double ?? 0.3 } set { d.set(newValue, forKey: "soundVolume"); changed() } }
    /// 0 quiet, 1 normal, 2 chatty
    var chattiness: Int { get { d.object(forKey: "chattiness") as? Int ?? 1 } set { d.set(newValue, forKey: "chattiness"); changed() } }
    var quietStart: Int { get { d.object(forKey: "quietStart") as? Int ?? 23 } set { d.set(newValue, forKey: "quietStart"); changed() } }
    var quietEnd: Int { get { d.object(forKey: "quietEnd") as? Int ?? 6 } set { d.set(newValue, forKey: "quietEnd"); changed() } }

    /// Reaction categories the user can switch off.
    enum Category: String, CaseIterable { case appEvents, clipboard, filesAndDrives, music, globalClicks, hourlyHowl }
    func isEnabled(_ c: Category) -> Bool { d.object(forKey: "react.\(c.rawValue)") as? Bool ?? true }
    func setEnabled(_ c: Category, _ on: Bool) { d.set(on, forKey: "react.\(c.rawValue)"); changed() }

    private func changed() { NotificationCenter.default.post(name: .chimtuPreferencesChanged, object: nil) }
}

extension Notification.Name {
    static let chimtuPreferencesChanged = Notification.Name("chimtuPreferencesChanged")
}

import Foundation

/// This installation's id, for the `device` in journal file headers. Made once, at the first launch
/// that asks, and kept in UserDefaults; it never goes in the journal or syncs anywhere.
enum DeviceID {
    /// Where it's kept in the defaults.
    static let key = "deviceID"

    /// The id kept in `defaults`, made and saved first if there's none (or it doesn't read). Call it
    /// once at startup and keep the value: two first calls at once could make two ids.
    static func current(in defaults: UserDefaults) -> UUID {
        if let text = defaults.object(forKey: key) as? String, let id = UUID(uuidString: text) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}

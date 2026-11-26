import Observation

/// Each student's entry on a roster form (present/absent, marks) and whether the entries were filled from the server
/// (Android's RosterEntries).
///
/// The two live and die together, in the screen's model: on Android, entries kept apart from the flag were lost on a
/// rotation while the flag said "filled", so every student showed as present (or ungraded) and saving overwrote the
/// stored records.
@MainActor
@Observable
final class RosterEntries<V> {
    var values: [String: V] = [:]
    private(set) var initialised = false

    /// Fills the entries once, from [initial] (enrollment id → value).
    func initialiseOnce(_ initial: () -> [String: V]) {
        if initialised { return }
        values.merge(initial()) { _, new in new }
        initialised = true
    }
}

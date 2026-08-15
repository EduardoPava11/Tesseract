// ArrangementStore.swift
// Tesseract
//
// PORT of spec/ui/WidgetGrid.hs (WG4 — "an arrangement is a VALUE:
// serialisable, restorable"). The Haskell is authoritative; this is a
// port and may not improve on it.
//
// WG4 is what makes persistence honest: the entire surface is twelve
// (col, row) pairs, so restoring it is 25 integers, not a document
// format. This file is the ONLY place those integers cross the
// process boundary.
//
// ── THE TOTAL LOAD IS THE WHOLE DESIGN ──────────────────────────
//
// Persisting a layout the user can rearrange creates exactly one new
// failure mode: an unusable surface that survives a relaunch. So
// `load` NEVER throws and NEVER partially migrates. Any doubt at all
// — missing, wrong type, wrong length, wrong schema, wrong shape, or
// a decoded arrangement that is not LAWFUL — returns
// `Arrangement.default`. A stale layout is data; an unlawful one is a
// bug that would reach a renderer, and WG3 exists precisely so that
// never happens.
//
// RESET is the second half of that argument, and it lives on a STATIC
// region (GridLayout's settings cover), never on a movable widget: no
// arrangement, however bad, can make reset unreachable, because reset
// is not in the arrangement.
//
// PRIVACY: UserDefaults is already declared CA92.1 in
// PrivacyInfo.xcprivacy (the app's only required-reason API). No
// manifest work; nothing here leaves the device.

import Foundation

enum ArrangementStore {

    /// The one key. Namespaced so a future surface can add its own.
    static let key = "tesseract.widgetArrangement"

    /// Bump on ANY change to `Widget` — the vocabulary is CLOSED (WG6),
    /// so a vocabulary change makes every stored ordinal mean something
    /// else. A bump costs the user their layout once; not bumping costs
    /// them a scrambled surface, silently.
    static let schema = 1

    /// `[schema, col₀, row₀, …, col₁₁, row₁₁]` — 1 + 2 × 12 = 25 ints.
    static var storedCount: Int { 1 + 2 * Widget.allCases.count }

    /// WG4 — restore. Total: every corruption lands on `.default`.
    static func load(_ defaults: UserDefaults = .standard) -> Arrangement {
        guard let raw = defaults.array(forKey: key) as? [Int],
              raw.count == storedCount,
              raw[0] == schema,
              let decoded = Arrangement(serialised: Array(raw.dropFirst())),
              decoded.isLawful
        else { return .default }
        return decoded
    }

    /// WG4 — persist. Called on a COMMITTED move only: a refused move
    /// (`Arrangement.moving` → nil) writes nothing, so storage can only
    /// ever hold arrangements that passed the same lawfulness proof the
    /// static scenes pass at launch.
    static func save(_ a: Arrangement, to defaults: UserDefaults = .standard) {
        defaults.set([schema] + a.serialised, forKey: key)
    }

    /// The escape hatch. Removing the key (rather than writing the
    /// default) means a later schema change starts clean, and it makes
    /// "reset" and "never arranged" the same state.
    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

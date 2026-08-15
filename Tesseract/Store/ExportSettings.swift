// ExportSettings.swift
// Tesseract
//
// One of the app's FOUR persistence sites, all of which now live in
// Store/ (2026-08-14 directory ruling). The other three:
//
//   CubeStore         Documents/Cubes    1.75 MiB per capture, the
//                                        retained tensor CR1 keeps
//   GIFLibrary        Documents/Library  the artifacts, self-describing
//   ArrangementStore  UserDefaults       the widget arrangement
//   ExportSettings    UserDefaults       BLEED and MIRROR
//
// ★ WHY THEY ARE TOGETHER. UserDefaults is the ONLY required-reason API
// this app uses (PrivacyInfo.xcprivacy, CA92.1), so the declaration is
// auditable exactly when every writer of it is in one directory. It was
// spread across Edit/, Weave/ and UI/Widgets/ before, and no reader
// could see the whole memory bill from any one place.
//
// The persisted settings. Missing stored values parse to defaults.
// Useful and simple: every entry here has a visible effect on the GIF.
// (The old `method` setting is gone — DYAD is the law, not a choice; a
// stale "export.method" default is simply ignored.)

import Foundation

struct ExportSettings: Sendable {
    /// DYAD background: coverage dither band (true) or hard MAP
    /// classes only (false — role law v1, a lawful subset).
    var bleed: Bool
    /// Mirror the exported GIF horizontally (selfie orientation).
    /// Index-domain flip — exact.
    var mirror: Bool

    static let bleedKey = "export.bleed"
    static let mirrorKey = "export.mirror"

    static func load() -> ExportSettings {
        let defaults = UserDefaults.standard
        return ExportSettings(
            bleed: defaults.object(forKey: bleedKey) as? Bool ?? true,
            mirror: defaults.object(forKey: mirrorKey) as? Bool ?? false)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(bleed, forKey: Self.bleedKey)
        defaults.set(mirror, forKey: Self.mirrorKey)
    }
}

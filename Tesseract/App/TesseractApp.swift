// TesseractApp.swift
// Tesseract
//
// 4⁴ = 256. R1 ⊕ R3 = R4.
// 64³ sRGB GIFs with Birkhoff beauty.

import SwiftUI

@main
struct TesseractApp: App {
    init() {
        #if DEBUG
        // The grid constitution re-asserts itself on every launch:
        // atom identity, tiling, touch floor, scene disjointness.
        TesseractLattice.selfCheck()
        GridLayout.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

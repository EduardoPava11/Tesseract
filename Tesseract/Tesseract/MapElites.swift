// MapElites.swift
// Tesseract
//
// Port of spec/neural/MapElites.hs: quality-diversity exploration.
// 3×3 grid indexed by (temporal rhythm, color spread).
// Each cell holds the BEST gene (by Birkhoff beauty).
//
// Sobol directions guarantee each swipe is NEW.
// DPP-inspired repulsion rejects duplicates.
// The user sees a MAP of the aesthetic space they've explored.

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. BEHAVIORAL DESCRIPTOR
// ════════════════════════════════════════════════════════════════

/// Where in the aesthetic space this organism lives.
/// Two axes from EntropyFeedback:
///   rhythm = H(d) — how active the temporal axis is
///   spread = H(joint) — how many palette entries are used
struct Descriptor: Equatable {
    let rhythm: Float    // H(d) / log(4) ∈ [0,1]
    let spread: Float    // H(d,a,b,c) / log(256) ∈ [0,1]

    /// Grid cell in the 3×3 MAP
    var gridRow: Int { min(2, max(0, Int(rhythm * 3))) }
    var gridCol: Int { min(2, max(0, Int(spread * 3))) }

    /// Euclidean distance to another descriptor
    func distance(to other: Descriptor) -> Float {
        sqrt(pow(rhythm - other.rhythm, 2) + pow(spread - other.spread, 2))
    }

    /// Build from EntropyFeedback
    static func from(_ entropy: EntropyFeedback) -> Descriptor {
        Descriptor(rhythm: entropy.epoch, spread: entropy.joint)
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. ELITE MAP — 3×3 grid, best gene per cell
// ════════════════════════════════════════════════════════════════

/// One cell in the MAP: the best organism found at this (rhythm, spread) point.
struct EliteCell {
    let gene: GeneWeights
    let beauty: Float         // Birkhoff M = O/C
    let descriptor: Descriptor
    let gifData: Data         // the GIF for this organism
    let entropy: EntropyFeedback
}

/// The 3×3 MAP-Elites grid.
/// Each cell holds the BEST organism (by Birkhoff beauty) found at that
/// behavioral descriptor. Empty cells = unexplored aesthetic regions.
class EliteMap {
    static let rows = 3
    static let cols = 3

    private(set) var cells: [[EliteCell?]]
    private(set) var history: [Descriptor] = []

    init() {
        cells = Array(repeating: Array(repeating: nil, count: EliteMap.cols), count: EliteMap.rows)
    }

    /// How many cells are populated
    var coverage: Int {
        cells.flatMap { $0 }.compactMap { $0 }.count
    }

    /// Place a new organism. Returns true if it was placed (new or better).
    @discardableResult
    func place(gene: GeneWeights, beauty: Float, descriptor: Descriptor,
               gifData: Data, entropy: EntropyFeedback) -> Bool {
        let row = descriptor.gridRow
        let col = descriptor.gridCol

        let shouldPlace: Bool
        if let existing = cells[row][col] {
            shouldPlace = beauty > existing.beauty  // only replace if better
        } else {
            shouldPlace = true  // empty cell, always place
        }

        history.append(descriptor)

        if shouldPlace {
            cells[row][col] = EliteCell(
                gene: gene, beauty: beauty, descriptor: descriptor,
                gifData: gifData, entropy: entropy
            )
            return true
        }
        return false
    }

    /// Best organism across the entire map
    func bestOverall() -> EliteCell? {
        cells.flatMap { $0 }.compactMap { $0 }.max(by: { $0.beauty < $1.beauty })
    }

    /// All populated descriptors (for boldness check)
    var descriptors: [Descriptor] {
        cells.flatMap { $0 }.compactMap { $0?.descriptor }
    }

    /// Reset (new capture session)
    func reset() {
        cells = Array(repeating: Array(repeating: nil, count: EliteMap.cols), count: EliteMap.rows)
        history.removeAll()
    }

    // ── Boldness Check (DPP-inspired) ──

    /// Minimum distance threshold for a descriptor to be "bold"
    static let boldnessThreshold: Float = 0.1

    /// Is a new descriptor bold relative to existing organisms?
    func isBold(_ desc: Descriptor) -> Bool {
        let existing = descriptors
        guard !existing.isEmpty else { return true }
        let minDist = existing.map { desc.distance(to: $0) }.min() ?? 0
        return minDist > EliteMap.boldnessThreshold
    }

    /// Repulsion score: sum of squared distances to existing organisms.
    /// Higher = more repulsive = bolder.
    func repulsionScore(_ desc: Descriptor) -> Float {
        let existing = descriptors
        guard !existing.isEmpty else { return 1.0 }
        return existing.map { pow(desc.distance(to: $0), 2) }.reduce(0, +) / Float(existing.count)
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. GRID LABELS (for UI)
// ════════════════════════════════════════════════════════════════

extension EliteMap {
    static let rowLabels = ["static", "pulsing", "dynamic"]   // rhythm: low → high
    static let colLabels = ["mono", "natural", "vivid"]       // spread: low → high
}

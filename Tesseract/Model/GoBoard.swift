// GoBoard.swift
// Tesseract
//
// Port of TesseractGo.hs: 19×19 color blocks as Go positions.
//
// 3D sRGB decomposes into 3 pairwise comparisons:
//   R/G, G/B, B/R → three 19×19 Go boards.
//
// Go territory analysis reveals SPATIAL COLOR STRUCTURE
// that histograms alone cannot see:
//   Territory  → which channel dominates spatially
//   Liberties  → boundary pixels available for dithering
//   Complexity → how much color structure exists
//
// Memory per block: 3 × 361 stones = 1,083 bytes

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. ALGEBRAIC TYPES (match Haskell: Stone, Board, GoBoards)
// ════════════════════════════════════════════════════════════════

/// A stone on the Go board: which channel dominates at this position.
enum GoStone: UInt8 {
    case black = 0   // channel A dominates (A > B + threshold)
    case white = 1   // channel B dominates (B > A + threshold)
    case empty = 2   // balanced (boundary — dithering candidate)
}

/// A 19×19 Go board from one channel-pair comparison.
/// Memory: 361 bytes (19 × 19 × 1 byte per stone).
struct GoBoard {
    static let size = 19
    static let count = size * size  // 361

    /// Row-major storage: board[y * 19 + x]
    var stones: [GoStone]

    init() {
        stones = [GoStone](repeating: .empty, count: GoBoard.count)
    }

    subscript(x: Int, y: Int) -> GoStone {
        get { stones[y * GoBoard.size + x] }
        set { stones[y * GoBoard.size + x] = newValue }
    }
}

/// Three pairwise channel comparison boards from one 19×19 block.
/// Memory: 3 × 361 = 1,083 bytes.
struct GoBoards {
    var rg: GoBoard   // Red vs Green
    var gb: GoBoard   // Green vs Blue
    var br: GoBoard   // Blue vs Red
}

// ════════════════════════════════════════════════════════════════
// § 2. BLOCK → THREE GO BOARDS
// ════════════════════════════════════════════════════════════════

/// Threshold for "balanced" — below this, the pixel is at the boundary.
private let goThreshold: Float = 0.08

/// Convert a 19×19 block of RGB pixels to three Go boards.
/// Each pixel becomes an intersection on each board.
func blockToGoBoards(pixels: [(Float, Float, Float)]) -> GoBoards {
    var rg = GoBoard(), gb = GoBoard(), br = GoBoard()

    for i in 0..<min(GoBoard.count, pixels.count) {
        let (r, g, b) = pixels[i]
        rg.stones[i] = stoneCompare(r, g)
        gb.stones[i] = stoneCompare(g, b)
        br.stones[i] = stoneCompare(b, r)
    }

    return GoBoards(rg: rg, gb: gb, br: br)
}

private func stoneCompare(_ a: Float, _ b: Float) -> GoStone {
    if a - b > goThreshold { return .black }
    if b - a > goThreshold { return .white }
    return .empty
}

// ════════════════════════════════════════════════════════════════
// § 3. TERRITORY ANALYSIS
// ════════════════════════════════════════════════════════════════

/// Territory count for one board.
/// Memory: 4 × Int + 1 × Double = 40 bytes.
struct Territory {
    let black: Int      // channel A territory
    let white: Int      // channel B territory
    let empty: Int      // boundary pixels
    let score: Float    // (black - white) / total, >0 = A dominates
}

func countTerritory(_ board: GoBoard) -> Territory {
    var b = 0, w = 0, e = 0
    for s in board.stones {
        switch s {
        case .black: b += 1
        case .white: w += 1
        case .empty: e += 1
        }
    }
    let total = Float(max(1, b + w + e))
    return Territory(black: b, white: w, empty: e,
                     score: Float(b - w) / total)
}

// ════════════════════════════════════════════════════════════════
// § 4. LIBERTIES (boundary pixels adjacent to a color)
// ════════════════════════════════════════════════════════════════

/// Count liberties: empty intersections adjacent to stones of given color.
/// In Go: liberties = survival potential.
/// In color: liberties = dithering candidates.
func countLiberties(_ board: GoBoard, color: GoStone) -> Int {
    let s = GoBoard.size
    var count = 0
    for y in 0..<s {
        for x in 0..<s {
            guard board[x, y] == .empty else { continue }
            // Check 4-connected neighbors
            let neighbors = [(x-1,y), (x+1,y), (x,y-1), (x,y+1)]
            for (nx, ny) in neighbors {
                if nx >= 0 && nx < s && ny >= 0 && ny < s && board[nx, ny] == color {
                    count += 1
                    break  // count this empty position once
                }
            }
        }
    }
    return count
}

// ════════════════════════════════════════════════════════════════
// § 5. BOARD EVALUATION
// ════════════════════════════════════════════════════════════════

/// Full evaluation of one Go board.
/// Memory: ~80 bytes.
struct BoardEval {
    let territory: Territory
    let libertyBlack: Int
    let libertyWhite: Int
    let complexity: Float    // (liberties + empty) / 361
}

func evaluateBoard(_ board: GoBoard) -> BoardEval {
    let terr = countTerritory(board)
    let libB = countLiberties(board, color: .black)
    let libW = countLiberties(board, color: .white)
    let total = Float(GoBoard.count)
    let cmplx = Float(libB + libW + terr.empty) / total
    return BoardEval(territory: terr, libertyBlack: libB,
                     libertyWhite: libW, complexity: cmplx)
}

/// Full evaluation of all 3 boards in a block.
/// Memory: 3 × 80 + 16 = 256 bytes.
struct BlockEval {
    let rg: BoardEval
    let gb: BoardEval
    let br: BoardEval
    let complexity: Float     // average of 3 boards
    let ditherBudget: Int     // total liberties across all boards
}

func evaluateBlock(_ boards: GoBoards) -> BlockEval {
    let eRG = evaluateBoard(boards.rg)
    let eGB = evaluateBoard(boards.gb)
    let eBR = evaluateBoard(boards.br)
    let avgCmplx = (eRG.complexity + eGB.complexity + eBR.complexity) / 3.0
    let totalLibs = eRG.libertyBlack + eRG.libertyWhite
                  + eGB.libertyBlack + eGB.libertyWhite
                  + eBR.libertyBlack + eBR.libertyWhite
    return BlockEval(rg: eRG, gb: eGB, br: eBR,
                     complexity: avgCmplx, ditherBudget: totalLibs)
}

// needsNNEval removed — KataGo deprecated.
// Territory + liberties from evaluateBlock() are sufficient.
// See spec/deprecated/DEPRECATED.md for rationale.

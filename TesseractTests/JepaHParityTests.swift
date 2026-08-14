// ★JEPA-H (JH4) — the deployed head's CI teeth.
//
// The full 8-ring float64 parity gate lives in nn/jepa/parity_swift.sh
// (machine-epsilon agreement with the training forward). This suite
// pins one embedded fixture ring plus the LAWS the placement relies
// on: exact ring-rotation equivariance (no phase origin), constancy
// on constant rings, and the jepaSmoothed structure contract
// (slot sharing, PSD covariance, partial-capture refusal).

import XCTest
@testable import Tesseract

final class JepaHParityTests: XCTestCase {

    // Fixture: held-out corpus ring #1016, expected = float64
    // training forward (nn/jepa/export_swift.py).
    private let y: [[Double]] = [
        [0.5502017804019925, 0.04747601122519471, 0.08181364436878963, -5.1149580275924205, -3.959200483028044, -6.783421107245732],
        [0.6770151141188815, 0.04178653670074508, 0.09303863627177505, -5.530424965426663, -3.210615362005658, -6.492666735717577],
        [0.6914128078513387, 0.04987252203659626, 0.09298204862304928, -5.607008857541931, -3.3944921319039265, -6.338207941347511],
        [0.6756527265284238, 0.030833808030893868, 0.09165760777614555, -5.57688345036896, -3.4179797060676576, -6.48200173617477],
        [0.6558917484541352, 0.0415410021302044, 0.08740853283358477, -5.332056686203203, -3.5064894350514204, -6.35449559367266],
        [0.7092823577818274, 0.04447986205693265, 0.09356378516674442, -5.385195617886433, -3.7693045999777954, -5.930399200603889],
        [0.7056416520618651, 0.04554827466191769, 0.09720274034470248, -5.283692547334984, -3.8213072433458706, -6.225491884727296],
        [0.7376694288974961, 0.03100826256012324, 0.09666185039658087, -5.350970427684948, -3.6265174474308446, -6.492993831109399],
        [0.7476676719722704, 0.050726844549238016, 0.09252678257007747, -5.338757263385346, -3.7778611778106783, -6.371028886286229],
        [0.7879866286962702, 0.03958925566583975, 0.09854089610451595, -5.1512288655769565, -3.9403523649847854, -6.354004365229401],
        [0.7883802856650524, 0.03779401697442615, 0.09849753567976353, -5.07132532913876, -4.0411764326715165, -6.562708461851146],
        [0.7911444589140726, 0.03170816165306116, 0.11191080438667061, -5.195854493165872, -4.064351311872519, -6.555242383204937],
        [0.7904283806164881, 0.050263367692707894, 0.11216723493686186, -5.142017012019365, -3.922445969242717, -6.417708833598064],
        [0.8055064937377076, 0.05039555898481, 0.120452925732609, -5.079368224761145, -4.056959052231284, -6.366662220209461],
        [0.8686317415744831, 0.05034208622717093, 0.11867605194780247, -5.0330356875668665, -3.7059513840435843, -6.017208044830277],
        [0.8250172291499958, 0.04562701841004975, 0.11438618582689795, -5.207837771382832, -3.7078426312764607, -5.924881416335241]
    ]
    private let want: [[Double]] = [
        [0.5791292839866663, 0.046373721304523066, 0.08398598140546536, -5.160534322729268, -3.8269171322362405, -6.52688725254428],
        [0.6661916446868955, 0.044008449061614635, 0.09213976861206279, -5.482409435593602, -3.342781274147187, -6.462870781548916],
        [0.6741876406887546, 0.043538997805000555, 0.09209805291341314, -5.5633235066398825, -3.407285107900538, -6.43270453066561],
        [0.6771967247067262, 0.03879260380841733, 0.09133525080147345, -5.53920088103826, -3.4412205015396693, -6.384661072061789],
        [0.6746232292766169, 0.04119700900102826, 0.08955834976375264, -5.376554848880301, -3.5545596538256063, -6.289356575331872],
        [0.6983578113086438, 0.04086690964727627, 0.09321933199819889, -5.368644330647864, -3.695754627211822, -6.144813236167366],
        [0.7118784766624404, 0.04230943319428623, 0.09596887034174179, -5.311351524636754, -3.750559452336986, -6.246336980495509],
        [0.7349046739231484, 0.039067197635628215, 0.09605345037840966, -5.333075220949141, -3.7185428382410874, -6.361753486402981],
        [0.753331453143264, 0.04328365844873899, 0.09445898932614369, -5.302564613699172, -3.8014653775291665, -6.3939387710719835],
        [0.7774197784089273, 0.039815559096411615, 0.09807061356529902, -5.175942670910744, -3.9146433856217704, -6.4251484845585],
        [0.7862773040661323, 0.03975970408041953, 0.10073544663083196, -5.111350503131863, -3.9992166261891677, -6.493517575084596],
        [0.7912150668517018, 0.03931784597141418, 0.10981756346326234, -5.164981089998318, -4.022693649101033, -6.495885308349929],
        [0.7984558127601958, 0.045046530604258395, 0.11310289375687188, -5.133924906517237, -3.969075827319236, -6.409168996613019],
        [0.8148273578800185, 0.0475853223503305, 0.11837769689654898, -5.091032016040494, -3.954629611692965, -6.291294398134587],
        [0.8259390008687911, 0.04893266740421983, 0.11651655136684017, -5.06978296859236, -3.7997135246465437, -6.169951265700552],
        [0.7869662934509638, 0.047224874543757844, 0.11110619536848841, -5.179213736124746, -3.7465748027082535, -6.154063907643374]
    ]

    func testEmbeddedFixtureParity() {
        let got = JepaHHead.smoothRing(y)
        var worst = 0.0
        for t in 0..<16 {
            for d in 0..<6 { worst = max(worst, abs(got[t][d] - want[t][d])) }
        }
        XCTAssertLessThan(worst, 1e-9,
            "Swift head drifted from the float64 training forward")
    }

    /// The model has no phase origin (spec JepaH.hs JH4 + the filter
    /// being a ring convolution): rotating the input ring rotates
    /// the output ring EXACTLY.
    func testRingRotationEquivariance() {
        func rot(_ x: [[Double]], _ k: Int) -> [[Double]] {
            (0..<16).map { x[($0 + k) % 16] }
        }
        let base = JepaHHead.smoothRing(y)
        for k in [1, 3, 7] {
            let rotated = JepaHHead.smoothRing(rot(y, k))
            for t in 0..<16 {
                for d in 0..<6 {
                    XCTAssertEqual(rotated[t][d], rot(base, k)[t][d],
                                   accuracy: 1e-9)
                }
            }
        }
    }

    /// A constant ring is a fixed point: whitening zeroes it, the
    /// filter and gate act on zeros, de-whitening restores the mean.
    func testConstantRingFixedPoint() {
        let flat = [[Double]](repeating: [0.6, 0.02, 0.05, -5, -4, -6.5],
                              count: 16)
        let out = JepaHHead.smoothRing(flat)
        for t in 0..<16 {
            for d in 0..<6 {
                XCTAssertEqual(out[t][d], flat[t][d], accuracy: 1e-9)
            }
        }
    }

    /// The placement contract (ONE ring for ALL generating state,
    /// ruling R2): 64 stats + bg triples → 64, frames within a
    /// 4-frame slot share ONE state — stats AND bg — covariances
    /// stay PSD (positive diagonals, |r| ≤ 1 recombination),
    /// bg gaps fill around the torus, sdLnC stays positive, an
    /// all-nil bg stays nil (the prior rules downstream), and a
    /// partial capture refuses (nil ⇒ the EMA law stands).
    func testJepaSmoothedStructure() {
        var raw: [DyadPalette.Stats] = []
        var bg: [DyadPalette.BackgroundMoments?] = []
        for f in 0..<64 {
            let x = Double(f) / 63.0
            let cov = [[0.004 + 0.002 * x, 0.0005, 0.0002],
                       [0.0005, 0.02 + 0.01 * x, 0.0004],
                       [0.0002, 0.0004, 0.0015 + 0.001 * x]]
            raw.append(DyadPalette.makeStats(
                centroid: OKLabColor(l: 0.5 + 0.3 * x, a: 0.03, b: 0.06 + 0.04 * x),
                covariance: cov))
            // slots 3..5 (frames 12..23) carry no background evidence
            bg.append((12..<24).contains(f) ? nil
                : DyadPalette.BackgroundMoments(
                    meanL: 0.7 - 0.1 * x, meanLnC: -2.5 + 0.3 * x,
                    sdLnC: 0.2 + 0.05 * x,
                    // ★ GroundHue GH13: the hue rides the ring as a
                    // unit VECTOR; here it sweeps 0° → 45° across the
                    // capture so the extra dims are exercised.
                    hueA: cos(0.25 * .pi * x), hueB: sin(0.25 * .pi * x)))
        }
        guard let out = DyadPipeline.jepaSmoothed(raw, bg: bg) else {
            return XCTFail("full 64-frame capture must smooth")
        }
        XCTAssertEqual(out.stats.count, 64)
        XCTAssertEqual(out.bg.count, 64)
        for s in 0..<16 {
            let head = out.stats[s * 4]
            let bgHead = out.bg[s * 4]
            XCTAssertNotNil(bgHead, "torus fill must cover empty slots")
            XCTAssertGreaterThan(bgHead!.sdLnC, 0)
            for f in (s * 4)..<(s * 4 + 4) {
                XCTAssertEqual(out.stats[f].centroid.l, head.centroid.l)
                XCTAssertEqual(out.stats[f].covariance[0][0], head.covariance[0][0])
                XCTAssertEqual(out.bg[f]!.meanL, bgHead!.meanL)
                XCTAssertEqual(out.bg[f]!.sdLnC, bgHead!.sdLnC)
                // ★ GroundHue GH13: the hue dims hold at the same
                // 5 Hz cadence as the rest of the generating state.
                XCTAssertEqual(out.bg[f]!.hueA, bgHead!.hueA)
                XCTAssertEqual(out.bg[f]!.hueB, bgHead!.hueB)
            }
            let c = head.covariance
            for i in 0..<3 { XCTAssertGreaterThan(c[i][i], 0) }
            for (i, j) in [(0, 1), (0, 2), (1, 2)] {
                XCTAssertLessThanOrEqual(
                    abs(c[i][j]), (c[i][i] * c[j][j]).squareRoot() + 1e-12)
                XCTAssertEqual(c[i][j], c[j][i])
            }
        }
        // single-phase: no bg anywhere ⇒ bg stays nil everywhere
        let noBg = DyadPipeline.jepaSmoothed(
            raw, bg: [DyadPalette.BackgroundMoments?](
                repeating: nil, count: 64))
        XCTAssertNotNil(noBg)
        XCTAssertTrue(noBg!.bg.allSatisfy { $0 == nil })
        // partial capture refuses
        XCTAssertNil(DyadPipeline.jepaSmoothed(Array(raw.prefix(63)),
                                               bg: Array(bg.prefix(63))),
                     "partial capture must refuse and fall back to EMA")
    }
}

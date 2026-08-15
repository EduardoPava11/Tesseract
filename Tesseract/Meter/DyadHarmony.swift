// DyadHarmony.swift
// Tesseract
//
// Ou & Luo two-colour harmony model, closed form (Li-Chen Ou and
// M. Ronnier Luo, "A colour harmony model for two-colour
// combinations", Color Research & Application 31(3), 2006):
//
//     CH = HC + HL + HH
//
// CH is CIELAB-based (D65); larger = more harmonious, published range
// roughly -1.24 to 1.39. Pure scoring: reads palette entries, never
// shapes them. Reported in the GIF provenance trace by GIFMachine.

import Foundation

enum DyadHarmony {

    /// sRGB 8-bit to CIELAB, D65 white, 2-degree observer.
    /// IEC 61966-2-1 linearization + sRGB-to-XYZ matrix, then CIE L*a*b*.
    static func srgb8ToCIELAB(_ rgb: (UInt8, UInt8, UInt8)) -> (L: Double, a: Double, b: Double) {
        func lin(_ v: UInt8) -> Double {
            let c = Double(v) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = lin(rgb.0), g = lin(rgb.1), b = lin(rgb.2)
        // sRGB (D65) linear RGB to XYZ, IEC 61966-2-1 primaries.
        let x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
        // D65 reference white.
        let xn = 0.95047, yn = 1.0, zn = 1.08883
        // CIE 1976 f: cube root above (6/29)^3, linear ramp below.
        func f(_ t: Double) -> Double {
            let d = 6.0 / 29.0
            return t > d * d * d ? cbrt(t) : t / (3 * d * d) + 4.0 / 29.0
        }
        let fx = f(x / xn), fy = f(y / yn), fz = f(z / zn)
        return (L: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// CH of one colour pair: CH = HC + HL + HH (Ou & Luo 2006).
    /// Symmetric in its arguments; every effect below is even in the
    /// pair swap, so equality is exact in Double.
    static func pairHarmony(_ a: (UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8)) -> Double {
        let p = srgb8ToCIELAB(a)
        let q = srgb8ToCIELAB(b)
        // CIELAB chroma C*ab = (a*^2 + b*^2)^1/2.
        let c1 = (p.a * p.a + p.b * p.b).squareRoot()
        let c2 = (q.a * q.a + q.b * q.b).squareRoot()

        // -- Chromatic effect --
        // Delta C*ab and Delta H*ab, with
        // (Delta H*ab)^2 = (Delta a*)^2 + (Delta b*)^2 - (Delta C*ab)^2.
        let dC = c1 - c2
        let da = p.a - q.a, db = p.b - q.b
        let dH2 = max(0, da * da + db * db - dC * dC)
        // Ou & Luo 2006: DeltaC = [(DeltaH*ab)^2 + (DeltaC*ab / 1.46)^2]^1/2
        let deltaC = (dH2 + (dC / 1.46) * (dC / 1.46)).squareRoot()
        // Ou & Luo 2006: HC = 0.04 + 0.53 tanh(0.8 - 0.045 DeltaC)
        let hC = 0.04 + 0.53 * tanh(0.8 - 0.045 * deltaC)

        // -- Lightness effect: HL = HLsum + HdeltaL --
        // Ou & Luo 2006: HLsum = 0.28 + 0.54 tanh(-3.88 + 0.029 Lsum),
        // Lsum = L*1 + L*2
        let hLsum = 0.28 + 0.54 * tanh(-3.88 + 0.029 * (p.L + q.L))
        // Ou & Luo 2006: HdeltaL = 0.14 + 0.15 tanh(-2 + 0.2 DeltaL),
        // DeltaL = |L*1 - L*2|
        let hDeltaL = 0.14 + 0.15 * tanh(-2 + 0.2 * abs(p.L - q.L))
        let hL = hLsum + hDeltaL

        // -- Hue effect --
        // Ou & Luo 2006: HH = HSY1 + HSY2
        let hH = hueEffect(p, chroma: c1) + hueEffect(q, chroma: c2)

        return hC + hL + hH
    }

    /// One colour's contribution to the hue effect:
    /// Ou & Luo 2006: HSY = EC (HS + EY).
    private static func hueEffect(_ lab: (L: Double, a: Double, b: Double),
                                  chroma: Double) -> Double {
        // CIELAB hue angle hab in degrees, [0, 360).
        var h = atan2(lab.b, lab.a) * 180 / Double.pi
        if h < 0 { h += 360 }
        let rad = Double.pi / 180
        // Ou & Luo 2006: EC = 0.5 + 0.5 tanh(-2 + 0.5 C*ab)
        let eC = 0.5 + 0.5 * tanh(-2 + 0.5 * chroma)
        // Ou & Luo 2006: HS = -0.08 - 0.14 sin(hab + 50 deg)
        //                          - 0.07 sin(2 hab + 90 deg)
        let hS = -0.08 - 0.14 * sin((h + 50) * rad) - 0.07 * sin((2 * h + 90) * rad)
        // Ou & Luo 2006: EY = [(0.22 L* - 12.8) / 10]
        //     exp{(90 deg - hab) / 10 - exp[(90 deg - hab) / 10]}
        let t = (90 - h) / 10
        let eY = (0.22 * lab.L - 12.8) / 10 * exp(t - exp(t))
        return eC * (hS + eY)
    }

    /// CH over the 128 sigma-pairs (i, 255 - i) of a DYAD-256 table.
    static func tableHarmony(_ table: [(UInt8, UInt8, UInt8)]) -> (mean: Double, min: Double) {
        precondition(table.count == 256, "DYAD table has 256 entries")
        var sum = 0.0
        var minCH = Double.infinity
        for i in 0..<128 {
            let ch = pairHarmony(table[i], table[255 - i])
            sum += ch
            if ch < minCH { minCH = ch }
        }
        return (mean: sum / 128, min: minCH)
    }
}

// JH4 parity harness (Mac, swiftc): the pure-Swift head vs the
// float64 training forward on 8 held-out corpus rings.
// Run: ./parity_swift.sh

import Foundation

let url = URL(fileURLWithPath: "fixtures_head.json")
let data = try! Data(contentsOf: url)
let fixtures = try! JSONSerialization.jsonObject(with: data) as! [[String: [[Double]]]]

var worst = 0.0
for fx in fixtures {
    let y = fx["y"]!, want = fx["shat"]!
    let got = JepaHHead.smoothRing(y)
    for t in 0..<16 {
        for d in 0..<6 {
            worst = max(worst, abs(got[t][d] - want[t][d]))
        }
    }
}
print(String(format: "  swift head parity vs python float64: max |diff| = %.2e", worst))
guard worst < 1e-9 else {
    print("  PARITY GATE ✗")
    exit(1)
}
print("  PARITY GATE ✓")

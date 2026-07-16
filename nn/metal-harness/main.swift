// Parity + timing harness for DebayerNet.metal against nn/debayer/golden.npz.
// Usage: harness <debayer.metallib> <golden.bin>
// Gate: FP32-weight kernel max-abs error vs golden FP32 outputs <= 2e-3.
import Foundation
import Metal

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(("FATAL: " + msg + "\n").data(using: .utf8)!)
    exit(1)
}

// ---- load golden.bin ----
struct GoldenCase {
    let name: String
    let h: Int, w: Int
    let mosaic: [Float]
    let output: [Float]
}

func loadGolden(_ path: String) -> [GoldenCase] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { die("cannot read \(path)") }
    var off = 0
    func u32() -> Int {
        let v = data.subdata(in: off..<off + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
        off += 4
        return Int(v)
    }
    func floats(_ n: Int) -> [Float] {
        let d = data.subdata(in: off..<off + 4 * n)
        off += 4 * n
        return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
    var cases: [GoldenCase] = []
    let n = u32()
    for _ in 0..<n {
        let nameLen = u32()
        let name = String(data: data.subdata(in: off..<off + nameLen), encoding: .utf8)!
        off += nameLen
        let h = u32(), w = u32()
        cases.append(GoldenCase(name: name, h: h, w: w, mosaic: floats(h * w), output: floats(h * w * 3)))
    }
    return cases
}

// ---- Metal setup ----
let args = CommandLine.arguments
guard args.count == 3 else { die("usage: harness <metallib> <golden.bin>") }
let cases = loadGolden(args[2])

guard let device = MTLCreateSystemDefaultDevice() else { die("no Metal device") }
guard let queue = device.makeCommandQueue() else { die("no command queue") }
let lib: MTLLibrary
do { lib = try device.makeLibrary(URL: URL(fileURLWithPath: args[1])) } catch { die("makeLibrary: \(error)") }

func pipeline(_ name: String) -> MTLComputePipelineState {
    guard let fn = lib.makeFunction(name: name) else { die("missing kernel \(name)") }
    do { return try device.makeComputePipelineState(function: fn) } catch { die("pipeline \(name): \(error)") }
}
let psoF32 = pipeline("debayer_f32")
let psoF16 = pipeline("debayer_f16")

func encode(_ enc: MTLComputeCommandEncoder, _ pso: MTLComputePipelineState,
            _ inBuf: MTLBuffer, _ outBuf: MTLBuffer, h: Int, w: Int) {
    enc.setComputePipelineState(pso)
    enc.setBuffer(inBuf, offset: 0, index: 0)
    enc.setBuffer(outBuf, offset: 0, index: 1)
    var dims = SIMD2<Int32>(Int32(h), Int32(w))
    enc.setBytes(&dims, length: MemoryLayout<SIMD2<Int32>>.size, index: 2)
    enc.dispatchThreadgroups(MTLSize(width: (w + 7) / 8, height: (h + 7) / 8, depth: 1),
                             threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
}

func run(_ pso: MTLComputePipelineState, mosaic: [Float], h: Int, w: Int) -> [Float] {
    guard let inBuf = device.makeBuffer(bytes: mosaic, length: 4 * h * w, options: .storageModeShared),
          let outBuf = device.makeBuffer(length: 4 * h * w * 3, options: .storageModeShared),
          let cb = queue.makeCommandBuffer(),
          let enc = cb.makeComputeCommandEncoder() else { die("alloc/encode failure") }
    encode(enc, pso, inBuf, outBuf, h: h, w: w)
    enc.endEncoding()
    cb.commit()
    cb.waitUntilCompleted()
    if let err = cb.error { die("command buffer: \(err)") }
    let p = outBuf.contents().bindMemory(to: Float.self, capacity: h * w * 3)
    return Array(UnsafeBufferPointer(start: p, count: h * w * 3))
}

// ---- parity ----
func errStats(_ a: [Float], _ b: [Float]) -> (maxAbs: Float, meanAbs: Float) {
    var mx: Float = 0, sum: Double = 0
    for i in 0..<a.count {
        let e = abs(a[i] - b[i])
        mx = max(mx, e)
        sum += Double(e)
    }
    return (mx, Float(sum / Double(a.count)))
}

print("device: \(device.name)")
print("")
var overall: [String: (Float, Double, Int)] = [:]
for (label, pso) in [("FP32", psoF32), ("FP16", psoF16)] {
    print("\(label)-weight kernel vs golden FP32 outputs:")
    var mx: Float = 0, sum: Double = 0, n = 0
    for c in cases {
        let out = run(pso, mosaic: c.mosaic, h: c.h, w: c.w)
        let (m, mean) = errStats(out, c.output)
        print(String(format: "  %-15s max-abs %.3e  mean-abs %.3e", (c.name as NSString).utf8String!, m, mean))
        mx = max(mx, m)
        sum += Double(mean) * Double(out.count)
        n += out.count
    }
    print(String(format: "  %-15s max-abs %.3e  mean-abs %.3e", ("OVERALL" as NSString).utf8String!, mx, Float(sum / Double(n))))
    overall[label] = (mx, sum / Double(n), n)
    print("")
}

let gate: Float = 2e-3
let fp32Max = overall["FP32"]!.0
let pass = fp32Max <= gate
print(String(format: "PARITY GATE (FP32 kernel, max-abs <= %.0e): %@  (max-abs = %.3e)",
             gate, pass ? "PASS" : "FAIL", fp32Max))
print("")

// ---- timing: 256x256 mosaic ----
let TH = 256, TW = 256
var seed: UInt64 = 0x1234_5678_9ABC_DEF0
var timingMosaic = [Float](repeating: 0, count: TH * TW)
for i in 0..<timingMosaic.count {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    timingMosaic[i] = Float((seed >> 40) & 0xFF_FFFF) / Float(0xFF_FFFF)
}

func timeKernel(_ pso: MTLComputePipelineState, iters: Int) -> Double {
    guard let inBuf = device.makeBuffer(bytes: timingMosaic, length: 4 * TH * TW, options: .storageModeShared),
          let outBuf = device.makeBuffer(length: 4 * TH * TW * 3, options: .storageModeShared) else { die("alloc") }
    // warmup
    for _ in 0..<3 {
        guard let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { die("encode") }
        encode(enc, pso, inBuf, outBuf, h: TH, w: TW)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }
    guard let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { die("encode") }
    for _ in 0..<iters { encode(enc, pso, inBuf, outBuf, h: TH, w: TW) }
    enc.endEncoding()
    cb.commit()
    cb.waitUntilCompleted()
    return (cb.gpuEndTime - cb.gpuStartTime) / Double(iters)
}

for (label, pso) in [("FP32", psoF32), ("FP16", psoF16)] {
    let t = timeKernel(pso, iters: 200)
    print(String(format: "TIMING 256x256 (%@ kernel, GPU time, avg of 200 dispatches): %.1f us  (%.2f ms)",
                 label, t * 1e6, t * 1e3))
}

exit(pass ? 0 : 1)

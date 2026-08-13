# THE CAPTURE FUNNELS — where WATCHING destroys information

Measured 2026-08-13 (code audit + Apple documentation sweep). Companion to
[ATLAS.md](ATLAS.md) §3 movements ⓪–②, and the evidence base for
`spec/output/RateLadder.hs` step S2.

**Thesis under test (Daniel):** *WATCHING is compression. If we compress at capture
rate we can process later with more compute.*

**Verdict:** WATCHING is not compressing. It is decimating — three times, in
cascade, with no prefilter at any stage. Two of the three cascades are invisible
in the source. Nothing downstream can recover any of it.

---

## 1. The chain, end to end

| # | where | in | out | ratio | filtered? |
|---|---|---|---|---|---|
| 0 | sensor → ISP | 24 MP square, 10–14 b/ch linear | binned 18 MP, 8 b/ch gamma | ~1.3:1 + bit depth | yes (ISP) |
| **1** | **AVFoundation `.photo` preview downscale** | **format dims (up to 4032²)** | **≈ screen-sized (~1000×750)** | **≈ 16–24 : 1** | **UNKNOWN** |
| **2** | **`rgbCrop = 768` centered square** | delivered buffer | 589,824 px | **see §3** | n/a (crop) |
| **3** | **`downsampleRGB` point sample** | 589,824 px | 4,096 px | **144 : 1** | **NO** |
| 4 | γ-staging + second sRGB8 round trip | 24 b/px | 24 b/px | 1:1 | — |
| 5 | VQ to palette index | 24 b + role | 8 b | 2.53:1 | — |
| 6 | σ-side chaos blur + 32-level prefix | 64-px group | ~4 b | ~128:1 | intended |

Depth runs the same shape: crop 256², then **16:1 point sample**
(`Quantize.metal:213-216`).

**From the largest square video format the 17-line front camera appears to offer
(4032² = 16.3 MP) down to the 4,096 pixels the solver sees is about 4,000 : 1 —
and roughly 99.6 % of it is taken by two steps that have no perceptual model, no
rate-distortion argument, and no measurement behind them.**

---

## 2. Funnel 1 — the one nobody knew was there

`CameraManager.swift:283` sets `sessionPreset = .photo`.

Apple Media Engineering, [forum 60453](https://developer.apple.com/forums/thread/60453):

> "The `AVCaptureSessionPresetPhoto` preset is a **special case** with respect to
> video data output. **It always provides preview sized buffers to video data
> output. Always has.**"

Measured in that thread: `activeFormat` 3264×2448, delegate buffer **1000×750**.
Corroborated by the iOS 16 reference docs for
[`automaticallyConfiguresOutputBufferDimensions`](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/automaticallyconfiguresoutputbufferdimensions)
(default `true`) and
[`deliversPreviewSizedOutputBuffers`](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/deliverspreviewsizedoutputbuffers):
"the output is free to scale the buffers … to a size suitable for preview
(approximately the size of the screen)."

**The app never takes a photo.** `AVCapturePhotoOutput` appears once, at
`CameraManager.swift:392`, as a throwaway DEBUG `probe` for the FRONT-RAW check.
The session has a video data output and a depth data output and nothing else.
So the `.photo` preset buys the app nothing and costs it the entire sensor.

Consequences, in order of severity:

1. **An unknown scaler sits in front of everything.** Whether AVFoundation's
   preview downscale is box-filtered, bilinear, or nearest is undocumented. If it
   is not band-limited, the app is decimating an already-aliased buffer — the
   worst case, because the second decimation folds the first one's aliasing again.
2. **The 768 crop may not fit.** `MetalPipeline.swift:438-448` clamps
   `cropX/cropY` with `max(0, …)` but always spans `cropSize`. On a ~750-tall
   buffer the kernel reads 768 rows from 750 — Metal `texture.read` past the edge
   returns zero, so up to 18 rows of **black are baked into every frame of the
   cube**, and the crop is no longer centered.
3. **`.photo` cannot be combined with `activeFormat`.** Setting `activeFormat`
   flips the session to `.inputPriority`
   ([doc](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat)),
   so choosing a real format and keeping `.photo` are mutually exclusive. Today
   the app has chosen `.photo`, i.e. has chosen not to choose a format.

**There is no runtime dimension check anywhere in the app.** `CameraConfig.rgbCrop`
is a constant; `spec/output/FrameGeometry.hs:173-176` tabulates iPhone 12–15 and
16 Pro and has **no row for the 17 line's square sensor**. Under
[[feedback_no_crop_changes]] the crop cannot move until the real delivered
dimensions are read on device — which is exactly the measurement that has never
been taken.

---

## 3. Funnel 2 — the crop, magnitude unknown until §2 is measured

`rgbCrop = 768`, `depthCrop = 256`, `scaleFactor = 3` pinned by
`spec/output/FrameGeometry.hs:105` (axiom G3).

- If delivery is the spec's assumed 1080×1920: the crop keeps **28.4 %** of the
  field of view. 71.6 % discarded.
- If delivery is `.photo`-preview ~1000×750: the crop keeps ~77 % of width and
  overruns the height. FOV loss is small; the black-band bug is real.

**Both readings cannot be true.** Which one holds is the single most important
unmeasured fact about this app, and it decides whether funnel 2 is a catastrophe
or a non-issue.

The FACE path already resolves this correctly: `FaceCaptureManager.swift:290`
takes `let side = min(w, h)` — the largest centered square, whatever the device
delivers — discarding only a `side mod 64` border ring.

---

## 4. Funnel 3 — the point sample

`Quantize.metal:186-201`, complete kernel body:

```metal
uint srcX = params.cropX + gid.y * params.step + params.halfStep;
uint srcY = params.cropY + (params.outputSize - 1 - gid.x) * params.step + params.halfStep;
float4 color = srcTexture.read(uint2(srcX, srcY));
dstTexture.write(color, gid);
```

One `read` at the block centre. No loop, no accumulator, no mip, no sampler —
`access::read` cannot filter. **143 of every 144 pixels are never read.** The CPU
fallback (`CameraManager.swift:519-530`) applies the same law, as does depth at
16:1.

This is worse than lossy. Decimation without a prefilter folds high-frequency
energy into the 64² grid as **aliasing — fabricated detail the scene never
contained** — which then flows into:

- the two-Gaussian depth mixture (`SPLITTING`),
- the covariance and PCA that generate every palette (`SIGHTING`),
- the Birkhoff complexity term,
- the rate ledger's K̂.

The pipeline measures its own aliasing and reports it as scene complexity.

**The FACE twin does not have this problem.** `FaceCaptureManager.swift:305-331`
box-averages luma over the full step×step block with a matching 4:2:0 chroma pool.
**Your two capture modes disagree about both funnels, and the secondary one is
correct.**

---

## 5. What "compression" has to mean here

A funnel should either be a **mean** or not exist.

| | operator | what the 4,096 outputs are | mean preserved | aliasing |
|---|---|---|---|---|
| today | decimate | 4,096 arbitrary samples | no | injected |
| proposed | κ (box pool) | the exact mean of all 589,824 | **yes** | none |

κ is the same operator as the octave direction in [ATLAS.md](ATLAS.md) §7 — the
2×2×2 ↔ 1 contract — applied at acquisition instead of at telemetry. Same
bandwidth, same output count, same 50 ms budget. It changes a *discard* into a
*summary*.

And once the grid is a true mean, `spec/output/RateLadder.hs` RL3 becomes usable:
the eight polyphase offsets provably tile the torus, and
`docs/rate-ladder-redesign.md` records that **the 8-phase orbit equals the [1,2,1]³
tent at box cost** (TL10–12, already proved). Rotating the phase per frame makes
the 64-frame *sequence* carry the residual the single-phase mean drops — at zero
extra per-frame bandwidth. That is compression at capture rate whose detail is
recoverable later, which is the ask.

---

## 6. Ranked findings

### Tier 0 — pure wins, no look change

| what | why | anchor |
|---|---|---|
| `videoSettings = [:]` instead of BGRA | Apple: *"Avoid defaulting to a BGRA format… requires approximately **2.6× more memory**"* ([TN3121](https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput)). −62.5 % bandwidth and one conversion pass removed, identical pixels. | `CameraManager.swift:322` |
| retype `CapturedFrame` | fp32 tuples hold values that are exactly k/255. Cube is **4.20 MB storing 1.31 MB** of information — 3.2× inflation. | `CapturedFrame.swift:11-24` |
| log delivered dimensions | there is no dimension check anywhere; every crop constant is unverified on the target hardware | `CameraManager.swift:420` |

### Tier 1 — the actual compression fixes

| what | why |
|---|---|
| **drop `.photo`, select `activeFormat`** | the app takes no photos; `.photo` force-downscales the video output to preview size. Prefer a **binned** square format (`format.isVideoBinned`) — sensor-domain binning is a *true average*, i.e. κ done in analog, for free, with better SNR. |
| **box prefilter the downsample kernels** | already ruled as step **S2** in `docs/rate-ladder-redesign.md:82-89`, "look changes → device ruling required". Turns funnel 3 from discard into κ. |
| **crop with `min(w, h)`** | copy FACE. ⚠ blocked by [[feedback_no_crop_changes]] until delivered dims are read on device. |

### Tier 2 — retain more for the later pass

| what | cost |
|---|---|
| keep a 256² intermediate beside the 64² | ≈12.6 MB for 64 frames at 8-bit — *less* than the 4.20 MB → 1.31 MB retyping saves plus current usage. The solve can then pool with κ to any rung. |
| polyphase phase-per-frame (RL3) | zero extra bandwidth; residual recoverable later |
| full 768² crop retained | 116 MiB at 8-bit + fp16, **448 MiB at current typing** — jetsam territory |

### Tier 3 — ISP levers that matter *because this pipeline is statistical*

`isGlobalToneMappingEnabled` is the important one. Apple: *"Normally the active
camera uses adaptive, **local** tone curves… If set to its default value of false,
the framework may apply **different tone maps to different pixels**."* The entire
DYAD solver is statistics over the frame — centroid, 3×3 covariance, PCA, the
two-Gaussian mixture. A per-pixel nonlinearity corrupts precisely those moments.
Gated by `format.isGlobalToneMappingSupported`; **resets to false whenever
activeFormat, session membership, or preset changes — set it last.**

Also available: 10-bit `'x420'` formats on the front camera (12→10 instead of
12→8 at funnel 0), `activeColorSpace = .sRGB` pinned,
`automaticallyAdjustsVideoHDREnabled = false` then `isVideoHDREnabled = false`,
`photoQualityPrioritization = .speed`, stabilization off.

There is **no API** to disable demosaic, lens shading, per-pixel noise reduction,
or the tone curve on the video path. That is the floor.

### Tier 4 — depth

| finding | detail |
|---|---|
| `isFilteringEnabled = true` fabricates pixels | filtering does temporal interpolation **plus spatial smoothing plus RGB-guided hole fill** (WWDC18-503 + `AVDepthData.h`; the reference doc understates it as temporal only). Apple: *"alters the data such that it may no longer be suitable for computer vision tasks. (In an unfiltered depth map, missing values are represented as **NaN**.)"* |
| the fill sentinel collides with real data | `DepthSignal.swift:24` `fill = 0.5` solves to **0.4286 m** — inside the face band. An invalid pixel is bit-identical to a genuine 43 cm reading, and `CapturedFrame` carries no validity mask. Turning filtering **off** would give NaN as a free, exact validity channel. |
| range clamp | `dNear = 0.25`, `dFar = 1.5`: everything past 1.5 m collapses to exactly 0; the 1.0–1.5 m band gets s ∈ [0, 0.1] |
| whole-frame depth drop → flat wall | `MetalPipeline.swift:290-293` fills 4,096 × 0.5; the frame enters the cube as a wall at 43 cm |
| TrueDepth defaults to **disparity** | Apple: *"The TrueDepth camera produces disparity maps by default… To capture depth instead of disparity, set the `activeDepthDataFormat`."* The code does filter for `DepthFloat16` (`CameraManager.swift:341`) and converts at `:834`, so this is handled — but the nil branch is silent. |
| depth rate is a *fraction* of video | *"You can't set the frame rate of depth data directly"* — it follows `activeVideoMin/MaxFrameDuration`, or lower. TrueDepth native is 640×480 (WWDC18-503); a logged format shows 640×360 @ 2–30 fps, so 20 fps is legal. |

### Tier 5 — Center Stage, resolved

> "**The system deactivates Center Stage** … when you enable depth data delivery
> on a capture output, such as `AVCaptureDepthDataOutput`."
> — [`isCenterStageActive`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/iscenterstageactive)

The app already uses `AVCaptureDepthDataOutput`, so **Center Stage is already off**
and never crops our frames. The gate at `CameraManager.swift:292` remains correct
as a *hardware predicate*. Note `centerStageControlMode` and `isCenterStageEnabled`
are **class** properties, not instance ones.

---

## 7. The pivotal unknown

**Can depth delivery and the square ultra-wide stream coexist?**
`.builtInTrueDepthCamera` and front `.builtInUltraWideCamera` are distinct device
types. Smart framing and `dynamicAspectRatio` (`.ratio1x1`) explicitly require the
ultra-wide (WWDC26 341); depth requires the TrueDepth device. **No document
answers this.** If they cannot coexist, the square-sensor 1:1 route is closed to
LIVE and the answer is a binned square *format* on the TrueDepth device instead.

---

## 8. Device probe — the gate on everything above

Nothing in §6 should be written before this runs on a 17 Pro. It is read-only.

1. Dump every front format: dimensions, `supportedMaxPhotoDimensions`,
   `supportedDynamicAspectRatios`, `supportedDepthDataFormats`,
   `videoSupportedFrameRateRanges`, `supportedColorSpaces`, **`isVideoBinned`**,
   `isGlobalToneMappingSupported`.
2. **Log the actual delegate buffer dimensions under `.photo`** — settles §2 and §3.
3. Read `isCenterStageEnabled` / `centerStageControlMode` at cold start (defaults
   undocumented).
4. Log `depthData.depthDataType` and `depthDataAccuracy` per frame; assert
   `.absolute`.
5. Test whether `AVCaptureDepthDataOutput` can be added to a session whose input is
   the front `.builtInUltraWideCamera` (§7).
6. Log `captureOutput(_:didDrop:from:)` reasons — rising `.outOfBuffers` means the
   50 ms budget is already over-subscribed.

## 9. On the 50 ms budget

The comment at `CameraManager.swift:467` — *"store raw data ONLY, no heavy analysis
during capture"* — is true of the export path and **false of the preview path**.
While recording, each 50 ms frame runs a full DYAD assignment at 20 Hz and, every
fourth frame, a complete table solve inline (mixture fits, 4,096 OKLab conversions
with cube roots, aerial staging, a second stats pass, the pair tree) — plus **two
blocking `waitUntilCompleted` GPU syncs per frame**.

So the capture-rate compute budget is not idle. It is spent on preview. Any plan to
compress more at capture rate has to buy that time back first — which is another
argument for κ: a box pool is a handful of texture reads, whereas the preview solve
it would compete with is already the expensive thing in the loop.

**Incidental:** `PerfectQuantizer` runs over all 64 frames after capture and its
indices never reach the GIF (`GIFMachine.swift:244` re-solves from `rawRGB`). They
survive only into `TriScaleLadder` and `Dissonance` — so the octave ladder and the
urgency field both describe **a cube the app does not ship**. Fixing that is a
prerequisite for promoting RUNGING to a control signal (ATLAS §7 step 2).

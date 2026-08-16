# MVP READINESS

Assessment date 2026-08-16. Written against HEAD 4073512, verified by
building (`xcodebuild build-for-testing`, iPhone 17 Pro simulator, exit 0)
and by reading the files cited. Four independent assessors covered store
compliance, vision fidelity, runtime stability and device evidence; a
skeptic pass filtered their claims; this document is the reconciliation.

Every claim below carries a file:line. Claims that could not be settled off
hardware are marked as such rather than assumed.

## 1. THE ANSWER

**The binary is closer to submittable than the repo's own gap lists suggest,
and the evidence behind it is further from settled than any test suite
admits.** Nothing about the app's structure, plist, privacy manifest, icon,
permission handling or crash surface is standing between this and App Store
Connect: what stands between it is account setup you have not done, two prose
documents that describe a different app than the one that ships, about 110
lines of AVFoundation lifecycle handling that was never written, and one
15-minute device session that has never happened. The single largest risk is
not any of the six ship blockers below: it is that four binary questions about
the capture geometry (D1 to D4) have never been asked of a physical iPhone,
and a wrong answer to D1 means the app refuses 100% of its target hardware
while every test in the tree stays green.

## 2. THE CRITICAL PATH

Ordered by what unblocks the most other work, not by severity. Steps 1 and 2
are independent of each other and can run in parallel.

### 1. Run one device session on a 17-line iPhone (Release build)

**Unblocks:** D1, D2, D3, D4, the entire performance question, and the
`no_crop_changes` decree that currently forbids touching the crop constants.
Nothing downstream of the capture path can be called correct until this runs,
and the fixes for D2/D3/D4 are cheap only if you know which way they go.

**Files that change:** none, initially. The instrumentation is already
compiled in and logs without a debugger attached: `Sense/CameraManager.swift:700`
(the C4 registration verdict, MATCH/MISMATCH in words), `:507` (delivered RGB
dims, depth presence, rolling avgFPS every 20 frames), `:453` (the front-RAW
probe). Launch with Console open and read three lines.

**Size:** 15 minutes of device time. See section 6 for the checklist.

### 2. Set up the distribution signing path (account work, not code)

**Unblocks:** every subsequent submission attempt. Today there is no path from
this repo to an `.ipa` that App Store Connect will accept, so no amount of code
work gets closer to a submission until this is done. It also forces the
bundle-identifier decision (`com.tesseract.app`, which you do not own the
namespace for) permanently, so it must happen before the App ID is registered,
not after.

**Files that change:** `project.yml` only, one line (`CODE_SIGN_STYLE: Automatic`
under the target's `settings.base`, so xcodegen stops emitting the legacy
`CODE_SIGN_IDENTITY = "iPhone Developer"` pin that `Tesseract.xcodeproj/project.pbxproj:1059`
currently carries into the Release config used for archive). Everything else is
Apple Developer / ASC account state.

**Size:** an afternoon, most of it waiting on Apple.

### 3. Rewrite `docs/app-review-notes.md` and fix the 256x256 figure

**Unblocks:** the submission itself. This is the cheapest blocker on the list
and the most likely to cost a full review cycle if left. It does not depend on
step 1 or step 2.

**Files that change:** `docs/app-review-notes.md` (lines 13 to 19 and 38 to 40),
`docs/privacy-policy.md` (lines 5 to 6). The correct reasoning is already
written at `CLAUDE.md:24-49` and can be lifted verbatim.

**Size:** under an hour.

### 4. Host the privacy policy at a public URL

**Unblocks:** the ASC App Information form, which cannot be completed without a
fetchable URL. Do it after step 3 so the hosted copy carries the corrected
output figure.

**Files that change:** none in the app. GitHub Pages on this repo, or any
static host.

**Size:** under an hour.

### 5. Close the two AVFoundation lifecycle holes (R1 and R2)

**Unblocks:** nothing else, but these are the two ways a reviewer reaches a
dead screen with no button, which is the most common rejection shape there is.
Both refusal branches already exist in `EditMachine` and already render; only
the constructors are missing.

**Files that change:** `Tesseract/Sense/CameraManager.swift` (notification
observers near `configureAndStart` at :320, a capture watchdog armed in
`startRecording` at :301, one new message constant beside `noCenterStageMessage`
at :263), `Tesseract/Sense/FaceCaptureManager.swift` (the watchdog twin near
:167), `Tesseract/Surface/EditMachine.swift:348-356` (parse the new messages).

**Size:** roughly 110 lines across three files.

### 6. Cap the cube store and page the shelf (V3)

**Unblocks:** nothing, but it is the one defect that compounds with use, and
the fix is small enough that leaving it is not a saving.

**Files that change:** `Tesseract/Surface/Scenes/LibraryView.swift:65`
(`prefix(9)` becomes a page index over the full list), `Tesseract/Store/CubeStore.swift`
(a retention cap enforced on `save` at :126, plus `isExcludedFromBackup` on the
directory created at :53), optionally `Tesseract/Surface/Scenes/SettingsView.swift:96-108`
(a purge action beside the storage readout that already computes held/each/moments).

**Size:** roughly 60 lines across three files.

### 7. Apply whatever step 1 returned

**Files that change:** depends entirely on the device answers. Worst case
(D2 reads MISMATCH) the crop constants move together in
`Tesseract/Sense/CameraManager.swift:82-84`, `Tesseract/Signal/FrameGeometry.swift:41-43`
and the assumed sensor rows in `spec/output/FrameGeometry.hs:277-278`. Best
case (all four MATCH) nothing changes and the numbers get recorded.

**Size:** between zero and a week.

## 3. SHIP BLOCKERS

Six established blockers, each verified in a file. Four further device-gated
unknowns follow in section 6; they are not listed here because a blocker you
cannot see is not a blocker you can fix.

### SB1. There is no distribution signing path at all

`security find-identity -v -p codesigning` returns exactly one identity,
"Apple Development: Daniel Mosquera (QFTX3897B7)". There is no Apple
Distribution certificate on this machine. Both profiles in
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/` decode to
development profiles carrying `get-task-allow => true`, and neither is for
`com.tesseract.app` (one is the wildcard `9WANULVN2G.*`, one is
`9WANULVN2G.com.danielpavia.tenuki`). `xcodebuild -exportArchive` with method
`app-store-connect` fails with "No Accounts" and "No profiles for
'com.tesseract.app' were found". `project.yml:32-34` states the design intent
that made this invisible: "the cached wildcard profile (9WANULVN2G.*) on this
machine signs device builds offline; no Xcode account needed", which is true
for device builds and false for distribution.

**What Apple hits:** App Store Connect rejects any upload whose entitlements
contain `get-task-allow`. This is a hard validation failure before a human ever
sees the app. Note also that the one signing certificate expires 2026-09-20.

### SB2. The App Review notes describe a gate the app no longer has, and state the output size wrong

`docs/app-review-notes.md:13-19` says the hardware requirement is "an iPhone
with a Face ID (TrueDepth) front camera" and that unsupported devices show a
"NO TRUEDEPTH" screen. The shipped gate is much tighter and says something
else: `Tesseract/Sense/CameraManager.swift:355` and
`Tesseract/Sense/FaceCaptureManager.swift:129` both require a front-position
`.builtInUltraWideCamera`, which no iPhone before the 17 line has, and
`Tesseract/Surface/EditMachine.swift:121` renders "NO CENTER STAGE" as a
TERMINAL refusal (`:172-173` gives it `recovery == .none`, `:438-440` gives it
no successors, `Tesseract/Surface/App/ContentView.swift:316-317` renders it with
no retry button). `CLAUDE.md:44-49` explicitly requires the notes to say this
and they were never updated.

Separately, `docs/app-review-notes.md:9-10` and `docs/privacy-policy.md:5-6`
both describe the output as a "256 x 256" GIF. `Tesseract/Sense/CameraManager.swift:88`
pins `CubeMode.training`, so `outputSize` and `totalFrames` are both 64: the
artifact is 64x64x64 with 256-ENTRY per-frame palettes.

**What Apple hits:** a reviewer on any iPhone 11 through 16 reads the notes,
concludes their Face ID phone qualifies, grants camera permission (requested at
`CameraManager.swift:282-297`, which runs BEFORE the Center Stage check at
:354), and lands on a dead-end screen with no button and no explanation in the
notes. That is Guideline 2.1 App Completeness. The wrong output figure
compounds it: reviewers cross-check notes against screenshots.

**Worth doing while you are there:** move the Center Stage check ahead of the
permission request in `CameraManager.start()` so an ineligible device is never
asked for the camera at all. Roughly 10 lines, and a better first contact.

### SB3. The privacy policy has no public URL

`docs/privacy-policy.md` exists and is 79 lines of accurate, submission-grade
text. Nothing hosts it: there is no Pages config, no CNAME, no URL anywhere in
the tree. `docs/app-review-notes.md:40` records the gap itself ("Privacy policy
URL: host docs/privacy-policy.md and link it here").

**What Apple hits:** the Privacy Policy URL is a mandatory field on the App
Information page. The submission form cannot be completed without a URL Apple
can fetch, and Apple spot-checks that it loads and describes this app.

### SB4. Nothing observes session interruption, so a session that starts but never delivers a frame is a permanent silent loading screen

`grep -rn 'NotificationCenter\|WasInterrupted\|RuntimeError\|scenePhase\|thermalState' --include='*.swift' Tesseract/`
returns **zero hits in Swift source**. `CameraManager.swift:328` sets
`state = .previewing` as soon as `session.startRunning()` returns, whether or
not a frame ever arrives; `previewImage` is only ever assigned inside
`processFrame` (`:537-544`). `EditMachine.swift:312` and `:335` both read
`case .previewing: return hasPreview ? .watching : .waking`, and
`ContentView.swift:134-135` supplies `hasPreview: camera.previewImage != nil`.
So "no frames" maps to `.waking` forever, against
`Tesseract/Surface/Scenes/IdleStateView.swift:4`, which states "This screen
should only be visible for the first few hundred ms."

The vocabulary to say what happened already exists and is unreachable:
`EditMachine.swift:98` declares `Refusal.interrupted(.cameraInUse/.backgrounded/.multipleApps/.overheated)`
with headlines at `:123-126`, explainers at `:147-153` and `recovery == .wait`
at `:176`, and `ContentView.swift:325-330` renders it. `grep -rn 'interrupted('`
outside `EditMachine.swift` returns zero constructors.

**What the user hits:** another client holding the capture device, a media
services reset, or a resume from background that does not auto-recover, and the
app shows the TESSERACT loading tile with a spinner indefinitely. No timeout,
no diagnostic, no recovery.

### SB5. WEAVING is a one-way street with no cancel and no timeout

`state = .recording(count)` is advanced only from inside a frame callback
(`CameraManager.swift:557`, `:670`, `FaceCaptureManager.swift:235`), and the
transition to `.processing` fires only when `count >= CameraConfig.totalFrames`
(`:559`, `:672`, `:237`). Once in WEAVING every exit is closed:
`EditMachine.swift:226-231` makes `.weaving` and `.solving` the only
non-`interruptible` states, `ContentView.swift:146` feeds that to
`modeSwitchAllowed` so the SET cover's CAMERA rows are disabled
(`SettingsView.swift:187`), `ContentView.swift:84` blocks ARRANGE the same way,
and the shutter is inert because `startRecording()` guards `state == .previewing`
(`CameraManager.swift:301`). There is no cancel control in `instrumentSurface`
(`ContentView.swift:221-239`).

As with SB4, the refusal is written and unreachable: `EditMachine.swift:107`
declares `captureIncomplete(kept:wanted:)` with the headline "SHORT WEAVE"
(`:128`), the explainer at `:155` and `recovery == .reshoot` at `:180`. The only
occurrence of that case being constructed anywhere is `EditMachine.swift:374`,
inside `erased(_:)`, which is a payload canonicaliser for the edge table and not
a runtime path.

**What the user hits:** tap record, something takes the camera, the counter
freezes at n/64 forever, and the only exit is force-quitting. That is a hang on
the app's primary action, one tap from the home surface.

### SB6. Every capture writes 1.75 MiB to Documents/ that nothing reads, with no cap, no backup exclusion, and no in-app reclaim past the newest 9

`CameraManager.swift:883` and `FaceCaptureManager.swift:440` call
`CubeStore.save(frames:forGIF:)` on every successful export.
`Tesseract/Store/CubeStore.swift:19-23` documents the cost as 1,835,024 B per
capture, and `TesseractTests/CaptureTensorTests.swift:186` proves that figure to
the byte. The only reader is `CubeStore.load(forGIF:)` at `CubeStore.swift:184`,
whose only caller is `Reweave.reweave(gifURL:)` at
`Tesseract/Edit/Reweave.swift:123`, which nothing calls (see section 5). There
is no eviction, cap or LRU anywhere in `CubeStore.swift`. The directory is
created under `.documentDirectory` (`CubeStore.swift:50-53`) and
`isExcludedFromBackup` appears nowhere in the repo, so it is iCloud-backed by
default. The only in-app delete is `GIFLibrary.delete` (`GIFLibrary.swift:53-56`,
which correctly removes the paired cube), reachable only by selecting a library
tile, and `Tesseract/Surface/Scenes/LibraryView.swift:65` does
`GIFLibrary.list().prefix(9)`. From the tenth capture onward, the GIF and its
1.75 MiB cube are permanently unselectable and permanently undeletable inside
the app.

**What the user hits:** 200 captures is roughly 350 MB of backed-up files they
cannot see, cannot reach and cannot delete except by deleting the app, paid for
a re-editing feature that does not exist. The SET cover already shows them the
bill (`SettingsView.swift:96-108`, "KEPT FOR RE-EDITING / HELD, EACH, MOMENTS")
with no way to act on it.

**Severity note:** one assessor filed this as a ship blocker and I have kept
that severity, but on narrower grounds than filed. Apple will not reject for it
and the app remains usable, so the "unusable" test does not carry it. It stays a
blocker because kept GIFs also live in the user's photo library, which means the
cube half is pure unreclaimable cost with no user-visible benefit whatsoever
until section 5 lands, and unbounded iCloud-backed growth is squarely against
the iOS Data Storage Guidelines. If you disagree, demote it and ship: it is the
one blocker on this list that is a judgment call.

## 4. WHAT IS ALREADY DONE

This is not a project with a long tail of unfinished plumbing. The following
were verified, not assumed, and several are in better shape than `CLAUDE.md`
claims.

**The build and the bundle.** `xcodebuild build-for-testing` on the iPhone 17
Pro simulator exits 0 clean, and `xcodebuild archive` succeeds. The generated
Info.plist is complete and correct: `com.tesseract.app`, 1.0.0/1, portrait only,
`UIDeviceFamily [1]`, `MinimumOSVersion 26.0`, both usage strings,
`ITSAppUsesNonExemptEncryption=false` (which skips the ASC export-compliance
prompt), `UILaunchScreen`, `CFBundleIconName`, and
`UIRequiredDeviceCapabilities = [arm64, front-facing-camera, iphone-performance-gaming-tier]`,
all three real published Apple values. Source is `project.yml:51-70`. Payload is
6.9 MB. Nothing ASC validation checks is missing.

**The privacy manifest verifies, independently of its own comment.**
`Tesseract/PrivacyInfo.xcprivacy:17-27` declares only
`NSPrivacyAccessedAPICategoryUserDefaults / CA92.1`. All four other
required-reason families were grepped separately: file timestamps
(creationDate/modificationDate/attributesOfItem/getattrlist/stat/fstat/lstat/
NSURLContentModificationDateKey), system boot time (systemUptime/
mach_absolute_time/clock_gettime), disk space (statfs/attributesOfFileSystem/
NSURLVolumeAvailableCapacity), active keyboard (activeInputModes/UITextInputMode).
Zero hits in each. The one near-miss, `CubeStore.swift:202`
`resourceValues(forKeys: [.fileSizeKey])`, is on neither list.
`GIFLibrary.swift:46` sorting by `lastPathComponent` rather than a file date is
exactly the choice that keeps this clean. The manifest ships as a resource
(`project.pbxproj:697`) and is present in the archived `.app`.

**No networking anywhere, so Guideline 1.2 does not apply.** URLSession,
NWConnection, CFStream and `http(s)://` return nothing across app Swift; there
is no SPM manifest and no embedded Frameworks directory in the archive. The only
outbound paths are the system share sheet (`Weave/GIFSaver.swift:42`) and saving
to the user's own photo library (`:21-30`). No feed, no comments, no accounts, no
user-to-user content. None of the report/block/EULA/moderation machinery that
XIII owes is owed here. Age rating should come out 4+. Say it plainly: this
dimension is finished.

**The permission story is complete on both managers.**
`CameraManager.swift:282-297` switches on authorization status and lands denied
and restricted on `cameraDeniedMessage`; `FaceCaptureManager.swift:121-124`
reuses it and `:527-542` maps `ARError.cameraUnauthorized` to it too.
`EditMachine.swift:348-356` maps that to `.cameraOff`, whose recovery is
`.openSettings` (`:176`), rendered as a real deep link by
`Surface/Scenes/ErrorStateView.swift:6-8`. A denied Photos add becomes an
"ALLOW" button rather than a useless RETRY (`ResultStateView.swift:70,117,126`).
There is no permission dead end.

**The crash surface is genuinely small.** Ten force-unwraps in about 17,600
lines, every one guarded or on static data: `DyadPipeline.swift:835,848` inside
an `if haveBg`; `DyadPipeline.swift:165-166` and `ResolutionGate.swift:62-63`
`.min()!`/`.max()!` on non-empty literals; `Arrangement.swift:66` keyed from
`allCases`; `DyadPalette.swift:61` on a seeded accumulator;
`SKGeneWeights.swift:141` a static blob never touched in Release. No `try!`, no
`as!`, no `fatalError` in app source. Every hot-loop subscript on capture and
export is shape-guarded first (`GIFEncoder.swift:36-39`,
`StrataDescent.swift:141-149`, `PhaseTelemetry.swift:154-170`,
`QuantizedImage.swift:27-28`, `GIFMachine.swift:273`).

**Concurrency is clean.** Exactly one `.sync` in the entire app
(`CameraManager.swift:313`, see the quality gaps), and no `DispatchQueue.main`
dispatches at all. Both export paths are `Task.detached(priority: .userInitiated)`
(`CameraManager.swift:794`, `FaceCaptureManager.swift:378`) with only
`await MainActor.run` for progress. Frame work runs on the synchronizer's
delegate queue and ARKit's. The two blocking `waitUntilCompleted` calls
(`MetalPipeline.swift:275,358`) are on the capture queue, never main.
`alwaysDiscardsLateVideoFrames = true` (`:386`) bounds the backlog.

**Memory is better than the docs say.** The tabulated export peak is roughly
35 to 40 MB above baseline, transient. `CLAUDE.md:760-762` still claims a 17 MB
transient OKLab cost; `unstagedLabsAll` was deleted in be4dbbf and the real Lab
peak is about 6.3 MB. The doc overstates it.

**The Center Stage gate is a hardware predicate, not a version string, and its
refusal is correctly terminal.** `CameraManager.swift:354-358` and
`FaceCaptureManager.swift:129-131` both test the device, not the model name.
`CameraManager.swift:341-342` opens with `beginConfiguration()` plus a
`defer { commitConfiguration() }` so the early return at :357 cannot poison a
later attempt, and the session is never started. This is exactly what the decree
asked for and it is well built. Its only problem is that nobody has confirmed
the predicate resolves on the hardware it targets (D1).

**The capture surface is real and complete, not a mock.** `ContentView.swift:105-109`
starts clock and camera at launch; `EditMachine.swift:300-319` is a total map
from CameraState to scene; `ContentView.swift:166-201` is a one-scene-per-state
switch with no default hole. All three preview rungs are published and drawn
(`CameraManager.swift:203-207`, written at `:540-542` and `:655-657`, mirrored at
`FaceCaptureManager.swift:80-84,219-221`, drawn at `WidgetSurfaceView.swift:240-258`).
Drag-to-move is quantized to cells and persisted with a reset escape hatch on a
static region (`WidgetSurfaceView.swift:207-231`, `ContentView.swift:88-95`), and
a corrupt stored arrangement cannot hide its own escape
(`Arrangement.swift:313`, `init?(serialised:)` length check plus `isLawful`).

**Every settings control changes output; nothing in the cover is decorative.**
BLEED reaches `DyadPipeline.process` (`GIFMachine.swift:274,297`) and the Metal
state (`MetalPipeline.swift:340`); MIRROR reaches the index-domain flip
(`GIFMachine.swift:317`); both are traced into the GIF comment
(`GIFMachine.swift:76`). CAMERA LIVE/FACE switches managers with a correct
synchronous TrueDepth ownership handoff and is refused mid-capture.

**The shelf does all four things asked.** 3x3 tiles with thumbnails decoded once
per reload (`LibraryView.swift:34-36,66-68`), replay with a correct reload on
selection change (`GIFPlayerView.swift:41-46`), share (`:145-152`), delete that
also removes the paired cube (`:154-169`, `GIFLibrary.swift:53-56`), and palette
plus provenance read back out of the file itself (`GIFLibrary.swift:60-81`). The
self-describing-GIF claim is real.

**The eFig edit axis works at the API level.** `EditDialTests` runs 8 tests, 0
failures. `Reweave.swift:113-115` threads `figureDepth: edit.fig` into
`GIFMachine.makeGIF` and on to `PairTree.solveFigures(stats:).truncated(toFigureDepth:)`
(`DyadPipeline.swift:675-683`). 9a92972's claim that the dial moves exported
bytes is true. The only thing missing is a caller.

**The three geometry ports agree with each other.** `spec/output/FrameGeometry.hs`
G11 to G13, `Signal/FrameGeometry.swift:83-101` and `Solve/Quantize.metal:241-242`,
gated by `MetalGeometryParityTests`, which paints each source texel with its own
coordinates in rgba32Float and checks all 4096 addresses exactly. That verifies
the address read rather than a colour, which means when the device finally
answers the rotation question, one edit answers it in all three places. This is
the correct architecture for an unsettled device question and it is worth saying
so.

**The claim register exists and is honest.** `docs/adversarial/CLAIM-REGISTER.md`
tallies PROVEN 28, UNGATED 9, DIVERGENT 7, VACUOUS 4, UNKNOWN 3 across 51 rows,
and lists the clean rows alongside the broken ones. Several DIVERGENT rows were
closed in the three commits since. A project that maintains this against itself
is not a project that needs to be told about self-confirming green.

## 5. THE VISION GAP

Kept separate on purpose. **None of what follows blocks a submission.** The app
that exists is a complete, coherent single-shot GIF camera and it will pass
review on its own terms. What follows is the distance between that app and the
2026-08-13 decree, which is large and is concentrated in exactly one place.

**"EDIT is the whole app" is not implemented. Not partially: not at all.**

* `Tesseract/Edit/Reweave.swift` has **zero callers in app source**. `grep -rn
  "Reweave" Tesseract --include="*.swift"` returns 4 hits: two inside
  `Reweave.swift` itself and two in comments (`Solve/PairTree.swift:67,92`).
  `makeGIF` has exactly two live callers, both on the capture path
  (`CameraManager.swift:864`, `FaceCaptureManager.swift:440`).
* `Tesseract/Surface/Widgets/DetentDial.swift` is 566 lines porting DD1 to DD10,
  heavily tested by `TesseractTests/DetentDialTests.swift`, and has **zero
  references outside its own file** except one doc comment at `Reweave.swift:86`.
  The widget vocabulary the surface can actually draw is closed at twelve entries
  and contains no dial (`Surface/Widgets/Arrangement.swift:45-61`).
* `EditMachine.Surface.editing(sealed:)` is **never constructed**. Its only
  occurrences are the two switch bodies that consume it
  (`EditMachine.swift:307,330`). TUNING is only ever entered from `.done`.
* The shelf is not home and cannot become one: `ContentView.swift:50` launches
  on `.capture` (documented candidly at `:40-49` as owed ruling R2), and
  `EditMachine.swift:397-398` declares the SHELF to TUNING edge that
  `LibraryView.swift` offers no control for. Select, SHARE, DELETE, DONE, and no
  EDIT.

The consequence, stated exactly: **one captured moment yields exactly one GIF,
which is 1 of the 32768 the spec enumerates** (`spec/quantization/RoleAllocation.hs:405`
pins `length editSpace == 32768`). Even the 8 points the working eFig axis can
execute are unreachable, because no surface constructs a `Reweave.Edit`. And the
1.75 MiB per capture written to enable re-editing (SB6) is the bill for a
feature with no caller.

This is also where the standing lesson lands hardest.
`TesseractTests/EditMachineTests.swift:142-153` (`testShelfIsHome`) and `:265-274`
(`testForkFreedom`) are green, and both quantify only over `EditMachine.swift`'s
own `successors` table. They certify a topology the surface does not implement,
and no test can catch that, because there is no UI test target in
`TesseractTests/`.

**Rough size to close it:** one new scene of roughly 150 to 250 lines
(`Tesseract/Surface/Scenes/EditStateView.swift`, hosting the dial and calling
`Reweave.reweave(cube:edit:)` on each detent crossing), about 30 lines of wiring
in `ContentView.swift` (hold an `edit` and an `editedGIF`, set
`surface = .editing(sealed:)` on solve completion), publishing the retained
cube's URL from `CameraManager` (it saves at :883 and never exposes it), and an
EDIT button in `LibraryView.swift` beside share at :145, gated on
`CubeStore.exists(forGIF:)` so it is absent rather than dead. One real decision
is embedded and is yours, not an implementer's: `DialLaw.roleSplit` has 12
detents (`DetentDial.swift:60,98-100`) where the eFig axis has 8, so either a
fifth `DialLaw` case derived from `PairTree.fullDepth`, or a ruling that eFig
rides `rungPick`.

**Two smaller vision gaps, both future work.** Three superseded scene files ship
in the binary with zero references and 246 lines between them
(`Surface/Scenes/LivePreviewStateView.swift`, `FacePreviewStateView.swift`,
`RecordingStateView.swift`; the second is explained as SUPERSEDED at
`ContentView.swift:218`). And `PhaseStripWidget` sits on the home surface in
three states permanently showing its no-evidence face, because nothing publishes
a `LiveComposition` (`WidgetSurfaceView.swift:255-256,399-421`). Refusing to
invent the number is correct under the no-naked-constants decree; a permanently
grey instrument on the primary surface still reads as a rendering bug to anyone
who cannot hear the VoiceOver label at `:424`.

**Quality gaps that ship but are worth an hour each.** Three preview builders
hand `CGContext` an inout pointer that Swift only guarantees for the duration of
the initialiser call, then call `makeImage()` on the next statement
(`CameraManager.swift:987,1002`, `FaceCaptureManager.swift:508`); this is
undefined behaviour on the 20 Hz preview path, and the codebase already carries
the correct pattern and the reasoning verbatim at `QuantizedImage.swift:38-49`.
`sessionQueue.sync` runs on the main actor from a user-facing SET tap
(`CameraManager.swift:313`, invoked from `ContentView.swift:120`). Opening the
shelf decodes nine thumbnails plus a multi-megabyte GIF plus 64 UIImages on the
main thread (`LibraryView.swift:64-80`, `GIFPlayerView.swift:64-77`), and both
cover bodies re-run a full-buffer scan (`GIFLibrary.mixtureLine`) or a directory
stat sweep (`CubeStore.totalBytes`) at 20 Hz because they read `clock.tick`
(`LibraryView.swift:102,121`, `SettingsView.swift:97,122`).

## 6. WHAT ONE DEVICE SESSION WOULD SETTLE

Everything below is unanswerable off hardware and every item is already
instrumented. `docs/session-2026-08-15-sunset.md:141-146` and `docs/ATLAS.md:336`
both state the position honestly: zero device evidence exists, for anything,
since 2026-08-11. Run this with a Release build on a 17-line iPhone, Console
attached, and read the log.

1. **D1, the Center Stage predicate.** Does the app get past WAKING at all? If
   `AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .front)`
   returns nil on an iPhone 17 (for instance because the camera is only vended
   through a `DiscoverySession`, or under a different deviceType), then every
   user on the only hardware the app supports sees NO CENTER STAGE and the app
   does nothing, with every test still green. This is a single Bool with no
   second path by design (`EditMachine.swift:172-173`, terminal, no retry).
   Repair if wrong: about 20 lines across `CameraManager.swift:354` and
   `FaceCaptureManager.swift:128`. Worth adding a DEBUG enumeration of
   `DiscoverySession(deviceTypes:.allCases, position:.front)` beside the
   front-RAW probe at `CameraManager.swift:453` before you go.

2. **D2, the registration ratio.** Read the MATCH/MISMATCH word the probe at
   `CameraManager.swift:700-712` already logs once per session.
   `CameraConfig.rgbCrop = 768`, `depthCrop = 256`, `scaleFactor = 3`
   (`CameraManager.swift:82-84`, restated at `Signal/FrameGeometry.swift:41-43`)
   have never been compared to a delivered buffer, and the repo's own research
   predicts they are wrong: `docs/CAPTURE-FUNNELS.md:41-49` quotes Apple that
   `sessionPreset = .photo` (set at `CameraManager.swift:345`) always hands
   video-data-output preview-sized buffers, which against the depth format
   selected at `:401-412` gives about 1.56, not 3. `spec/output/FrameGeometry.hs:277-278`
   quantifies G5/G6/G13 over two invented sensor rows that are 3:1 by
   construction, and its own header at :10 admits the dims are unknown. Two
   consequences if MISMATCH: the figure/ground role mask is computed over about
   half the picture it is applied to, silently, in every exported GIF; and
   `MetalPipeline.swift:439-448` clamps the crop origin but always spans 768
   while `Quantize.metal:241-244` reads to srcX 762 with no bounds check, so a
   ~750px buffer bakes zeroed rows into every frame. Note the `no_crop_changes`
   decree blocks any repair until this reading exists, so this session is the
   only thing standing in its way.

3. **D3, the quarter turn.** Is the preview rotated 90 degrees from the world?
   `spec/output/FrameGeometry.hs:243-249` states outright that no axiom and no
   simulator can decide the direction, and `MetalGeometryParityTests.swift:233-253`
   pins the shipped CCW direction as data rather than as truth. G11 guarantees no
   information is lost, so a wrong turn degrades nothing and errors nowhere: it
   just renders sideways forever. Repair if wrong: `spec/output/FrameGeometry.hs:186`,
   `Signal/FrameGeometry.swift:84`, `Solve/Quantize.metal:241-242` and `:256-257`,
   `CameraManager.swift:742-743`. Under an hour, and the parity test re-pins it.

4. **D4, LIVE against FACE.** Switch modes once and compare handedness. The two
   paths apply structurally different maps and nothing compares them: LIVE sets
   `isVideoMirrored = true` in hardware (`CameraManager.swift:421,428`) then
   applies the CCW map `(x,y) -> (y, n-1-x)`, while FACE does no hardware mirror,
   uses `srcX0 = offX + y*step; srcY0 = offY + x*step` (`FaceCaptureManager.swift:325-327`),
   which is the plain transpose with no flip, and mirrors the mesh separately in
   software at `:272`. `CLAUDE.md`'s Build section lists "first on-device FACE run
   (mirroring unverified)" as open. A selfie camera with the handedness wrong in
   one of its two modes is a rejection-grade defect and an obvious one.

5. **Performance, which has no measurement of any kind.** The watching surface
   does two blocking GPU round-trips per frame at 20 Hz
   (`MetalPipeline.swift:275,358`) plus a 5 Hz CPU solve (`DyadPipeline.swift:1140-1150`),
   and FACE is heavier still: `FaceCaptureManager.swift:203` runs the full CPU
   128-leaf assignment at 20 Hz, and the frame-drop guard its own comment
   describes at `:521-522` was never written (the line below calls `processFrame`
   unconditionally). `CameraManager.swift:507-512` already logs rolling avgFPS
   every 20 frames. Read it in both modes.

6. **Free while you are there:** confirm the app icon renders correctly on a
   17-line home screen, and confirm the terminal refusal copy reads well at
   device size.

## 7. WHAT THIS ASSESSMENT DOES NOT ESTABLISH

Stated in the register's own vocabulary, because the standing lesson applies to
this document as much as to anything it examined.

* **Nothing here was verified on hardware.** Every claim in sections 3, 4 and 5
  is a claim about source, a simulator build or an archive. Section 6 exists
  because that boundary is real. If D1 reads wrong, most of section 4 describes
  an app nobody can launch.
* **The test suite was not run in full.** I ran the build
  (`build-for-testing`, exit 0) and relied on the assessors' reported runs of
  `EditDialTests` (8 tests, 0 failures) and `DetentDialTests`. The rest of
  `TesseractTests/` and the Haskell spec suite were not executed in this pass.
  A green suite would not change any finding above, because every ship blocker
  is a thing no test covers.
* **Of the 51 claims in `docs/adversarial/CLAIM-REGISTER.md`, 23 are not
  PROVEN** (UNGATED 9, DIVERGENT 7, VACUOUS 4, UNKNOWN 3), and this assessment
  re-examined none of them. Three commits since (4073512, 9a92972, 6990404)
  closed several DIVERGENT rows; the tally line at the top of the register was
  not recomputed and should not be read as current.
* **Of the four assessors' filed items, one severity was changed here** (SB6,
  kept as a blocker but on narrower and explicitly contestable grounds), and
  four filed ship blockers were reclassified as device-gated unknowns rather
  than blockers (D1 to D4 in section 6), because a defect that may not exist is
  not a defect you can schedule. Two duplicate filings of the review-notes
  problem (APPLE-2 and V4) were merged into SB2.
* **Three claims in `CLAUDE.md` were found stale in passing** and were not
  systematically hunted: the UIRequiredDeviceCapabilities "simulator plists omit
  it by design" clause at `CLAUDE.md:41-43` is false (the key is present in both
  the simulator plist and the archive, and `project.yml:64` has no platform
  condition, so there was never a mechanism for it); the 17 MB transient OKLab
  figure at `:760-762` predates be4dbbf; and `docs/app-review-notes.md` describes
  a gate two rulings out of date. There may be more. This assessment did not
  audit `CLAUDE.md` against the tree.
* **App Store metadata was not examined**, because it does not live in this
  repo. The description text, screenshots, age rating, category and the "Requires
  iPhone 17, iPhone Air, or later" line that `CLAUDE.md:44-49` mandates are all
  ASC state and all unverified.
* **No accessibility, localisation or App Store screenshot review was
  performed.** VoiceOver labels exist in places (`WidgetSurfaceView.swift:424`)
  and the swift-port arc records accepted VoiceOver debt; none of it was
  assessed here.
* **The app was never launched.** Not on a device and not in the simulator.
  Every behavioural claim above (what a reviewer sees, where the app hangs) is
  derived from reading control flow, not from watching it happen.

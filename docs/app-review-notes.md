# App Review notes (paste into App Store Connect)

Draft for the "Notes" field of App Review Information. Keep it short;
reviewers read this before launching the app.

---

Tesseract is a single-purpose artistic camera. It records 64 frames
from the front TrueDepth camera and encodes them into a 256 x 256
palette-quantized GIF. All processing is on-device; the app contains
no networking code.

**Hardware requirement: an iPhone with a Face ID (TrueDepth) front
camera.** On devices without one (iPhone SE 2nd/3rd generation, or
iPad compatibility mode) the app intentionally shows a "NO TRUEDEPTH"
gate screen and does not proceed. This is stated in the App Store
description. There is no UIRequiredDeviceCapabilities value that
expresses TrueDepth, so the gate is the honest in-app expression of
the requirement.

The preview is intentionally a 64 x 64 pixel-quantized image; the
pixelated look is the product, not a rendering defect. The screenshots
show the same look.

FACE mode uses the ARKit face mesh only to shape dither cadence
(nose = 1, background = 0). It works with no face in frame: recording
and export still function, with a uniform diffuse cadence. Face data
is processed per frame in memory and never stored or transmitted
(see the privacy policy).

TrueDepth depth data (LIVE mode) similarly drives dither strength
only, per frame, in memory.

---

Also set in App Store Connect before submission:

- App description: include the line "Requires an iPhone with Face ID
  (TrueDepth front camera)."
- Privacy policy URL: host docs/privacy-policy.md and link it here.
- Privacy label: Data Not Collected.

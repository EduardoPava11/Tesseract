# App Review notes (paste into App Store Connect)

For the "Notes" field of App Review Information. Reviewers read this
before launching the app, so the hardware gate is stated first.

## Paste this

Tesseract is a single-purpose artistic camera. It records 64 frames
from the front camera and encodes them into a 256 x 256 palette
quantized GIF. All processing happens on device. The app contains no
networking code of any kind.

PLEASE REVIEW ON AN iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, or
iPhone Air.

HARDWARE REQUIREMENT, and the expected reviewer experience. The app
requires the 18MP square sensor Center Stage front camera, introduced
on the iPhone 17 line and iPhone Air. On any earlier iPhone, INCLUDING
the entire iPhone 16 line and iPhone 15 Pro, the app deliberately shows
a terminal screen reading NO CENTER STAGE and does not proceed. That is
designed behaviour under Guideline 2.4.1, not a crash, a hang, or an
incomplete build. There is no Retry button on that screen because the
condition cannot change on that device.

Why the requirement cannot be expressed in UIRequiredDeviceCapabilities:
Apple publishes no key for the Center Stage camera. The tightest key
that exists is iphone-performance-gaming-tier (A17 Pro and later), and
the app declares it, so iPhone 15 Pro and iPhone 16 users can still
install the app and will meet the gate screen. The in-app gate is
therefore the honest expression of the requirement, and the App Store
description states "Requires iPhone 17, iPhone Air, or later."

The gate is a hardware predicate rather than a model-name check: the
Center Stage front camera is the only front-position
.builtInUltraWideCamera Apple has shipped on iPhone (WWDC26 session
341, "Support the Center Stage front camera in your iOS app").

The preview and the exported GIF are intentionally coarse: a 64 x 64
image scaled to 256 x 256 by pixel replication. The blocky look is the
product, not a rendering defect, and the screenshots show the same
look.

FACE mode uses the ARKit face mesh only to shape dither cadence. It
works with no face in frame: recording and export still function, with
a uniform cadence. Face geometry is processed per frame in memory and
is never stored or transmitted.

Depth data from the front camera similarly drives dither strength only,
per frame, in memory.

## Also set in App Store Connect before submission

- Privacy policy URL. REQUIRED for every app whether or not it collects
  data; a blank field is rejected. Host docs/privacy-policy.md at a
  publicly fetchable URL and paste it here.
- App description: include "Requires iPhone 17, iPhone Air, or later."
- Privacy label: Data Not Collected.
- Age rating: 4+. The app has no networking, no user accounts, and no
  user-generated content shared between users, so Guideline 1.2 does
  not apply.
- Build must be compiled with the iOS 26 SDK or later, required for new
  submissions since 28 April 2026. This project targets iOS 26.0 and
  builds with Xcode 26.x, so it complies.

## Why this file was rewritten (2026-08-16)

The previous version described a TrueDepth gate and named "iPhone SE
2nd/3rd generation, or iPad compatibility mode" as the excluded
devices. That has been wrong since the 2026-08-12 Center Stage ruling.
The shipped gate excludes every iPhone before the 17 line, which is a
far larger set, and it includes the hardware a reviewer is most likely
to be holding.

A reviewer on an iPhone 16 would have hit a terminal refusal that the
review notes did not describe, with notes explaining a DIFFERENT
requirement that the app no longer enforces. That is the exact shape of
a Guideline 2.1 App Completeness rejection, which is the single largest
category of App Store rejections.

The 256 x 256 figure in this file and in the privacy policy is CORRECT
and was left alone: DyadGIFContractTests:67-68 asserts the exported GIF
is exactly 256 x 256 pixels.

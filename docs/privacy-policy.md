# Tesseract Privacy Policy

Effective date: August 9, 2026

Tesseract is a camera app that turns short front-camera captures into
256 x 256 pixel GIF animations. This policy describes exactly what the
app does with the camera, depth, and face data it touches. The short
version: everything happens on your iPhone, and nothing leaves it.

## What the app accesses

**Front camera video.** Tesseract uses the front TrueDepth camera to
show a live preview and to record the 64 frames that become your GIF.

**Depth data (LIVE mode).** The TrueDepth sensor's depth map is read in
real time. Depth values drive the dither strength and the temporal
cadence of the GIF. Depth maps are processed frame by frame in memory
and are not saved.

**Face mesh data (FACE mode).** ARKit face tracking provides a facial
mesh geometry. Tesseract reduces this mesh to a per-pixel nearness
signal (nose = 1, background = 0) that fills the same pipeline slot as
depth. The mesh is processed frame by frame in memory. It is never
stored, never used to identify you, and never used for any purpose
other than shaping the visual cadence of the GIF you are recording.

## Where processing happens

All processing is performed on your device. Tesseract contains no
networking code: it makes no network requests, embeds no analytics,
advertising, or tracking SDKs, and transmits nothing to us or to any
third party.

## What is stored

- **Your GIFs.** A finished GIF is kept only when you choose to save it
  to your photo library (add-only access) or share it with the system
  share sheet. The camera frames, depth maps, and face meshes used to
  build it are discarded after encoding.
- **Your settings.** Export preferences (look, bleed, mirror) are stored
  on the device in the app's own settings. They contain no personal
  data.

## What is collected

Nothing. Tesseract collects no personal data, no usage data, no
identifiers, and no face data. The App Store privacy label for
Tesseract is "Data Not Collected."

## Face data, in Apple's terms

Because Tesseract uses the TrueDepth camera and ARKit face tracking:
face data is used solely to drive the visual effect described above,
is processed only on the device and only for the duration of the
frame in which it appears, is never retained, and is never shared
with anyone.

## Permissions

- **Camera** is required to show the preview and record.
- **Photo library (add only)** is requested only when you choose to
  keep a GIF.

You can withdraw either permission at any time in Settings; the app
will continue to work to the extent the remaining permissions allow.

## Children

Tesseract does not collect data from anyone, including children.

## Changes

If a future version of Tesseract ever changes what data is accessed or
where it is processed, this policy will be updated before that version
ships, and the change will be described in the App Store release notes.

## Contact

Questions about this policy: maxypava@gmail.com

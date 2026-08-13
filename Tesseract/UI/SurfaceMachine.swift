// SurfaceMachine.swift
// Tesseract
//
// THE GRID IS A STATE MACHINE (Daniel's ruling, 2026-08-12): the
// app is a strict grid of squares; squares make words; the machine
// maps every app state to the ONE word it speaks and the ONE scene
// it surfaces — including after capture (SOLVING shows the palette
// being born; SEALED shows the verdict). Port of
// spec/ui/SurfaceMachine.hs (SM1–SM5 — the Haskell spec is
// authoritative). ContentView consults this machine instead of
// scattering the mapping across per-mode switches.

import Foundation

enum SurfaceMachine {

    enum Refusal: Equatable, Sendable {
        case cameraOff
        case noTrueDepth
        case noCenterStage
        case noFaceTracking
        case exportFailed
        case unknown(String)
    }

    enum State: Equatable, Sendable {
        case waking      // session configuring / first frame pending
        case watching    // live preview, shutter armed
        case weaving     // recording the 64-frame cube
        case solving     // after capture: mixture, tree, tables, encode
        case sealed      // GIF encoded + archived
        case refused(Refusal)

        /// THE word the grid speaks in squares (SM1: uppercase
        /// letters and spaces only — digits ride payload rows).
        var word: String {
            switch self {
            case .waking:                    return "WAKING"
            case .watching:                  return "WATCHING"
            case .weaving:                   return "WEAVING"
            case .solving:                   return "SOLVING"
            case .sealed:                    return "SEALED"
            case .refused(.cameraOff):       return "CAMERA OFF"
            case .refused(.noTrueDepth):     return "NO TRUEDEPTH"
            case .refused(.noCenterStage):   return "NO CENTER STAGE"
            case .refused(.noFaceTracking):  return "NO FACE TRACKING"
            case .refused(.exportFailed):    return "EXPORT FAILED"
            case .refused(.unknown):         return "ERROR"
            }
        }

        /// Settings/mode interruption law (SM3): work is sacred —
        /// exactly WEAVING and SOLVING refuse interruption.
        var interruptible: Bool {
            switch self {
            case .weaving, .solving: return false
            default: return true
            }
        }
    }

    /// The total map from the camera's state (SM1: every state
    /// surfaces). `hasPreview` is the graceful-arrival clause: a
    /// previewing session without a first frame still WAKES.
    static func state(for camera: CameraState, hasPreview: Bool) -> State {
        switch camera {
        case .idle:
            return .waking
        case .previewing:
            return hasPreview ? .watching : .waking
        case .recording:
            return .weaving
        case .processing:
            return .solving
        case .done:
            return .sealed
        case .error(let msg):
            return .refused(refusal(for: msg))
        }
    }

    /// FACE twin: FaceCaptureState mirrors CameraState case for
    /// case — ONE machine serves both capture systems.
    static func state(for face: FaceCaptureState, hasPreview: Bool) -> State {
        switch face {
        case .idle:
            return .waking
        case .previewing:
            return hasPreview ? .watching : .waking
        case .recording:
            return .weaving
        case .processing:
            return .solving
        case .done:
            return .sealed
        case .error(let msg):
            return .refused(refusal(for: msg))
        }
    }

    /// The two-register error voice, keyed off the managers' ruled
    /// message constants — the machine owns the headline words.
    static func refusal(for message: String) -> Refusal {
        switch message {
        case CameraManager.cameraDeniedMessage:               return .cameraOff
        case CameraManager.noTrueDepthMessage:                return .noTrueDepth
        case CameraManager.noCenterStageMessage:              return .noCenterStage
        case FaceCaptureManager.faceTrackingUnsupportedMessage: return .noFaceTracking
        case CameraManager.encodeFailedMessage:               return .exportFailed
        default:                                              return .unknown(message)
        }
    }

    /// The lawful edges (SM2/SM4): the capture arc WEAVING →
    /// SOLVING → SEALED admits no skips; WEAVING is re-entered only
    /// through WATCHING; hardware refusals are terminal.
    static func canStep(from: State, to: State) -> Bool {
        switch (from, to) {
        case (.waking, .watching),
             (.watching, .weaving),
             (.watching, .waking),
             (.weaving, .solving),
             (.solving, .sealed),
             (.sealed, .watching):
            return true
        case (.refused(.cameraOff), .waking),
             (.refused(.exportFailed), .watching),
             (.refused(.unknown), .waking):
            return true
        case (.waking, .refused(.cameraOff)),
             (.waking, .refused(.noTrueDepth)),
             (.waking, .refused(.noCenterStage)),
             (.waking, .refused(.noFaceTracking)):
            return true
        case (.solving, .refused(.exportFailed)):
            return true
        case (.waking, .refused(.unknown)),
             (.watching, .refused(.unknown)),
             (.weaving, .refused(.unknown)),
             (.solving, .refused(.unknown)):
            return true
        default:
            return false
        }
    }
}

// RAWCaptureManager.swift
// Tesseract
//
// Rear 48MP wide camera, Bayer RAW DNG burst. Structurally mirrors ROTAS's
// CameraManager (Sources/Camera/CameraManager.swift) — that one is known to
// work on iPhone 17 Pro + iOS 26. Adopted from there:
//
//   • not @MainActor; @unchecked Sendable + all session work on sessionQueue
//   • 48MP format dance: .photo preset → addInput/addOutput →
//     lockForConfiguration + activeFormat = 48MP format → .inputPriority →
//     enable ProRAW → set maxPhotoDimensions
//   • explicit teardown() that removes inputs/outputs (fixes double-configure)
//   • ≥200 ms delay between A and B (prevents err=-12710 ISP pipeline bail)
//
// The Tesseract-specific bits that are preserved:
//   • @Published state so SwiftUI can bind via ObservableObject
//   • Burst semantics with a user-configurable delta (clamped ≥200 ms)
//   • pendingDelegates dictionary keyed by AVCapturePhotoSettings.uniqueID
//   • RAWPhoto / RAWBurstPackage output shape (unchanged)

@preconcurrency import AVFoundation
import Combine
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "RAWCapture")

final class RAWCaptureManager: NSObject, ObservableObject, @unchecked Sendable {

    enum State: Equatable, Sendable {
        case idle
        case configuring
        case ready
        case capturing(label: String)
        case waitingDelta
        case packaging
        case done(RAWBurst)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    /// Inter-capture Delta t in milliseconds. Clamped to ≥200 at capture time
    /// because the 48MP ISP pipeline bails with err=-12710 below that.
    @Published var deltaMs: Double = 200

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tesseract.raw.session")
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?
    private var rawFormat: OSType?

    /// Preview layer owned by the manager. Mirrors ROTAS — survives session
    /// reconfigures because it's bound to the session, not to a transient view.
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        return layer
    }()

    // Retain delegates until their callbacks fire. Keyed by uniqueID so a
    // burst (two concurrent-ish captures) never loses a delegate.
    private var pendingDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private let delegatesLock = NSLock()

    // MARK: - Configure / start / stop

    func configure() {
        sessionQueue.async { [weak self] in
            self?.configureOnQueue()
        }
    }

    private func configureOnQueue() {
        // Re-entrancy guard. Read state on main — whatever; a single-word
        // enum read across threads is benign and the worst case is a
        // duplicate dispatch, which is no-op because the inner guard will
        // already have flipped state to .configuring.
        switch state {
        case .configuring, .ready, .capturing, .waitingDelta, .packaging, .done:
            return
        case .idle, .error:
            break
        }

        // Permission. Punt to a later re-entry if user hasn't been asked yet.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configure()
                } else {
                    self.setState(.error(RAWError.cameraPermissionDenied.localizedDescription))
                }
            }
            return
        case .denied, .restricted:
            setState(.error(RAWError.cameraPermissionDenied.localizedDescription))
            return
        @unknown default:
            setState(.error(RAWError.cameraPermissionDenied.localizedDescription))
            return
        }

        setState(.configuring)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            setState(.error(RAWError.noRearCamera.localizedDescription))
            return
        }
        self.currentDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                setState(.error(RAWError.cannotAddInput.localizedDescription))
                return
            }
            session.addInput(input)
        } catch {
            setState(.error(error.localizedDescription))
            return
        }

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            setState(.error(RAWError.cannotAddOutput.localizedDescription))
            return
        }
        session.addOutput(output)
        self.photoOutput = output

        // 48MP format dance — copied from ROTAS. Without this, .photo picks
        // a binned 4224×3024 format and availableRawPhotoPixelFormatTypes
        // can be empty for ProRAW-gated formats.
        //   1. addOutput first (above)
        //   2. pick a format whose supportedMaxPhotoDimensions includes 48MP
        //   3. lock device, assign activeFormat, unlock
        //   4. switch preset to .inputPriority (required after activeFormat)
        var selected48MP = false
        for format in device.formats {
            let dims = format.supportedMaxPhotoDimensions
            guard dims.contains(where: { $0.width >= 8064 && $0.height >= 6048 }) else { continue }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.unlockForConfiguration()
                session.sessionPreset = .inputPriority
                selected48MP = true
                logger.info("RAW: selected 48MP format")
                break
            } catch {
                logger.error("RAW: lockForConfiguration failed: \(error.localizedDescription)")
            }
        }
        if !selected48MP {
            logger.info("RAW: no 48MP format — using device default")
        }

        // Must be set AFTER format selection and BEFORE querying RAW formats.
        if output.isAppleProRAWSupported {
            output.isAppleProRAWEnabled = true
            logger.info("RAW: Apple ProRAW enabled")
        }

        if let largest = device.activeFormat.supportedMaxPhotoDimensions.last {
            output.maxPhotoDimensions = largest
        }

        let rawFormats = output.availableRawPhotoPixelFormatTypes
        guard let bayer = rawFormats.first else {
            setState(.error(RAWError.noRAWFormat.localizedDescription))
            return
        }
        self.rawFormat = bayer

        // Commit happens via defer, THEN we start running below.
        // Can't start inside the begin/commit scope.
        // Schedule the start as a follow-up on the same queue so it runs
        // after commitConfiguration has executed.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.setState(.ready)
        }
    }

    func retry() {
        teardown()
        // After teardown the state bounces to .idle (via main). Schedule
        // configure after that so the re-entrancy guard sees .idle.
        sessionQueue.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.configure()
            }
        }
    }

    // MARK: - Lifecycle

    /// Kept for compatibility — delegates to teardown() so re-entry is always
    /// a clean re-configure instead of trying to restart a stale session.
    func stop() {
        teardown()
    }

    /// Fully releases the camera: stops running, removes all inputs/outputs,
    /// drops device/output refs, resets state. Next configure() builds fresh.
    func teardown() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.photoOutput = nil
            self.currentDevice = nil
            self.rawFormat = nil
            self.setState(.idle)
        }
    }

    // MARK: - Burst

    func captureBurst() async {
        guard case .ready = state, let output = photoOutput, let raw = rawFormat else {
            logger.warning("RAW: captureBurst called but not ready")
            return
        }
        // Hard floor on the delta — 48MP ISP can't turn around faster.
        let clampedMs = max(200.0, deltaMs)

        do {
            let start = Date()
            setState(.capturing(label: "A"))
            let a = try await capturePhoto(label: "A", output: output, rawFormat: raw)

            setState(.waitingDelta)
            try await Task.sleep(nanoseconds: UInt64(clampedMs * 1_000_000))

            setState(.capturing(label: "B"))
            let b = try await capturePhoto(label: "B", output: output, rawFormat: raw)

            setState(.packaging)
            let burst = try RAWBurstPackage.assemble(
                a: a, b: b, deltaMs: clampedMs, startTime: start
            )
            setState(.done(burst))
        } catch {
            setState(.error((error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription))
            logger.error("RAW: captureBurst failed: \(String(describing: error))")
        }
    }

    private func capturePhoto(label: String,
                              output: AVCapturePhotoOutput,
                              rawFormat: OSType) async throws -> RAWPhoto {
        let settings = AVCapturePhotoSettings(
            rawPixelFormatType: rawFormat,
            rawFileType: .dng,
            processedFormat: nil,
            processedFileType: nil
        )
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        if let previewType = settings.availablePreviewPhotoPixelFormatTypes.first {
            settings.previewPhotoFormat = [
                kCVPixelBufferPixelFormatTypeKey as String: previewType,
                kCVPixelBufferWidthKey           as String: 512,
                kCVPixelBufferHeightKey          as String: 512
            ]
        }

        return try await withCheckedThrowingContinuation { cont in
            let uid = settings.uniqueID
            let delegate = PhotoCaptureDelegate(label: label) { [weak self] result in
                self?.removeDelegate(for: uid)
                cont.resume(with: result)
            }
            storeDelegate(delegate, for: uid)
            sessionQueue.async {
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func storeDelegate(_ d: PhotoCaptureDelegate, for id: Int64) {
        delegatesLock.lock()
        pendingDelegates[id] = d
        delegatesLock.unlock()
    }

    private func removeDelegate(for id: Int64) {
        delegatesLock.lock()
        pendingDelegates[id] = nil
        delegatesLock.unlock()
    }

    // MARK: - State dispatch

    /// Writes to @Published state from any thread. SwiftUI requires main-
    /// thread publishing; configureOnQueue and the capture delegates all run
    /// on background queues.
    private func setState(_ new: State) {
        if Thread.isMainThread {
            self.state = new
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.state = new
            }
        }
    }
}

// MARK: - RAWPhoto

struct RAWPhoto: Sendable {
    let label: String
    let dngData: Data
    let previewJPEG: Data?
    let timestamp: Date
    let sensorWidth: Int
    let sensorHeight: Int
    let exposureSeconds: Double
    let isoSpeed: Int
    let apertureFNumber: Double
    let focalLengthMm: Double
    let lensModel: String?
    let rawMetadata: [String: String]
}

// MARK: - Delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let label: String
    let completion: (Result<RAWPhoto, Error>) -> Void
    private let timestamp = Date()
    private var hasCompleted = false
    private let completionLock = NSLock()

    init(label: String, completion: @escaping (Result<RAWPhoto, Error>) -> Void) {
        self.label = label
        self.completion = completion
        super.init()
    }

    private func fire(_ result: Result<RAWPhoto, Error>) {
        completionLock.lock()
        let already = hasCompleted
        hasCompleted = true
        completionLock.unlock()
        if already { return }
        completion(result)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            fire(.failure(error))
            return
        }
        guard let dng = photo.fileDataRepresentation() else {
            fire(.failure(RAWError.captureFailed("no DNG data")))
            return
        }

        let md         = photo.metadata
        let exif       = md[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff       = md[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exposureS  = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue ?? 0
        let isoArr     = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int]
        let iso        = isoArr?.first ?? 0
        let aperture   = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue ?? 0
        let focalMm    = (exif[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue ?? 0
        let lensModel  = exif[kCGImagePropertyExifLensModel as String] as? String
            ?? (tiff["Model"] as? String)

        let dims = photo.resolvedSettings.photoDimensions
        let w = Int(dims.width)
        let h = Int(dims.height)

        let rawMd = flatten(md)
        let previewJPEG: Data? = {
            guard let pb = photo.previewPixelBuffer else { return nil }
            let ci = CIImage(cvPixelBuffer: pb)
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
            let ui = UIImage(cgImage: cg)
            return ui.jpegData(compressionQuality: 0.9)
        }()

        let raw = RAWPhoto(
            label: label,
            dngData: dng,
            previewJPEG: previewJPEG,
            timestamp: timestamp,
            sensorWidth: w,
            sensorHeight: h,
            exposureSeconds: exposureS,
            isoSpeed: iso,
            apertureFNumber: aperture,
            focalLengthMm: focalMm,
            lensModel: lensModel,
            rawMetadata: rawMd
        )
        fire(.success(raw))
    }
}

private func flatten(_ d: [String: Any], prefix: String = "") -> [String: String] {
    var out: [String: String] = [:]
    for (k, v) in d {
        let key = prefix.isEmpty ? k : "\(prefix).\(k)"
        if let sub = v as? [String: Any] {
            for (sk, sv) in flatten(sub, prefix: key) { out[sk] = sv }
        } else {
            out[key] = String(describing: v)
        }
    }
    return out
}

// MARK: - Errors

enum RAWError: LocalizedError {
    case cameraPermissionDenied
    case noRearCamera
    case cannotAddInput
    case cannotAddOutput
    case noRAWFormat
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied: return "Camera access denied. Enable it in Settings."
        case .noRearCamera:           return "No rear wide-angle camera on this device."
        case .cannotAddInput:         return "Cannot add camera input to capture session."
        case .cannotAddOutput:        return "Cannot add photo output to capture session."
        case .noRAWFormat:            return "Device does not support Bayer RAW DNG capture."
        case .captureFailed(let s):   return "Capture failed: \(s)"
        }
    }
}

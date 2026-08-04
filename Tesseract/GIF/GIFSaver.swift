// GIFSaver.swift
// Tesseract
//
// Persistence for exported GIFs: save to the Photos library (add-only
// authorization) and present the system share sheet. The GIF Data is
// written as-is — the byte-level export contract survives into Photos.

import Photos
import UIKit
import UniformTypeIdentifiers

enum GIFSaver {

    /// Save GIF data to the Photos library. Returns true on success.
    /// Requests add-only authorization on first use.
    static func saveToPhotos(_ data: Data) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.gif.identifier
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: options)
            }
            return true
        } catch {
            return false
        }
    }

    /// Present the system share sheet for GIF data.
    @MainActor
    static func presentShareSheet(_ data: Data) {
        guard let url = GIFEncoder.saveToTempFile(data) else { return }

        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        controller.popoverPresentationController?.sourceView = UIView()

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        // Present on top of whatever is frontmost (e.g. the elite map cover).
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }
}

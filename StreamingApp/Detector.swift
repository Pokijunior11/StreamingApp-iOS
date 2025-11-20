import Foundation
import CoreML
import Vision
import UIKit

@objc final class Detector: NSObject {
    private var visionModel: VNCoreMLModel!

    override init() {
        super.init()
        do {
            visionModel = try Utils.loadModel(named: "yolo11n")
        } catch {
            print("❌ Failed to load model:", error)
        }
    }

    // GStreamer sends RGBA bytes; convert → CVPixelBuffer → Vision
    @objc func detectRGBA(_ data: Data,
                          width: Int,
                          height: Int,
                          stride: Int) -> [[String: Any]] {

        guard let pixelBuffer = Self.pixelBuffer(fromRGBA: data,
                                                 width: width,
                                                 height: height) else {
            print("⚠️ Could not create pixel buffer")
            return []
        }

        // --- run Vision exactly like the GitHub repo ---
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("⚠️ Vision request failed:", error)
            return []
        }

        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            print("⚠️ No VNRecognizedObjectObservation results")
            return []
        }

        var dets: [[String: Any]] = []
        for obs in results {
            if obs.confidence < 0.35 { continue }
            guard let label = obs.labels.first else { continue }
            if label.identifier.lowercased() != "person" { continue }
            dets.append([
                "label": label.identifier,
                "score": obs.confidence,
                "rect": NSCoder.string(for: obs.boundingBox)
            ])
        }


        return dets
    }

    private static func pixelBuffer(fromRGBA data: Data,
                                    width: Int,
                                    height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault,
                            width, height,
                            kCVPixelFormatType_32BGRA,
                            attrs, &pb)
        guard let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let dest = CVPixelBufferGetBaseAddress(pixelBuffer) {
            data.copyBytes(to: dest.assumingMemoryBound(to: UInt8.self),
                           count: data.count)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }
}

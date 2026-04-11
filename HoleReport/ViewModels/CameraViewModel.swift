import Foundation
import ARKit
import RealityKit
import CoreLocation
import UIKit
import AVFoundation
import Combine

enum MeasureMode {
    case idle
    case placingFirst
    case placingSecond(start: SIMD3<Float>)
}

class CameraViewModel: NSObject, ObservableObject {
    @Published var measureMode: MeasureMode = .idle
    @Published var currentMeasurements: [Measurement] = []
    @Published var statusMessage: String = "Point camera at a surface"
    @Published var capturedImage: UIImage?
    @Published var showPhotoPreview: Bool = false
    @Published var lastSavedPhoto: MeasuredPhoto?
    @Published var isMeasuring: Bool = false
    @Published var zoomLevel: CGFloat = 1.0
    @Published var isTorchOn: Bool = false

    var arView: ARView?
    weak var locationManager: LocationManager?
    weak var photoStore: PhotoStore?
    
    private var anchorEntities: [AnchorEntity] = []
    private var startWorldPosition: SIMD3<Float>?
    private var startAnchor: AnchorEntity?
    
    // MARK: - Setup
    
    func setupAR(_ view: ARView) {
        self.arView = view
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        view.session.delegate = self
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }
    
    // MARK: - Torch

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            isTorchOn ? (device.torchMode = .off) : (try device.setTorchModeOn(level: 1.0))
            isTorchOn = device.torchMode == .on
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let clamped = max(1.0, min(factor, maxZoom))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {}
        DispatchQueue.main.async { self.zoomLevel = clamped }
    }

    // MARK: - Measure control

    func startMeasuring() {
        isMeasuring = true
        measureMode = .placingFirst
        statusMessage = "Tap a surface to place the first point"
    }
    
    func cancelMeasuring() {
        isMeasuring = false
        measureMode = .idle
        startWorldPosition = nil
        startAnchor?.removeFromParent()
        startAnchor = nil
        statusMessage = "Point camera at a surface"
    }
    
    func clearMeasurements() {
        currentMeasurements.removeAll()
        anchorEntities.forEach { $0.removeFromParent() }
        anchorEntities.removeAll()
        startAnchor = nil
        startWorldPosition = nil
        isMeasuring = false
        measureMode = .idle
        statusMessage = "Point camera at a surface"
    }
    
    // MARK: - Tap handler
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard isMeasuring, let arView = arView else { return }
        
        let loc = gesture.location(in: arView)
        let results = arView.raycast(from: loc, allowing: .estimatedPlane, alignment: .any)
        guard let hit = results.first else {
            statusMessage = "No surface detected — move camera slowly over a surface"
            return
        }
        
        let col = hit.worldTransform.columns.3
        let pos = SIMD3<Float>(col.x, col.y, col.z)
        
        switch measureMode {
        case .idle:
            break
        case .placingFirst:
            placeFirstPoint(pos: pos, transform: hit.worldTransform)
        case .placingSecond(let start):
            placeSecondPoint(start: start, end: pos, transform: hit.worldTransform)
        }
    }
    
    // MARK: - Point placement
    
    private func placeFirstPoint(pos: SIMD3<Float>, transform: simd_float4x4) {
        startWorldPosition = pos
        
        let anchor = AnchorEntity(world: transform)
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.008),
                                 materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
        anchor.addChild(sphere)
        arView?.scene.addAnchor(anchor)
        startAnchor = anchor
        anchorEntities.append(anchor)
        
        measureMode = .placingSecond(start: pos)
        statusMessage = "Now tap the second point"
    }
    
    private func placeSecondPoint(start: SIMD3<Float>, end: SIMD3<Float>, transform: simd_float4x4) {
        // End sphere
        let endAnchor = AnchorEntity(world: transform)
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.008),
                                 materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)])
        endAnchor.addChild(sphere)
        arView?.scene.addAnchor(endAnchor)
        anchorEntities.append(endAnchor)
        
        let distance = simd_distance(start, end)
        drawLine(from: start, to: end)
        addDistanceLabel(distance: distance, near: (start + end) / 2)
        
        let label = "Measurement \(currentMeasurements.count + 1)"
        let m = Measurement(label: label, value: distance,
                            startPoint: .zero, endPoint: .zero,
                            startWorld: [start.x, start.y, start.z],
                            endWorld: [end.x, end.y, end.z])
        
        DispatchQueue.main.async {
            self.currentMeasurements.append(m)
            self.statusMessage = "\(m.displayString) — tap again for another, or capture"
            self.measureMode = .placingFirst
            self.startAnchor = nil
            self.startWorldPosition = nil
        }
    }
    
    // MARK: - Visual helpers
    
    private func drawLine(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        let mid = (start + end) / 2
        let length = simd_distance(start, end)
        
        var transform = Transform(translation: mid)
        // Rotate the box so its Z-axis aligns with the start→end vector
        let dir = normalize(end - start)
        let defaultDir = SIMD3<Float>(0, 0, 1)
        let dot = simd_dot(defaultDir, dir)
        if abs(dot) < 0.9999 {
            let axis = normalize(simd_cross(defaultDir, dir))
            let angle = acos(max(-1, min(1, dot)))
            transform.rotation = simd_quaternion(angle, axis)
        } else if dot < 0 {
            transform.rotation = simd_quaternion(Float.pi, SIMD3<Float>(0, 1, 0))
        }
        
        let line = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.003, 0.003, length)),
            materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
        )
        line.transform = transform
        
        let anchor = AnchorEntity(world: .init(1))
        anchor.addChild(line)
        arView?.scene.addAnchor(anchor)
        anchorEntities.append(anchor)
    }
    
    private func addDistanceLabel(distance: Float, near position: SIMD3<Float>) {
        let text = distance >= 1.0
            ? String(format: "%.2f m", distance)
            : String(format: "%.1f cm", distance * 100)
        
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let label = ModelEntity(mesh: mesh,
                                materials: [SimpleMaterial(color: .white, isMetallic: false)])
        label.scale = SIMD3<Float>(repeating: 0.4)
        
        var labelPos = position
        labelPos.y += 0.025
        let anchor = AnchorEntity(world: Transform(translation: labelPos).matrix)
        anchor.addChild(label)
        arView?.scene.addAnchor(anchor)
        anchorEntities.append(anchor)
    }
    
    // MARK: - Capture Photo
    
    func capturePhoto() {
        guard let arView = arView,
              let frame = arView.session.currentFrame else { return }

        // Convert the AR camera's pixel buffer directly to UIImage.
        // arView.snapshot() renders via Metal and returns black on many devices;
        // ARFrame.capturedImage always contains the real camera data.
        guard let rawImage = imageFromARFrame(frame) else { return }

        let location    = locationManager?.currentLocation
        let cachedAddress = locationManager?.currentAddress
        let measurements  = currentMeasurements

        let image: UIImage = measurements.isEmpty
            ? rawImage
            : drawMeasurementOverlay(on: rawImage, frame: frame, measurements: measurements)

        let fileName = "photo_\(UUID().uuidString).jpg"

        let savePhoto = { [weak self] (address: String?) in
            guard let self = self else { return }
            let photo = MeasuredPhoto(
                imageFileName: fileName,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude,
                altitude: location?.altitude,
                measurements: measurements,
                locationAddress: address ?? cachedAddress
            )
            DispatchQueue.main.async {
                self.photoStore?.save(image: image, photo: photo)
                self.capturedImage = image
                self.lastSavedPhoto = photo
                self.showPhotoPreview = true
                self.clearMeasurements()
            }
        }

        if let loc = location {
            locationManager?.geocodeOnce(for: loc) { address in savePhoto(address) }
        } else {
            savePhoto(nil)
        }
    }

    /// Convert ARFrame's camera pixel buffer to a correctly-oriented UIImage.
    private func imageFromARFrame(_ frame: ARFrame) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        // The camera sensor is always landscape; rotate to match the current interface orientation.
        let interfaceOrientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait

        let imageOrientation: UIImage.Orientation
        switch interfaceOrientation {
        case .portrait:           imageOrientation = .right
        case .portraitUpsideDown: imageOrientation = .left
        case .landscapeRight:     imageOrientation = .up
        case .landscapeLeft:      imageOrientation = .down
        default:                  imageOrientation = .right
        }

        return UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)
    }

    // MARK: - Measurement Overlay

    private func drawMeasurementOverlay(on image: UIImage,
                                        frame: ARFrame,
                                        measurements: [Measurement]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)
            let cgCtx = ctx.cgContext
            let size = image.size

            // Scale drawing elements to match image resolution.
            // Reference: 390 pt (standard iPhone width in portrait).
            let scale = min(size.width, size.height) / 390.0
            let lineWidth   = 3.0  * scale
            let dotRadius   = 8.0  * scale
            let fontSize    = 20.0 * scale
            let labelOffset = 10.0 * scale

            let orientation = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.interfaceOrientation ?? .portrait

            for m in measurements {
                guard let sw = m.startWorld, let ew = m.endWorld,
                      sw.count == 3, ew.count == 3 else { continue }
                let startW = SIMD3<Float>(sw[0], sw[1], sw[2])
                let endW   = SIMD3<Float>(ew[0], ew[1], ew[2])

                let startPt = frame.camera.projectPoint(startW, orientation: orientation, viewportSize: size)
                let endPt   = frame.camera.projectPoint(endW,   orientation: orientation, viewportSize: size)
                let midPt   = CGPoint(x: (startPt.x + endPt.x) / 2, y: (startPt.y + endPt.y) / 2)

                // Yellow line
                cgCtx.setStrokeColor(UIColor.systemYellow.cgColor)
                cgCtx.setLineWidth(lineWidth)
                cgCtx.move(to: startPt)
                cgCtx.addLine(to: endPt)
                cgCtx.strokePath()

                // Endpoint circles
                for pt in [startPt, endPt] {
                    cgCtx.setFillColor(UIColor.white.cgColor)
                    cgCtx.fillEllipse(in: CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius,
                                                 width: dotRadius * 2, height: dotRadius * 2))
                }

                // Distance label
                let labelText = m.displayString as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor.black.withAlphaComponent(0.6)
                ]
                labelText.draw(at: CGPoint(x: midPt.x + labelOffset, y: midPt.y - labelOffset),
                               withAttributes: attrs)
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension CameraViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = "AR Error: \(error.localizedDescription)"
        }
    }
    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { self.statusMessage = "Session interrupted" }
        if isTorchOn { toggleTorch() }
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        guard let arView = arView else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        DispatchQueue.main.async { self.statusMessage = "Session resumed" }
    }
}

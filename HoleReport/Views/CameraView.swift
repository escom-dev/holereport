import SwiftUI
import ARKit
import RealityKit

// MARK: - ARView SwiftUI Wrapper

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: CameraViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        viewModel.setupAR(arView)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        arView.addGestureRecognizer(pinch)
        return arView
    }
    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    class Coordinator: NSObject {
        let viewModel: CameraViewModel
        private var zoomAtGestureStart: CGFloat = 1.0

        init(viewModel: CameraViewModel) { self.viewModel = viewModel }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                zoomAtGestureStart = viewModel.zoomLevel
            case .changed:
                viewModel.setZoom(zoomAtGestureStart * gesture.scale)
            default:
                break
            }
        }
    }
}

// MARK: - Main Camera View

struct CameraView: View {
    @StateObject private var viewModel       = CameraViewModel()
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var photoStore:    PhotoStore
    @EnvironmentObject var uploadManager: UploadManager

    var body: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                .ignoresSafeArea()
                .onAppear {
                    viewModel.locationManager = locationManager
                    viewModel.photoStore      = photoStore
                }

            VStack {
                GPSInfoBar(locationManager: locationManager)
                    .padding(.top, 8)

                Spacer()

                if !viewModel.currentMeasurements.isEmpty {
                    MeasurementBadgeStack(measurements: viewModel.currentMeasurements)
                        .padding(.horizontal)
                }

                if viewModel.zoomLevel > 1.01 {
                    Text(String(format: "%.1f×", viewModel.zoomLevel))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .transition(.opacity)
                }

                Text(viewModel.statusMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 4)

                BottomControlBar(viewModel: viewModel)
            }
        }
        .fullScreenCover(isPresented: $viewModel.showPhotoPreview) {
            if let image = viewModel.capturedImage,
               let photo = viewModel.lastSavedPhoto {
                PhotoPreviewSheet(image: image, photo: photo, uploadManager: uploadManager)
            }
        }
    }
}

// MARK: - GPS Info Bar

struct GPSInfoBar: View {
    @ObservedObject var locationManager: LocationManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundColor(accuracyColor)

            if let loc = locationManager.currentLocation {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%.6f°,  %.6f°",
                                loc.coordinate.latitude, loc.coordinate.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Text(String(format: "Alt: %.1f m", loc.altitude))
                            .font(.caption2).foregroundColor(.white.opacity(0.8))
                        Text(String(format: "±%.0f m", loc.horizontalAccuracy))
                            .font(.caption2).foregroundColor(.yellow.opacity(0.9))
                    }
                }
            } else {
                Text("Acquiring GPS…")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
            }

            Spacer()
            Circle().fill(accuracyColor).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    var accuracyColor: Color {
        guard let loc = locationManager.currentLocation else { return .gray }
        if loc.horizontalAccuracy < 5  { return .green }
        if loc.horizontalAccuracy < 20 { return .yellow }
        return .orange
    }
}

// MARK: - Measurement Badges

struct MeasurementBadgeStack: View {
    let measurements: [Measurement]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(measurements) { m in
                    VStack(spacing: 2) {
                        Text(m.label)
                            .font(.caption2).foregroundColor(.white.opacity(0.7))
                        Text(m.displayString)
                            .font(.caption.weight(.bold)).foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Bottom Controls

struct BottomControlBar: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        HStack(spacing: 16) {
            Spacer()

            // Torch
            ControlButton(
                icon: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                label: viewModel.isTorchOn ? "Light On" : "Light",
                iconColor: viewModel.isTorchOn ? .yellow : .white,
                bgColor: viewModel.isTorchOn ? Color(white: 0.32) : Color(white: 0.18),
                disabled: false
            ) { viewModel.toggleTorch() }

            // Clear
            ControlButton(
                icon: "trash.fill",
                label: "Clear",
                iconColor: .white,
                bgColor: Color(white: 0.18),
                disabled: viewModel.currentMeasurements.isEmpty
            ) { viewModel.clearMeasurements() }

            // Shutter
            Button { viewModel.capturePhoto() } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)
                    Circle()
                        .strokeBorder(Color.yellow, lineWidth: 3)
                        .frame(width: 92, height: 92)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.black)
                }
            }

            // Measure / Cancel
            ControlButton(
                icon: viewModel.isMeasuring ? "xmark" : "ruler.fill",
                label: viewModel.isMeasuring ? "Cancel" : "Measure",
                iconColor: .white,
                bgColor: viewModel.isMeasuring ? .red : Color(white: 0.18),
                disabled: false
            ) {
                if viewModel.isMeasuring { viewModel.cancelMeasuring() }
                else { viewModel.startMeasuring() }
            }

            Spacer()
        }
        .padding(.vertical, 18)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.82))
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct ControlButton: View {
    let icon: String
    let label: String
    let iconColor: Color
    let bgColor: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(bgColor)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(iconColor)
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
            }
        }
        .opacity(disabled ? 0.25 : 1)
        .disabled(disabled)
    }
}

// MARK: - Photo Preview (full-screen, with Upload button)

struct PhotoPreviewSheet: View {
    let image: UIImage
    let photo: MeasuredPhoto
    @ObservedObject var uploadManager: UploadManager
    @EnvironmentObject var photoStore: PhotoStore
    @Environment(\.dismiss) var dismiss

    @State private var savedLocally = false
    @State private var uploadState: UploadState = .idle
    @State private var categories: [UploadManager.Category] = []
    @State private var selectedCategoryId: Int? = nil

    enum UploadState {
        case idle, uploading, success(String), failure(String)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.65)

                Spacer()

                // Measurement summary
                if !photo.measurements.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photo.measurements) { m in
                                VStack(spacing: 2) {
                                    Text(m.label).font(.caption2).foregroundColor(.white.opacity(0.6))
                                    Text(m.displayString).font(.caption.bold()).foregroundColor(.yellow)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 8)
                }

                // GPS info
                if let lat = photo.latitude, let lon = photo.longitude {
                    Text(String(format: "📍 %.5f°, %.5f°", lat, lon))
                        .font(.caption).foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 4)
                }

                // Category picker
                if !categories.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .font(.caption).foregroundColor(.white.opacity(0.6))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                CategoryChip(label: "None", color: .gray, isSelected: selectedCategoryId == nil) {
                                    selectedCategoryId = nil
                                }
                                ForEach(categories) { cat in
                                    CategoryChip(
                                        label: cat.nameEn.isEmpty ? cat.name : cat.nameEn,
                                        color: Color(hex: cat.color) ?? .blue,
                                        isSelected: selectedCategoryId == cat.id
                                    ) { selectedCategoryId = cat.id }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Upload status
                uploadStatusView
                    .padding(.horizontal, 20).padding(.bottom, 8)

                // Action buttons
                HStack(spacing: 12) {
                    // Save to Photos
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        savedLocally = true
                    } label: {
                        Label(savedLocally ? "Saved" : "Save", systemImage: savedLocally ? "checkmark" : "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(savedLocally ? Color.green : Color.white.opacity(0.2), in: Capsule())
                    }

                    // Upload to server
                    Button { uploadToServer() } label: {
                        HStack(spacing: 6) {
                            if case .uploading = uploadState {
                                ProgressView().scaleEffect(0.8).tint(.white)
                            } else {
                                Image(systemName: "arrow.up.to.line")
                            }
                            Text(uploadButtonLabel)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(uploadButtonColor, in: Capsule())
                    }
                    .disabled(uploadManager.isUploading || {
                        if case .success = uploadState { return true }
                        return false
                    }())

                    // Close
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            uploadManager.fetchCategories { cats in
                categories = cats
            }
        }
    }

    @ViewBuilder
    var uploadStatusView: some View {
        switch uploadState {
        case .success(let url):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Uploaded!").foregroundColor(.green)
                Text(url).foregroundColor(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
            }
            .font(.caption)
        case .failure(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                Text(msg).foregroundColor(.red)
            }
            .font(.caption)
        default:
            EmptyView()
        }
    }

    var uploadButtonLabel: String {
        switch uploadState {
        case .uploading: return "Uploading…"
        case .success:   return "Uploaded ✓"
        case .failure:   return "Retry Upload"
        default:         return "Upload"
        }
    }

    var uploadButtonColor: Color {
        switch uploadState {
        case .success:  return .green
        case .failure:  return .red.opacity(0.7)
        default:        return .blue
        }
    }

    private func uploadToServer() {
        uploadState = .uploading
        uploadManager.upload(image: image, photo: photo, categoryId: selectedCategoryId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    uploadState = .success(url)
                    photoStore.markUploaded(photo: photo)
                case .failure(let err):
                    uploadState = .failure(err.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.3) : Color.white.opacity(0.1),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? color : Color.clear, lineWidth: 1.5))
        }
        .foregroundColor(.white)
    }
}

// MARK: - Color from hex string

private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}

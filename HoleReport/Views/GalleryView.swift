import SwiftUI
import UIKit
import PhotosUI
import ImageIO

struct GalleryView: View {
    @EnvironmentObject var photoStore: PhotoStore
    @EnvironmentObject var uploadManager: UploadManager
    @State private var selectedPhoto: MeasuredPhoto?
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if photoStore.photos.isEmpty {
                    ContentUnavailableView(
                        loc("No Photos Yet"),
                        systemImage: "camera.badge.clock",
                        description: Text(loc("Capture photos with measurements using the Camera tab."))
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(photoStore.photos) { photo in
                                PhotoCard(photo: photo)
                                    .onTapGesture { selectedPhoto = photo }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(loc("Gallery"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPicker = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
                    .environmentObject(photoStore)
                    .environmentObject(uploadManager)
            }
            .sheet(isPresented: $showPicker) {
                LibraryPicker { image, date, lat, lon, alt in
                    let photo = MeasuredPhoto(
                        imageFileName: "photo_\(UUID().uuidString).jpg",
                        timestamp: date ?? Date(),
                        latitude: lat,
                        longitude: lon,
                        altitude: alt
                    )
                    photoStore.save(image: image, photo: photo)
                }
            }
        }
    }
}

// MARK: - Photo Card

struct PhotoCard: View {
    let photo: MeasuredPhoto
    @EnvironmentObject var photoStore: PhotoStore

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Photo image ───────────────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                if let image = photoStore.loadImage(fileName: photo.imageFileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .overlay(Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray))
                }

                // Badges top-right
                HStack(spacing: 4) {
                    if photo.isUploaded {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(5)
                            .background(.green.opacity(0.9), in: Circle())
                    }
                    if !photo.measurements.isEmpty {
                        Label("\(photo.measurements.count)", systemImage: "ruler")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.blue.opacity(0.85), in: Capsule())
                    }
                    if photo.latitude != nil {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(5)
                            .background(.green.opacity(0.85), in: Circle())
                    }
                }
                .padding(8)
            }

            // ── Info panel ────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {

                // Date
                Label(dateFormatter.string(from: photo.timestamp), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                // Address or coordinates
                if let address = photo.locationAddress {
                    Label(address, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let lat = photo.latitude, let lon = photo.longitude {
                    Label(String(format: "%.5f°, %.5f°", lat, lon), systemImage: "location")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Measurements
                if !photo.measurements.isEmpty {
                    Divider()
                    FlowRow(measurements: photo.measurements)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Measurement pills row

struct FlowRow: View {
    let measurements: [Measurement]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(measurements) { m in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(m.displayString)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct PhotoDetailView: View {
    let photo: MeasuredPhoto
    @EnvironmentObject var photoStore: PhotoStore
    @EnvironmentObject var uploadManager: UploadManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var shareItems: [Any]?
    @State private var showShareSheet = false
    @State private var uploadState: UploadState = .idle
    @State private var categories: [UploadManager.Category] = []
    @State private var selectedCategoryId: Int?

    private var initialUploadState: UploadState {
        photo.isUploaded ? .success(NSLocalizedString("Previously uploaded", comment: "")) : .idle
    }

    enum UploadState { case idle, uploading, success(String), failure(String) }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = photoStore.loadImage(fileName: photo.imageFileName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                    }

                    GroupBox {
                        InfoRow(label: loc("Date"),     value: dateFormatter.string(from: photo.timestamp), icon: "calendar")
                        Divider()
                        InfoRow(label: loc("GPS"),      value: photo.coordinateString, icon: "location.fill")
                        Divider()
                        InfoRow(label: loc("Altitude"), value: photo.altitudeString,   icon: "arrow.up.to.line")
                        if let address = photo.locationAddress {
                            Divider()
                            InfoRow(label: loc("Address"), value: address, icon: "mappin")
                        }
                    } label: {
                        Label(loc("Location"), systemImage: "map.fill")
                    }

                    if !photo.measurements.isEmpty {
                        GroupBox {
                            ForEach(Array(photo.measurements.enumerated()), id: \.element.id) { index, m in
                                if index > 0 { Divider() }
                                InfoRow(label: m.label, value: m.displayString, icon: "ruler")
                            }
                        } label: {
                            Label(loc("Measurements"), systemImage: "ruler")
                        }
                    }

                    // ── Category picker ───────────────────────────────────────
                    if !categories.isEmpty {
                        GroupBox {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    CategoryChip(label: loc("None"), color: .gray, isSelected: selectedCategoryId == nil) {
                                        selectedCategoryId = nil
                                        photoStore.updateCategory(photo: photo, categoryId: nil, categoryName: nil)
                                    }
                                    ForEach(categories) { cat in
                                        CategoryChip(
                                            label: languageManager.currentLanguage == "bg" ? cat.name : (cat.nameEn.isEmpty ? cat.name : cat.nameEn),
                                            color: Color(hex: cat.color) ?? .blue,
                                            isSelected: selectedCategoryId == cat.id
                                        ) {
                                            selectedCategoryId = cat.id
                                            photoStore.updateCategory(photo: photo, categoryId: cat.id, categoryName: cat.name)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } label: {
                            Label(loc("Category"), systemImage: "tag.fill")
                        }
                    }

                    // ── Upload button ─────────────────────────────────────────
                    Button { uploadPhoto() } label: {
                        HStack(spacing: 8) {
                            if case .uploading = uploadState {
                                ProgressView().scaleEffect(0.8).tint(.white)
                            } else {
                                Image(systemName: uploadIcon)
                            }
                            Text(uploadLabel)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(uploadColor, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled({
                        if case .uploading = uploadState { return true }
                        if case .success   = uploadState { return true }
                        return false
                    }())

                    // Upload result message
                    if case .success(let url) = uploadState {
                        Label(url, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if case .failure(let msg) = uploadState {
                        Label(msg, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // ── Share button ──────────────────────────────────────────
                    Button { prepareAndShare() } label: {
                        Label(loc("Share with Metadata"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle(loc("Photo Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(loc("Done")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        photoStore.delete(photo: photo)
                        dismiss()
                    } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                }
            }
            .background(ShareSheetPresenter(items: $shareItems, isPresented: $showShareSheet))
            .onAppear {
                uploadState = initialUploadState
                selectedCategoryId = photo.categoryId
                uploadManager.fetchCategories { cats in
                    categories = cats
                }
            }
        }
    }

    private var uploadLabel: String {
        switch uploadState {
        case .uploading:    return NSLocalizedString("Uploading…", comment: "")
        case .success:      return NSLocalizedString("Uploaded ✓", comment: "")
        case .failure:      return NSLocalizedString("Retry Upload", comment: "")
        default:            return NSLocalizedString("Upload to Server", comment: "")
        }
    }

    private var uploadIcon: String {
        switch uploadState {
        case .success:  return "checkmark.circle.fill"
        case .failure:  return "arrow.clockwise"
        default:        return "arrow.up.to.line"
        }
    }

    private var uploadColor: Color {
        switch uploadState {
        case .success:  return .green
        case .failure:  return .red.opacity(0.8)
        default:        return .blue
        }
    }

    private func uploadPhoto() {
        guard let image = photoStore.loadImage(fileName: photo.imageFileName) else { return }
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
    
    private func prepareAndShare() {
        guard let image = photoStore.loadImage(fileName: photo.imageFileName) else { return }
        
        var text = "📸 Hole Report\n"
        text += "📅 \(dateFormatter.string(from: photo.timestamp))\n"
        text += "📍 \(photo.coordinateString)\n"
        text += "🏔 Altitude: \(photo.altitudeString)\n"
        if let address = photo.locationAddress {
            text += "🗺 \(address)\n"
        }
        if !photo.measurements.isEmpty {
            text += "\n📐 Measurements:\n"
            photo.measurements.forEach { m in
                text += "  • \(m.label): \(m.displayString)\n"
            }
        }
        shareItems = [image, text]
        showShareSheet = true
    }
}

// MARK: - Share Sheet Presenter
// Uses a hidden background UIViewControllerRepresentable so the share sheet
// is presented from its OWN view controller, not the parent sheet's VC.
// This avoids the "already presenting" crash.

struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var items: [Any]?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> ShareHostVC {
        ShareHostVC()
    }
    
    func updateUIViewController(_ vc: ShareHostVC, context: Context) {
        guard isPresented, let items = items, !vc.isPresenting else { return }
        vc.presentShare(items: items) {
            DispatchQueue.main.async {
                self.isPresented = false
                self.items = nil
            }
        }
    }
}

class ShareHostVC: UIViewController {
    var isPresenting = false
    
    func presentShare(items: [Any], completion: @escaping () -> Void) {
        guard !isPresenting else { return }
        isPresenting = true
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        ac.completionWithItemsHandler = { _, _, _, _ in
            self.isPresenting = false
            completion()
        }
        // On iPad, anchor to the view to avoid a crash
        if let popover = ac.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(ac, animated: true)
    }
}

// MARK: - Photos Library Picker

struct LibraryPicker: UIViewControllerRepresentable {
    /// Called on the main thread for each selected photo.
    let onImport: (UIImage, _ date: Date?, _ lat: Double?, _ lon: Double?, _ alt: Double?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0          // unlimited multi-select
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LibraryPicker

        init(_ parent: LibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            // Process one photo at a time so only one full-res buffer is in memory at once.
            processNext(results: results, index: 0)
        }

        private func processNext(results: [PHPickerResult], index: Int) {
            guard index < results.count else { return }
            results[index].itemProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, _ in
                guard let self else { return }
                if let data {
                    let (date, lat, lon, alt) = exifMetadata(from: data)
                    // Downsample at decode time — never loads full-res pixels into RAM.
                    let image = downsampledImage(from: data, maxPixelSize: 2048)
                    DispatchQueue.main.async {
                        if let image { self.parent.onImport(image, date, lat, lon, alt) }
                        self.processNext(results: results, index: index + 1)
                    }
                } else {
                    DispatchQueue.main.async { self.processNext(results: results, index: index + 1) }
                }
            }
        }
    }
}

/// Decode a downsampled UIImage from raw data without ever loading the full-resolution pixels.
/// `kCGImageSourceCreateThumbnailWithTransform` applies EXIF orientation automatically.
private func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
    let thumbOptions: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,   // respects EXIF orientation
        kCGImageSourceShouldCacheImmediately: false
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
    return UIImage(cgImage: cgImage)
}

/// Extract date and GPS coordinates from raw image data using ImageIO.
private func exifMetadata(from data: Data) -> (date: Date?, lat: Double?, lon: Double?, alt: Double?) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props  = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return (nil, nil, nil, nil) }

    // ── GPS ───────────────────────────────────────────────────────────────────
    var lat: Double? = nil
    var lon: Double? = nil
    var alt: Double? = nil
    if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
        if let v = gps[kCGImagePropertyGPSLatitude] as? Double {
            lat = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -v : v
        }
        if let v = gps[kCGImagePropertyGPSLongitude] as? Double {
            lon = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -v : v
        }
        alt = gps[kCGImagePropertyGPSAltitude] as? Double
    }

    // ── Date (EXIF → TIFF fallback) ───────────────────────────────────────────
    let df = DateFormatter()
    df.dateFormat = "yyyy:MM:dd HH:mm:ss"
    var date: Date? = nil
    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
       let s    = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
        date = df.date(from: s)
    }
    if date == nil,
       let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
       let s    = tiff[kCGImagePropertyTIFFDateTime] as? String {
        date = df.date(from: s)
    }

    return (date, lat, lon, alt)
}

// MARK: - InfoRow

struct InfoRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.blue)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

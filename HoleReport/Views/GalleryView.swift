import SwiftUI
import UIKit

struct GalleryView: View {
    @EnvironmentObject var photoStore: PhotoStore
    @EnvironmentObject var uploadManager: UploadManager
    @State private var selectedPhoto: MeasuredPhoto?

    var body: some View {
        NavigationStack {
            Group {
                if photoStore.photos.isEmpty {
                    ContentUnavailableView(
                        "No Photos Yet",
                        systemImage: "camera.badge.clock",
                        description: Text("Capture photos with measurements using the Camera tab.")
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
            .navigationTitle("Gallery")
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
                    .environmentObject(photoStore)
                    .environmentObject(uploadManager)
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

    @State private var shareItems: [Any]?
    @State private var showShareSheet = false
    @State private var uploadState: UploadState = .idle

    private var initialUploadState: UploadState {
        photo.isUploaded ? .success("Previously uploaded") : .idle
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
                        InfoRow(label: "Date",     value: dateFormatter.string(from: photo.timestamp), icon: "calendar")
                        Divider()
                        InfoRow(label: "GPS",      value: photo.coordinateString, icon: "location.fill")
                        Divider()
                        InfoRow(label: "Altitude", value: photo.altitudeString,   icon: "arrow.up.to.line")
                        if let address = photo.locationAddress {
                            Divider()
                            InfoRow(label: "Address", value: address, icon: "mappin")
                        }
                    } label: {
                        Label("Location", systemImage: "map.fill")
                    }

                    if !photo.measurements.isEmpty {
                        GroupBox {
                            ForEach(Array(photo.measurements.enumerated()), id: \.element.id) { index, m in
                                if index > 0 { Divider() }
                                InfoRow(label: m.label, value: m.displayString, icon: "ruler")
                            }
                        } label: {
                            Label("Measurements", systemImage: "ruler")
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
                        Label("Share with Metadata", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Photo Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
            .onAppear { uploadState = initialUploadState }
        }
    }

    private var uploadLabel: String {
        switch uploadState {
        case .uploading:    return "Uploading…"
        case .success:      return "Uploaded ✓"
        case .failure:      return "Retry Upload"
        default:            return "Upload to Server"
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
        uploadManager.upload(image: image, photo: photo) { result in
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

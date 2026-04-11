import SwiftUI
import MapKit

// MARK: - Cluster model

struct PhotoCluster: Identifiable {
    let id: String          // "lat_lon" key
    let coordinate: CLLocationCoordinate2D
    let photos: [MeasuredPhoto]
    var count: Int { photos.count }
}

/// Round coordinate to ~1 m precision for grouping
private func clusterKey(lat: Double, lon: Double) -> String {
    String(format: "%.5f_%.5f", lat, lon)
}

// MARK: - Map Tab

struct MapTabView: View {
    @EnvironmentObject var photoStore: PhotoStore
    @EnvironmentObject var uploadManager: UploadManager

    @State private var selectedCluster: PhotoCluster?
    @State private var detailPhoto: MeasuredPhoto?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.5, longitude: 25.5),
        span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
    )
    @State private var hasSetInitialRegion = false

    var clusters: [PhotoCluster] {
        var dict: [String: [MeasuredPhoto]] = [:]
        for photo in photoStore.photos {
            guard let lat = photo.latitude, let lon = photo.longitude else { continue }
            let key = clusterKey(lat: lat, lon: lon)
            dict[key, default: []].append(photo)
        }
        return dict.map { key, photos in
            PhotoCluster(
                id: key,
                coordinate: CLLocationCoordinate2D(
                    latitude: photos[0].latitude!,
                    longitude: photos[0].longitude!
                ),
                photos: photos.sorted { $0.timestamp > $1.timestamp }
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if clusters.isEmpty {
                    ContentUnavailableView(
                        "No Locations Yet",
                        systemImage: "map",
                        description: Text("Photos with GPS data will appear as markers on the map.")
                    )
                } else {
                    Map(coordinateRegion: $region, annotationItems: clusters) { cluster in
                        MapAnnotation(coordinate: cluster.coordinate) {
                            ClusterPin(cluster: cluster, isSelected: selectedCluster?.id == cluster.id)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedCluster = (selectedCluster?.id == cluster.id) ? nil : cluster
                                    }
                                }
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)

                    // Bottom card
                    if let cluster = selectedCluster {
                        VStack {
                            Spacer()
                            if cluster.count == 1 {
                                PhotoMapCard(
                                    photo: cluster.photos[0],
                                    onDismiss: { withAnimation { selectedCluster = nil } },
                                    onOpen:    { detailPhoto = cluster.photos[0] }
                                )
                                .padding(.horizontal, 16)
                                .padding(.bottom, 90)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else {
                                ClusterListCard(
                                    cluster: cluster,
                                    onDismiss: { withAnimation { selectedCluster = nil } },
                                    onOpen:    { detailPhoto = $0 }
                                )
                                .padding(.horizontal, 16)
                                .padding(.bottom, 90)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !clusters.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { withAnimation { fitAllMarkers() } } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                }
            }
            .onAppear {
                if !hasSetInitialRegion { fitAllMarkers(); hasSetInitialRegion = true }
            }
            .onChange(of: photoStore.photos.count) { _ in fitAllMarkers() }
            .sheet(item: $detailPhoto) { photo in
                PhotoDetailView(photo: photo)
                    .environmentObject(photoStore)
                    .environmentObject(uploadManager)
            }
        }
    }

    private func fitAllMarkers() {
        guard !clusters.isEmpty else { return }
        let lats = clusters.map { $0.coordinate.latitude }
        let lons = clusters.map { $0.coordinate.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude:  (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta:  max(0.01, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.01, (maxLon - minLon) * 1.4)
            )
        )
    }
}

// MARK: - Cluster Pin

struct ClusterPin: View {
    let cluster: PhotoCluster
    let isSelected: Bool

    private var pinColor: Color { isSelected ? .yellow : (cluster.count > 1 ? .orange : .blue) }
    private var size: CGFloat   { isSelected ? 46 : 34 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(pinColor)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                Image(systemName: cluster.count > 1 ? "photo.stack.fill" : (cluster.photos[0].measurements.isEmpty ? "camera.fill" : "ruler"))
                    .font(.system(size: isSelected ? 18 : 14, weight: .bold))
                    .foregroundColor(.white)

                // Count badge for clusters
                if cluster.count > 1 {
                    Text("\(cluster.count)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Color.red, in: Circle())
                        .offset(x: 8, y: -8)
                }
            }
            Triangle()
                .fill(pinColor)
                .frame(width: isSelected ? 14 : 10, height: isSelected ? 9 : 6)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Single Photo Card

struct PhotoMapCard: View {
    let photo: MeasuredPhoto
    let onDismiss: () -> Void
    let onOpen: () -> Void
    @EnvironmentObject var photoStore: PhotoStore

    private let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let img = photoStore.loadImage(fileName: photo.imageFileName) {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            Color.gray.opacity(0.3)
                                .overlay(Image(systemName: "photo").foregroundColor(.gray))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(3)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(df.string(from: photo.timestamp))
                    .font(.subheadline.weight(.semibold))
                if let addr = photo.locationAddress {
                    Text(addr).font(.caption).foregroundColor(.secondary).lineLimit(1)
                } else if let lat = photo.latitude, let lon = photo.longitude {
                    Text(String(format: "%.5f°, %.5f°", lat, lon))
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary).lineLimit(1)
                }
                if !photo.measurements.isEmpty {
                    Label(photo.measurements.map { $0.displayString }.joined(separator: " • "), systemImage: "ruler")
                        .font(.caption).foregroundColor(.yellow).lineLimit(1)
                }
                Button(action: onOpen) {
                    Label("Open Photo", systemImage: "photo")
                        .font(.caption.weight(.semibold)).foregroundColor(.blue)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold))
                    .foregroundColor(.secondary).padding(6)
                    .background(Color(.systemFill), in: Circle())
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Cluster List Card (multiple photos at same location)

struct ClusterListCard: View {
    let cluster: PhotoCluster
    let onDismiss: () -> Void
    let onOpen: (MeasuredPhoto) -> Void
    @EnvironmentObject var photoStore: PhotoStore

    private let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Label("\(cluster.count) photos at this location", systemImage: "photo.stack.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                        .foregroundColor(.secondary).padding(6)
                        .background(Color(.systemFill), in: Circle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Scrollable list of photos
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(cluster.photos) { photo in
                        Button { onOpen(photo) } label: {
                            HStack(spacing: 10) {
                                // Thumbnail
                                Group {
                                    if let img = photoStore.loadImage(fileName: photo.imageFileName) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.3)
                                            .overlay(Image(systemName: "photo").foregroundColor(.gray))
                                    }
                                }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                // Info
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(df.string(from: photo.timestamp))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                    if !photo.measurements.isEmpty {
                                        Label(photo.measurements.map { $0.displayString }.joined(separator: " • "), systemImage: "ruler")
                                            .font(.caption).foregroundColor(.yellow).lineLimit(1)
                                    } else {
                                        Text("No measurements")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }

                        if photo.id != cluster.photos.last?.id {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

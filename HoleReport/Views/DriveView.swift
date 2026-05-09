import SwiftUI
import UIKit
import MapKit

struct DriveView: View {
    @ObservedObject private var detector = PotholeDetector.shared

    // Sheet / dialog flags
    @State private var showClearConfirm         = false
    @State private var showDeleteFilteredConfirm = false
    @State private var showExportSheet          = false
    @State private var showMap                  = false
    @State private var showUploadResult         = false

    // Date filter
    @State private var isFilterEnabled = false
    @State private var filterFrom: Date = Calendar.current.startOfDay(for: Date())
    @State private var filterTo:   Date = Date()

    // G-force filter
    @State private var isGFilterEnabled = false
    @State private var filterMinG: Double = 0.0
    @State private var filterMaxG: Double = 5.0

    // Events visible in the log (respects active filters)
    private var filteredEvents: [PotholeEvent] {
        detector.events.filter { event in
            let passDate = !isFilterEnabled  || (event.timestamp >= filterFrom && event.timestamp <= filterTo)
            let passG    = !isGFilterEnabled || (event.peakG >= filterMinG && event.peakG <= filterMaxG)
            return passDate && passG
        }
    }

    private var anyFilterActive: Bool { isFilterEnabled || isGFilterEnabled }

    private var uploadAlertTitle: String {
        switch detector.uploadState {
        case .success: return loc("Upload Complete")
        case .failure: return loc("Upload Failed")
        default:       return ""
        }
    }

    private var uploadAlertMessage: String {
        switch detector.uploadState {
        case .success(let n): return String(format: loc("%d events uploaded to server."), n)
        case .failure(let m): return m
        default:              return ""
        }
    }

    var body: some View {
        NavigationStack {
            List {

                // ── Status card ───────────────────────────────────────────────
                Section {
                    StatusCard(detector: detector)
                }

                // ── Start / Stop ─────────────────────────────────────────────
                Section {
                    Button {
                        if detector.isRunning { detector.stop() } else { detector.start() }
                    } label: {
                        HStack {
                            Spacer()
                            Label(
                                loc(detector.isRunning ? "Stop Detection" : "Start Detection"),
                                systemImage: detector.isRunning ? "stop.circle.fill" : "play.circle.fill"
                            )
                            .font(.headline)
                            .foregroundColor(detector.isRunning ? .red : .green)
                            Spacer()
                        }
                    }
                }

                // ── Detection Settings ────────────────────────────────────────
                Section(header: Text(loc("Detection Settings"))) {
                    SettingRow(
                        label: loc("G-force Threshold"),
                        value: String(format: "%.1f G", detector.gThreshold)
                    ) {
                        Slider(value: $detector.gThreshold, in: 0.5...5.0, step: 0.1)
                    }
                    SettingRow(
                        label: loc("Min Speed"),
                        value: String(format: "%.0f km/h", detector.minSpeedKmh)
                    ) {
                        Slider(value: $detector.minSpeedKmh, in: 0...60, step: 5)
                    }
                    SettingRow(
                        label: loc("Cooldown"),
                        value: String(format: "%.1f s", detector.cooldownSeconds)
                    ) {
                        Slider(value: $detector.cooldownSeconds, in: 0.5...5.0, step: 0.5)
                    }
                }

                // ── Date Filter ───────────────────────────────────────────────
                Section(header: Text(loc("Filter"))) {
                    Toggle(loc("Filter by Date"), isOn: $isFilterEnabled.animation())
                    if isFilterEnabled {
                        DatePicker(loc("From"), selection: $filterFrom,
                                   in: ...filterTo,
                                   displayedComponents: [.date, .hourAndMinute])
                        DatePicker(loc("To"), selection: $filterTo,
                                   in: filterFrom...,
                                   displayedComponents: [.date, .hourAndMinute])
                    }

                    Toggle(loc("Filter by G-force"), isOn: $isGFilterEnabled.animation())
                    if isGFilterEnabled {
                        SettingRow(
                            label: loc("Min G"),
                            value: String(format: "%.1f G", filterMinG)
                        ) {
                            Slider(value: $filterMinG, in: 0...filterMaxG, step: 0.1)
                        }
                        SettingRow(
                            label: loc("Max G"),
                            value: String(format: "%.1f G", filterMaxG)
                        ) {
                            Slider(value: $filterMaxG, in: filterMinG...5.0, step: 0.1)
                        }
                    }
                }

                // ── Pothole Log ───────────────────────────────────────────────
                Section {
                    if detector.events.isEmpty {
                        Text(loc("No potholes detected yet."))
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else if filteredEvents.isEmpty {
                        Text(loc("No events in selected range."))
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(filteredEvents.reversed()) { event in
                            PotholeRow(event: event)
                        }
                    }
                } header: {
                    HStack {
                        Text(loc("Pothole Log"))
                        Spacer()
                        if !detector.events.isEmpty {
                            Group {
                                if anyFilterActive {
                                    Text(String(format: loc("%d of %d events"),
                                                filteredEvents.count, detector.events.count))
                                } else {
                                    Text(String(format: loc("%d events"), detector.events.count))
                                }
                            }
                            .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                // ── Delete filtered ───────────────────────────────────────────
                if anyFilterActive && !filteredEvents.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            showDeleteFilteredConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Label(
                                    String(format: loc("Delete %d Events"), filteredEvents.count),
                                    systemImage: "trash"
                                )
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(loc("Drive"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !detector.events.isEmpty {
                        // Upload
                        if case .uploading = detector.uploadState {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button {
                                detector.uploadEvents(filteredEvents)
                            } label: {
                                Image(systemName: "icloud.and.arrow.up")
                            }
                        }
                        Button { showMap = true } label: {
                            Image(systemName: "map")
                        }
                        Button { showExportSheet = true } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .confirmationDialog(
                loc("Clear pothole log?"),
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button(loc("Clear Log"), role: .destructive) { detector.clearLog() }
                Button(loc("Cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                String(format: loc("Delete %d filtered events?"), filteredEvents.count),
                isPresented: $showDeleteFilteredConfirm,
                titleVisibility: .visible
            ) {
                Button(loc("Delete"), role: .destructive) {
                    let ids = Set(filteredEvents.map(\.id))
                    detector.deleteEvents { ids.contains($0.id) }
                }
                Button(loc("Cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $showExportSheet) {
                ShareSheet(url: detector.logFileURL)
            }
            .sheet(isPresented: $showMap) {
                PotholeMapView(events: filteredEvents)
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = detector.isRunning }
            .onChange(of: detector.isRunning) { _, running in
                UIApplication.shared.isIdleTimerDisabled = running
            }
            .onChange(of: detector.uploadState) { _, state in
                if case .success = state { showUploadResult = true }
                if case .failure = state { showUploadResult = true }
            }
            .alert(uploadAlertTitle, isPresented: $showUploadResult) {
                Button(loc("OK")) { detector.uploadState = .idle }
            } message: {
                Text(uploadAlertMessage)
            }
        }
    }
}

// MARK: - Status Card

private struct StatusCard: View {
    @ObservedObject var detector: PotholeDetector

    var body: some View {
        VStack(spacing: 12) {
            // Status row
            HStack(spacing: 8) {
                Circle()
                    .fill(detector.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(detector.isRunning ? detector.statusMessage : loc("Idle"))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(detector.isRunning ? .primary : .secondary)
                Spacer()
            }

            // Gauge tiles
            HStack(spacing: 0) {
                GaugeTile(
                    label: loc("Speed"),
                    value: String(format: "%.0f", detector.currentSpeedKmh),
                    unit: "km/h",
                    color: .blue,
                    active: detector.isRunning
                )
                Divider().frame(height: 52)
                GaugeTile(
                    label: loc("Accel"),
                    value: String(format: "%.2f", detector.currentG),
                    unit: "G",
                    color: detector.currentG >= detector.gThreshold ? .red : .orange,
                    active: detector.isRunning
                )
                Divider().frame(height: 52)
                GaugeTile(
                    label: loc("Detected"),
                    value: "\(detector.events.count)",
                    unit: loc("holes"),
                    color: .purple,
                    active: true
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct GaugeTile: View {
    let label: String
    let value: String
    let unit:  String
    let color: Color
    let active: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(active ? color : Color(.secondaryLabel))
            Text(unit).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Setting Row

private struct SettingRow<S: View>: View {
    let label: String
    let value: String
    @ViewBuilder let slider: () -> S

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            slider()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Pothole Row

private struct PotholeRow: View {
    let event: PotholeEvent
    @State private var showShareSheet = false

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    private var googleMapsURL: URL {
        URL(string: "https://maps.google.com/?q=\(event.latitude),\(event.longitude)")!
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(df.string(from: event.timestamp))
                    .font(.subheadline.weight(.medium))
                Text(String(format: "%.5f°, %.5f°", event.latitude, event.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f G", event.peakG))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.orange)
                Text(String(format: "%.0f km/h", event.speedKmh))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .contextMenu {
            Button {
                UIApplication.shared.open(googleMapsURL)
            } label: {
                Label(loc("Open in Google Maps"), systemImage: "map")
            }
            Button {
                showShareSheet = true
            } label: {
                Label(loc("Share Location"), systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(url: googleMapsURL)
        }
    }
}

// MARK: - Pothole Map

struct PotholeMapView: View {
    let events: [PotholeEvent]

    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.5, longitude: 25.5),
        span:   MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
    ))
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(events) { event in
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: event.latitude, longitude: event.longitude
                    ), anchor: .bottom) {
                        PotholePin(peakG: event.peakG)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(loc("Pothole Map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(loc("Done")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { fitEvents() }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            .onAppear { fitEvents() }
        }
    }

    private func fitEvents() {
        guard !events.isEmpty else { return }
        let lats = events.map(\.latitude)
        let lons = events.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude:  (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta:  max(0.005, (maxLat - minLat) * 1.5),
                longitudeDelta: max(0.005, (maxLon - minLon) * 1.5)
            )
        ))
    }
}

private struct PotholePin: View {
    let peakG: Double

    /// Red when ≥ 3 G, orange 2–3 G, yellow below 2 G
    private var color: Color {
        peakG >= 3.0 ? .red : peakG >= 2.0 ? .orange : .yellow
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
            }
            Triangle()
                .fill(color)
                .frame(width: 9, height: 6)
        }
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

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

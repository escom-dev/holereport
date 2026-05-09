import Foundation
import CoreMotion
import CoreLocation
import UIKit

// MARK: - Upload state

enum PotholeUploadState: Equatable {
    case idle
    case uploading
    case success(Int)   // number of events inserted on server
    case failure(String)
}

// MARK: - Event model

struct PotholeEvent: Codable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)_\(latitude)_\(longitude)" }
    let timestamp:  Date
    let latitude:   Double
    let longitude:  Double
    let speedKmh:   Double
    let peakG:      Double
    let accuracyM:  Double
}

// MARK: - Detector

final class PotholeDetector: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = PotholeDetector()

    // MARK: Tunable settings (persisted in UserDefaults)

    @Published var gThreshold: Double {
        didSet { UserDefaults.standard.set(gThreshold,      forKey: "pd_gThreshold") }
    }
    @Published var minSpeedKmh: Double {
        didSet { UserDefaults.standard.set(minSpeedKmh,     forKey: "pd_minSpeedKmh") }
    }
    @Published var cooldownSeconds: Double {
        didSet { UserDefaults.standard.set(cooldownSeconds, forKey: "pd_cooldown") }
    }

    // MARK: Live state (read-only from views)

    @Published private(set) var isRunning      = false
    @Published private(set) var currentSpeedKmh: Double = 0
    @Published private(set) var currentG:        Double = 0
    @Published private(set) var events:          [PotholeEvent] = []
    @Published private(set) var statusMessage    = ""
    @Published var uploadState: PotholeUploadState = .idle

    var logFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pothole_log.csv")
    }

    // MARK: Privates

    private let motionManager   = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var lastEventTime:   Date = .distantPast
    private let iso8601 = ISO8601DateFormatter()

    private override init() {
        let ud = UserDefaults.standard
        gThreshold      = ud.double(forKey: "pd_gThreshold")      .nonZeroOrDefault(1.5)
        minSpeedKmh     = ud.double(forKey: "pd_minSpeedKmh")     .nonZeroOrDefault(10.0)
        cooldownSeconds = ud.double(forKey: "pd_cooldown")        .nonZeroOrDefault(1.0)
        super.init()
        locationManager.delegate        = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        loadCSV()
    }

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }
        isRunning     = true
        statusMessage = NSLocalizedString("Starting…", comment: "")
        locationManager.startUpdatingLocation()
        startMotion()
    }

    func stop() {
        isRunning     = false
        statusMessage = NSLocalizedString("Stopped", comment: "")
        motionManager.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
        currentSpeedKmh = 0
        currentG        = 0
    }

    func clearLog() {
        events = []
        rewriteCSV()
    }

    /// Upload `eventsToUpload` to the server. Updates `uploadState` on main thread.
    func uploadEvents(_ eventsToUpload: [PotholeEvent]) {
        guard !eventsToUpload.isEmpty else { return }
        guard let url = URL(string: "\(UploadManager.serverURL)/api/upload_potholes.php") else {
            uploadState = .failure("Invalid server URL"); return
        }
        uploadState = .uploading

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let payload: [String: Any] = [
            "device_id": deviceId,
            "events": eventsToUpload.map { e in [
                "timestamp":  iso8601.string(from: e.timestamp),
                "latitude":   e.latitude,
                "longitude":  e.longitude,
                "speed_kmh":  e.speedKmh,
                "peak_g":     e.peakG,
                "accuracy_m": e.accuracyM,
            ] as [String: Any] }
        ]

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json",       forHTTPHeaderField: "Content-Type")
        req.setValue(UploadManager.apiKey,     forHTTPHeaderField: "X-API-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.uploadState = .failure(error.localizedDescription); return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    self?.uploadState = .failure(NSLocalizedString("Invalid server response", comment: ""))
                    return
                }
                if let inserted = json["inserted"] as? Int {
                    self?.uploadState = .success(inserted)
                } else if let msg = json["error"] as? String {
                    self?.uploadState = .failure(msg)
                } else {
                    self?.uploadState = .failure(NSLocalizedString("Unexpected response", comment: ""))
                }
            }
        }.resume()
    }

    /// Remove all events matching the predicate and rewrite the CSV.
    func deleteEvents(where predicate: (PotholeEvent) -> Bool) {
        events.removeAll(where: predicate)
        rewriteCSV()
    }

    // MARK: - Motion

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            statusMessage = NSLocalizedString("Accelerometer not available", comment: "")
            isRunning = false
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0   // 100 Hz
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let ua = motion.userAcceleration
            let g  = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)
            self.currentG = g
            if g >= self.gThreshold { self.recordEventIfArmed(peakG: g) }
        }
    }

    private func recordEventIfArmed(peakG: Double) {
        guard currentSpeedKmh >= minSpeedKmh,
              Date().timeIntervalSince(lastEventTime) >= cooldownSeconds,
              let location = currentLocation else { return }
        lastEventTime = Date()
        let event = PotholeEvent(
            timestamp: lastEventTime,
            latitude:  location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speedKmh:  currentSpeedKmh,
            peakG:     peakG,
            accuracyM: location.horizontalAccuracy
        )
        events.append(event)
        appendCSV(event)
        statusMessage = String(
            format: NSLocalizedString("Pothole! %.1f G at %.0f km/h", comment: ""),
            peakG, currentSpeedKmh
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        currentLocation = loc
        currentSpeedKmh = max(0, loc.speed) * 3.6
        guard isRunning else { return }
        if currentSpeedKmh >= minSpeedKmh {
            statusMessage = String(
                format: NSLocalizedString("Armed • %.0f km/h", comment: ""), currentSpeedKmh)
        } else {
            statusMessage = String(
                format: NSLocalizedString("Waiting • %.0f km/h", comment: ""), currentSpeedKmh)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus),
           isRunning {
            locationManager.startUpdatingLocation()
        }
    }

    // MARK: - CSV persistence

    private var csvHeader: String { "timestamp,latitude,longitude,speed_kmh,peak_g,accuracy_m\n" }

    private func loadCSV() {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            try? csvHeader.write(to: logFileURL, atomically: true, encoding: .utf8)
            return
        }
        let lines = content.components(separatedBy: "\n").dropFirst()
        events = lines.compactMap { line -> PotholeEvent? in
            let p = line.components(separatedBy: ",")
            guard p.count >= 6,
                  let date = iso8601.date(from: p[0]),
                  let lat  = Double(p[1]),
                  let lon  = Double(p[2]),
                  let spd  = Double(p[3]),
                  let g    = Double(p[4]),
                  let acc  = Double(p[5]) else { return nil }
            return PotholeEvent(timestamp: date, latitude: lat, longitude: lon,
                                speedKmh: spd, peakG: g, accuracyM: acc)
        }
    }

    private func rewriteCSV() {
        var content = csvHeader
        for event in events {
            content += String(
                format: "%@,%.6f,%.6f,%.1f,%.3f,%.1f\n",
                iso8601.string(from: event.timestamp),
                event.latitude, event.longitude,
                event.speedKmh, event.peakG, event.accuracyM
            )
        }
        try? content.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    private func appendCSV(_ event: PotholeEvent) {
        let line = String(
            format: "%@,%.6f,%.6f,%.1f,%.3f,%.1f\n",
            iso8601.string(from: event.timestamp),
            event.latitude, event.longitude,
            event.speedKmh, event.peakG, event.accuracyM
        )
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) { handle.write(data) }
            try? handle.close()
        } else {
            try? (csvHeader + line).write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Helpers

private extension Double {
    func nonZeroOrDefault(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}

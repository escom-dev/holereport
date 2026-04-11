import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()  // Reuse single geocoder instance
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentAddress: String?
    
    // Throttle geocoding: only re-geocode when moved >50m or after 60s
    private var lastGeocodedLocation: CLLocation?
    private var lastGeocodeTime: Date = .distantPast
    private let geocodeDistanceThreshold: CLLocationDistance = 50  // meters
    private let geocodeTimeThreshold: TimeInterval = 60            // seconds
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Use significantLocationChange filter to reduce update frequency
        manager.distanceFilter = 10  // Only fire updates after 10m movement
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdating() {
        manager.startUpdatingLocation()
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
    
    /// Call once when a photo is captured to get the freshest address for that location
    func geocodeOnce(for location: CLLocation, completion: @escaping (String?) -> Void) {
        guard !geocoder.isGeocoding else {
            completion(currentAddress)
            return
        }
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }
            var parts: [String] = []
            if let name = placemark.name       { parts.append(name) }
            if let city = placemark.locality   { parts.append(city) }
            if let country = placemark.country { parts.append(country) }
            let address = parts.joined(separator: ", ")
            DispatchQueue.main.async { completion(address) }
        }
    }
    
    // MARK: - Private throttled geocode
    
    private func throttledReverseGeocode(_ location: CLLocation) {
        let now = Date()
        let movedFar: Bool
        if let last = lastGeocodedLocation {
            movedFar = location.distance(from: last) > geocodeDistanceThreshold
        } else {
            movedFar = true
        }
        let longAgo = now.timeIntervalSince(lastGeocodeTime) > geocodeTimeThreshold
        
        guard (movedFar || longAgo), !geocoder.isGeocoding else { return }
        
        lastGeocodedLocation = location
        lastGeocodeTime = now
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            var parts: [String] = []
            if let name = placemark.name       { parts.append(name) }
            if let city = placemark.locality   { parts.append(city) }
            if let country = placemark.country { parts.append(country) }
            let address = parts.joined(separator: ", ")
            DispatchQueue.main.async { self?.currentAddress = address }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,          // negative = invalid
              location.horizontalAccuracy < 200 else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
            self.throttledReverseGeocode(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Suppress common non-fatal errors
        let nsError = error as NSError
        guard nsError.code != CLError.locationUnknown.rawValue else { return }
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdating()
            default:
                break
            }
        }
    }
}

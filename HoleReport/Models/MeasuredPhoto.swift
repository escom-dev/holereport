import Foundation
import CoreLocation
import UIKit

struct MeasuredPhoto: Identifiable, Codable {
    let id: UUID
    let imageFileName: String
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let measurements: [Measurement]
    let locationAddress: String?
    var isUploaded: Bool = false
    var uploadedAt: Date? = nil
    var categoryId: Int? = nil
    var categoryName: String? = nil

    init(
        id: UUID = UUID(),
        imageFileName: String,
        timestamp: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        measurements: [Measurement] = [],
        locationAddress: String? = nil,
        isUploaded: Bool = false,
        uploadedAt: Date? = nil,
        categoryId: Int? = nil,
        categoryName: String? = nil
    ) {
        self.id = id
        self.imageFileName = imageFileName
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.measurements = measurements
        self.locationAddress = locationAddress
        self.isUploaded = isUploaded
        self.uploadedAt = uploadedAt
        self.categoryId = categoryId
        self.categoryName = categoryName
    }
    
    var coordinateString: String {
        guard let lat = latitude, let lon = longitude else { return "No GPS" }
        return String(format: "%.6f°, %.6f°", lat, lon)
    }
    
    var altitudeString: String {
        guard let alt = altitude else { return "N/A" }
        return String(format: "%.1f m", alt)
    }
}

struct Measurement: Identifiable, Codable {
    let id: UUID
    let label: String
    let value: Float   // in meters
    let startPoint: CGPoint
    let endPoint: CGPoint
    var startWorld: [Float]?   // SIMD3<Float> stored as [x, y, z]
    var endWorld: [Float]?

    init(id: UUID = UUID(), label: String, value: Float, startPoint: CGPoint, endPoint: CGPoint,
         startWorld: [Float]? = nil, endWorld: [Float]? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.startWorld = startWorld
        self.endWorld = endWorld
    }
    
    var displayString: String {
        if value >= 1.0 {
            return String(format: "%.2f m", value)
        } else {
            return String(format: "%.1f cm", value * 100)
        }
    }
}

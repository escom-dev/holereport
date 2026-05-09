import Foundation
import UIKit

/// Handles uploading MeasuredPhoto + image data to the MeasureSnap Apache server.
class UploadManager: ObservableObject {

    // ── Configuration ─────────────────────────────────────────────────────────
    static let serverURL = "https://hrep.haskovo.org"
    static let apiKey    = "api-key"
    // ─────────────────────────────────────────────────────────────────────────

    enum UploadError: LocalizedError {
        case noServerConfigured
        case imageConversionFailed
        case serverError(Int, String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .noServerConfigured:        return "Server URL not configured. Check Settings."
            case .imageConversionFailed:     return "Could not convert image for upload."
            case .serverError(let c, let m): return "Server error \(c): \(m)"
            case .networkError(let e):       return "Network error: \(e.localizedDescription)"
            }
        }
    }

    @Published var isUploading = false
    @Published var lastUploadURL: String?
    @Published var lastError: String?

    // ── Category model ────────────────────────────────────────────────────────
    struct Category: Identifiable, Decodable {
        let id: Int
        let slug: String
        let name: String
        let nameEn: String
        let color: String
        enum CodingKeys: String, CodingKey {
            case id, slug, name, color
            case nameEn = "name_en"
        }
    }

    // ── Fetch categories from server ──────────────────────────────────────────
    func fetchCategories(completion: @escaping ([Category]) -> Void) {
        guard let url = URL(string: "\(Self.serverURL)/api/categories.php") else {
            completion([]); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONDecoder().decode([String: [Category]].self, from: data),
                  let cats = json["categories"] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            DispatchQueue.main.async { completion(cats) }
        }.resume()
    }

    // ── Main upload function ──────────────────────────────────────────────────
    func upload(image: UIImage, photo: MeasuredPhoto, categoryId: Int? = nil, completion: @escaping (Result<String, UploadError>) -> Void) {
        let base = Self.serverURL

        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            completion(.failure(.imageConversionFailed))
            return
        }

        guard let url = URL(string: "\(base)/api/upload.php") else {
            completion(.failure(.noServerConfigured))
            return
        }

        DispatchQueue.main.async { self.isUploading = true }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60

        let boundary = "MeasureSnap_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")

        var body = Data()

        // ── Build measurements JSON ───────────────────────────────────────────
        let measArray: [[String: Any]] = photo.measurements.map { m in
            ["label": m.label, "value": m.value, "display": m.displayString]
        }
        let measJSON = (try? JSONSerialization.data(withJSONObject: measArray, options: [])).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[]"

        // ── Form fields ───────────────────────────────────────────────────────
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        var fields: [(String, String)] = [
            ("api_key",      Self.apiKey),
            ("device_id",    deviceId),
            ("latitude",     photo.latitude.map  { String($0) } ?? ""),
            ("longitude",    photo.longitude.map { String($0) } ?? ""),
            ("altitude",     photo.altitude.map  { String($0) } ?? ""),
            ("address",      photo.locationAddress ?? ""),
            ("photo_date",   ISO8601DateFormatter().string(from: photo.timestamp)),
            ("measurements", measJSON),
            ("device_note",  "iPhone Hole Report App"),
        ]
        if let cid = categoryId { fields.append(("category_id", String(cid))) }

        for (name, value) in fields {
            body.appendField(name: name, value: value, boundary: boundary)
        }

        // ── Image file field ──────────────────────────────────────────────────
        body.appendFile(name: "photo",
                        filename: photo.imageFileName,
                        mimeType: "image/jpeg",
                        data: imageData,
                        boundary: boundary)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // ── Send ──────────────────────────────────────────────────────────────
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.isUploading = false }

            if let error = error {
                DispatchQueue.main.async { self?.lastError = error.localizedDescription }
                completion(.failure(.networkError(error)))
                return
            }

            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.networkError(URLError(.badServerResponse))))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.serverError(http.statusCode, "Invalid response")))
                return
            }

            if http.statusCode == 201, let photoURL = json["photo_url"] as? String {
                DispatchQueue.main.async {
                    self?.lastUploadURL = photoURL
                    self?.lastError = nil
                }
                completion(.success(photoURL))
            } else {
                let msg = json["error"] as? String ?? "Unknown server error"
                DispatchQueue.main.async { self?.lastError = msg }
                completion(.failure(.serverError(http.statusCode, msg)))
            }
        }.resume()
    }
}

// MARK: - Multipart helpers

private extension Data {
    mutating func appendField(name: String, value: String, boundary: String) {
        guard !value.isEmpty else { return }
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, data fileData: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}

import Foundation
import UIKit

class PhotoStore: ObservableObject {
    @Published var photos: [MeasuredPhoto] = []
    
    private let dataFileName = "photos.json"
    private let imagesDirectory: URL
    private let dataFileURL: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        imagesDirectory = docs.appendingPathComponent("CapturedImages", isDirectory: true)
        dataFileURL = docs.appendingPathComponent(dataFileName)
        
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        loadPhotos()
    }
    
    func save(image: UIImage, photo: MeasuredPhoto) {
        // Save image
        if let data = image.jpegData(compressionQuality: 0.85) {
            let imageURL = imagesDirectory.appendingPathComponent(photo.imageFileName)
            try? data.write(to: imageURL)
        }
        
        DispatchQueue.main.async {
            self.photos.insert(photo, at: 0)
            self.saveMetadata()
        }
    }
    
    func loadImage(fileName: String) -> UIImage? {
        let url = imagesDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    func markUploaded(photo: MeasuredPhoto) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        photos[index].isUploaded = true
        photos[index].uploadedAt = Date()
        saveMetadata()
    }

    func delete(photo: MeasuredPhoto) {
        let imageURL = imagesDirectory.appendingPathComponent(photo.imageFileName)
        try? FileManager.default.removeItem(at: imageURL)
        photos.removeAll { $0.id == photo.id }
        saveMetadata()
    }
    
    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(photos) {
            try? data.write(to: dataFileURL)
        }
    }
    
    private func loadPhotos() {
        guard let data = try? Data(contentsOf: dataFileURL),
              let decoded = try? JSONDecoder().decode([MeasuredPhoto].self, from: data) else { return }
        photos = decoded
    }
}

import SwiftUI

struct ContentView: View {
    @StateObject private var photoStore    = PhotoStore()
    @StateObject private var uploadManager = UploadManager()

    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            CameraView()
                .tabItem { Label("Camera", systemImage: "camera.fill") }
                .tag(0)

            GalleryView()
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle.angled") }
                .tag(1)

            MapTabView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(3)
        }
        .accentColor(.blue)
        .environmentObject(photoStore)
        .environmentObject(uploadManager)
    }
}

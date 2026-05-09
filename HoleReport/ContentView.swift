import SwiftUI

struct ContentView: View {
    @StateObject private var photoStore    = PhotoStore()
    @StateObject private var uploadManager = UploadManager()
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            CameraView()
                .tabItem { Label(loc("Camera"), systemImage: "camera.fill") }
                .tag(0)

            GalleryView()
                .tabItem { Label(loc("Gallery"), systemImage: "photo.on.rectangle.angled") }
                .tag(1)

            MapTabView()
                .tabItem { Label(loc("Map"), systemImage: "map.fill") }
                .tag(2)

            DriveView()
                .tabItem { Label(loc("Drive"), systemImage: "car.fill") }
                .tag(3)

            SettingsView()
                .tabItem { Label(loc("Settings"), systemImage: "gear") }
                .tag(4)
        }
        // Changing the id destroys + recreates the TabView and all child views,
        // flushing SwiftUI's cached localised strings.
        .id(languageManager.currentLanguage)
        .accentColor(.blue)
        .environmentObject(photoStore)
        .environmentObject(uploadManager)
    }
}

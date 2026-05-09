# CLAUDE.md — MeasureSnap Android

## Project Overview
Android port of the MeasureSnap iOS app. Uses ARCore for AR-based distance measurements, GPS tagging, and uploads annotated photos to the same PHP server.

## Requirements
- Android Studio Hedgehog or newer
- Android SDK 35, minSdk 26 (Android 8.0)
- Physical Android device with ARCore support (NOT an emulator — ARCore requires real hardware with depth sensor support)
- Google Play Services installed on device

## Build & Run
1. Open `MeasureSnapAndroid/` in Android Studio
2. Sync Gradle
3. Connect an ARCore-compatible Android device
4. Run -> select your device -> Build & Run (Shift+F10)

## Architecture — mirrors iOS app exactly

### Structure
```
app/src/main/java/com/measuresnap/
├── HoleReportApp.kt          # Application class
├── MainActivity.kt             # Single Activity + NavHost + bottom navigation
├── models/
│   └── MeasuredPhoto.kt       # Data models (Kotlin data classes)
├── managers/
│   ├── LocationManager.kt     # FusedLocationProvider + Geocoder (mirrors iOS LocationManager)
│   ├── PhotoStore.kt          # JSON persistence in filesDir (mirrors iOS PhotoStore)
│   └── UploadManager.kt       # OkHttp multipart upload (mirrors iOS UploadManager)
├── viewmodels/
│   └── CameraViewModel.kt     # ARCore session + measurement state machine
└── ui/
    ├── camera/CameraScreen.kt     # AR view + HUD + shutter
    ├── gallery/GalleryScreen.kt   # Photo grid + detail dialog
    ├── settings/SettingsScreen.kt # Server URL + API key
    └── theme/Theme.kt             # Dark theme matching web UI colours
```

### AR Measurement Flow
1. User taps "Measure" -> state: IDLE -> PLACING_FIRST
2. Tap on AR surface -> ARCore hit test -> Anchor created -> state: PLACING_SECOND
3. Tap second surface -> distance computed via 3D Euclidean distance -> state: PLACING_FIRST (loop)
4. Shutter button -> capture ARCore frame bitmap -> save JPEG + metadata -> upload

### Key difference from iOS
- ARKit -> ARCore (Google)
- RealityKit entities -> SceneView library (io.github.sceneview:arsceneview)
- SwiftUI -> Jetpack Compose
- @AppStorage -> DataStore Preferences
- MVVM pattern identical

## Uploading
Same server as iOS — same `/api/upload.php` endpoint, same multipart form fields, same `X-API-Key` header. Configure in Settings tab.

## ARCore device compatibility
Check https://developers.google.com/ar/devices for supported devices.
Minimum: any device with ARCore support (most Android phones from 2018+).

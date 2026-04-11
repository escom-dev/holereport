# MeasureSnap 📸📐📍

An iPhone app that captures photos with real-world AR dimension measurements and GPS coordinates embedded in each shot.

---

## Features

| Feature | Details |
|---|---|
| 📸 **AR Camera** | Live ARKit camera feed with plane detection |
| 📐 **Dimension Measuring** | Tap two points in 3D space → get real-world distance in cm/m |
| 📍 **GPS Tagging** | Latitude, longitude, altitude with accuracy indicator |
| 🗺 **Reverse Geocoding** | Human-readable address from GPS coords |
| 🖼 **Gallery** | Browse all captured photos with metadata |
| 📤 **Share** | Export photo + measurements + GPS as image + text |
| 🗑 **Delete** | Remove photos from the gallery |

---

## Requirements

- **iPhone** with A12 chip or newer (iPhone XS / XR and later)
- **iOS 16.0+**
- **ARKit support** (requires physical device — does NOT run on Simulator)
- **Xcode 15+**

---

## Setup Instructions

### 1. Open in Xcode
```bash
open MeasureSnap.xcodeproj
```

### 2. Set your Team
- Select the `MeasureSnap` target
- Go to **Signing & Capabilities**
- Set your Apple Developer **Team**
- Xcode will auto-manage provisioning

### 3. Update Bundle ID
In `project.pbxproj` or Target Settings, change:
```
com.yourcompany.MeasureSnap
```
to your own unique bundle identifier.

### 4. Connect iPhone & Build
- Select your iPhone as the run destination
- Press **⌘R** to build and run

---

## How to Use

### Taking a Photo
1. Open the app — camera starts automatically
2. The **GPS bar** at the top shows your current coordinates
3. Tap the **camera button** to capture a photo

### Measuring Dimensions
1. Tap **Measure** button (ruler icon)
2. Point camera at a flat surface — ARKit detects planes
3. **Tap first point** on the surface
4. **Tap second point** — the distance appears in real-time
5. Add more measurements before capturing
6. Tap the **camera button** to save photo with all measurements
7. Tap **Clear** to remove all measurement markers

### Viewing Photos
1. Switch to the **Gallery** tab
2. Tap any photo to see full details:
   - GPS coordinates and altitude
   - Street address (reverse geocoded)
   - All measurements taken
3. Tap **Share** to export photo + metadata

---

## Project Structure

```
MeasureSnap/
├── MeasureSnapApp.swift          # App entry point
├── ContentView.swift              # Tab navigation
├── Models/
│   └── MeasuredPhoto.swift        # Photo + Measurement data models
├── Managers/
│   ├── LocationManager.swift      # CoreLocation GPS manager
│   ├── PhotoStore.swift           # Photo persistence (JSON + images)
│   └── UploadManager.swift        # Server upload handler (multipart form)
├── ViewModels/
│   └── CameraViewModel.swift      # ARKit logic, measurement engine
├── Views/
│   ├── CameraView.swift           # AR camera + HUD + controls
│   └── GalleryView.swift          # Photo gallery + detail view
└── Resources/
    └── Info.plist                 # Permissions + configuration
```

---

## Permissions Required

The app requests these permissions on first launch:

| Permission | Purpose |
|---|---|
| **Camera** | AR camera feed and photo capture |
| **Location (When In Use)** | GPS tagging of photos |
| **Photo Library Add** | Saving photos to Camera Roll (optional) |

---

## Technical Details

- **ARKit** + **RealityKit** for AR plane detection and 3D raycasting
- **CoreLocation** with `kCLLocationAccuracyBestForNavigation` for precise GPS
- **CLGeocoder** for reverse geocoding addresses
- **SwiftUI** for all UI, with `UIViewRepresentable` wrapping ARView
- **Codable** models persisted as JSON in the app's Documents directory
- **UIActivityViewController** for sharing

---

## Measurement Accuracy

Measurement accuracy depends on:
- Surface detection quality (flat, textured surfaces work best)
- Lighting conditions (brighter = more accurate plane detection)
- Distance to measured object (0.3m–5m optimal range)
- Device motion stability (hold steady when placing points)

Typical accuracy: **±1–3 cm** in good conditions.

---

## Troubleshooting

**"No surface detected"**
→ Move camera slowly over a flat, textured surface. Avoid plain white walls.

**GPS showing "Acquiring..."**
→ Ensure Location permission is granted in Settings → Privacy → Location Services → MeasureSnap.

**Build fails with "ARKit not available"**
→ Must build to a physical iPhone, not the Simulator.

---

## License
MIT — free to use and modify.

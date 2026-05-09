# Hole Report

An iPhone app that combines AR measurements, GPS photo logging, and automatic pothole detection while driving.

---

## Features

### 📸 Camera & AR Measurements
| Feature | Details |
|---|---|
| **AR Camera** | Live ARKit camera feed with plane detection |
| **Dimension Measuring** | Tap two points in 3D space → real-world distance in cm/m |
| **GPS Tagging** | Latitude, longitude, altitude stamped on every photo |
| **Reverse Geocoding** | Human-readable street address from GPS coordinates |
| **Photo Categories** | Tag photos by category before uploading |
| **Server Upload** | Upload photos + measurements to the Hole Report server |

### 🖼 Gallery
| Feature | Details |
|---|---|
| **Browse** | All captured photos with metadata |
| **Full Detail** | GPS, altitude, address, measurements per photo |
| **Share** | Export photo + metadata as image |
| **Upload / Retry** | Upload individual photos to the server |

### 🗺 Map
| Feature | Details |
|---|---|
| **Photo Map** | All geotagged photos as pins on a map |
| **Clustering** | Multiple photos at the same location grouped into one pin |
| **Detail Card** | Tap a pin to preview the photo and open its detail view |
| **Fit All** | One-tap button to zoom map to show all markers |

### 🚗 Drive — Pothole Detector
| Feature | Details |
|---|---|
| **Automatic Detection** | Uses accelerometer (`CMDeviceMotion`) at 100 Hz to detect road impacts |
| **Speed Gating** | Only arms when GPS speed exceeds a configurable threshold (default 10 km/h) |
| **G-force Threshold** | Configurable impact sensitivity (default 1.5 G user acceleration) |
| **Cooldown** | Prevents logging the same hole multiple times (default 1 s) |
| **Live Gauges** | Real-time speed, G-force, and detected hole count |
| **CSV Log** | Events saved to `Documents/pothole_log.csv` — timestamp, GPS, speed, peak G |
| **Date Filter** | Filter the log by From / To date and time |
| **G-force Filter** | Filter the log by Min / Max G-force range |
| **Delete Filtered** | Remove only the filtered events from the log |
| **Pothole Map** | View all detected potholes as colour-coded pins (yellow / orange / red by severity) |
| **Upload to Server** | Send detected events (or filtered subset) to the server API |
| **Export CSV** | Share the log file via the iOS share sheet |
| **Google Maps** | Long-press any event row → Open in Google Maps or share the location URL |

### 🌐 Localisation
- **English** and **Bulgarian** (Български)
- In-app language switcher in Settings — no app restart required

---

## Requirements

- **iPhone** with A12 chip or newer (iPhone XS / XR and later)
- **iOS 17.0+**
- **ARKit support** — physical device required, Simulator will not work
- **Xcode 15+**

---

## Setup

### 1. Open in Xcode
```bash
open HoleReport.xcodeproj
```

### 2. Set Signing Team
- Select the `HoleReport` target → **Signing & Capabilities**
- Set your Apple Developer **Team**

### 3. Build & Run
- Select a connected iPhone as the run destination
- **⌘R** to build and run

---

## How to Use

### Taking a Measured Photo
1. Open the **Camera** tab — AR camera starts automatically
2. Tap **Measure** to enter measurement mode
3. Point at a surface and tap two points to measure a distance
4. Tap the capture button to save the photo with all measurements embedded
5. Choose a category and tap **Upload** to send to the server

### Detecting Potholes While Driving
1. Open the **Drive** tab
2. Adjust the G-force threshold, minimum speed, and cooldown if needed
3. Tap **Start Detection** — keep the phone mounted in the car
4. Drive normally — potholes are logged automatically when an impact exceeds the threshold at speed
5. Tap **Stop Detection** when done
6. Use the **Filter** section to narrow the log by date range or G-force severity
7. Tap the **map icon** to see all detected potholes on a map
8. Tap the **cloud icon** to upload the (filtered) events to the server
9. Long-press any event row to **Open in Google Maps** or **Share Location**

---

## Project Structure

```
HoleReport/
├── HoleReportApp.swift
├── ContentView.swift               # Tab navigation (Camera / Gallery / Map / Drive / Settings)
├── Models/
│   └── MeasuredPhoto.swift         # Photo + Measurement data models
├── Managers/
│   ├── LocationManager.swift       # CoreLocation GPS + reverse geocoding
│   ├── PhotoStore.swift            # Photo persistence (JSON + JPEG files)
│   ├── UploadManager.swift         # Photo upload — multipart/form-data POST
│   ├── PotholeDetector.swift       # Accelerometer-based pothole detection + CSV log
│   └── LanguageManager.swift       # In-app language switching (EN / BG)
├── ViewModels/
│   └── CameraViewModel.swift       # ARKit plane detection + measurement engine
├── Views/
│   ├── WelcomeView.swift           # Onboarding screen
│   ├── CameraView.swift            # AR camera + HUD + controls
│   ├── GalleryView.swift           # Photo gallery + detail view
│   ├── MapView.swift               # Clustered photo map
│   ├── DriveView.swift             # Pothole detector UI + pothole map
│   └── SettingsView.swift          # Server config + language picker
└── Resources/
    ├── Info.plist
    ├── Assets.xcassets
    ├── en.lproj/Localizable.strings
    └── bg.lproj/Localizable.strings
```

---

## Server API

The app connects to a PHP / PostgreSQL backend at the configured server URL.

| Endpoint | Method | Description |
|---|---|---|
| `/api/upload.php` | POST | Upload a photo with GPS + measurements |
| `/api/upload_potholes.php` | POST | Upload pothole events (JSON array) |
| `/api/list.php` | GET | List uploaded photos |
| `/api/categories.php` | GET | Fetch photo categories |
| `/api/create_user.php` | POST | Create a web login account |
| `/api/status.php` | GET | Server health check |

### Pothole upload payload
```json
{
  "device_id": "UUID",
  "events": [
    {
      "timestamp": "2026-04-28T10:23:45Z",
      "latitude": 41.99812,
      "longitude": 25.48763,
      "speed_kmh": 47.3,
      "peak_g": 2.14,
      "accuracy_m": 4.2
    }
  ]
}
```
Response: `{ "inserted": 1, "skipped": 0, "total_sent": 1 }`

Duplicate events (same device + timestamp + coordinates) are silently ignored on re-upload.

---

## Permissions Required

| Permission | Purpose |
|---|---|
| **Camera** | AR camera feed and photo capture |
| **Location (When In Use)** | GPS tagging of photos and speed reading for pothole detection |
| **Photo Library Add** | Saving photos to Camera Roll (optional) |

---

## Technical Stack

| Component | Technology |
|---|---|
| UI | SwiftUI (iOS 17+) |
| AR & Measurement | ARKit + RealityKit |
| Pothole Detection | CoreMotion `CMDeviceMotion` |
| Maps | MapKit (new `Map` / `MapCameraPosition` API) |
| GPS | CoreLocation |
| Persistence | JSON + JPEG in Documents directory; CSV for pothole log |
| Localisation | `.lproj` string bundles + runtime bundle switching |
| Server | PHP 8 + PostgreSQL on Apache |

---

## Pothole Detection — How It Works

1. `CMDeviceMotion` samples `userAcceleration` at **100 Hz** (gravity already removed by CoreMotion)
2. The total acceleration magnitude `√(x²+y²+z²)` is computed each sample
3. If magnitude ≥ **G threshold** AND GPS speed ≥ **min speed** AND cooldown has elapsed → event is recorded
4. Each event stores: timestamp, GPS coordinates, speed, peak G-force, GPS accuracy
5. Events are appended to `pothole_log.csv` immediately and kept in memory for display

Colour coding on the map: **yellow** < 2 G · **orange** 2–3 G · **red** ≥ 3 G

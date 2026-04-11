# HoleReport — Complete System
### iPhone App + Apache/PHP Server + Web Gallery

---

## Architecture

```
iPhone App  ──→  Apache Server (PHP)  ──→  Browser Gallery
  (ARKit)          /api/upload.php          index.html
  (CoreLocation)   /uploads/photos
  (SwiftUI)        /api/list.php
```

---

## Part 1 — Server Setup (Linux)

### Requirements
- Ubuntu 20.04 / 22.04 / 24.04  **or**  Debian 11 / 12
- A static IP or domain name reachable from your iPhone (same Wi-Fi LAN is fine)
- Root / sudo access

### One-command install
```bash
# Copy the holereport-server folder to your server, then:
sudo bash install.sh
```

The installer:
1. Installs Apache2 + PHP + php-gd (for thumbnails)
2. Creates `/var/www/holereport/` with correct permissions
3. Generates a random API key
4. Writes the Apache virtual host config
5. Opens ports 80 / 443 in UFW (if present)
6. Prints your server IP and API key

### Manual setup (if you prefer)
```bash
sudo apt-get install apache2 php libapache2-mod-php php-gd
sudo mkdir -p /var/www/holereport/{public,api,uploads/{thumbs,meta}}
sudo cp -r public/. /var/www/holereport/public/
sudo cp -r api/.    /var/www/holereport/api/
sudo chown -R www-data:www-data /var/www/holereport
sudo chmod -R 775 /var/www/holereport/uploads
sudo cp holereport.conf /etc/apache2/sites-available/
sudo a2ensite holereport
sudo a2enmod rewrite headers
sudo systemctl restart apache2
```

Set your API key in Apache's environment:
```bash
# In /etc/apache2/sites-available/holereport.conf, inside <VirtualHost>:
SetEnv MEASURESNAP_API_KEY your-secret-key-here
```

### API Endpoints

| Method | URL | Purpose |
|---|---|---|
| `POST` | `/api/upload.php` | Upload a photo (requires `X-API-Key` header) |
| `GET`  | `/api/list.php?page=1&limit=20&sort=newest` | List all photos |
| `GET`  | `/api/photo.php?id=UUID` | Single photo metadata |
| `POST` | `/api/delete.php` | Delete a photo (requires key) |

### Upload form fields

| Field | Type | Description |
|---|---|---|
| `photo` | file | JPEG/PNG image (max 30 MB) |
| `latitude` | float | GPS latitude |
| `longitude` | float | GPS longitude |
| `altitude` | float | Altitude in meters |
| `address` | string | Reverse-geocoded address |
| `photo_date` | ISO8601 | When the photo was taken |
| `measurements` | JSON array | `[{"label":"…","value":1.23,"display":"1.23 m"}]` |

### HTTPS (strongly recommended for production)
```bash
sudo apt-get install certbot python3-certbot-apache
sudo certbot --apache -d yourdomain.com
```

---

## Part 2 — iPhone App Configuration

1. Open `HoleReport.xcodeproj` in Xcode 15+
2. Set your Team in **Signing & Capabilities**
3. Change bundle ID from `com.yourcompany.HoleReport` to your own
4. Build & run on a physical iPhone (iOS 16+, A12+)

### Connecting to your server
1. Open the app → **Settings** tab (gear icon)
2. Enter **Server URL**: `http://192.168.1.x` (or your domain)
3. Enter **API Key**: from `/root/holereport_api_key.txt` on the server
4. Tap **Test Connection** — should show "Connected! N photo(s)"

### Taking a photo and uploading
1. **Camera** tab → point at surfaces to detect planes
2. Tap **Measure** → tap two points → see distance
3. Tap the **shutter button** to capture
4. Preview appears with:
   - **Save** — saves to Camera Roll
   - **Upload** — sends to your Apache server
5. Check `http://YOUR_SERVER_IP` in browser to see the gallery

---

## Part 3 — Web Gallery Features

- **Grid or list view** of all uploaded photos
- **Search** by address
- **Filter**: GPS only, measurements only
- **Click any photo** → full metadata modal:
  - GPS coordinates with "Copy" button
  - Altitude
  - Street address
  - All measurements with labels and values
  - **Open in Google Maps** link
  - **Download** button (saves original full-res image)
  - **Delete** button (requires API key)
- **Pagination** (24 per page)
- **Stats** — total photos, total measurements

---

## File Structure

```
holereport-server/
├── install.sh              ← Run this on your server
├── holereport.conf        ← Apache virtual host (reference)
├── php.ini.example         ← PHP upload settings
├── public/
│   ├── index.html          ← Web gallery frontend
│   └── .htaccess
├── api/
│   ├── upload.php          ← Receives photos from iPhone
│   ├── list.php            ← Lists all photos (JSON)
│   ├── photo.php           ← Single photo metadata
│   └── delete.php          ← Deletes a photo

HoleReport/ (iOS Xcode project)
├── Managers/
│   ├── UploadManager.swift ← Sends photos to server
│   ├── LocationManager.swift
│   └── PhotoStore.swift
├── Views/
│   ├── CameraView.swift    ← AR + Upload button
│   ├── GalleryView.swift
│   └── SettingsView.swift  ← Configure server URL + key
├── ViewModels/
│   └── CameraViewModel.swift
└── Models/
    └── MeasuredPhoto.swift
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Server URL not configured" | Enter URL in Settings tab |
| Test returns HTTP 401 | Wrong API key — check `/root/holereport_api_key.txt` |
| Upload fails: "File too large" | Increase limits in `/etc/php/X.X/apache2/php.ini` |
| Gallery shows no photos | Check `/var/www/holereport/uploads/` permissions: `sudo chmod 775 uploads/` |
| Apache won't start | `sudo apache2ctl configtest` then `sudo journalctl -xe` |
| No thumbnails | Install php-gd: `sudo apt-get install php-gd && sudo systemctl restart apache2` |

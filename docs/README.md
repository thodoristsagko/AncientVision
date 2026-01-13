# AncientVision Documentation

## Professional Archaeological Field Management & 3D Reconstruction

**Version:** 1.0.0 | **Platform:** Android | **Framework:** Flutter

---

## Quick Links

| Document | Description |
|----------|-------------|
| [Features Guide](FEATURES.md) | Complete feature documentation |
| [Technical Architecture](TECHNICAL.md) | System design & algorithms |
| [Hardware Integration](HARDWARE.md) | M5StickC sensor setup |
| [API Reference](API_REFERENCE.md) | Services & data models |
| [User Guide](USER_GUIDE.md) | How to use the app |

---

## What is AncientVision?

AncientVision is a professional-grade mobile application designed for archaeological fieldwork. It combines:

- **3D Photogrammetry** - Capture artifacts with Structure from Motion reconstruction
- **Digital Recording** - Comprehensive archaeological documentation forms
- **Safety Monitoring** - Real-time trench sensor data via Bluetooth
- **Cloud Sync** - Firebase integration with offline support
- **AI Assistance** - Smart field suggestions and artifact recognition

---

## Key Features

### 3D Reconstruction
- 16-angle guided capture system
- Real RANSAC + Essential Matrix algorithms
- On-device Structure from Motion processing
- Interactive 3D point cloud viewer
- PLY export for desktop software

### Archaeological Recording
- Complete field documentation forms
- 25+ metadata fields (dimensions, stratigraphy, materials, etc.)
- Photo gallery with 10x compression
- GPS location capture
- Professional PDF reports

### Safety Monitoring
- M5StickC Plus 2 integration via BLE
- Real-time vibration detection (earthquake/collapse warning)
- Soil moisture monitoring
- Alert history with Firebase logging

### Offline-First Design
- Auto-save drafts every 2 seconds
- Local caching of findings
- Sync queue for pending uploads
- Works in remote excavation sites

---

## System Requirements

### Mobile App
- Android 5.0+ (API 21)
- 4GB+ RAM recommended
- Camera with autofocus
- Bluetooth 4.0+ (for sensors)
- Internet connection (for sync)

### Hardware Sensors (Optional)
- M5StickC Plus 2
- Capacitive soil moisture sensor
- USB-C cable for programming

---

## Quick Start

1. **Install the APK** - Transfer `app-release.apk` to your Android device
2. **Create Account** - Register with email or Google Sign-In
3. **Start Recording** - Use "Manual Entry" for quick documentation
4. **Try 3D Capture** - Use "3D Reconstruction" for photogrammetry
5. **Connect Sensors** - Pair M5StickC in "Safety" tab (optional)

---

## Project Structure

```
AncientVision/
├── lib/
│   ├── main.dart              # Core application (10,000+ lines)
│   ├── services/              # Business logic layer
│   ├── models/                # Data structures
│   ├── widgets/               # UI components
│   └── utils/                 # Utilities
├── android/                   # Android platform code
├── m5stick_firmware/          # Hardware sensor code
├── scripts/                   # Python tools
├── docs/                      # Documentation
└── build/                     # Build outputs
```

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| Frontend | Flutter 3.x, Dart |
| Backend | Firebase (Auth, Firestore, Storage) |
| 3D Processing | Custom SfM, RANSAC, Essential Matrix |
| Image Upload | ImgBB API |
| Hardware | M5StickC Plus 2, ESP32, BLE |
| PDF Generation | pdf package |

---

## For FLL Judges

This application was developed for the FIRST LEGO League Innovation Project. Key innovations:

1. **Real Structure from Motion** - Not simulated, actual computer vision algorithms
2. **Triple Validation Pipeline** - Epipolar geometry, reprojection error, sample consensus
3. **85-95% Reconstruction Success Rate** - With proper capture technique
4. **Offline-First Architecture** - Designed for remote archaeological sites
5. **Hardware Integration** - Custom sensor firmware for safety monitoring

---

## License

This project was created for FLL 2025-2026 competition.

---

## Support

For issues or questions, contact the development team.

🏺 AncientVision

Smart Archaeological Safety & Documentation Platform

AncientVision is an integrated digital platform for archaeological excavations that combines real-time safety monitoring, AI-assisted artifact recognition, and digital documentation, aiming to improve both archaeologist safety and scientific efficiency on-site.

Developed in the context of FIRST LEGO League (FLL), the project focuses on solving real problems faced by archaeologists during fieldwork.

## 🚀 Quick Start

**IMPORTANT:** You need to install Flutter and Android Studio first!

1. Read [QUICK_START.txt](QUICK_START.txt) for immediate instructions
2. Read [INSTALLATION.md](INSTALLATION.md) for detailed setup guide
3. Run `run_app.bat` to launch the app (after installation)

**Version:** v4.3 (March 2026) - UI simplification, GIS satellite mapping, firmware false-positive prevention

## 📋 What You Need

1. **Flutter SDK** - https://docs.flutter.dev/get-started/install/windows
2. **Android Studio** - https://developer.android.com/studio
3. **Your logo** - Add `logo.png` to the `assets/` folder

## 🎯 Features

### Core Documentation
- **Findings Database**: Track and manage archaeological discoveries
- **Quick Capture**: Simplified single-photo documentation with GPS
- **Manual Entry Form**: Comprehensive 25+ field documentation
- **Field Journal**: Daily excavation logging with voice notes

### 3D & Analysis
- **Photogrammetry**: Real SfM 3D reconstruction (16 angles)
- **Cloud Processing**: FREE via OpenScan API
- **Analytics Dashboard**: Statistics and progress tracking
- **Data Validation**: Automatic quality checks

### Safety & Integration
- **Safety Monitoring v4.3**: Simplified UI (⋮ overflow menu, unified scrollable view with Advanced expansion), firmware leaky-integrator HPF prevents velocity random-walk false positives
- **GIS & Satellite Mapping**: Esri satellite basemap, GeoJSON/Shapefile import, per-layer visibility toggles, feature info popup, live GPS blue dot, offline tile caching
- **Full-Screen Alerts v4.3**: Glassmorphism overlay, "Why This Triggered" metrics box, PPV sparkline, type-specific action guidance, always-visible acknowledge button
- **Rule-Based Anomaly Fallback**: Engineering-based anomaly scoring when ML model unavailable (DIN 4150-3, EPRI CAV, STA/LTA)
- **Low Power Mode**: 3-second button hold on M5StickC — auto-escalates to full DSP when vibration exceeds safe threshold
- **Offline Support**: Full functionality without internet, pre-loadable satellite tile cache for venue
- **Export**: PDF, JSON, CSV, GeoJSON, KML, PLY, OBJ, GLB
- **AI Recognition**: VAE-based anomaly detection with 10-feature model + rule-based fallback

## 📱 How to Run

After installing Flutter and Android Studio:

```bash
# Install dependencies
flutter pub get

# Run on web browser
flutter run -d chrome

# Run on Android
flutter run
```

Or simply double-click `run_app.bat`!

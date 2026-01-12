# AncientVision - Installation Guide

## Prerequisites to Download

### 1. Flutter SDK
- **Download from:** https://docs.flutter.dev/get-started/install/windows
- **File:** flutter_windows_3.27.1-stable.zip (~1GB)
- **Extract to:** `C:\src\flutter\`

### 2. Android Studio
- **Download from:** https://developer.android.com/studio
- **Install:** Standard installation with all defaults

## Installation Steps

### Step 1: Install Flutter

1. Download Flutter SDK from the link above
2. Create folder `C:\src\`
3. Extract downloaded zip to `C:\src\` → you should have `C:\src\flutter\`

4. **Add Flutter to PATH:**
   - Press `Win + R`, type `sysdm.cpl`, press Enter
   - Go to "Advanced" tab → "Environment Variables"
   - Under "User variables", select "Path" → "Edit"
   - Click "New" and add: `C:\src\flutter\bin`
   - Click "OK" on all windows

5. **Open a NEW terminal** and verify:
   ```bash
   flutter --version
   ```

### Step 2: Install Android Studio

1. Download and run Android Studio installer
2. Choose "Standard" installation
3. Accept all licenses during installation

4. **Install SDK Command-line Tools:**
   - Open Android Studio
   - Go to: Tools → SDK Manager
   - Click "SDK Tools" tab
   - Check "Android SDK Command-line Tools (latest)"
   - Click "Apply" → "OK"

5. **Accept Android licenses:**
   Open a terminal and run:
   ```bash
   flutter doctor --android-licenses
   ```
   Type `y` for all prompts

### Step 3: Verify Installation

Open a terminal and run:
```bash
flutter doctor
```

You should see checkmarks (✓) for:
- Flutter
- Windows
- Android toolchain
- Android Studio

### Step 4: Add Logo Image

⚠️ **IMPORTANT:** You need to add your logo!

1. Create or find your logo image (180x180 pixels recommended)
2. Save it as `logo.png` in the `assets/` folder
3. Path should be: `AncientVision/assets/logo.png`

### Step 5: Install Project Dependencies

In the AncientVision project folder, run:
```bash
flutter pub get
```

### Step 6: Run the App

#### Option A: Run on Chrome (Easiest for testing)
```bash
flutter run -d chrome
```

#### Option B: Run on Android Emulator
1. Open Android Studio
2. Tools → Device Manager
3. Create a new Virtual Device (Pixel 5 recommended)
4. Start the emulator
5. In terminal, run:
   ```bash
   flutter run
   ```

#### Option C: Run on Physical Android Device
1. Enable Developer Options on your phone
2. Enable USB Debugging
3. Connect phone via USB
4. Run:
   ```bash
   flutter run
   ```

## Quick Start After Installation

Once everything is installed, you can run the app with:

```bash
# Navigate to project folder
cd "C:\Users\thodo\Desktop\FLL_Thodoris\AncientVisionFLL\AncientVision"

# Run on Chrome
flutter run -d chrome

# Or run on Android
flutter run
```

## Troubleshooting

### "flutter: command not found"
- Make sure you added Flutter to PATH
- Open a **NEW** terminal window
- Restart your computer if needed

### "No devices available"
- For web: Make sure Chrome is installed
- For Android: Create an emulator or connect a physical device
- Run `flutter devices` to see available devices

### License errors
- Run `flutter doctor --android-licenses` and accept all

### Missing logo.png error
- Add your `logo.png` file to the `assets/` folder

## What This App Does

AncientVision is an archaeological field management app with:
- User authentication (login/register)
- Dashboard with statistics
- Archaeological findings database
- Real-time trench safety monitoring
- AI recognition & photogrammetry features (coming soon)

Built for FIRST LEGO League (FLL) project.

# AncientVision User Guide

Step-by-step guide for using the AncientVision app.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Creating an Account](#creating-an-account)
3. [Dashboard Overview](#dashboard-overview)
4. [Recording a Finding](#recording-a-finding)
5. [3D Photogrammetry](#3d-photogrammetry)
6. [Managing Findings](#managing-findings)
7. [Safety Monitoring](#safety-monitoring)
8. [Exporting Data](#exporting-data)
9. [Tips & Best Practices](#tips--best-practices)

---

## Getting Started

### Installation

1. Transfer `app-release.apk` to your Android device
2. Open the APK file
3. Allow installation from unknown sources if prompted
4. Wait for installation to complete
5. Open "AncientVision" from your app drawer

### Requirements

- Android 5.0 or later
- 4GB RAM recommended
- Camera with autofocus
- Internet connection (for sync)
- Bluetooth 4.0+ (for sensors)

---

## Creating an Account

### Email Registration

1. Open the app
2. Tap "Register"
3. Enter your full name
4. Enter your email address
5. Create a password (6+ characters)
6. Tap "Create Account"

### Google Sign-In

1. Open the app
2. Tap "Sign in with Google"
3. Select your Google account
4. Allow permissions

### Logging In

1. Enter your email
2. Enter your password
3. Tap "Login"

---

## Dashboard Overview

The dashboard shows your archaeological data at a glance.

### Statistics

| Card | Shows |
|------|-------|
| Total Findings | All recorded artifacts |
| Today's Finds | Added in last 24 hours |
| By Type | Breakdown by category |
| By Site | Distribution by site |

### Quick Actions

- **Manual Entry** - Record a new finding
- **3D Capture** - Start photogrammetry
- **Export PDF** - Generate reports
- **View All** - Browse gallery

### Sync Status

If you see a yellow banner:
- Shows count of pending uploads
- Tap "Sync Now" when online
- Data saves automatically when connection returns

---

## Recording a Finding

### Quick Method

1. Tap "Manual Entry" on dashboard
2. Fill in basic fields:
   - **Name** - What is it? (e.g., "Bronze Coin")
   - **Type** - Category (e.g., "Numismatic")
   - **Site** - Where found (e.g., "Delphi Sector A")
   - **Date** - Discovery date
3. Add a photo (optional)
4. Tap "Save Finding"

### Complete Documentation

For thorough archaeological recording:

**Basic Information**
- Name, type, site, date
- Description and notes

**Location**
- Use "Get GPS" for automatic coordinates
- Or enter manually

**Archaeological Context**
- Find number (your catalog system)
- Excavation unit (grid square)
- Stratigraphic layer
- Depth measurements

**Physical Properties**
- Dimensions (length, width, height in mm)
- Weight in grams

**Classification**
- Material (terracotta, bronze, etc.)
- Condition (excellent to fragmentary)
- Dating method
- Cultural period

**Additional**
- Soil type and Munsell color
- Associated finds
- Field notes
- Excavator name

### Auto-Save Feature

Your work is automatically saved:
- Drafts save every 2 seconds while typing
- If app closes unexpectedly, your data is preserved
- On next launch, you'll be asked to resume or discard

---

## 3D Photogrammetry

### Overview

Create 3D models of artifacts using your phone camera.

### Starting a Capture

1. Go to **Tools** tab
2. Tap the purple **3D Reconstruction** card
3. Read the tutorial (first time)
4. Tap "Start Capture"

### Capturing Photos

#### Understanding the Angle Guide

The screen shows:
- **Current angle** (1 of 16)
- **Target position** (front, left, top, etc.)
- **Elevation** (eye level, high angle, top)
- **Sensor guidance** (device tilt)

#### Capture Technique

1. Place artifact on neutral background
2. Ensure good lighting (avoid shadows)
3. Hold phone steady
4. Align with on-screen guide
5. Tap capture button
6. Wait for quality check
7. Move to next angle

#### Photo Requirements

| Requirement | Why It Matters |
|-------------|----------------|
| Minimum 8 photos | Basic reconstruction |
| Recommended 16 | Best quality |
| Overlap 60-80% | Feature matching |
| Sharp focus | Point detection |
| Even lighting | Color accuracy |

### Running Reconstruction

After capturing:

1. Tap "Reconstruct 3D Model"
2. Watch progress indicator:
   - Loading images
   - Extracting features
   - Matching features
   - Estimating poses
   - Triangulating points
   - Bundle adjustment
3. Wait 1-3 minutes (depends on photo count)
4. View your 3D model!

### 3D Viewer Controls

| Gesture | Action |
|---------|--------|
| Drag | Rotate model |
| Pinch | Zoom in/out |
| Two-finger drag | Pan |
| Double tap | Reset view |

### Viewer Options

- **Auto-rotate** - Continuous spin
- **Point size** - Adjust dot size
- **Colors** - Toggle RGB/grayscale
- **Export** - Save as PLY file

### After Reconstruction

Two options:

1. **View 3D Model** - Explore the reconstruction
2. **Complete Form** - Go to manual entry with 3D data attached

The 3D model data is automatically included when you save the finding.

---

## Managing Findings

### Viewing Findings

**Gallery View**
1. Go to **Findings** tab
2. Browse grid of all findings
3. Tap any card to view details

**Map View**
1. Go to **Findings** tab
2. Tap map icon
3. See findings as map markers
4. Tap marker for preview

### Searching

1. Tap search icon
2. Enter search term
3. Searches: name, type, site
4. Results update live

### Filtering

1. Tap filter icon
2. Select criteria:
   - Date range
   - Type
   - Site
3. Apply filters

### Finding Details

Tap any finding to see:
- Full photo gallery (swipe)
- All metadata fields
- 3D model (if available)
- Export options

### Editing a Finding

1. Open finding details
2. Tap edit icon
3. Modify fields
4. Tap "Save Changes"

### Deleting a Finding

1. Open finding details
2. Tap delete icon
3. Confirm deletion

> **Warning:** Deletion is permanent!

---

## Safety Monitoring

### Connecting Sensor

1. Power on M5StickC Plus 2
2. Wait for "Sensor Ready" on device screen
3. Go to **Safety** tab in app
4. Tap "Scan for Devices"
5. Select "AncientVision-Sensor"
6. Wait for connection

### Understanding Readings

**Vibration**
| Value | Status | Meaning |
|-------|--------|---------|
| <0.3g | Safe | Normal |
| 0.3-0.8g | Warning | Ground movement |
| >0.8g | Critical | Earthquake/collapse risk |

**Soil Moisture**
| Value | Status | Meaning |
|-------|--------|---------|
| 30-60% | Safe | Optimal |
| <30% | Dry | Cracking risk |
| 60-80% | Wet | Saturation warning |
| >80% | Critical | Collapse risk |

### Alert System

**Full-Screen Alerts**
- Critical alerts appear as full-screen overlays on ALL tabs, not just the Safety tab
- Includes haptic feedback (phone vibration)
- Voice alerts via text-to-speech announce the danger
- Alarm sound plays on critical alerts

**Push Notifications**
- Safety notifications fire regardless of which screen you're on
- Works even when the app is minimized

**Alert Indicators**
- **Green** - All safe
- **Yellow/Orange** - Warning level
- **Red** - Critical - take action!

### Global Mute Button

- A mute button is visible in the bottom navigation bar on ALL tabs
- Pressing it toggles all alert sounds, alarms, TTS, and full-screen overlays
- The mute state is synchronized across the entire app
- Green speaker icon = unmuted, Red speaker-off icon = muted

### BLE Connection Persistence

The Bluetooth connection to the M5StickC sensor stays alive even when you switch to other tabs (Home, Findings, Tools). You don't need to stay on the Safety tab to keep receiving sensor data.

### Alert History

Scroll down on the Safety tab to see:
- Past alerts with timestamps
- Vibration/moisture at time of alert
- Trend patterns

### Test Alert

Press **Button A** on M5StickC to send test alert.

---

## Exporting Data

### PDF Reports

Generate professional documentation:

1. Go to **Tools** tab
2. Tap "PDF Reports"
3. Select findings to include
4. Tap "Generate PDF"
5. Share or save the file

**PDF Contents:**
- Finding name and photo
- Metadata table
- Archaeological context
- Measurements
- 3D model info (if available)

### JSON Export

Export all data as structured JSON:

1. Go to **Tools** tab
2. Tap "Export Data"
3. Tap "Export as JSON"
4. Share or save the file

**Use cases:**
- Backup your data
- Import to other systems
- Data analysis

### 3D Model Export

Export point clouds as PLY:

1. Open finding with 3D model
2. View 3D model
3. Tap export icon
4. Share PLY file

**Compatible software:**
- MeshLab
- CloudCompare
- Blender

---

## Tips & Best Practices

### Photogrammetry Tips

**Lighting**
- Use natural daylight when possible
- Avoid direct sunlight (causes shadows)
- Indoor: use diffused lighting
- Avoid mixed light sources

**Background**
- Use neutral, matte background
- Avoid shiny surfaces
- Newspaper or cardboard works well
- Ensure contrast with artifact

**Capture**
- Keep artifact stationary
- Move around the object, not it
- Maintain consistent distance
- Overlap photos 60-80%

**Quality Checklist**
- [ ] All angles covered
- [ ] Sharp focus in all photos
- [ ] Consistent lighting
- [ ] No motion blur
- [ ] Artifact fills frame

### Scanning Difficult Objects

Some artifacts are challenging for photogrammetry. Here's how to handle them:

**Problem Objects & Solutions:**

| Object Type | Problem | Solution |
|-------------|---------|----------|
| Black/dark | Low contrast | Light chalk spray or flour dusting |
| Shiny metal | Reflections move | Matte spray or powder coating |
| Smooth pottery | Few features | Raking light to show texture |
| Glass/transparent | Light passes through | Not suitable for photogrammetry |

**Quick Fix: Temporary Texture**

For black or smooth objects:
1. Lightly dust with flour or talcum powder
2. Use a soft brush to spread evenly
3. Capture photos
4. Brush/blow off powder when done

This is a standard professional technique - even museum conservators use it!

**Processing Method for Difficult Objects:**

| Object Type | Recommended Method |
|-------------|-------------------|
| Textured artifacts | Either works |
| Slightly smooth | Cloud Processing |
| Very dark/smooth | Cloud + temporary texture |
| Shiny metal | Must use powder coating |

**Cloud vs On-Device:**
- Cloud processing has better algorithms for difficult objects
- But physics limits apply to both
- For truly challenging objects, texture spray is the real solution

### Data Entry Tips

**Be Consistent**
- Use same naming conventions
- Follow your institution's standards
- Use dropdown options when available

**Be Complete**
- Fill all applicable fields
- Add photos whenever possible
- Include GPS coordinates

**Be Accurate**
- Double-check measurements
- Verify coordinates
- Use correct dating methods

### Offline Work

**Before Going to Field**
- Charge your phone fully
- Ensure app is updated
- Test camera and sensors

**In the Field**
- Data saves locally automatically
- Don't worry about connectivity
- Take as many photos as needed

**After Returning**
- Connect to WiFi
- Tap "Sync Now" on dashboard
- Verify all data uploaded

### Battery Management

**Save Battery**
- Lower screen brightness
- Turn off Bluetooth when not using sensors
- Close other apps
- Avoid video mode for photogrammetry

**Expected Battery Use**
- ~15-20% for full photogrammetry session
- ~5% per hour with sensors connected
- ~2% per hour idle

---

## Troubleshooting

### App Won't Open

1. Restart phone
2. Clear app cache (Settings → Apps → AncientVision → Clear Cache)
3. Reinstall app

### Camera Not Working

1. Check camera permissions (Settings → Apps → AncientVision → Permissions)
2. Restart app
3. Restart phone

### 3D Reconstruction Fails

**"Not enough features"**
- Take more photos (minimum 8)
- Ensure better lighting
- Add texture to background

**"Processing failed"**
- Reduce number of photos to 12-16
- Ensure photos are sharp
- Try again with better conditions

### Sync Not Working

1. Check internet connection
2. Check Firebase status
3. Try manual sync
4. Restart app

### Sensor Not Connecting

1. Ensure M5StickC is powered on
2. Check Bluetooth is enabled on phone
3. Move devices closer together
4. Restart both devices

### Data Missing

1. Check if in offline queue (sync indicator)
2. Search all findings
3. Check date filters
4. Contact support if still missing

---

## Keyboard Shortcuts

For external keyboards:

| Shortcut | Action |
|----------|--------|
| Tab | Next field |
| Shift+Tab | Previous field |
| Enter | Submit form |
| Esc | Cancel/back |

---

## Getting Help

**In-App**
- Tap (?) icon for contextual help
- Tutorial mode for photogrammetry

**Online**
- Documentation: This guide
- Video tutorials: Coming soon

**Contact**
- Report bugs via GitHub issues
- Email support for urgent issues

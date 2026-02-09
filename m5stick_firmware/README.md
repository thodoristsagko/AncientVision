# M5StickC Plus 2 - AncientVision Trench Safety Sensor v3.0

## What's New in v3.0

- **Madgwick quaternion gravity removal** - accurate at any sensor orientation (was scalar `|a|-1g`)
- **Tri-axial PCPV** - proper DIN 4150-3 Peak Component Particle Velocity per X/Y/Z axis
- **2nd-order Butterworth HPF on velocity** - replaces crude 0.998 exponential decay
- **Adaptive FFT noise floor** - dominant frequency reported as 0 when below 3x RMS threshold
- **STA/LTA seismic event trigger** - standard seismology algorithm (Short-Term/Long-Term Average ratio)
- **Kurtosis computation** - 4th statistical moment for impact event detection
- **Hysteresis alert state machine** - 2 windows to escalate, 4 to clear, prevents flickering
- **Filter warm-up discard** - first 2 FFT windows discarded after boot
- **Extended BLE JSON** - 7 features sent (was 4): +centroid, +kurtosis, +STA/LTA ratio

## Hardware Required
- M5StickC Plus 2
- Capacitive Soil Moisture Sensor (analog output)
- Jumper wires

## Wiring Diagram

```
M5StickC Plus 2          Soil Moisture Sensor
----------------         -------------------
3.3V (or 5V)     ----→   VCC
GND              ----→   GND
GPIO 33          ----→   Signal (Analog Out)
```

**Note:** GPIO 33 is available on the Grove port of the M5StickC Plus 2.

## Software Setup

### 1. Install Arduino IDE
Download from: https://www.arduino.cc/en/software

### 2. Install M5StickC Plus 2 Board Support
1. Open Arduino IDE
2. Go to **File → Preferences**
3. Add this URL to "Additional Board Manager URLs":
   ```
   https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/arduino/package_m5stack_index.json
   ```
4. Go to **Tools → Board → Boards Manager**
5. Search for "M5Stack" and install **M5Stack by M5Stack**
6. Select **Tools → Board → M5Stack → M5StickCPlus2**

### 3. Install Required Libraries
Go to **Sketch → Include Library → Manage Libraries** and install:
- **M5StickCPlus2** (by M5Stack)
- **arduinoFFT** (by Enrique Condes) - for frequency analysis
- **MadgwickAHRS** (by Arduino) - for quaternion-based gravity removal

The ESP32 BLE library is included with the board support.

### 4. Upload the Firmware
1. Connect M5StickC Plus 2 via USB-C
2. Select the correct port: **Tools → Port → COMx** (or /dev/ttyUSBx on Linux)
3. Open `AncientVisionSensor.ino`
4. Click **Upload** (→ arrow button)

## Signal Processing Pipeline

```
Raw IMU (200Hz) → DLPF (99Hz HW) → Madgwick Gravity Removal (quaternion)
                                      ↓
                          Per-axis linear acceleration (X, Y, Z)
                                      ↓
                      HPF 0.5Hz → LPF 100Hz (per axis, Butterworth)
                                      ↓
                ┌─────────────────────┼─────────────────────┐
                ↓                     ↓                     ↓
         Tri-axial PPV         FFT (256-pt)          STA/LTA ratio
         (velocity HPF         Noise floor           (per-sample)
          @ 0.3 Hz)            + Frequency
                ↓                     ↓
         PCPV = max(X,Y,Z)   Centroid + Kurtosis
                ↓                     ↓
                └──────── DIN 4150-3 Classification ────────┘
                          (Hysteresis state machine)
                                      ↓
                              BLE JSON (7 features)
```

1. **IMU sampling at 200 Hz** - captures vibrations up to 100 Hz (Nyquist)
2. **DLPF at 99 Hz** - hardware anti-aliasing on the MPU6886 chip
3. **Madgwick filter** - fuses accelerometer + gyroscope to track orientation, removes gravity
4. **Butterworth bandpass (0.5-100 Hz) per axis** - isolates structural vibrations from noise
5. **Tri-axial velocity integration** - trapezoidal rule with 0.3 Hz HPF drift removal
6. **256-point FFT with Hanning window** - identifies dominant vibration frequency
7. **Adaptive noise floor** - 3x RMS threshold prevents false frequency readings
8. **Feature extraction** - PCPV, RMS, crest factor, spectral centroid, kurtosis, STA/LTA
9. **DIN 4150-3 classification** - hysteresis state machine with 2-window trigger, 4-window clear

## Calibration

### Soil Moisture Sensor Calibration
Edit these values in the code based on your sensor:

```cpp
const int MOISTURE_AIR = 3500;    // Value when sensor is in air (dry)
const int MOISTURE_WATER = 1500;  // Value when sensor is in water (wet)
```

### DIN 4150-3 Vibration Thresholds
These are based on international standards for heritage structures:

```cpp
const float PPV_SAFE_MAX = 0.3;           // Below human perception (mm/s)
const float PPV_HERITAGE_LOW = 3.0;       // Heritage limit 1-10 Hz (mm/s)
const float PPV_HERITAGE_HIGH = 8.0;      // Heritage limit 50-100 Hz (mm/s)
const float PPV_STRUCTURAL_DAMAGE = 10.0; // Structural damage risk (mm/s)
const float PPV_CONTINUOUS_LIMIT = 2.5;   // Continuous vibration limit (mm/s)
const float CREST_IMPACT_THRESHOLD = 5.0; // Impact detection (Peak/RMS ratio)
```

### STA/LTA Configuration
Seismic event trigger parameters:

```cpp
const int STA_LEN = 40;           // 0.2 sec short-term window
const int LTA_LEN = 2000;         // 10 sec long-term window
const float STA_TRIGGER = 4.0;    // Trigger when ratio > 4.0
const float STA_DETRIGGER = 1.5;  // De-trigger when ratio < 1.5
```

## Using with the App

1. Power on the M5StickC Plus 2
2. The display shows "AncientVision" and "Madgwick+FFT+STA/LTA"
3. Open the AncientVision app on your phone
4. Go to the **Safety** tab
5. The app automatically scans for and connects to "AncientVision-Sensor"
6. You'll see live PPV (smoothed), frequency, crest factor, kurtosis, STA/LTA, and hazard classification

## Display Layout

```
┌─────────────────────────────────┐
│ AncientVision        BT  85%   │  ← Title + BLE + Battery
│ PPV:0.2mm/s                    │  ← PPV (key metric, large font)
│ 3Hz S/L:1.2                    │  ← Dominant freq + STA/LTA ratio
│ Safe - DIN 4150-3              │  ← Hazard status
│ Mst:45% OK                     │  ← Moisture
│ RMS:0.0012 CF:1.8 K:0.3       │  ← RMS, Crest, Kurtosis (small)
└─────────────────────────────────┘
```

### Background Colors

| Color | Meaning |
|-------|---------|
| Green | All safe - DIN 4150-3 compliant |
| Orange | Warning - hazard detected |
| Red | Critical - evacuate area! |

## Button Functions

- **Button A** (front): Test alert (sends test notification to app)

## BLE Data Format (v3.0)

The sensor sends JSON data over BLE characteristics:

| Characteristic | UUID suffix | Data Format |
|---------------|-------------|-------------|
| IMU | `...26a8` | `{"x":0.01,"y":0.02,"z":1.00,"vib":0.03,"ppv":0.2,"rms":0.0012,"freq":3.0,"crest":1.8,"cent":5.2,"kurt":0.3,"stalta":1.1}` |
| Moisture | `...26a9` | `{"percent":45,"raw":2500}` |
| Alert | `...26aa` | `{"level":"safe","message":"","type":"none"}` |

### v3.0 Fields (backward compatible with v2.0)

| Field | Unit | Description |
|-------|------|-------------|
| `ppv` | mm/s | Peak Component Particle Velocity (tri-axial PCPV) |
| `rms` | g | RMS acceleration (vibration energy) |
| `freq` | Hz | Dominant vibration frequency from FFT (0 if below noise floor) |
| `crest` | ratio | Crest factor (Peak/RMS - detects impacts) |
| `cent` | Hz | Spectral centroid (frequency center of mass) |
| `kurt` | ratio | Excess kurtosis (>3 = impulsive events) |
| `stalta` | ratio | STA/LTA ratio (>4 = seismic event trigger) |
| `type` | string | Hazard classification (seismic/machinery/impact/etc) |

### Hazard Types

| Type | Meaning | Trigger |
|------|---------|---------|
| `none` | Safe conditions | PPV < 0.3 mm/s |
| `seismic` | Seismic activity | PPV > 3 mm/s, freq 0.5-10 Hz, or STA/LTA > 4 |
| `machinery` | Heavy machinery | PPV > 3 mm/s, freq 10-50 Hz |
| `structural` | Structural damage risk | PPV > 10 mm/s |
| `hf_stress` | High-frequency stress | PPV > 8 mm/s, freq > 50 Hz |
| `impact` | Impact/collapse | Crest factor > 5, PPV > 1 mm/s |
| `continuous` | Sustained vibration | PPV > 2.5 mm/s |
| `source_change` | Vibration source changed | Spectral centroid shift > 50% |

**Note:** The app automatically negotiates a 512-byte BLE MTU to prevent JSON truncation.

## DIN 4150-3 Reference

The international standard for vibration effects on heritage structures:

| Frequency | Heritage/Archaeological Limit (PPV) |
|-----------|-------------------------------------|
| 1-10 Hz | 3 mm/s |
| 10-50 Hz | 3-8 mm/s |
| 50-100 Hz | 8-10 mm/s |
| Continuous | 2.5 mm/s (any frequency) |

Human perception threshold: 0.14-0.3 mm/s PPV

## Troubleshooting

### App can't find the sensor
- Make sure Bluetooth is enabled on your phone
- Ensure the M5StickC Plus 2 is powered on and showing "BT" on screen
- Try restarting both devices

### Sensor values show 0 in the app
- This is usually caused by BLE MTU being too small (JSON gets truncated)
- The latest app version negotiates MTU automatically
- Try disconnecting and reconnecting the sensor

### Incorrect moisture readings
- Recalibrate the sensor (see Calibration section)
- Check wiring connections

### PPV readings seem too high/low
- Ensure the M5StickC is firmly mounted (not loose/dangling)
- The first 2 FFT windows (~2.5s) are discarded for filter warm-up
- Check Serial Monitor at 115200 baud for DSP debug output
- Tilt test: v3.0 with Madgwick should show near-zero PPV when tilted (v2.0 showed ~0.13g error)

### STA/LTA ratio stays high
- After a strong vibration event, the LTA needs ~10 seconds to settle
- This is normal behavior - the algorithm adapts its baseline

## ML Anomaly Detection (Tier 2)

The Flutter app includes a TensorFlow Lite autoencoder trained on normal vibration data:
- v3.0 architecture: 7→6→4→3→4→6→7 (deeper than v2.0's 4→4→3→4→4)
- 7 input features: [rms, ppv, freq, crest, cent, kurt, stalta]
- Model: `assets/ml/vibration_anomaly.tflite` (~5 KB)
- To retrain with real site data: `python scripts/train_vibration_autoencoder.py`

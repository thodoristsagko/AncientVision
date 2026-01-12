# M5StickC Plus 2 - AncientVision Trench Safety Sensor

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

The ESP32 BLE library is included with the board support.

### 4. Upload the Firmware
1. Connect M5StickC Plus 2 via USB-C
2. Select the correct port: **Tools → Port → COMx** (or /dev/ttyUSBx on Linux)
3. Open `AncientVisionSensor.ino`
4. Click **Upload** (→ arrow button)

## Calibration

### Soil Moisture Sensor Calibration
Edit these values in the code based on your sensor:

```cpp
const int MOISTURE_AIR = 3500;    // Value when sensor is in air (dry)
const int MOISTURE_WATER = 1500;  // Value when sensor is in water (wet)
```

To calibrate:
1. Upload code with Serial Monitor open (115200 baud)
2. Note the raw value when sensor is in air → set as `MOISTURE_AIR`
3. Note the raw value when sensor is in water → set as `MOISTURE_WATER`
4. Re-upload the code

### Vibration Thresholds
```cpp
const float VIBRATION_WARNING = 0.3;   // Warning level (yellow)
const float VIBRATION_CRITICAL = 0.8;  // Critical level (red)
```

## Using with the App

1. Power on the M5StickC Plus 2
2. The display will show "AncientVision" and "Initializing..."
3. Open the AncientVision app on your phone
4. Go to the **Safety** tab
5. The app will automatically scan for and connect to "AncientVision-Sensor"
6. Once connected, you'll see live data from the sensors

## LED/Display Indicators

| Color | Meaning |
|-------|---------|
| Green | All values safe |
| Orange | Warning - check values |
| Red | Critical - take action! |

## Button Functions

- **Button A** (front): Test alert (sends test notification to app)

## Troubleshooting

### App can't find the sensor
- Make sure Bluetooth is enabled on your phone
- Ensure the M5StickC Plus 2 is powered on and showing "BT" on screen
- Try restarting both devices

### Incorrect moisture readings
- Recalibrate the sensor (see Calibration section)
- Check wiring connections
- Ensure sensor is inserted vertically into soil

### Unstable vibration readings
- Place device on a stable surface during calibration
- The IMU auto-calibrates on startup

## Thresholds Used in App

| Sensor | Safe Range | Warning | Critical |
|--------|------------|---------|----------|
| Soil Moisture | 30-60% | <30% or >60% | >60% (collapse risk) |
| Vibration | <0.3g | 0.3-0.8g | >0.8g (earthquake) |

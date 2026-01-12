# AncientVision Hardware Integration

Complete guide to M5StickC Plus 2 sensor integration.

---

## Table of Contents

1. [Hardware Overview](#hardware-overview)
2. [Components](#components)
3. [Wiring Diagram](#wiring-diagram)
4. [Firmware Setup](#firmware-setup)
5. [BLE Protocol](#ble-protocol)
6. [Mobile App Integration](#mobile-app-integration)
7. [Desktop Monitor](#desktop-monitor)
8. [Troubleshooting](#troubleshooting)

---

## Hardware Overview

AncientVision uses an M5StickC Plus 2 microcontroller to monitor archaeological excavation safety conditions in real-time.

### Purpose
- **Vibration Detection** - Earthquake/collapse early warning
- **Soil Moisture** - Ground stability monitoring
- **Remote Alerts** - Bluetooth transmission to mobile app

### System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  EXCAVATION TRENCH                           │
│                                                              │
│    ┌─────────────────────┐      ┌─────────────────────┐     │
│    │   M5StickC Plus 2   │      │  Soil Moisture      │     │
│    │                     │──────│  Sensor             │     │
│    │   ┌─────────────┐   │      │                     │     │
│    │   │ IMU Sensor  │   │      └─────────────────────┘     │
│    │   │ (Built-in)  │   │                                  │
│    │   └─────────────┘   │                                  │
│    │                     │                                  │
│    │   ┌─────────────┐   │                                  │
│    │   │   Display   │   │                                  │
│    │   └─────────────┘   │                                  │
│    └──────────┬──────────┘                                  │
│               │ BLE                                         │
└───────────────┼─────────────────────────────────────────────┘
                │
                ▼
┌───────────────────────────────────────────────────────────┐
│                    BLUETOOTH LOW ENERGY                    │
└───────────────┬───────────────────────────────────────────┘
                │
        ┌───────┴───────┐
        │               │
        ▼               ▼
┌───────────────┐ ┌───────────────┐
│  Mobile App   │ │ Desktop       │
│  (Flutter)    │ │ Monitor       │
│               │ │ (Python)      │
│  ┌─────────┐  │ │               │
│  │ Safety  │  │ │  ┌─────────┐  │
│  │   Tab   │  │ │  │ Console │  │
│  └─────────┘  │ │  └─────────┘  │
└───────────────┘ └───────────────┘
        │               │
        └───────┬───────┘
                │
                ▼
┌───────────────────────────────────────────────────────────┐
│                  FIREBASE CLOUD                            │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                   safety_alerts                       │ │
│  │  ┌────────┬───────────┬───────────┬────────────────┐ │ │
│  │  │ level  │ vibration │ moisture  │ timestamp      │ │ │
│  │  ├────────┼───────────┼───────────┼────────────────┤ │ │
│  │  │critical│   0.95    │    75     │ 2024-03-15...  │ │ │
│  │  │warning │   0.45    │    68     │ 2024-03-15...  │ │ │
│  │  └────────┴───────────┴───────────┴────────────────┘ │ │
│  └──────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
```

---

## Components

### M5StickC Plus 2

| Specification | Value |
|---------------|-------|
| Microcontroller | ESP32-PICO-V3-02 |
| CPU | Dual-core 240 MHz |
| RAM | 8 MB PSRAM |
| Flash | 8 MB |
| Display | 1.14" IPS LCD (135x240) |
| Battery | 200 mAh LiPo |
| Connectivity | WiFi, BLE 5.0 |
| Sensors | 6-axis IMU (MPU6886) |
| Buttons | 2 (A, B) + Power |
| Port | Grove (GPIO 32/33) |

### Soil Moisture Sensor

| Specification | Value |
|---------------|-------|
| Type | Capacitive |
| Output | Analog (0-3.3V) |
| Range | 0-100% relative humidity |
| Connection | Grove port |
| Pin | GPIO 33 |

### Calibration Values

```cpp
// Raw ADC values
#define MOISTURE_AIR    3500  // Sensor in air (0%)
#define MOISTURE_WATER  1500  // Sensor in water (100%)
```

---

## Wiring Diagram

```
M5StickC Plus 2
┌────────────────────────┐
│                        │
│    ┌──────────────┐    │
│    │              │    │
│    │   DISPLAY    │    │
│    │              │    │
│    └──────────────┘    │
│                        │
│  [A]            [B]    │ ← Buttons
│                        │
│  ┌────────────────┐    │
│  │  Grove Port    │    │
│  │  GND VCC G32 G33   │
│  └──┬───┬───┬───┬─┘    │
│     │   │   │   │      │
└─────┼───┼───┼───┼──────┘
      │   │   │   │
      │   │   │   └──────── Signal (Yellow)
      │   │   └──────────── Not Used
      │   └──────────────── VCC 3.3V (Red)
      └──────────────────── GND (Black)
                   │
                   ▼
┌─────────────────────────┐
│   Soil Moisture Sensor  │
│                         │
│   ┌─────────────────┐   │
│   │     ║║║║║║      │   │
│   │     ║║║║║║      │   │
│   │     ║║║║║║      │   │ ← Capacitive pads
│   │     ║║║║║║      │   │   (insert into soil)
│   │     ║║║║║║      │   │
│   └─────────────────┘   │
│                         │
│   [GND] [VCC] [SIG]     │
└─────────────────────────┘
```

### Connection Table

| Sensor Wire | M5StickC Pin | Description |
|-------------|--------------|-------------|
| GND (Black) | GND | Ground |
| VCC (Red) | 3.3V | Power |
| SIG (Yellow) | GPIO 33 | Analog signal |

---

## Firmware Setup

### Prerequisites

1. **Arduino IDE** 2.0+
2. **M5StickCPlus2 Library** from Arduino Library Manager
3. **USB-C Cable** for programming

### Installing Libraries

```
Arduino IDE → Tools → Manage Libraries

Search and install:
1. M5StickCPlus2
2. ArduinoBLE (or use built-in ESP32 BLE)
```

### Board Configuration

```
Arduino IDE → Tools:
- Board: "M5StickC Plus2"
- Upload Speed: 1500000
- Port: (your COM port)
```

### Firmware Code

**File:** `m5stick_firmware/AncientVisionSensor.ino`

```cpp
#include <M5StickCPlus2.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// BLE Configuration
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define IMU_CHAR_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define MOISTURE_CHAR_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define ALERT_CHAR_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26aa"

// Sensor pins
#define MOISTURE_PIN 33

// Thresholds
#define VIBRATION_WARNING   0.3
#define VIBRATION_CRITICAL  0.8
#define MOISTURE_WARNING    60
#define MOISTURE_CRITICAL   80

// Calibration
#define MOISTURE_AIR        3500
#define MOISTURE_WATER      1500

// Global variables
BLEServer* pServer = NULL;
BLECharacteristic* pIMUChar = NULL;
BLECharacteristic* pMoistureChar = NULL;
BLECharacteristic* pAlertChar = NULL;
bool deviceConnected = false;

float accX, accY, accZ;
float vibration = 0;
int moisturePercent = 0;
String alertLevel = "safe";

void setup() {
    M5.begin();
    M5.Imu.begin();

    // Initialize display
    M5.Lcd.setRotation(3);
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setTextSize(2);

    // Initialize moisture sensor pin
    pinMode(MOISTURE_PIN, INPUT);

    // Setup BLE
    setupBLE();

    M5.Lcd.println("AncientVision");
    M5.Lcd.println("Sensor Ready");
}

void setupBLE() {
    BLEDevice::init("AncientVision-Sensor");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);

    // IMU Characteristic
    pIMUChar = pService->createCharacteristic(
        IMU_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pIMUChar->addDescriptor(new BLE2902());

    // Moisture Characteristic
    pMoistureChar = pService->createCharacteristic(
        MOISTURE_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pMoistureChar->addDescriptor(new BLE2902());

    // Alert Characteristic
    pAlertChar = pService->createCharacteristic(
        ALERT_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pAlertChar->addDescriptor(new BLE2902());

    pService->start();

    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->start();
}

void loop() {
    M5.update();

    // Read IMU
    M5.Imu.getAccel(&accX, &accY, &accZ);
    vibration = sqrt(accX*accX + accY*accY + accZ*accZ) - 1.0;
    vibration = abs(vibration);

    // Read moisture
    int rawMoisture = analogRead(MOISTURE_PIN);
    moisturePercent = map(rawMoisture, MOISTURE_AIR, MOISTURE_WATER, 0, 100);
    moisturePercent = constrain(moisturePercent, 0, 100);

    // Determine alert level
    if (vibration > VIBRATION_CRITICAL || moisturePercent > MOISTURE_CRITICAL) {
        alertLevel = "critical";
    } else if (vibration > VIBRATION_WARNING || moisturePercent > MOISTURE_WARNING) {
        alertLevel = "warning";
    } else {
        alertLevel = "safe";
    }

    // Update display
    updateDisplay();

    // Send BLE data
    if (deviceConnected) {
        sendBLEData();
    }

    // Button A: Test alert
    if (M5.BtnA.wasPressed()) {
        sendTestAlert();
    }

    delay(100);
}

void updateDisplay() {
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setCursor(0, 0);

    // Status color
    if (alertLevel == "critical") {
        M5.Lcd.setTextColor(RED);
    } else if (alertLevel == "warning") {
        M5.Lcd.setTextColor(YELLOW);
    } else {
        M5.Lcd.setTextColor(GREEN);
    }

    M5.Lcd.printf("Status: %s\n\n", alertLevel.c_str());

    M5.Lcd.setTextColor(WHITE);
    M5.Lcd.printf("Vib: %.2f g\n", vibration);
    M5.Lcd.printf("Moist: %d%%\n", moisturePercent);
    M5.Lcd.printf("\nBLE: %s", deviceConnected ? "Connected" : "Waiting...");
}

void sendBLEData() {
    // IMU data as JSON
    String imuJson = "{\"x\":" + String(accX, 2) +
                     ",\"y\":" + String(accY, 2) +
                     ",\"z\":" + String(accZ, 2) +
                     ",\"vib\":" + String(vibration, 2) + "}";
    pIMUChar->setValue(imuJson.c_str());
    pIMUChar->notify();

    // Moisture data as JSON
    String moistJson = "{\"percent\":" + String(moisturePercent) + "}";
    pMoistureChar->setValue(moistJson.c_str());
    pMoistureChar->notify();

    // Alert data as JSON
    String alertJson = "{\"level\":\"" + alertLevel +
                       "\",\"message\":\"" + getAlertMessage() + "\"}";
    pAlertChar->setValue(alertJson.c_str());
    pAlertChar->notify();
}

String getAlertMessage() {
    if (alertLevel == "critical") {
        if (vibration > VIBRATION_CRITICAL) {
            return "DANGER: High vibration detected!";
        }
        return "DANGER: Soil saturation critical!";
    } else if (alertLevel == "warning") {
        if (vibration > VIBRATION_WARNING) {
            return "Warning: Ground vibration detected";
        }
        return "Warning: High soil moisture";
    }
    return "All systems normal";
}

void sendTestAlert() {
    String testJson = "{\"level\":\"warning\",\"message\":\"Test alert - Button A pressed\"}";
    pAlertChar->setValue(testJson.c_str());
    pAlertChar->notify();
}

// BLE Server Callbacks
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
    }
    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        // Restart advertising
        BLEDevice::startAdvertising();
    }
};
```

### Upload Steps

1. Connect M5StickC via USB-C
2. Select correct COM port in Arduino IDE
3. Click Upload button
4. Wait for "Done uploading"
5. Device will restart and show "Sensor Ready"

---

## BLE Protocol

### Service & Characteristics

| Name | UUID | Properties |
|------|------|------------|
| Service | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` | - |
| IMU Data | `beb5483e-36e1-4688-b7f5-ea07361b26a8` | Read, Notify |
| Moisture | `beb5483e-36e1-4688-b7f5-ea07361b26a9` | Read, Notify |
| Alert | `beb5483e-36e1-4688-b7f5-ea07361b26aa` | Read, Notify |

### Data Formats

#### IMU Characteristic
```json
{
  "x": 0.02,
  "y": -0.05,
  "z": 0.98,
  "vib": 0.15
}
```

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| x | float | g | X-axis acceleration |
| y | float | g | Y-axis acceleration |
| z | float | g | Z-axis acceleration |
| vib | float | g | Vibration magnitude |

#### Moisture Characteristic
```json
{
  "percent": 45
}
```

| Field | Type | Unit | Range |
|-------|------|------|-------|
| percent | int | % | 0-100 |

#### Alert Characteristic
```json
{
  "level": "warning",
  "message": "Ground vibration detected"
}
```

| Field | Type | Values |
|-------|------|--------|
| level | string | "safe", "warning", "critical" |
| message | string | Human-readable description |

### Notification Interval

- IMU: Every 500ms
- Moisture: Every 500ms
- Alert: On level change + every 500ms

---

## Mobile App Integration

### Flutter Code

**File:** `lib/main.dart` (Safety View)

```dart
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class _SafetyViewState extends State<_SafetyView> {
  FlutterBluePlus flutterBlue = FlutterBluePlus.instance;
  BluetoothDevice? _connectedDevice;

  // Sensor values
  double _vibration = 0.0;
  int _moisture = 0;
  String _alertLevel = 'safe';

  // UUIDs
  static const serviceUUID = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const imuCharUUID = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const moistureCharUUID = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';
  static const alertCharUUID = 'beb5483e-36e1-4688-b7f5-ea07361b26aa';

  Future<void> _scanAndConnect() async {
    // Scan for devices
    await flutterBlue.startScan(timeout: Duration(seconds: 10));

    flutterBlue.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.name == 'AncientVision-Sensor') {
          _connectToDevice(r.device);
          flutterBlue.stopScan();
          break;
        }
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    await device.connect();
    _connectedDevice = device;

    // Discover services
    List<BluetoothService> services = await device.discoverServices();

    for (BluetoothService service in services) {
      if (service.uuid.toString() == serviceUUID) {
        for (BluetoothCharacteristic char in service.characteristics) {
          // Subscribe to notifications
          await char.setNotifyValue(true);
          char.value.listen((value) {
            _handleCharacteristicUpdate(char.uuid.toString(), value);
          });
        }
      }
    }
  }

  void _handleCharacteristicUpdate(String uuid, List<int> value) {
    final jsonStr = String.fromCharCodes(value);
    final data = json.decode(jsonStr);

    setState(() {
      if (uuid == imuCharUUID) {
        _vibration = (data['vib'] as num).toDouble();
      } else if (uuid == moistureCharUUID) {
        _moisture = data['percent'] as int;
      } else if (uuid == alertCharUUID) {
        _alertLevel = data['level'] as String;

        // Log critical alerts to Firebase
        if (_alertLevel == 'critical') {
          _logAlertToFirebase(data);
        }
      }
    });
  }

  Future<void> _logAlertToFirebase(Map<String, dynamic> alert) async {
    await FirebaseFirestore.instance.collection('safety_alerts').add({
      'level': alert['level'],
      'message': alert['message'],
      'vibration': _vibration,
      'moisture': _moisture,
      'timestamp': FieldValue.serverTimestamp(),
      'source': 'Mobile_App',
    });
  }
}
```

---

## Desktop Monitor

### Python BLE Monitor

**File:** `scripts/ble_monitor.py`

```python
#!/usr/bin/env python3
"""
AncientVision BLE Sensor Monitor
Desktop monitoring tool for M5StickC Plus 2
"""

import asyncio
import json
from datetime import datetime
from bleak import BleakClient, BleakScanner

# BLE Configuration
SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
IMU_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
MOISTURE_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9"
ALERT_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26aa"

# ANSI Colors
RED = "\033[91m"
YELLOW = "\033[93m"
GREEN = "\033[92m"
RESET = "\033[0m"

class SensorMonitor:
    def __init__(self):
        self.vibration = 0.0
        self.moisture = 0
        self.alert_level = "safe"

    def handle_imu(self, sender, data):
        try:
            json_data = json.loads(data.decode())
            self.vibration = json_data.get('vib', 0)
            self.print_status()
        except:
            pass

    def handle_moisture(self, sender, data):
        try:
            json_data = json.loads(data.decode())
            self.moisture = json_data.get('percent', 0)
            self.print_status()
        except:
            pass

    def handle_alert(self, sender, data):
        try:
            json_data = json.loads(data.decode())
            self.alert_level = json_data.get('level', 'safe')
            message = json_data.get('message', '')

            if self.alert_level == 'critical':
                print(f"\n{RED}!!! CRITICAL ALERT !!!{RESET}")
                print(f"{RED}{message}{RESET}\n")
            elif self.alert_level == 'warning':
                print(f"\n{YELLOW}⚠ WARNING: {message}{RESET}\n")
        except:
            pass

    def print_status(self):
        # Clear line and print status
        color = GREEN if self.alert_level == "safe" else (
            YELLOW if self.alert_level == "warning" else RED
        )

        print(f"\r{color}[{self.alert_level.upper()}]{RESET} "
              f"Vibration: {self.vibration:.2f}g | "
              f"Moisture: {self.moisture}%", end="", flush=True)

async def main():
    print("Scanning for AncientVision-Sensor...")

    # Find device
    device = None
    devices = await BleakScanner.discover()
    for d in devices:
        if d.name and "AncientVision" in d.name:
            device = d
            break

    if not device:
        print("Device not found. Make sure M5StickC is powered on.")
        return

    print(f"Found: {device.name} ({device.address})")
    print("Connecting...")

    monitor = SensorMonitor()

    async with BleakClient(device.address) as client:
        print("Connected! Monitoring sensors...\n")

        # Subscribe to characteristics
        await client.start_notify(IMU_CHAR_UUID, monitor.handle_imu)
        await client.start_notify(MOISTURE_CHAR_UUID, monitor.handle_moisture)
        await client.start_notify(ALERT_CHAR_UUID, monitor.handle_alert)

        # Keep running
        while True:
            await asyncio.sleep(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nMonitor stopped.")
```

### Running the Monitor

```bash
# Install dependencies
pip install bleak

# Run monitor
python scripts/ble_monitor.py
```

---

## Troubleshooting

### Device Not Found

**Symptoms:** App or Python monitor can't find sensor

**Solutions:**
1. Ensure M5StickC is powered on
2. Check display shows "Sensor Ready"
3. Move device closer (BLE range ~10m)
4. Restart Bluetooth on phone/computer
5. Reflash firmware

### Connection Drops

**Symptoms:** Frequent disconnections

**Solutions:**
1. Keep device within 5 meters
2. Avoid interference (WiFi routers, microwaves)
3. Ensure battery is charged (>30%)
4. Update M5StickC firmware

### Wrong Moisture Readings

**Symptoms:** Always 0% or 100%

**Solutions:**
1. Check sensor wire connections
2. Recalibrate values in firmware:
   - Measure raw value in air → MOISTURE_AIR
   - Measure raw value in water → MOISTURE_WATER
3. Ensure sensor is clean (no corrosion)

### High Vibration at Rest

**Symptoms:** Vibration shows >0.1g when stationary

**Solutions:**
1. Place on stable surface during calibration
2. Add vibration offset in firmware:
   ```cpp
   vibration = abs(vibration) - 0.05; // Offset
   ```
3. Ensure sensor is securely mounted

### BLE Characteristics Not Found

**Symptoms:** Service discovered but no characteristics

**Solutions:**
1. Check UUIDs match exactly (lowercase)
2. Reflash firmware
3. Reset BLE on device:
   ```cpp
   BLEDevice::deinit();
   BLEDevice::init("AncientVision-Sensor");
   ```

### Display Not Updating

**Symptoms:** Display shows static text

**Solutions:**
1. Check loop() is running (add Serial.print debug)
2. Ensure M5.update() is called
3. Check battery isn't critically low

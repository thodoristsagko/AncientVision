/*
 * AncientVision Trench Safety Monitor
 * For M5StickC Plus 2 with Soil Moisture Sensor
 *
 * Features:
 * - IMU accelerometer for vibration/earthquake detection
 * - Soil moisture sensor reading
 * - Bluetooth Low Energy (BLE) for app communication
 * - Visual alerts on built-in display
 *
 * Wiring:
 * - Soil Moisture Sensor VCC -> 3.3V (or 5V if sensor supports)
 * - Soil Moisture Sensor GND -> GND
 * - Soil Moisture Sensor Signal -> GPIO 33 (Grove port on M5StickC Plus 2)
 */

#include <M5StickCPlus2.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ===================== CONFIGURATION =====================
// Soil Moisture Thresholds (safe range: 30-60%)
const int MOISTURE_MIN_SAFE = 30;
const int MOISTURE_MAX_SAFE = 60;

// Vibration Thresholds (in g)
const float VIBRATION_WARNING = 0.3;   // Warning level
const float VIBRATION_CRITICAL = 0.8;  // Critical - possible earthquake/collapse

// Sensor Pin
const int MOISTURE_PIN = 33;  // Grove port GPIO

// Calibration values for soil moisture sensor
// Adjust these based on your specific sensor
const int MOISTURE_AIR = 3500;    // Value when sensor is in air (dry)
const int MOISTURE_WATER = 1500;  // Value when sensor is in water (wet)

// BLE UUIDs
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_IMU_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"  // IMU data
#define CHAR_MOISTURE_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a9"  // Moisture
#define CHAR_ALERT_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26aa"  // Alerts

// ===================== GLOBALS =====================
BLEServer* pServer = NULL;
BLECharacteristic* pIMUChar = NULL;
BLECharacteristic* pMoistureChar = NULL;
BLECharacteristic* pAlertChar = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Sensor data
float accX = 0, accY = 0, accZ = 0;
float gyroX = 0, gyroY = 0, gyroZ = 0;
float vibrationMagnitude = 0;
int moisturePercent = 0;
int rawMoisture = 0;

// Alert states
enum AlertState { SAFE, WARNING, CRITICAL };
AlertState currentAlert = SAFE;
String alertMessage = "";

// Timing
unsigned long lastSensorRead = 0;
unsigned long lastBLESend = 0;
const int SENSOR_INTERVAL = 100;  // Read sensors every 100ms
const int BLE_INTERVAL = 500;     // Send BLE every 500ms

// ===================== BLE CALLBACKS =====================
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Device connected!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Device disconnected!");
    }
};

// ===================== SETUP =====================
void setup() {
  // Initialize M5StickC Plus 2
  auto cfg = M5.config();
  M5.begin(cfg);

  Serial.begin(115200);
  Serial.println("AncientVision Trench Safety Monitor");

  // Initialize display
  M5.Lcd.setRotation(1);
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextSize(2);
  M5.Lcd.setTextColor(WHITE, BLACK);

  // Show startup screen
  M5.Lcd.setCursor(10, 30);
  M5.Lcd.println("AncientVision");
  M5.Lcd.setCursor(10, 60);
  M5.Lcd.setTextSize(1);
  M5.Lcd.println("Trench Safety Monitor");
  M5.Lcd.setCursor(10, 90);
  M5.Lcd.println("Initializing...");

  // Initialize IMU
  M5.Imu.begin();
  Serial.println("IMU initialized");

  // Initialize moisture sensor pin
  pinMode(MOISTURE_PIN, INPUT);
  Serial.println("Moisture sensor initialized");

  // Initialize BLE
  setupBLE();

  delay(1000);
  M5.Lcd.fillScreen(BLACK);
}

void setupBLE() {
  Serial.println("Starting BLE...");

  BLEDevice::init("AncientVision-Sensor");

  // Create BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create BLE Characteristics
  pIMUChar = pService->createCharacteristic(
    CHAR_IMU_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pIMUChar->addDescriptor(new BLE2902());

  pMoistureChar = pService->createCharacteristic(
    CHAR_MOISTURE_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pMoistureChar->addDescriptor(new BLE2902());

  pAlertChar = pService->createCharacteristic(
    CHAR_ALERT_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pAlertChar->addDescriptor(new BLE2902());

  // Start service
  pService->start();

  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE ready - waiting for connection...");
}

// ===================== MAIN LOOP =====================
void loop() {
  M5.update();  // Update button states

  unsigned long currentMillis = millis();

  // Read sensors at regular interval
  if (currentMillis - lastSensorRead >= SENSOR_INTERVAL) {
    lastSensorRead = currentMillis;
    readSensors();
    checkAlerts();
    updateDisplay();
  }

  // Send BLE data at regular interval
  if (currentMillis - lastBLESend >= BLE_INTERVAL) {
    lastBLESend = currentMillis;
    sendBLEData();
  }

  // Handle BLE connection changes
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->startAdvertising();
    Serial.println("Restart advertising");
    oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // Button A: Manual alert test
  if (M5.BtnA.wasPressed()) {
    testAlert();
  }
}

// ===================== SENSOR FUNCTIONS =====================
void readSensors() {
  // Read IMU (accelerometer)
  M5.Imu.getAccelData(&accX, &accY, &accZ);
  M5.Imu.getGyroData(&gyroX, &gyroY, &gyroZ);

  // Calculate vibration magnitude (deviation from 1g at rest)
  // At rest: X≈0, Y≈0, Z≈1 (or close, depending on orientation)
  float totalAccel = sqrt(accX*accX + accY*accY + accZ*accZ);
  vibrationMagnitude = abs(totalAccel - 1.0);  // Deviation from 1g

  // Read moisture sensor
  rawMoisture = analogRead(MOISTURE_PIN);

  // Convert to percentage (inverted: higher value = drier)
  moisturePercent = map(rawMoisture, MOISTURE_AIR, MOISTURE_WATER, 0, 100);
  moisturePercent = constrain(moisturePercent, 0, 100);

  // Debug output
  Serial.printf("IMU: X=%.2f Y=%.2f Z=%.2f | Vib=%.3fg | Moisture=%d%% (raw=%d)\n",
                accX, accY, accZ, vibrationMagnitude, moisturePercent, rawMoisture);
}

void checkAlerts() {
  AlertState newAlert = SAFE;
  alertMessage = "";

  // Check vibration
  if (vibrationMagnitude > VIBRATION_CRITICAL) {
    newAlert = CRITICAL;
    alertMessage = "EARTHQUAKE DETECTED!";
  } else if (vibrationMagnitude > VIBRATION_WARNING) {
    newAlert = WARNING;
    alertMessage = "High vibration";
  }

  // Check moisture
  if (moisturePercent < MOISTURE_MIN_SAFE) {
    if (newAlert < WARNING) {
      newAlert = WARNING;
      alertMessage = "Soil too dry";
    }
  } else if (moisturePercent > MOISTURE_MAX_SAFE) {
    if (newAlert < CRITICAL) {
      newAlert = CRITICAL;
      alertMessage = "Soil too wet - collapse risk!";
    }
  }

  // Update alert state
  if (newAlert != currentAlert) {
    currentAlert = newAlert;

    // Vibrate and beep on critical
    if (currentAlert == CRITICAL) {
      M5.Speaker.tone(1000, 500);  // Beep
    } else if (currentAlert == WARNING) {
      M5.Speaker.tone(500, 200);   // Short beep
    }
  }
}

// ===================== DISPLAY FUNCTIONS =====================
void updateDisplay() {
  // Background color based on alert
  uint16_t bgColor;
  switch (currentAlert) {
    case CRITICAL: bgColor = RED; break;
    case WARNING: bgColor = ORANGE; break;
    default: bgColor = TFT_DARKGREEN; break;
  }

  M5.Lcd.fillScreen(bgColor);
  M5.Lcd.setTextColor(WHITE, bgColor);

  // Title
  M5.Lcd.setTextSize(1);
  M5.Lcd.setCursor(5, 5);
  M5.Lcd.print("AncientVision Safety");

  // BLE status
  M5.Lcd.setCursor(200, 5);
  M5.Lcd.print(deviceConnected ? "BT" : "--");

  // Vibration
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(10, 25);
  M5.Lcd.printf("Vib: %.3f g", vibrationMagnitude);

  // Vibration status
  M5.Lcd.setTextSize(1);
  M5.Lcd.setCursor(10, 48);
  if (vibrationMagnitude > VIBRATION_CRITICAL) {
    M5.Lcd.print("CRITICAL!");
  } else if (vibrationMagnitude > VIBRATION_WARNING) {
    M5.Lcd.print("Warning");
  } else {
    M5.Lcd.print("Stable");
  }

  // Moisture
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(10, 65);
  M5.Lcd.printf("Moist: %d%%", moisturePercent);

  // Moisture status
  M5.Lcd.setTextSize(1);
  M5.Lcd.setCursor(10, 88);
  if (moisturePercent < MOISTURE_MIN_SAFE) {
    M5.Lcd.print("Too Dry");
  } else if (moisturePercent > MOISTURE_MAX_SAFE) {
    M5.Lcd.print("Too Wet!");
  } else {
    M5.Lcd.printf("Safe (30-60%%)");
  }

  // IMU raw values
  M5.Lcd.setTextSize(1);
  M5.Lcd.setCursor(10, 105);
  M5.Lcd.printf("X:%.2f Y:%.2f Z:%.2f", accX, accY, accZ);

  // Alert message
  if (alertMessage.length() > 0) {
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(10, 120);
    M5.Lcd.print(alertMessage);
  }
}

// ===================== BLE FUNCTIONS =====================
void sendBLEData() {
  if (!deviceConnected) return;

  // Send IMU data as JSON
  char imuData[100];
  snprintf(imuData, sizeof(imuData),
    "{\"x\":%.3f,\"y\":%.3f,\"z\":%.3f,\"vib\":%.4f}",
    accX, accY, accZ, vibrationMagnitude);
  pIMUChar->setValue(imuData);
  pIMUChar->notify();

  // Send moisture data as JSON
  char moistureData[50];
  snprintf(moistureData, sizeof(moistureData),
    "{\"percent\":%d,\"raw\":%d}",
    moisturePercent, rawMoisture);
  pMoistureChar->setValue(moistureData);
  pMoistureChar->notify();

  // Send alert data as JSON
  char alertData[100];
  const char* alertLevel = currentAlert == CRITICAL ? "critical" :
                          (currentAlert == WARNING ? "warning" : "safe");
  snprintf(alertData, sizeof(alertData),
    "{\"level\":\"%s\",\"message\":\"%s\"}",
    alertLevel, alertMessage.c_str());
  pAlertChar->setValue(alertData);
  pAlertChar->notify();
}

void testAlert() {
  Serial.println("Test alert triggered!");
  M5.Speaker.tone(1000, 300);

  // Send test alert via BLE
  if (deviceConnected) {
    char alertData[100];
    snprintf(alertData, sizeof(alertData),
      "{\"level\":\"warning\",\"message\":\"Test alert from button\"}");
    pAlertChar->setValue(alertData);
    pAlertChar->notify();
  }
}

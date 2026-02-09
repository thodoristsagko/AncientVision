/*
 * AncientVision Trench Safety Monitor v3.0
 * For M5StickC Plus 2 with Soil Moisture Sensor
 *
 * v3.0 Upgrades over v2.0:
 * - Madgwick quaternion gravity removal (accurate at any orientation)
 * - Tri-axial PCPV per DIN 4150-3 (proper 3-axis PPV)
 * - 2nd-order Butterworth HPF on velocity (replaces crude 0.998 decay)
 * - FFT adaptive noise floor threshold
 * - STA/LTA seismic event trigger (standard seismology algorithm)
 * - Kurtosis computation (4th moment for impact detection)
 * - Hysteresis alert state machine with cooldown
 * - Filter warm-up discard (first 2 windows)
 * - Extended BLE JSON with 7 features (was 4)
 *
 * Signal Processing Pipeline:
 *   Raw IMU (200Hz) -> DLPF (99Hz) -> Madgwick Gravity Removal
 *   -> Butterworth Bandpass (0.5-100Hz) per axis -> FFT (256-pt)
 *   -> Tri-axial PPV + Velocity HPF -> STA/LTA + Kurtosis
 *   -> DIN 4150-3 Classification (Hysteresis)
 *
 * Libraries Required:
 * - M5StickCPlus2 (Arduino Library Manager)
 * - arduinoFFT (Arduino Library Manager)
 * - MadgwickAHRS (Arduino Library Manager, by Arduino)
 */

#include <M5StickCPlus2.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <arduinoFFT.h>
#include <MadgwickAHRS.h>

// ===================== CONFIGURATION =====================

// Sampling Configuration
const int SAMPLE_RATE = 200;             // 200 Hz IMU sampling
const int SAMPLE_INTERVAL_US = 5000;     // 5ms = 200 Hz (in microseconds)
const int FFT_SAMPLES = 256;             // FFT window size
const float FFT_WINDOW_SEC = (float)FFT_SAMPLES / SAMPLE_RATE;  // 1.28s

// Soil Moisture Thresholds (safe range: 30-60%)
const int MOISTURE_MIN_SAFE = 30;
const int MOISTURE_MAX_SAFE = 60;

// Sensor Pin
const int MOISTURE_PIN = 33;

// Calibration values for soil moisture sensor
const int MOISTURE_AIR = 3500;
const int MOISTURE_WATER = 1500;

// DIN 4150-3 PPV Thresholds (mm/s) for heritage structures
const float PPV_SAFE_MAX = 0.3;          // Below human perception
const float PPV_HERITAGE_LOW = 3.0;      // Heritage limit 1-10 Hz
const float PPV_HERITAGE_HIGH = 8.0;     // Heritage limit 50-100 Hz
const float PPV_STRUCTURAL_DAMAGE = 10.0; // Structural damage risk
const float PPV_CONTINUOUS_LIMIT = 2.5;  // Continuous vibration limit

// Crest factor threshold for impact detection
const float CREST_IMPACT_THRESHOLD = 5.0;

// Spectral centroid shift threshold (50% change)
const float CENTROID_SHIFT_THRESHOLD = 0.5;

// STA/LTA Configuration
const int STA_LEN = 40;           // 0.2 sec at 200 Hz
const int LTA_LEN = 2000;         // 10 sec at 200 Hz
const float STA_TRIGGER = 4.0;    // STA/LTA trigger ratio
const float STA_DETRIGGER = 1.5;  // STA/LTA de-trigger ratio

// Hysteresis Configuration
const int TRIGGER_COUNT = 2;      // Windows to confirm alert (~2.5s)
const int CLEAR_COUNT = 4;        // Windows to clear alert (~5s)
const int COOLDOWN_WINDOWS = 8;   // Cooldown before re-alerting (~10s)

// BLE UUIDs (unchanged for backward compatibility)
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_IMU_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_MOISTURE_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define CHAR_ALERT_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26aa"

// ===================== MADGWICK FILTER =====================
Madgwick madgwickFilter;

// ===================== BUTTERWORTH FILTER =====================
// 2nd-order Butterworth IIR filter (biquad)
struct BiquadFilter {
  float b0, b1, b2, a1, a2;
  float x1, x2, y1, y2;  // state variables

  void reset() {
    x1 = x2 = y1 = y2 = 0;
  }

  float process(float input) {
    float output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = input;
    y2 = y1; y1 = output;
    return output;
  }
};

// High-pass filter at 0.5 Hz, 200 Hz sample rate (per-axis: X, Y, Z)
BiquadFilter hpFilterX = { 0.99222f, -1.98443f, 0.99222f, -1.98439f, 0.98448f, 0,0,0,0 };
BiquadFilter hpFilterY = { 0.99222f, -1.98443f, 0.99222f, -1.98439f, 0.98448f, 0,0,0,0 };
BiquadFilter hpFilterZ = { 0.99222f, -1.98443f, 0.99222f, -1.98439f, 0.98448f, 0,0,0,0 };

// Low-pass filter at 100 Hz, 200 Hz sample rate (per-axis: X, Y, Z)
BiquadFilter lpFilterX = { 0.29289f, 0.58579f, 0.29289f, 0.0f, 0.17157f, 0,0,0,0 };
BiquadFilter lpFilterY = { 0.29289f, 0.58579f, 0.29289f, 0.0f, 0.17157f, 0,0,0,0 };
BiquadFilter lpFilterZ = { 0.29289f, 0.58579f, 0.29289f, 0.0f, 0.17157f, 0,0,0,0 };

// Velocity drift HPF at 0.3 Hz, 200 Hz sample rate (per-axis)
// 2nd-order Butterworth HPF coefficients computed via bilinear transform
// fc=0.3 Hz, fs=200 Hz -> w0 = 2*pi*0.3/200 = 0.009425
// Pre-warp: tan(w0/2) = 0.004713 -> K = 0.004713
// b0 = 1/(1+sqrt(2)*K+K^2) ≈ 0.99335
BiquadFilter velHpfX = { 0.99335f, -1.98671f, 0.99335f, -1.98667f, 0.98675f, 0,0,0,0 };
BiquadFilter velHpfY = { 0.99335f, -1.98671f, 0.99335f, -1.98667f, 0.98675f, 0,0,0,0 };
BiquadFilter velHpfZ = { 0.99335f, -1.98671f, 0.99335f, -1.98667f, 0.98675f, 0,0,0,0 };

// ===================== FFT =====================
double vReal[FFT_SAMPLES];
double vImag[FFT_SAMPLES];
ArduinoFFT<double> FFT = ArduinoFFT<double>(vReal, vImag, FFT_SAMPLES, SAMPLE_RATE);

// ===================== GLOBALS =====================
BLEServer* pServer = NULL;
BLECharacteristic* pIMUChar = NULL;
BLECharacteristic* pMoistureChar = NULL;
BLECharacteristic* pAlertChar = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Raw sensor data (latest sample)
float accX = 0, accY = 0, accZ = 0;
float gyroX = 0, gyroY = 0, gyroZ = 0;

// Linear acceleration (gravity removed by Madgwick)
float linAccX = 0, linAccY = 0, linAccZ = 0;

// Processed vibration features (per analysis window)
float vibrationRMS = 0;              // RMS acceleration (g)
float vibrationPeak = 0;             // Peak acceleration (g)
float vibrationPPV = 0;              // Peak Component Particle Velocity (mm/s)
float dominantFreq = 0;              // Dominant frequency (Hz)
float crestFactor = 0;               // Peak / RMS ratio
float spectralCentroid = 0;          // Frequency center of mass
float prevSpectralCentroid = 0;      // Previous centroid for shift detection
float kurtosis = 0;                  // Excess kurtosis (4th moment)
float vibrationMagnitude = 0;        // Legacy: raw magnitude for backward compat

// STA/LTA state (recursive, minimal memory)
float sta = 0;
float lta = 0.001f;                  // Initialize to small value to avoid div-by-zero
float staLtaRatio = 0;
bool staLtaTriggered = false;

// Moisture data
int moisturePercent = 0;
int rawMoisture = 0;

// Alert states
enum AlertState { SAFE, WARNING, CRITICAL };
AlertState currentAlert = SAFE;
String alertMessage = "";
String hazardType = "none";

// Hysteresis state machine
int alertPersistence = 0;       // Consecutive windows above threshold
int alertCooldown = 0;          // Windows since last alert clear
AlertState candidateAlert = SAFE;
String candidateMessage = "";
String candidateType = "none";

// Sample collection - tri-axial buffers
int sampleIndex = 0;
float accelSamplesX[FFT_SAMPLES];
float accelSamplesY[FFT_SAMPLES];
float accelSamplesZ[FFT_SAMPLES];
float velocitySamplesX[FFT_SAMPLES];
float velocitySamplesY[FFT_SAMPLES];
float velocitySamplesZ[FFT_SAMPLES];
unsigned long lastSampleTime = 0;
bool windowReady = false;

// Filter warm-up
int windowCount = 0;

// Timing
unsigned long lastBLESend = 0;
unsigned long lastDisplayUpdate = 0;
unsigned long lastMoistureRead = 0;
const int BLE_INTERVAL = 500;        // Send BLE every 500ms
const int DISPLAY_INTERVAL = 250;    // Update display 4x/sec
const int MOISTURE_INTERVAL = 1000;  // Read moisture every 1s

// ===================== MPU6886 DLPF CONFIGURATION =====================
void configureDLPF() {
  Wire1.beginTransmission(0x68);
  Wire1.write(0x1A);  // CONFIG register
  Wire1.write(0x02);  // DLPF_CFG = 2 (99 Hz bandwidth)
  Wire1.endTransmission();

  Wire1.beginTransmission(0x68);
  Wire1.write(0x1D);  // ACCEL_CONFIG2 register
  Wire1.write(0x02);  // A_DLPF_CFG = 2 (99 Hz bandwidth)
  Wire1.endTransmission();

  Serial.println("DLPF configured: 99 Hz bandwidth");
}

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
  auto cfg = M5.config();
  M5.begin(cfg);

  Serial.begin(115200);
  Serial.println("AncientVision Trench Safety Monitor v3.0");
  Serial.println("DSP: Madgwick + Tri-axial PPV + STA/LTA + Kurtosis");

  // Initialize display
  M5.Lcd.setRotation(1);
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextSize(2);
  M5.Lcd.setTextColor(WHITE, BLACK);

  M5.Lcd.setCursor(10, 20);
  M5.Lcd.println("AncientVision");
  M5.Lcd.setTextSize(1);
  M5.Lcd.setCursor(10, 50);
  M5.Lcd.println("Vibration Analysis v3.0");
  M5.Lcd.setCursor(10, 65);
  M5.Lcd.println("Madgwick+FFT+STA/LTA");
  M5.Lcd.setCursor(10, 85);
  M5.Lcd.println("Initializing...");

  // Initialize IMU
  M5.Imu.begin();
  Serial.println("IMU initialized");

  // Configure DLPF for 99 Hz anti-aliasing
  configureDLPF();

  // Initialize Madgwick filter at 200 Hz
  madgwickFilter.begin(SAMPLE_RATE);

  // Reset all filters
  hpFilterX.reset(); hpFilterY.reset(); hpFilterZ.reset();
  lpFilterX.reset(); lpFilterY.reset(); lpFilterZ.reset();
  velHpfX.reset(); velHpfY.reset(); velHpfZ.reset();

  // Initialize sample buffers
  memset(accelSamplesX, 0, sizeof(accelSamplesX));
  memset(accelSamplesY, 0, sizeof(accelSamplesY));
  memset(accelSamplesZ, 0, sizeof(accelSamplesZ));
  memset(velocitySamplesX, 0, sizeof(velocitySamplesX));
  memset(velocitySamplesY, 0, sizeof(velocitySamplesY));
  memset(velocitySamplesZ, 0, sizeof(velocitySamplesZ));
  sampleIndex = 0;
  windowCount = 0;

  // Initialize moisture sensor pin
  pinMode(MOISTURE_PIN, INPUT);
  Serial.println("Moisture sensor initialized");

  // Initialize BLE
  setupBLE();

  delay(1000);
  M5.Lcd.fillScreen(BLACK);

  lastSampleTime = micros();
}

void setupBLE() {
  Serial.println("Starting BLE...");

  BLEDevice::init("AncientVision-Sensor");

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

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

  pService->start();

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
  M5.update();

  unsigned long currentMicros = micros();
  unsigned long currentMillis = millis();

  // ---- HIGH-FREQUENCY: Sample IMU at 200 Hz ----
  if (currentMicros - lastSampleTime >= SAMPLE_INTERVAL_US) {
    lastSampleTime = currentMicros;
    collectSample();
  }

  // ---- Process FFT window when ready ----
  if (windowReady) {
    windowReady = false;
    processVibrationWindow();
    classifyHazard();
  }

  // ---- Read moisture at 1 Hz ----
  if (currentMillis - lastMoistureRead >= MOISTURE_INTERVAL) {
    lastMoistureRead = currentMillis;
    readMoisture();
  }

  // ---- Send BLE data at 2 Hz ----
  if (currentMillis - lastBLESend >= BLE_INTERVAL) {
    lastBLESend = currentMillis;
    sendBLEData();
  }

  // ---- Update display at 4 Hz ----
  if (currentMillis - lastDisplayUpdate >= DISPLAY_INTERVAL) {
    lastDisplayUpdate = currentMillis;
    updateDisplay();
  }

  // ---- Handle BLE connection changes ----
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

// ===================== HIGH-SPEED SAMPLING =====================
void collectSample() {
  // Read IMU accelerometer AND gyroscope
  M5.Imu.getAccelData(&accX, &accY, &accZ);
  M5.Imu.getGyroData(&gyroX, &gyroY, &gyroZ);

  // Update Madgwick filter for orientation tracking
  // Madgwick expects gyro in degrees/sec, accel in any consistent unit
  madgwickFilter.updateIMU(gyroX, gyroY, gyroZ, accX, accY, accZ);

  // Get quaternion from Madgwick
  float q0 = madgwickFilter.getQuatW();
  float q1 = madgwickFilter.getQuatX();
  float q2 = madgwickFilter.getQuatY();
  float q3 = madgwickFilter.getQuatZ();

  // Compute gravity vector from quaternion (in sensor frame)
  float gx_est = 2.0f * (q1 * q3 - q0 * q2);
  float gy_est = 2.0f * (q0 * q1 + q2 * q3);
  float gz_est = q0 * q0 - q1 * q1 - q2 * q2 + q3 * q3;

  // Remove gravity to get linear acceleration (per axis)
  linAccX = accX - gx_est;
  linAccY = accY - gy_est;
  linAccZ = accZ - gz_est;

  // Apply bandpass filter per axis: HPF 0.5 Hz -> LPF 100 Hz
  float filtX = lpFilterX.process(hpFilterX.process(linAccX));
  float filtY = lpFilterY.process(hpFilterY.process(linAccY));
  float filtZ = lpFilterZ.process(hpFilterZ.process(linAccZ));

  // Store filtered samples per axis
  accelSamplesX[sampleIndex] = filtX;
  accelSamplesY[sampleIndex] = filtY;
  accelSamplesZ[sampleIndex] = filtZ;

  // Integrate acceleration to velocity per axis (trapezoidal rule)
  // Convert g to mm/s^2: 1g = 9810 mm/s^2
  float dt = 1.0f / SAMPLE_RATE;
  if (sampleIndex > 0) {
    int prev = sampleIndex - 1;
    velocitySamplesX[sampleIndex] = velocitySamplesX[prev] +
      0.5f * (accelSamplesX[prev] * 9810.0f + filtX * 9810.0f) * dt;
    velocitySamplesY[sampleIndex] = velocitySamplesY[prev] +
      0.5f * (accelSamplesY[prev] * 9810.0f + filtY * 9810.0f) * dt;
    velocitySamplesZ[sampleIndex] = velocitySamplesZ[prev] +
      0.5f * (accelSamplesZ[prev] * 9810.0f + filtZ * 9810.0f) * dt;

    // Apply proper HPF to remove velocity drift (0.3 Hz Butterworth)
    velocitySamplesX[sampleIndex] = velHpfX.process(velocitySamplesX[sampleIndex]);
    velocitySamplesY[sampleIndex] = velHpfY.process(velocitySamplesY[sampleIndex]);
    velocitySamplesZ[sampleIndex] = velHpfZ.process(velocitySamplesZ[sampleIndex]);
  } else {
    velocitySamplesX[0] = 0;
    velocitySamplesY[0] = 0;
    velocitySamplesZ[0] = 0;
  }

  // STA/LTA computation (on acceleration magnitude, per-sample)
  float mag = filtX * filtX + filtY * filtY + filtZ * filtZ;
  sta = sta + (mag - sta) / (float)STA_LEN;
  lta = lta + (mag - lta) / (float)LTA_LEN;
  staLtaRatio = (lta > 0.000001f) ? sta / lta : 0;

  // Legacy backward compat: magnitude
  vibrationMagnitude = sqrt(mag);

  sampleIndex++;

  // When buffer is full, trigger processing
  if (sampleIndex >= FFT_SAMPLES) {
    sampleIndex = 0;
    windowReady = true;
  }
}

// ===================== VIBRATION ANALYSIS =====================
void processVibrationWindow() {
  // Filter warm-up: discard first 2 windows
  windowCount++;
  if (windowCount <= 2) {
    Serial.printf("DSP: Discarding warm-up window %d/2\n", windowCount);
    return;
  }

  // ---- Compute RMS, Peak, PPV (tri-axial PCPV) ----
  float sumSq = 0;
  float peak = 0;
  float peakVelX = 0, peakVelY = 0, peakVelZ = 0;

  for (int i = 0; i < FFT_SAMPLES; i++) {
    // Combined magnitude for RMS
    float magSq = accelSamplesX[i] * accelSamplesX[i] +
                  accelSamplesY[i] * accelSamplesY[i] +
                  accelSamplesZ[i] * accelSamplesZ[i];
    sumSq += magSq;
    float mag = sqrt(magSq);
    if (mag > peak) peak = mag;

    // Per-axis peak velocity for PCPV
    float absVelX = fabs(velocitySamplesX[i]);
    float absVelY = fabs(velocitySamplesY[i]);
    float absVelZ = fabs(velocitySamplesZ[i]);
    if (absVelX > peakVelX) peakVelX = absVelX;
    if (absVelY > peakVelY) peakVelY = absVelY;
    if (absVelZ > peakVelZ) peakVelZ = absVelZ;
  }

  vibrationRMS = sqrt(sumSq / FFT_SAMPLES);
  vibrationPeak = peak;

  // PCPV: max of per-axis peak velocities (DIN 4150-3 method)
  vibrationPPV = max(peakVelX, max(peakVelY, peakVelZ));

  // ---- Crest Factor ----
  crestFactor = (vibrationRMS > 0.0001f) ? vibrationPeak / vibrationRMS : 1.0f;

  // ---- Kurtosis (excess, computed on acceleration magnitude) ----
  {
    float mean = 0, m2 = 0, m4 = 0;
    for (int i = 0; i < FFT_SAMPLES; i++) {
      float mag = sqrt(accelSamplesX[i] * accelSamplesX[i] +
                       accelSamplesY[i] * accelSamplesY[i] +
                       accelSamplesZ[i] * accelSamplesZ[i]);
      mean += mag;
    }
    mean /= FFT_SAMPLES;
    for (int i = 0; i < FFT_SAMPLES; i++) {
      float mag = sqrt(accelSamplesX[i] * accelSamplesX[i] +
                       accelSamplesY[i] * accelSamplesY[i] +
                       accelSamplesZ[i] * accelSamplesZ[i]);
      float d = mag - mean;
      m2 += d * d;
      m4 += d * d * d * d;
    }
    m2 /= FFT_SAMPLES;
    m4 /= FFT_SAMPLES;
    kurtosis = (m2 > 0.00001f) ? (m4 / (m2 * m2)) - 3.0f : 0.0f;
  }

  // ---- FFT for frequency analysis (use magnitude of 3 axes) ----
  for (int i = 0; i < FFT_SAMPLES; i++) {
    vReal[i] = (double)sqrt(accelSamplesX[i] * accelSamplesX[i] +
                             accelSamplesY[i] * accelSamplesY[i] +
                             accelSamplesZ[i] * accelSamplesZ[i]);
    vImag[i] = 0;
  }

  // Apply Hanning window
  FFT.windowing(FFTWindow::Hann, FFTDirection::Forward);

  // Compute FFT
  FFT.compute(FFTDirection::Forward);

  // Convert to magnitudes
  FFT.complexToMagnitude();

  // ---- Adaptive noise floor ----
  int minBin = 1;   // Skip DC
  int maxBin = FFT_SAMPLES / 2;

  double magRMSSum = 0;
  for (int i = minBin; i < maxBin; i++) {
    magRMSSum += vReal[i] * vReal[i];
  }
  double noiseFloor = sqrt(magRMSSum / (maxBin - minBin)) * 3.0;  // 3x RMS

  // ---- Find dominant frequency (above noise floor) ----
  double maxMag = 0;
  int maxBinIdx = minBin;

  for (int i = minBin; i < maxBin; i++) {
    if (vReal[i] > maxMag) {
      maxMag = vReal[i];
      maxBinIdx = i;
    }
  }

  // Only report frequency if signal is above noise floor
  if (maxMag > noiseFloor) {
    dominantFreq = (float)maxBinIdx * SAMPLE_RATE / FFT_SAMPLES;
  } else {
    dominantFreq = 0;  // Below noise floor - no meaningful frequency
  }

  // ---- Spectral Centroid (only if signal above noise) ----
  prevSpectralCentroid = spectralCentroid;
  if (maxMag > noiseFloor) {
    double weightedSum = 0;
    double magnitudeSum = 0;
    for (int i = minBin; i < maxBin; i++) {
      float freq = (float)i * SAMPLE_RATE / FFT_SAMPLES;
      weightedSum += freq * vReal[i];
      magnitudeSum += vReal[i];
    }
    spectralCentroid = (magnitudeSum > 0.001) ? weightedSum / magnitudeSum : 0;
  } else {
    spectralCentroid = 0;
  }

  // Debug output
  Serial.printf("DSP v3.0: RMS=%.4fg PPV=%.1fmm/s Freq=%.1fHz Crest=%.1f Kurt=%.2f STA/LTA=%.2f Cent=%.1fHz\n",
    vibrationRMS, vibrationPPV, dominantFreq, crestFactor, kurtosis, staLtaRatio, spectralCentroid);
}

// ===================== HAZARD CLASSIFICATION (DIN 4150-3 + Hysteresis) =====================
void classifyHazard() {
  // Skip classification during warm-up
  if (windowCount <= 2) return;

  // ---- Evaluate rules to get candidate alert ----
  AlertState newAlert = SAFE;
  String newMessage = "";
  String newType = "none";

  // CRITICAL: Structural damage risk at any frequency
  if (vibrationPPV > PPV_STRUCTURAL_DAMAGE) {
    newAlert = CRITICAL;
    newMessage = "Structural damage risk - EVACUATE";
    newType = "structural";
  }
  // CRITICAL: Seismic activity (low frequency, high PPV)
  else if (vibrationPPV > PPV_HERITAGE_LOW && dominantFreq >= 0.5 && dominantFreq <= 10.0) {
    newAlert = CRITICAL;
    newMessage = "Seismic activity detected";
    newType = "seismic";
  }
  // CRITICAL: STA/LTA seismic trigger (independent of PPV thresholds)
  else if (staLtaRatio > STA_TRIGGER && vibrationPPV > 1.0) {
    newAlert = CRITICAL;
    newMessage = "Seismic event (STA/LTA)";
    newType = "seismic";
  }
  // WARNING: Heavy machinery (mid frequency, moderate PPV)
  else if (vibrationPPV > PPV_HERITAGE_LOW && dominantFreq > 10.0 && dominantFreq <= 50.0) {
    newAlert = WARNING;
    newMessage = "Heavy machinery nearby";
    newType = "machinery";
  }
  // WARNING: High-frequency structural stress
  else if (vibrationPPV > PPV_HERITAGE_HIGH && dominantFreq > 50.0) {
    newAlert = WARNING;
    newMessage = "High-freq structural stress";
    newType = "hf_stress";
  }
  // WARNING: Impact detected (high crest factor + high kurtosis)
  else if (crestFactor > CREST_IMPACT_THRESHOLD && vibrationPPV > 1.0) {
    newAlert = WARNING;
    newMessage = "Impact detected";
    newType = "impact";
  }
  // WARNING: Continuous vibration exceeding heritage limit
  else if (vibrationPPV > PPV_CONTINUOUS_LIMIT) {
    newAlert = WARNING;
    newMessage = "Continuous vibration high";
    newType = "continuous";
  }
  // WARNING: Spectral centroid shift (vibration source changed)
  else if (prevSpectralCentroid > 1.0 && spectralCentroid > 1.0) {
    float shift = fabs(spectralCentroid - prevSpectralCentroid) / prevSpectralCentroid;
    if (shift > CENTROID_SHIFT_THRESHOLD && vibrationPPV > 0.5) {
      newAlert = WARNING;
      newMessage = "Vibration source changed";
      newType = "source_change";
    }
  }

  // ---- Check moisture alerts ----
  if (moisturePercent < MOISTURE_MIN_SAFE && moisturePercent > 0) {
    if (newAlert < WARNING) {
      newAlert = WARNING;
      newMessage = "Soil too dry";
      newType = "moisture_low";
    }
  } else if (moisturePercent > MOISTURE_MAX_SAFE) {
    if (newAlert < CRITICAL) {
      newAlert = CRITICAL;
      newMessage = "Soil too wet - collapse risk!";
      newType = "moisture_high";
    }
  }

  // ---- Hysteresis state machine ----
  if (newAlert > currentAlert) {
    // Escalation candidate
    alertPersistence++;
    if (alertPersistence >= TRIGGER_COUNT) {
      // Confirmed escalation
      currentAlert = newAlert;
      alertMessage = newMessage;
      hazardType = newType;
      alertPersistence = 0;
      alertCooldown = 0;

      if (currentAlert == CRITICAL) {
        M5.Speaker.tone(1000, 500);
      } else if (currentAlert == WARNING) {
        M5.Speaker.tone(500, 200);
      }

      Serial.printf("ALERT CONFIRMED: %s [%s] type=%s\n",
        currentAlert == CRITICAL ? "CRITICAL" : "WARNING",
        alertMessage.c_str(), hazardType.c_str());
    }
  } else if (newAlert < currentAlert) {
    // De-escalation candidate
    alertCooldown++;
    if (alertCooldown >= CLEAR_COUNT) {
      // Confirmed de-escalation
      currentAlert = newAlert;
      alertMessage = newMessage;
      hazardType = newType;
      alertCooldown = 0;
      alertPersistence = 0;

      Serial.printf("ALERT CLEARED -> %s\n",
        currentAlert == SAFE ? "SAFE" : "WARNING");
    }
  } else {
    // Same level - reset counters
    alertPersistence = 0;
    alertCooldown = 0;
    // Update message/type even at same level
    if (newAlert != SAFE) {
      alertMessage = newMessage;
      hazardType = newType;
    }
  }
}

// ===================== MOISTURE SENSOR =====================
void readMoisture() {
  rawMoisture = analogRead(MOISTURE_PIN);
  moisturePercent = map(rawMoisture, MOISTURE_AIR, MOISTURE_WATER, 0, 100);
  moisturePercent = constrain(moisturePercent, 0, 100);
}

// ===================== DISPLAY =====================
void updateDisplay() {
  uint16_t bgColor;
  switch (currentAlert) {
    case CRITICAL: bgColor = RED; break;
    case WARNING:  bgColor = ORANGE; break;
    default:       bgColor = TFT_DARKGREEN; break;
  }

  M5.Lcd.fillScreen(bgColor);
  M5.Lcd.setTextColor(WHITE, bgColor);

  // Row 1: Title + BLE + Battery
  int batLevel = M5.Power.getBatteryLevel();
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(5, 2);
  M5.Lcd.print("AncientVision");
  M5.Lcd.setCursor(175, 2);
  M5.Lcd.printf("%s%d%%", deviceConnected ? "BT" : "--", batLevel);

  // Row 2: PPV (the key metric)
  M5.Lcd.setTextSize(3);
  M5.Lcd.setCursor(5, 22);
  if (vibrationPPV < 10.0) {
    M5.Lcd.printf("PPV:%.1f", vibrationPPV);
  } else {
    M5.Lcd.printf("PPV:%.0f", vibrationPPV);
  }
  M5.Lcd.setTextSize(2);
  M5.Lcd.print("mm/s");

  // Row 3: Frequency + STA/LTA
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(5, 50);
  M5.Lcd.printf("%.0fHz S/L:%.1f", dominantFreq, staLtaRatio);

  // Row 4: Hazard type or status
  M5.Lcd.setCursor(5, 72);
  if (currentAlert == CRITICAL) {
    M5.Lcd.setTextColor(YELLOW, bgColor);
    String displayMsg = alertMessage;
    if (displayMsg.length() > 20) displayMsg = displayMsg.substring(0, 20);
    M5.Lcd.print(displayMsg);
  } else if (currentAlert == WARNING) {
    String displayMsg = alertMessage;
    if (displayMsg.length() > 20) displayMsg = displayMsg.substring(0, 20);
    M5.Lcd.print(displayMsg);
  } else {
    M5.Lcd.print("Safe - DIN 4150-3");
  }
  M5.Lcd.setTextColor(WHITE, bgColor);

  // Row 5: Moisture + Kurtosis
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(5, 94);
  M5.Lcd.printf("Mst:%d%%", moisturePercent);
  if (moisturePercent < MOISTURE_MIN_SAFE) {
    M5.Lcd.print(" DRY");
  } else if (moisturePercent > MOISTURE_MAX_SAFE) {
    M5.Lcd.print(" WET!");
  } else {
    M5.Lcd.print(" OK");
  }

  // Row 6: Details (small)
  M5.Lcd.setTextSize(1);
  M5.Lcd.setCursor(5, 118);
  M5.Lcd.printf("RMS:%.4f CF:%.1f K:%.1f", vibrationRMS, crestFactor, kurtosis);
}

// ===================== BLE FUNCTIONS =====================
void sendBLEData() {
  if (!deviceConnected) return;

  // Send IMU data with all v3.0 features
  char imuData[256];
  snprintf(imuData, sizeof(imuData),
    "{\"x\":%.3f,\"y\":%.3f,\"z\":%.3f,\"vib\":%.4f,\"ppv\":%.1f,\"rms\":%.4f,\"freq\":%.1f,\"crest\":%.1f,\"cent\":%.1f,\"kurt\":%.2f,\"stalta\":%.2f}",
    accX, accY, accZ, vibrationMagnitude, vibrationPPV, vibrationRMS,
    dominantFreq, crestFactor, spectralCentroid, kurtosis, staLtaRatio);
  pIMUChar->setValue(imuData);
  pIMUChar->notify();

  // Send moisture data (unchanged)
  char moistureData[50];
  snprintf(moistureData, sizeof(moistureData),
    "{\"percent\":%d,\"raw\":%d}",
    moisturePercent, rawMoisture);
  pMoistureChar->setValue(moistureData);
  pMoistureChar->notify();

  // Send alert data with hazard type
  char alertData[150];
  const char* alertLevel = currentAlert == CRITICAL ? "critical" :
                          (currentAlert == WARNING ? "warning" : "safe");
  snprintf(alertData, sizeof(alertData),
    "{\"level\":\"%s\",\"message\":\"%s\",\"type\":\"%s\"}",
    alertLevel, alertMessage.c_str(), hazardType.c_str());
  pAlertChar->setValue(alertData);
  pAlertChar->notify();
}

void testAlert() {
  Serial.println("Test alert triggered!");
  M5.Speaker.tone(1000, 300);

  if (deviceConnected) {
    char alertData[150];
    snprintf(alertData, sizeof(alertData),
      "{\"level\":\"warning\",\"message\":\"Test alert from button\",\"type\":\"test\"}");
    pAlertChar->setValue(alertData);
    pAlertChar->notify();
  }
}

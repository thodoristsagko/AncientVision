import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/alert_data.dart';
import '../widgets/safety_widgets.dart';
import '../widgets/full_screen_alert_overlay.dart';
import '../services/vibration_anomaly_service.dart';
import '../services/vibration_metrics_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/wavelet_service.dart';
import '../widgets/spectrogram_widget.dart';
import '../services/ppv_prediction_service.dart';
import '../utils/fft_ble_parser.dart';
import '../utils/circular_buffer.dart';
import 'vibration_event_log_screen.dart';

const String _bleSensorServiceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";

class SafetyView extends StatefulWidget {
  final bool isMuted;
  final VoidCallback onToggleMute;
  final void Function(String message, String level) onAlert;

  const SafetyView({
    super.key,
    required this.isMuted,
    required this.onToggleMute,
    required this.onAlert,
  });

  @override
  State<SafetyView> createState() => _SafetyViewState();
}

class _SafetyViewState extends State<SafetyView> with AutomaticKeepAliveClientMixin {
  // Keep the BLE connection alive when switching tabs
  @override
  bool get wantKeepAlive => true;

  BluetoothDevice? _connectedDevice;
  bool _isScanning = false;
  bool _isConnecting = false;
  String _connectionStatus = 'Disconnected';
  int? _lastRssi;

  double _accX = 0.0, _accY = 0.0, _accZ = 0.0;
  double _vibration = 0.0;
  int _moisturePercent = 0;
  String _alertLevel = 'safe';
  String _alertMessage = '';
  String _lastUpdate = '--:--';

  // New v2.0 vibration analysis fields from firmware
  double _ppv = 0.0;           // Peak Particle Velocity (mm/s)
  double _rms = 0.0;           // RMS acceleration (g)
  double _dominantFreq = 0.0;  // Dominant frequency (Hz)
  double _crestFactor = 0.0;   // Crest factor (Peak/RMS)
  String _hazardType = 'none'; // Hazard classification type

  // v3.0 fields
  double _centroid = 0.0;      // Spectral centroid (Hz)
  double _kurtosis = 0.0;      // Excess kurtosis
  double _staLtaRatio = 0.0;   // STA/LTA ratio
  double _ppvSmoothed = 0.0;   // EMA smoothed PPV
  double _ppvPeakHold = 0.0;   // 5-second peak hold
  DateTime _ppvPeakTime = DateTime.now();

  // v4.0 fields
  double _arias = 0.0;         // Arias Intensity (m/s)
  double _cav = 0.0;           // Cumulative Absolute Velocity (g·s)
  double _temp = 0.0;          // IMU temperature (°C)
  double _dwt1 = 0.0;          // DWT level 1 energy (50-100Hz)
  double _dwt2 = 0.0;          // DWT level 2 energy (25-50Hz)
  double _dwt3 = 0.0;          // DWT level 3 energy (12-25Hz)

  // v4.1 fields
  double _batteryVoltage = 0.0;  // Battery voltage (V)
  int _batteryPercent = 100;      // Battery percentage (0-100%)
  bool _batteryCharging = false;  // Charging status

  // Wavelet analysis (app-side DWT on rolling buffer)
  // Using CircularBuffer for O(1) eviction (Knuth Vol.1 S2.2.2)
  final CircularBuffer<double> _waveletBuffer = CircularBuffer(256);
  Map<String, double> _waveletBandEnergy = {};
  List<TransientEvent> _waveletTransients = [];
  bool _transientFlash = false;
  DateTime _lastTransientTime = DateTime(2000);

  // Spectrogram rolling buffer (synthesized from BLE frequency data)
  final SpectrogramBuffer _spectrogramBuffer = SpectrogramBuffer(maxColumns: 120);
  String _spectrogramColorMap = 'viridis';

  // PPV history for trend graph (DIN 4150-3)
  final CircularBuffer<Map<String, dynamic>> _ppvHistory = CircularBuffer(60);

  // Vibration feature log for ML training data
  final CircularBuffer<Map<String, dynamic>> _vibrationFeatureLog = CircularBuffer(500);

  // Kalman filter + trend prediction (v4.2)
  final _kalmanFilter = KalmanPPVFilter(q: 0.01, r: 0.5);
  final _trendPredictor = PPVTrendPredictor(windowSize: 20, sampleIntervalSec: 0.5);
  double _ppvKalman = 0.0;
  PPVPrediction? _ppvPrediction;
  final CircularBuffer<double> _ppvKalmanHistory = CircularBuffer(60);

  // ML Anomaly Detection (Tier 2)
  final _anomalyService = VibrationAnomalyService();
  AnomalyResult _lastAnomalyResult = const AnomalyResult(score: 0, level: AnomalyLevel.unknown, rawError: 0);
  bool _mlModelLoaded = false;
  final CircularBuffer<double> _anomalyScoreHistory = CircularBuffer(30);
  Map<String, double> _lastMLFeatures = {}; // features passed to last detect() call

  // Multi-standard classification (VibrationMetricsService)
  List<StandardClassification> _standardClassifications = [];
  final VibrationMetrics _vibrationMetrics = VibrationMetrics();
  double _housnerSI = 0.0;

  final List<AlertData> _alerts = [];

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  final List<StreamSubscription> _charSubscriptions = [];

  final bool _isSimulating = false;
  Timer? _simulationTimer;
  Timer? _firebaseLogTimer;
  final CircularBuffer<Map<String, dynamic>> _sensorHistory = CircularBuffer(30);

  // Enhanced connection management
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;
  DateTime? _lastDataReceived;
  DateTime? _keepAliveStartTime;
  String? _lastNotifiedAlertLevel; // Prevent duplicate notifications
  int _truncatedPackets = 0; // Count of dropped truncated BLE packets

  // Simple/Detailed view mode toggle (simple by default for archaeologist UX)
  bool _simpleMode = true;

  // FFT BLE data from firmware (real spectral bins)
  FftBleData? _lastFftData;

  // BLE characteristic references for bidirectional communication
  BluetoothCharacteristic? _alertCharacteristic;

  @override
  void initState() {
    super.initState();
    _checkBluetoothAndScan();
    _startFirebaseLogging();
    _loadSensorHistory();
    _initAnomalyModel();
  }

  Future<void> _initAnomalyModel() async {
    final success = await _anomalyService.initialize();
    if (mounted) {
      setState(() => _mlModelLoaded = success);
    }
    debugPrint('Anomaly detection ready: ${_anomalyService.modeLabel}');
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    for (var sub in _charSubscriptions) {
      sub.cancel();
    }
    _simulationTimer?.cancel();
    _firebaseLogTimer?.cancel();
    _reconnectTimer?.cancel();
    _keepAliveTimer?.cancel();
    _anomalyService.dispose();
    super.dispose();
  }

  Future<void> _checkBluetoothAndScan() async {
    if (await FlutterBluePlus.isSupported == false) {
      _showError('Bluetooth not supported');
      return;
    }
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      setState(() => _connectionStatus = 'Bluetooth OFF');
      return;
    }

    // FIRST: Check if device is already connected
    try {
      final lockedMac = SettingsService().settings.lockedSensorMac;
      final connectedDevices = FlutterBluePlus.connectedDevices;
      for (final device in connectedDevices) {
        // If MAC is locked, only connect to that exact device
        if (lockedMac.isNotEmpty) {
          if (device.remoteId.str.toLowerCase() != lockedMac.toLowerCase()) continue;
        } else {
          final name = device.platformName.toLowerCase();
          if (!(name.contains('ancientvision') || name.contains('ancient') ||
              name.contains('m5stick') || name.contains('m5-') || name.startsWith('m5'))) {
            continue;
          }
        }
        debugPrint('>>> ALREADY CONNECTED: ${device.platformName} - subscribing to data...');
        setState(() {
          _connectedDevice = device;
          _connectionStatus = 'Connected';
          _isConnecting = false;
          _isScanning = false;
        });
        _startKeepAliveMonitor();
        // Request larger MTU for already-connected devices too
        try {
          final mtu = await device.requestMtu(512);
          debugPrint('>>> MTU negotiated (already connected): $mtu');
        } catch (e) {
          debugPrint('>>> MTU request failed (non-fatal): $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
        await _discoverAndSubscribe(device);
        return;
      }
    } catch (e) {
      debugPrint('Error checking connected devices: $e');
    }

    // If not already connected, start scanning
    _startScan();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _connectionStatus = 'Scanning...';
    });

    try {
      // Scan for ALL BLE devices (don't filter by service - ESP32 may not advertise it)
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),
      );

      int devicesFound = 0;
      final lockedMac = SettingsService().settings.lockedSensorMac;
      bool alreadyMatched = false;
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (alreadyMatched || _isConnecting || _connectedDevice != null) return;
        for (ScanResult r in results) {
          final name = r.device.platformName;
          final nameLower = name.toLowerCase();

          // Log all devices found for debugging
          if (name.isNotEmpty && devicesFound < 20) {
            debugPrint('BLE Found: "$name" (${r.device.remoteId}) RSSI=${r.rssi}');
            devicesFound++;
          }

          // If MAC is locked, only connect to that exact device
          bool matched = false;
          if (lockedMac.isNotEmpty) {
            matched = r.device.remoteId.str.toLowerCase() == lockedMac.toLowerCase();
          } else {
            // Match our device by name (case insensitive)
            matched = nameLower.contains('ancientvision') ||
                nameLower.contains('ancient') ||
                nameLower.contains('m5stick') ||
                nameLower.contains('m5-') ||
                nameLower.startsWith('m5');
          }

          if (matched) {
            alreadyMatched = true;
            debugPrint('>>> MATCHED DEVICE: $name (${r.device.remoteId}) - connecting...');
            FlutterBluePlus.stopScan();
            _scanSubscription?.cancel();
            _connectToDevice(r.device);
            return; // Exit the listener
          }
        }
      });

      await Future.delayed(const Duration(seconds: 20));
      if (_connectedDevice == null && !_isConnecting && !alreadyMatched && mounted) {
        setState(() {
          _isScanning = false;
          _connectionStatus = 'Sensor not found - check device is on';
        });
        debugPrint('Scan complete - AncientVision device not found');
      }
    } catch (e) {
      debugPrint('BLE Scan error: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _connectionStatus = 'Scan failed: $e';
        });
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
    });

    try {
      // Enable auto-connect for persistent connection
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: true,
      );

      setState(() {
        _connectedDevice = device;
        _isConnecting = false;
        _isScanning = false;
        _connectionStatus = 'Connected';
        _reconnectAttempts = 0; // Reset on successful connection
      });

      // Start keepalive monitoring
      _startKeepAliveMonitor();

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          _handleDisconnection();
        } else if (state == BluetoothConnectionState.connected && mounted) {
          setState(() {
            _connectionStatus = 'Connected';
            _reconnectAttempts = 0;
            _truncatedPackets = 0;
          });
        }
      });

      // Request larger MTU so BLE JSON payloads are not truncated
      try {
        final mtu = await device.requestMtu(512);
        debugPrint('>>> MTU negotiated: $mtu');
      } catch (e) {
        debugPrint('>>> MTU request failed (non-fatal): $e');
      }

      // Small delay to let MTU take effect before service discovery
      await Future.delayed(const Duration(milliseconds: 500));

      await _discoverAndSubscribe(device);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionStatus = 'Connection failed';
        });
        // Auto-retry with exponential backoff
        _scheduleReconnect();
      }
    }
  }

  /// Handle device disconnection with smart reconnect
  void _handleDisconnection() {
    if (!mounted) return;
    final deviceName = _connectedDevice?.platformName ?? 'Sensor';

    setState(() {
      _connectedDevice = null;
      _lastRssi = null;
      _connectionStatus = 'Reconnecting...';
    });

    // Send notification about disconnection
    NotificationService().showDeviceDisconnected(deviceName: deviceName);

    // Cancel keepalive
    _keepAliveTimer?.cancel();

    // Schedule reconnect with exponential backoff
    _scheduleReconnect();
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      setState(() => _connectionStatus = 'Connection lost - tap Scan');
      return;
    }

    // Exponential backoff: 1s, 2s, 4s, 8s... max 30s
    final delaySeconds = (1 << _reconnectAttempts).clamp(1, 30);
    _reconnectAttempts++;

    setState(() {
      _connectionStatus = 'Reconnecting in ${delaySeconds}s... ($_reconnectAttempts/$_maxReconnectAttempts)';
    });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && _connectedDevice == null) {
        _startScan();
      }
    });
  }

  /// Monitor connection health and request RSSI periodically
  void _startKeepAliveMonitor() {
    _keepAliveTimer?.cancel();
    _lastDataReceived = DateTime.now();
    _keepAliveStartTime = DateTime.now();

    _keepAliveTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || _connectedDevice == null) {
        timer.cancel();
        return;
      }

      // Read RSSI every tick for signal strength indicator
      try {
        final rssi = await _connectedDevice!.readRssi();
        if (mounted) setState(() => _lastRssi = rssi);
      } catch (e) {
        // RSSI read failed — only disconnect if we HAD data before and lost it
        final now = DateTime.now();
        final lastData = _lastDataReceived;
        // Don't trigger disconnect if we never received data yet (still setting up)
        if (lastData != null &&
            now.difference(lastData).inSeconds > 15 &&
            now.difference(_keepAliveStartTime ?? now).inSeconds > 20) {
          debugPrint('Connection stale - no data for 15s, RSSI read failed');
          _handleDisconnection();
          return;
        }
      }

      // Also check for stale data even if RSSI read succeeded
      final now = DateTime.now();
      if (_lastDataReceived != null &&
          now.difference(_lastDataReceived!).inSeconds > 15) {
        debugPrint('Connection stale - no data for 15s');
      }
    });
  }

  Future<void> _disconnectDevice() async {
    if (_connectedDevice == null) return;

    try {
      // Cancel characteristic subscriptions
      for (final sub in _charSubscriptions) {
        await sub.cancel();
      }
      _charSubscriptions.clear();

      // Cancel connection subscription
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;

      // Disconnect the device
      await _connectedDevice!.disconnect();

      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _lastRssi = null;
          _connectionStatus = 'Disconnected';
        });
      }
    } catch (e) {
      debugPrint('Disconnect error: $e');
      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _lastRssi = null;
          _connectionStatus = 'Disconnected';
        });
      }
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    try {
      debugPrint('>>> Starting service discovery for ${device.platformName}...');
      List<BluetoothService> services = await device.discoverServices();
      debugPrint('>>> Found ${services.length} services');

      bool foundService = false;
      for (BluetoothService service in services) {
        final serviceUuid = service.uuid.toString().toLowerCase();
        debugPrint('>>> Service: $serviceUuid');

        // Check if this is our sensor service
        if (serviceUuid.contains('4fafc201') || serviceUuid == _bleSensorServiceUUID.toLowerCase()) {
          foundService = true;
          debugPrint('>>> MATCHED our sensor service!');

          for (BluetoothCharacteristic char in service.characteristics) {
            final charUuidStr = char.uuid.toString().toLowerCase();
            debugPrint('>>>   Characteristic: $charUuidStr notify=${char.properties.notify} read=${char.properties.read}');
            // Store alert characteristic reference for bidirectional TX
            if (charUuidStr.endsWith('26aa') || charUuidStr.contains('b26aa')) {
              _alertCharacteristic = char;
              debugPrint('>>>   Alert characteristic stored for TX');
            }

            if (char.properties.notify) {
              try {
                await char.setNotifyValue(true);
                debugPrint('>>>   Notifications ENABLED for $charUuidStr');
                final sub = char.onValueReceived.listen((value) {
                  debugPrint('>>>   DATA RECEIVED on $charUuidStr: ${value.length} bytes');
                  _handleCharacteristicData(charUuidStr, value);
                });
                _charSubscriptions.add(sub);
                debugPrint('>>>   SUBSCRIBED to $charUuidStr');
              } catch (e) {
                debugPrint('>>>   FAILED to subscribe to $charUuidStr: $e');
                if (mounted) {
                  setState(() => _connectionStatus = 'Data subscribe failed');
                }
              }
            }
          }
        }
      }

      if (!foundService) {
        debugPrint('>>> WARNING: Our sensor service was NOT found!');
      }
    } catch (e) {
      debugPrint('Service discovery error: $e');
    }
  }

  void _handleCharacteristicData(String charUuid, List<int> value) {
    if (!mounted) return;

    // FFT characteristic sends binary data, not JSON
    if (isFftCharacteristic(charUuid)) {
      final fftData = parseFftBlePayload(value);
      if (fftData != null) {
        _lastFftData = fftData;
        _lastDataReceived = DateTime.now();
        debugPrint('>>> FFT BLE: ${fftData.binCount} bins, dominant=${fftData.dominantFrequency.toStringAsFixed(1)}Hz');
      }
      return;
    }

    try {
      // Strip null bytes that C snprintf may include
      final cleaned = value.where((b) => b != 0).toList();
      final jsonStr = String.fromCharCodes(cleaned).trim();
      debugPrint('>>> RAW BLE DATA from $charUuid (${value.length} bytes): "$jsonStr"');
      if (jsonStr.isEmpty) return;

      // Check for truncated JSON (missing closing brace)
      if (!jsonStr.endsWith('}')) {
        debugPrint('>>> WARNING: Truncated BLE data! MTU too small. Raw length=${value.length}');
        _truncatedPackets++;
        // Show amber snackbar on first truncation (Nielsen Heuristic #9)
        if (_truncatedPackets == 1 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Partial data received — move closer to sensor'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        setState(() {});
        return;
      }

      final data = json.decode(jsonStr);
      if (data == null) return;

      // Update last data received for keepalive monitoring
      _lastDataReceived = DateTime.now();

      // Debug: log received data with full UUID
      debugPrint('>>> PARSED BLE Data UUID=$charUuid data=$data');

      setState(() {
        _lastUpdate = _formatTime(DateTime.now());

        // Match by last part of UUID (the unique suffix)
        // IMU: beb5483e-36e1-4688-b7f5-ea07361b26a8
        // Moisture: beb5483e-36e1-4688-b7f5-ea07361b26a9
        // Alert: beb5483e-36e1-4688-b7f5-ea07361b26aa
        if (charUuid.endsWith('26a8') || charUuid.contains('b26a8')) {
          // IMU characteristic (v2.0: includes processed vibration features)
          _accX = (data['x'] as num?)?.toDouble() ?? 0.0;
          _accY = (data['y'] as num?)?.toDouble() ?? 0.0;
          _accZ = (data['z'] as num?)?.toDouble() ?? 0.0;
          _vibration = (data['vib'] as num?)?.toDouble() ?? 0.0;

          // Parse v2.0+ fields (backward compatible - defaults to 0 if missing)
          _ppv = (data['ppv'] as num?)?.toDouble() ?? 0.0;
          _rms = (data['rms'] as num?)?.toDouble() ?? 0.0;
          _dominantFreq = (data['freq'] as num?)?.toDouble() ?? 0.0;
          _crestFactor = (data['crest'] as num?)?.toDouble() ?? 0.0;

          // Parse v3.0 fields
          _centroid = (data['cent'] as num?)?.toDouble() ?? 0.0;
          _kurtosis = (data['kurt'] as num?)?.toDouble() ?? 0.0;
          _staLtaRatio = (data['stalta'] as num?)?.toDouble() ?? 0.0;

          // Parse v4.0 fields (backward compatible - defaults to 0 if missing)
          _arias = (data['arias'] as num?)?.toDouble() ?? 0.0;
          _cav = (data['cav'] as num?)?.toDouble() ?? 0.0;
          _temp = (data['temp'] as num?)?.toDouble() ?? 0.0;
          _dwt1 = (data['dwt1'] as num?)?.toDouble() ?? 0.0;
          _dwt2 = (data['dwt2'] as num?)?.toDouble() ?? 0.0;
          _dwt3 = (data['dwt3'] as num?)?.toDouble() ?? 0.0;

          // PPV EMA smoothing (alpha = 0.3)
          _ppvSmoothed = _kalmanFilter.update(_ppv);
          _ppvKalman = _ppvSmoothed;

          // 5-second peak hold
          if (_ppv > _ppvPeakHold) {
            _ppvPeakHold = _ppv;
            _ppvPeakTime = DateTime.now();
          } else if (DateTime.now().difference(_ppvPeakTime).inSeconds >= 5) {
            _ppvPeakHold = _ppv;
            _ppvPeakTime = DateTime.now();
          }

          // Add to legacy graph history (O(1) via CircularBuffer)
          _sensorHistory.add({
            'vibration': _vibration,
            'moisture': _moisturePercent,
            'timestamp': DateTime.now(),
          });

          // Add to PPV trend history (for DIN 4150-3 graph)
          _ppvHistory.add({
            'ppv': _ppv,
            'freq': _dominantFreq,
            'crest': _crestFactor,
            'rms': _rms,
            'cent': _centroid,
            'kurt': _kurtosis,
            'stalta': _staLtaRatio,
            'timestamp': DateTime.now(),
          });

          // Log feature vector for ML training
          _vibrationFeatureLog.add({
            'rms': _rms,
            'ppv': _ppv,
            'freq': _dominantFreq,
            'crest': _crestFactor,
            'cent': _centroid,
            'kurt': _kurtosis,
            'stalta': _staLtaRatio,
            'timestamp': DateTime.now().toIso8601String(),
          });

          debugPrint('>>> VIBRATION v4.0: PPV=${_ppv}mm/s Freq=${_dominantFreq}Hz Crest=$_crestFactor Kurt=$_kurtosis STA/LTA=$_staLtaRatio Arias=$_arias CAV=$_cav Temp=${_temp}C DWT=[$_dwt1,$_dwt2,$_dwt3] History=${_ppvHistory.length} pts ML=${_lastAnomalyResult.levelLabel}');
        } else if (charUuid.endsWith('26a9') || charUuid.contains('b26a9')) {
          // Moisture characteristic (also includes vibration for reliability)
          _moisturePercent = (data['percent'] as num?)?.toInt() ?? 0;
          // Read vibration from moisture characteristic (more reliable than IMU char)
          if (data.containsKey('vib')) {
            _vibration = (data['vib'] as num?)?.toDouble() ?? 0.0;
            debugPrint('>>> VIBRATION FROM MOISTURE: $_vibration');
          }
          debugPrint('>>> MOISTURE UPDATED: $_moisturePercent%');
        } else if (charUuid.endsWith('26aa') || charUuid.contains('b26aa')) {
          final newLevel = data['level'] as String? ?? 'safe';
          final newMessage = data['message'] as String? ?? '';
          _hazardType = data['type'] as String? ?? 'none';

          if (newLevel != 'safe' && newMessage.isNotEmpty) {
            _alerts.insert(0, AlertData(
              time: _lastUpdate,
              level: newLevel == 'critical' ? AlertLevel.critical : AlertLevel.warning,
              title: newLevel == 'critical' ? 'Critical Alert' : 'Warning',
              message: newMessage,
            ));
            if (_alerts.length > 10) _alerts.removeLast();
            _saveAlertToFirebase(newLevel, newMessage);

            // Send push notification for alerts (only if level changed)
            _sendAlertNotification(newLevel, newMessage);

            // Show full-screen alert for ALL alerts (both warning and critical)
            _triggerFullScreenAlert(newMessage, newLevel);
          }

          _alertLevel = newLevel;
          _alertMessage = newMessage;
        } else if (charUuid.endsWith('26ab') || charUuid.contains('b26ab')) {
          // Battery characteristic (v4.1)
          _batteryVoltage = (data['voltage'] as num?)?.toDouble() ?? 0.0;
          _batteryPercent = (data['percent'] as num?)?.toInt() ?? 100;
          _batteryCharging = data['charging'] as bool? ?? false;

          debugPrint('>>> BATTERY: ${_batteryPercent}% (${_batteryVoltage}V) ${_batteryCharging ? 'CHARGING' : ''}');

          // Low battery warning
          if (_batteryPercent < 20 && !_batteryCharging) {
            NotificationService().showSafetyWarning(
              message: 'M5StickC Plus 2 battery low: ${_batteryPercent}%',
              sensorType: 'Device Battery',
            );
          }
        }
      });

      // Run heavy processing outside setState to avoid blocking BLE
      if (charUuid.endsWith('26a8') || charUuid.contains('b26a8')) {
        _runDeferredProcessing();
      }
    } catch (e) {
      debugPrint('Error parsing BLE data: $e');
    }
  }

  /// Debounce flag — skip stale BLE packets if processing is still running.
  bool _deferredProcessingPending = false;

  /// Run heavy analytics in a microtask so the UI paints first, then
  /// analytics run before the next event. Debounces rapid BLE packets.
  void _runDeferredProcessing() {
    if (!mounted || _deferredProcessingPending) return;
    _deferredProcessingPending = true;
    Future.microtask(() {
      _deferredProcessingPending = false;
      if (!mounted) return;
      _doDeferredProcessing();
    });
  }

  /// Actual deferred processing logic (runs in microtask after UI paint).
  /// All state mutations are batched into a single setState at the end
  /// to minimise widget rebuilds (Flutter rendering pipeline docs).
  void _doDeferredProcessing() {
    bool needsRebuild = false;

    // 1. Feed wavelet buffer with vibration magnitude (O(1) circular buffer)
    _waveletBuffer.add(_vibration > 0 ? _vibration : _rms);

    // 2. Run app-side wavelet analysis when buffer is full enough
    bool hasNewTransient = false;
    if (_waveletBuffer.length >= 32) {
      final waveletList = _waveletBuffer.toList();
      final bandEnergy = WaveletService.bandEnergy(
        waveletList,
        levels: 3,
        sampleRate: 200.0,
      );
      final transients = WaveletService.detectTransients(
        waveletList,
        sensitivity: 3.0,
        sampleRate: 200.0,
      );

      if (transients.isNotEmpty) {
        final now = DateTime.now();
        if (now.difference(_lastTransientTime).inMilliseconds > 500) {
          hasNewTransient = true;
          _lastTransientTime = now;
        }
      }

      _waveletBandEnergy = bandEnergy;
      _waveletTransients = transients;
      if (hasNewTransient) _transientFlash = true;
      needsRebuild = true;
    }

    // 3. Feed spectrogram buffer — prefer real FFT bins from firmware
    if (_lastFftData != null) {
      _spectrogramBuffer.addColumn(_lastFftData!.toSpectrogramColumn());
      _lastFftData = null;
      needsRebuild = true;
    } else if (_dominantFreq > 0 || _rms > 0) {
      const fftBins = 128;
      final column = List<double>.filled(fftBins, 0.0);
      final binResolution = 200.0 / 256;

      if (_dominantFreq > 0 && _rms > 0) {
        final dominantBin = (_dominantFreq / binResolution).round().clamp(0, fftBins - 1);
        column[dominantBin] = _rms * 100;
        for (int i = 1; i <= 3; i++) {
          final spread = _rms * 100 * math.exp(-i * i * 0.5);
          if (dominantBin + i < fftBins) column[dominantBin + i] = spread;
          if (dominantBin - i >= 0) column[dominantBin - i] = spread;
        }
      }

      if (_dwt1 > 0) {
        final startBin = (50.0 / binResolution).round().clamp(0, fftBins - 1);
        final endBin = (100.0 / binResolution).round().clamp(0, fftBins - 1);
        for (int i = startBin; i < endBin && i < fftBins; i++) {
          column[i] += _dwt1 * 50;
        }
      }
      if (_dwt2 > 0) {
        final startBin = (25.0 / binResolution).round().clamp(0, fftBins - 1);
        final endBin = (50.0 / binResolution).round().clamp(0, fftBins - 1);
        for (int i = startBin; i < endBin && i < fftBins; i++) {
          column[i] += _dwt2 * 50;
        }
      }
      if (_dwt3 > 0) {
        final startBin = (12.5 / binResolution).round().clamp(0, fftBins - 1);
        final endBin = (25.0 / binResolution).round().clamp(0, fftBins - 1);
        for (int i = startBin; i < endBin && i < fftBins; i++) {
          column[i] += _dwt3 * 50;
        }
      }

      _spectrogramBuffer.addColumn(column);
      needsRebuild = true;
    }

    // 4. Multi-standard classification
    if (_ppv > 0 || _rms > 0) {
      _standardClassifications = VibrationMetricsService.classifyAllStandards(
        _ppv,
        _dominantFreq,
      );

      _vibrationMetrics.updateWithSample(_rms, 1.0 / 2.0);
      _housnerSI = _vibrationMetrics.housnerSI;

      if (_ppv > 0 && _dominantFreq > 0) {
        _vibrationMetrics.damageIndex = VibrationMetricsService.updateDamageIndex(
          _vibrationMetrics.damageIndex,
          _ppv,
          0.5,
          _dominantFreq,
        );
      }
      needsRebuild = true;
    }

    // 5. ML anomaly detection
    if (_mlModelLoaded && (_ppv > 0 || _rms > 0)) {
      final features = {
        'rms': _rms,
        'ppv': _ppv,
        'freq': _dominantFreq,
        'crest': _crestFactor,
        'centroid': _centroid,
        'kurtosis': _kurtosis,
        'stalta': _staLtaRatio,
        'arias': _arias,
        'cav': _cav,
        'temp': _temp,
      };

      final result = _anomalyService.detect(features);
      _anomalyScoreHistory.add(result.score);
      _lastAnomalyResult = result;
      _lastMLFeatures = features;
      needsRebuild = true;
    }

    // 6. PPV trend prediction
    if (_ppv > 0 || _rms > 0) {
      _ppvKalmanHistory.add(_ppvKalman);

      if (_ppvKalmanHistory.length >= 5) {
        final limit = _dominantFreq <= 10 ? 3.0 : (_dominantFreq <= 50 ? 5.0 : 8.0);
        _ppvPrediction = _trendPredictor.predict(
          _ppvKalmanHistory.toList(),
          limitMmPerSec: limit,
        );
        needsRebuild = true;
      }
    }

    // Single batched setState for all deferred analytics
    if (needsRebuild && mounted) {
      setState(() {});
    }

    // Clear transient flash after short delay
    if (hasNewTransient) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _transientFlash = false);
      });
    }
  }

  /// Send push notification for safety alerts
  void _sendAlertNotification(String level, String message) {
    // Only notify if alert level changed (prevent spam)
    if (_lastNotifiedAlertLevel == level) return;
    _lastNotifiedAlertLevel = level;

    if (level == 'critical') {
      NotificationService().showSafetyCritical(
        message: message,
        sensorType: 'Trench Safety',
      );
    } else if (level == 'warning') {
      NotificationService().showSafetyWarning(
        message: message,
        sensorType: 'Trench Safety',
      );
    } else {
      // Alert cleared
      _lastNotifiedAlertLevel = null;
    }
  }

  /// Trigger full-screen alert via parent Dashboard (works on all tabs)
  void _triggerFullScreenAlert(String message, String level) {
    widget.onAlert(message, level);
  }

  /// Write a command to the device via the alert characteristic (App → Device)
  Future<void> _writeAlertCommand(String command) async {
    if (_alertCharacteristic == null) {
      debugPrint('>>> Alert characteristic not available for TX');
      return;
    }
    try {
      final bytes = utf8.encode(command);
      await _alertCharacteristic!.write(bytes, withoutResponse: false);
      debugPrint('>>> TX to device: $command');
    } catch (e) {
      debugPrint('>>> TX error: $e');
    }
  }

  String _generateDamageAssessment() {
    final ppv = _ppvSmoothed > 0 ? _ppvSmoothed : _ppv;
    if (ppv <= 0 && _rms <= 0) return '';

    final parts = <String>[];

    // DIN 4150-3 heritage structure assessment based on PPV + frequency
    if (ppv > 0) {
      final freqLimit = _dominantFreq <= 10 ? 3.0 : (_dominantFreq <= 50 ? 5.0 : 8.0);
      final ratio = ppv / freqLimit;
      if (ratio >= 1.0) {
        parts.add('PPV exceeds DIN 4150-3 heritage limit (${freqLimit.toStringAsFixed(0)} mm/s)');
      } else if (ratio >= 0.7) {
        parts.add('PPV approaching heritage limit (${(ratio * 100).toStringAsFixed(0)}%)');
      } else if (ratio >= 0.4) {
        parts.add('Moderate vibration — monitor closely');
      } else {
        parts.add('Vibration within safe limits');
      }
    }

    // Kurtosis assessment
    if (_kurtosis > 6) {
      parts.add('Severe impulsive loading detected (kurtosis ${_kurtosis.toStringAsFixed(1)})');
    } else if (_kurtosis > 3) {
      parts.add('Impact-type vibration present');
    }

    // STA/LTA assessment
    if (_staLtaRatio > 4.0) {
      parts.add('Seismic event trigger active (STA/LTA ${_staLtaRatio.toStringAsFixed(1)})');
    } else if (_staLtaRatio > 2.0) {
      parts.add('Elevated seismic activity');
    }

    // Crest factor
    if (_crestFactor > 5) {
      parts.add('High crest factor — transient impacts');
    }

    return parts.join('. ');
  }

  Future<void> _saveAlertToFirebase(String level, String message) async {
    try {
      // Get last known GPS position (non-blocking)
      double? lat, lng;
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (e) {
        debugPrint('Geolocation unavailable for alert: $e');
      }

      final assessment = _generateDamageAssessment();
      await FirebaseFirestore.instance.collection('safety_alerts').add({
        'level': level,
        'message': message,
        'vibration': _vibration,
        'moisture': _moisturePercent,
        'accX': _accX,
        'accY': _accY,
        'accZ': _accZ,
        'ppv': _ppv,
        'rms': _rms,
        'freq': _dominantFreq,
        'crest': _crestFactor,
        'kurtosis': _kurtosis,
        'staLta': _staLtaRatio,
        'hazardType': _hazardType,
        'assessment': assessment,
        'deviceName': _isSimulating ? 'Simulator' : (_connectedDevice?.platformName ?? 'Unknown'),
        'timestamp': FieldValue.serverTimestamp(),
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
      });
    } catch (e) {
      debugPrint('Error saving alert: $e');
    }
  }

  void _startFirebaseLogging() {
    _firebaseLogTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && (_connectedDevice != null || _isSimulating)) {
        _saveSensorDataToFirebase();
      }
    });
  }

  Future<void> _saveSensorDataToFirebase() async {
    try {
      await FirebaseFirestore.instance.collection('sensor_data').add({
        'vibration': _vibration,
        'moisture': _moisturePercent,
        'accX': _accX,
        'accY': _accY,
        'accZ': _accZ,
        'ppv': _ppv,
        'rms': _rms,
        'freq': _dominantFreq,
        'crest': _crestFactor,
        'hazardType': _hazardType,
        'deviceName': _isSimulating ? 'Simulator' : (_connectedDevice?.platformName ?? 'Unknown'),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving sensor data: $e');
    }
  }

  Future<void> _loadSensorHistory() async {
    // Don't load from Firebase if device is connected - use live BLE data instead
    if (_connectedDevice != null) {
      debugPrint('Device connected - using live BLE data for graph');
      return;
    }

    try {
      // Only load from Firebase when no device connected
      final snapshot = await FirebaseFirestore.instance
          .collection('sensor_data')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();

      if (mounted && _connectedDevice == null) {
        setState(() {
          _sensorHistory.clear();
          final docs = snapshot.docs.reversed.toList();
          for (final doc in docs) {
            final data = doc.data();
            _sensorHistory.add({
              'vibration': (data['vibration'] as num?)?.toDouble() ?? 0.0,
              'moisture': (data['moisture'] as num?)?.toInt() ?? 0,
              'timestamp': (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading sensor history: $e');
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  String _getVibrationStatus() {
    // DIN 4150-3 compliant status using PPV
    if (_ppv > 10.0) return 'CRITICAL - EVACUATE';
    if (_ppv > 3.0) return 'DIN 4150-3 EXCEEDED';
    if (_ppv > 2.5) return 'Heritage limit';
    if (_ppv > 0.3) return 'Perceptible';
    // Fallback to legacy threshold if no PPV data
    if (_ppv == 0.0 && _vibration > 0.8) return 'CRITICAL!';
    if (_ppv == 0.0 && _vibration > 0.3) return 'Warning';
    return 'Safe';
  }

  String _getHazardTypeLabel() {
    switch (_hazardType) {
      case 'seismic': return 'Seismic Activity';
      case 'machinery': return 'Heavy Machinery';
      case 'structural': return 'Structural Risk';
      case 'hf_stress': return 'HF Stress';
      case 'impact': return 'Impact';
      case 'continuous': return 'Continuous Vib.';
      case 'source_change': return 'Source Changed';
      case 'moisture_low': return 'Dry Soil';
      case 'moisture_high': return 'Wet Soil';
      case 'test': return 'Test Alert';
      default: return 'Normal';
    }
  }

  Color _getPPVColor() {
    if (_ppv > 10.0) return const Color(0xFFE53935); // Red - structural damage
    if (_ppv > 3.0) return const Color(0xFFFF5722);  // Deep orange - DIN exceeded
    if (_ppv > 2.5) return const Color(0xFFFF9800);  // Orange - heritage limit
    if (_ppv > 0.3) return const Color(0xFFFFC107);  // Amber - perceptible
    return const Color(0xFF4CAF50);                    // Green - safe
  }

  String _getMoistureStatus() {
    if (_moisturePercent < 30) return 'Too Dry';
    if (_moisturePercent > 60) return 'Too Wet!';
    return 'Safe range';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isConnected = _connectedDevice != null;

    return Stack(
      children: [
        // Main content
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER
                  Row(
                    children: [
                      const Icon(Icons.engineering_rounded, color: Colors.white, size: 26),
                      const SizedBox(width: 8),
                      const Text(
                        'Trench Safety',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      LiveChip(isConnected: isConnected, status: _connectionStatus),
                      if (isConnected) ...[
                        const SizedBox(width: 8),
                        _buildBatteryChip(),
                        if (_lastRssi != null) ...[
                          const SizedBox(width: 4),
                          _buildRssiChip(),
                        ],
                      ],
                      const SizedBox(width: 8),
                      _buildSimpleModeToggle(),
                    ],
                  ),
                  const SizedBox(height: 8),

              // Connection status and action buttons
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isConnected
                            ? 'Connected to M5StickC Plus 2'
                            : _isConnecting
                              ? 'Scanning for devices...'
                              : _connectionStatus,
                          style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 13),
                        ),
                        if (_truncatedPackets > 0)
                          Text(
                            '$_truncatedPackets partial packet(s) — reconnecting clears',
                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Scan/Reconnect button
                  GestureDetector(
                    onTap: isConnected ? null : () {
                      _reconnectTimer?.cancel();
                      _reconnectAttempts = 0;
                      _startScan();
                    },
                    child: AnimatedOpacity(
                      opacity: isConnected ? 0.3 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _connectionStatus.contains('Reconnecting') || _connectionStatus.contains('Connection lost')
                              ? 'Reconnect'
                              : 'Scan',
                          style: const TextStyle(color: Color(0xFF0D3A39), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Disconnect button - enabled when connected
                  GestureDetector(
                    onTap: isConnected ? _disconnectDevice : null,
                    child: AnimatedOpacity(
                      opacity: isConnected ? 1.0 : 0.3,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Disconnect',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Mute button - uses global mute from Dashboard
                  GestureDetector(
                    onTap: widget.onToggleMute,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.isMuted ? Colors.grey : Colors.green.withAlpha(200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.isMuted ? 'Muted' : 'Sound',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ===== SIMPLE MODE: archaeologist-friendly status =====
              if (_simpleMode) ...[
                _buildSimpleStatusDisplay(isConnected),

                // Current Alert Banner (always visible in both modes)
                if (_alertLevel != 'safe' && _alertMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CurrentAlertBanner(level: _alertLevel, message: _alertMessage),
                ],

                // Test Alert button (always available in both modes)
                if (isConnected && _alertCharacteristic != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: () => _writeAlertCommand('test'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withAlpha(40)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_active, color: Colors.white.withAlpha(150), size: 16),
                            const SizedBox(width: 6),
                            Text('Test Alert', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 100),
              ],

              // ===== DETAILED MODE: full technical view (unchanged) =====
              if (!_simpleMode) ...[
              // STATS ROW - PPV (primary metric) + Moisture
              Row(
                children: [
                  Expanded(
                    child: SafetyStatCard(
                      title: 'PPV (DIN 4150-3)',
                      value: _ppv > 0 ? '${_ppv.toStringAsFixed(1)} mm/s' : '${_vibration.toStringAsFixed(3)} g',
                      status: _getVibrationStatus(),
                      statusColor: _getPPVColor(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SafetyStatCard(
                      title: 'Soil Moisture',
                      value: '$_moisturePercent %',
                      status: _getMoistureStatus(),
                      statusColor: (_moisturePercent < 30 || _moisturePercent > 60) ? Colors.orange : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Vibration Analysis Card (v4.0)
              VibrationAnalysisCard(
                ppv: _ppv,
                rms: _rms,
                dominantFreq: _dominantFreq,
                crestFactor: _crestFactor,
                ppvSmoothed: _ppvSmoothed,
                ppvPeakHold: _ppvPeakHold,
                kurtosis: _kurtosis,
                staLtaRatio: _staLtaRatio,
                centroid: _centroid,
                arias: _arias,
                cav: _cav,
                temp: _temp,
                dwt1: _dwt1,
                dwt2: _dwt2,
                dwt3: _dwt3,
                hazardType: _hazardType,
                hazardLabel: _getHazardTypeLabel(),
                ppvColor: _getPPVColor(),
                isConnected: isConnected,
                damageAssessment: _generateDamageAssessment(),
                onHistoryTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VibrationEventLogScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Multi-Standard Classification Card
              if (_ppv > 0 || _rms > 0)
                MultiStandardCard(
                  classifications: _standardClassifications,
                  damageIndex: _vibrationMetrics.damageIndex,
                  housnerSI: _housnerSI,
                  isConnected: isConnected,
                ),
              if (_ppv > 0 || _rms > 0)
                const SizedBox(height: 12),

              // Wavelet Analysis Card (app-side DWT)
              if (_waveletBandEnergy.isNotEmpty)
                WaveletAnalysisCard(
                  bandEnergy: _waveletBandEnergy,
                  transients: _waveletTransients,
                  transientFlash: _transientFlash,
                  bufferFill: _waveletBuffer.length / _waveletBuffer.capacity,
                ),
              if (_waveletBandEnergy.isNotEmpty)
                const SizedBox(height: 12),

              // PPV Trend Graph with DIN 4150-3 limit lines
              // PPV Trend Warning Banner
              if (_ppvPrediction != null && _ppvPrediction!.isTrendingUp && _ppvPrediction!.minutesToLimit != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8F00).withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFF8F00).withAlpha(100), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up, color: Color(0xFFFF8F00), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'PPV trending toward DIN 4150-3 limit in ~${_ppvPrediction!.minutesToLimit!.toStringAsFixed(1)} min '
                          '(R²=${_ppvPrediction!.rSquared.toStringAsFixed(2)})',
                          style: const TextStyle(color: Color(0xFFFF8F00), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              RepaintBoundary(
                child: PPVTrendGraphCard(
                  ppvHistory: _ppvHistory.toList(),
                  prediction: _ppvPrediction,
                  kalmanHistory: _ppvKalmanHistory.toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Time-Frequency Spectrogram (RepaintBoundary isolates repaints)
              if (_spectrogramBuffer.length > 2)
                RepaintBoundary(child: _buildSpectrogramCard()),
              if (_spectrogramBuffer.length > 2)
                const SizedBox(height: 12),

              // ML / Adaptive Anomaly Detection Indicator (Tier 2)
              if (_mlModelLoaded && (_ppv > 0 || _rms > 0))
                MLAnomalyIndicator(
                  result: _lastAnomalyResult,
                  features: _lastMLFeatures,
                  anomalyHistory: _anomalyScoreHistory.toList(),
                  modelVersion: _anomalyService.modeLabel,
                ),
              if (_mlModelLoaded && (_ppv > 0 || _rms > 0))
                const SizedBox(height: 12),

              // Live Sensors Card (legacy + enhanced)
              LiveSensorsCard(
                accX: _accX, accY: _accY, accZ: _accZ,
                vibration: _vibration,
                moisturePercent: _moisturePercent,
                lastUpdate: _lastUpdate,
                isConnected: isConnected,
                ppv: _ppv,
                dominantFreq: _dominantFreq,
                crestFactor: _crestFactor,
                rms: _rms,
                hazardType: _hazardType,
              ),
              const SizedBox(height: 12),

              // Sensor History Graph Card (legacy moisture + vibration)
              RepaintBoundary(
                child: SensorHistoryGraphCard(sensorHistory: _sensorHistory.toList()),
              ),
              const SizedBox(height: 12),

              // Alerts Card
              SafetyAlertsCard(alerts: _alerts),
              const SizedBox(height: 12),

              // Current Alert Banner (if any)
              if (_alertLevel != 'safe' && _alertMessage.isNotEmpty)
                CurrentAlertBanner(level: _alertLevel, message: _alertMessage),

              // Test Alert button (only when connected)
              if (isConnected && _alertCharacteristic != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onTap: () => _writeAlertCommand('test'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(40)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_active, color: Colors.white.withAlpha(150), size: 16),
                          const SizedBox(width: 6),
                          Text('Test Alert', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 12),
              const SafetyInsightCard(),
              const SizedBox(height: 100),
              ], // end !_simpleMode
            ],
          ),
        ),
      ),
    ),
      ],
    );
  }

  /// Build the Simple/Detailed mode toggle chip for the header
  Widget _buildSimpleModeToggle() {
    return GestureDetector(
      onTap: () => setState(() => _simpleMode = !_simpleMode),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _simpleMode
                  ? const Color(0xFF4CAF50).withAlpha(50)
                  : const Color(0xFF2196F3).withAlpha(50),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _simpleMode
                    ? const Color(0xFF4CAF50).withAlpha(120)
                    : const Color(0xFF2196F3).withAlpha(120),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _simpleMode ? Icons.shield_rounded : Icons.analytics_rounded,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _simpleMode ? 'Simple' : 'Detail',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Determine the simplified safety level from all available data
  String _getSimpleSafetyLevel() {
    // Danger: PPV exceeds DIN 4150-3 heritage limits or critical alert active
    if (_ppv > 3.0 || _alertLevel == 'critical') return 'danger';
    // Also danger if legacy vibration is critical and no PPV data
    if (_ppv == 0.0 && _vibration > 0.8) return 'danger';

    // Caution: approaching limits, warning alert, or notable vibration
    if (_ppv > 1.5 || _alertLevel == 'warning') return 'caution';
    if (_ppv > 0.3) return 'caution';
    if (_ppv == 0.0 && _vibration > 0.3) return 'caution';
    // Soil moisture out of range
    if (_moisturePercent > 0 && (_moisturePercent < 30 || _moisturePercent > 60)) return 'caution';

    return 'safe';
  }

  /// Build the simplified status display for archaeologists
  Widget _buildSimpleStatusDisplay(bool isConnected) {
    final safetyLevel = _getSimpleSafetyLevel();

    // Status color, label, and description
    final Color statusColor;
    final String statusLabel;
    final String statusDescription;
    final IconData statusIcon;

    switch (safetyLevel) {
      case 'danger':
        statusColor = const Color(0xFFE53935);
        statusLabel = 'Stop Work - High Vibration';
        statusDescription = 'Vibration exceeds safe limits for heritage structures. Stop all nearby machinery and assess the site.';
        statusIcon = Icons.dangerous_rounded;
        break;
      case 'caution':
        statusColor = const Color(0xFFFFC107);
        statusLabel = 'Use Caution';
        statusDescription = 'Elevated vibration detected. Monitor conditions and reduce heavy equipment use if possible.';
        statusIcon = Icons.warning_amber_rounded;
        break;
      default:
        statusColor = const Color(0xFF4CAF50);
        statusLabel = 'Safe to Work';
        statusDescription = 'Vibration levels are within safe limits for archaeological structures.';
        statusIcon = Icons.check_circle_rounded;
    }

    // PPV context string
    final String ppvContext;
    if (_ppv > 0) {
      final freqLimit = _dominantFreq <= 10 ? 3.0 : (_dominantFreq <= 50 ? 5.0 : 8.0);
      final percentage = (_ppv / freqLimit * 100).clamp(0, 999).toStringAsFixed(0);
      if (_ppv >= freqLimit) {
        ppvContext = '${_ppv.toStringAsFixed(1)} mm/s - EXCEEDS safe limit';
      } else if (_ppv >= freqLimit * 0.5) {
        ppvContext = '${_ppv.toStringAsFixed(1)} mm/s - $percentage% of limit';
      } else {
        ppvContext = '${_ppv.toStringAsFixed(1)} mm/s - within safe limits';
      }
    } else if (_vibration > 0) {
      ppvContext = '${_vibration.toStringAsFixed(3)} g';
    } else {
      ppvContext = 'No data yet';
    }

    // Find DIN 4150-3 classification for badge
    String dinBadge = '';
    for (final c in _standardClassifications) {
      if (c.standard == VibrationStandard.din4150) {
        dinBadge = 'DIN 4150-3: ${c.level}';
        break;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withAlpha(25),
                Colors.white.withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: statusColor.withAlpha(120), width: 1.5),
          ),
          child: Column(
            children: [
              // Large status circle
              Container(
                width: (MediaQuery.of(context).size.width * 0.28).clamp(100.0, 140.0),
                height: (MediaQuery.of(context).size.width * 0.28).clamp(100.0, 140.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withAlpha(40),
                  border: Border.all(color: statusColor, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withAlpha(60),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(statusIcon, color: statusColor, size: 56),
              ),
              const SizedBox(height: 20),

              // Status label
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Status description
              Text(
                statusDescription,
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 14,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // PPV value with context
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(40)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.speed_rounded, color: _getPPVColor(), size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        ppvContext,
                        style: TextStyle(
                          color: Colors.white.withAlpha(220),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // DIN standard compliance badge
              if (dinBadge.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getPPVColor().withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getPPVColor().withAlpha(80)),
                  ),
                  child: Text(
                    dinBadge,
                    style: TextStyle(
                      color: _getPPVColor(),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              // Soil moisture (simple)
              if (_moisturePercent > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.water_drop_rounded,
                        color: (_moisturePercent < 30 || _moisturePercent > 60)
                            ? Colors.orange
                            : Colors.white.withAlpha(160),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Soil Moisture: $_moisturePercent% - ${_getMoistureStatus()}',
                        style: TextStyle(
                          color: (_moisturePercent < 30 || _moisturePercent > 60)
                              ? Colors.orange
                              : Colors.white.withAlpha(180),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // PPV trend prediction warning (simple)
              if (_ppvPrediction != null && _ppvPrediction!.isTrendingUp && _ppvPrediction!.minutesToLimit != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8F00).withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFF8F00).withAlpha(100), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up, color: Color(0xFFFF8F00), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Vibration increasing - may exceed limits in ~${_ppvPrediction!.minutesToLimit!.toStringAsFixed(0)} minutes',
                          style: const TextStyle(
                            color: Color(0xFFFF8F00),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ML anomaly warning (simple)
              if (_mlModelLoaded && _lastAnomalyResult.level == AnomalyLevel.anomaly) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(25),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withAlpha(80), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.psychology_alt, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Unusual vibration pattern detected',
                          style: TextStyle(
                            color: Colors.redAccent.withAlpha(230),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Connection / last update info
              const SizedBox(height: 16),
              Text(
                isConnected
                    ? 'Sensor active - last update: $_lastUpdate'
                    : 'Sensor not connected',
                style: TextStyle(
                  color: Colors.white.withAlpha(100),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the spectrogram card with colormap selector
  Widget _buildSpectrogramCard() {
    const colormaps = ['viridis', 'hot', 'inferno'];

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withAlpha(25),
                Colors.white.withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(90), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9C27B0).withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.waterfall_chart_rounded, color: Color(0xFF9C27B0), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Time-Frequency Analysis', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(height: 2),
                        Text('Real-time spectrogram with DIN 4150-3 limits', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Colormap selector chips
              Row(
                children: colormaps.map((cm) {
                  final selected = cm == _spectrogramColorMap;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _spectrogramColorMap = cm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFF9C27B0).withAlpha(80) : Colors.white.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? const Color(0xFF9C27B0).withAlpha(150) : Colors.white.withAlpha(40),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          cm,
                          style: TextStyle(
                            color: selected ? const Color(0xFFCE93D8) : Colors.white.withAlpha(160),
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              // Spectrogram widget
              SizedBox(
                height: (MediaQuery.of(context).size.height * 0.12).clamp(150.0, 250.0),
                child: SpectrogramWidget(
                  spectrogramData: _spectrogramBuffer.data,
                  sampleRate: 200,
                  fftSize: 256,
                  maxFrequency: 100,
                  colorMap: _spectrogramColorMap,
                  height: (MediaQuery.of(context).size.height * 0.12).clamp(150.0, 250.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRssiChip() {
    final rssi = _lastRssi ?? -100;
    final IconData icon;
    final Color color;
    if (rssi > -60) {
      icon = Icons.signal_cellular_4_bar;
      color = const Color(0xFF4CAF50);
    } else if (rssi > -75) {
      icon = Icons.signal_cellular_alt;
      color = const Color(0xFFFFC107);
    } else {
      icon = Icons.signal_cellular_alt_1_bar;
      color = Colors.orangeAccent;
    }
    return Tooltip(
      message: 'RSSI: $rssi dBm',
      child: Icon(icon, color: color, size: 16),
    );
  }

  /// Build battery indicator chip (v4.1)
  Widget _buildBatteryChip() {
    final Color batteryColor = _batteryCharging
        ? const Color(0xFF4CAF50) // Green when charging
        : _batteryPercent < 20
            ? Colors.red // Red when low
            : _batteryPercent < 50
                ? Colors.orange // Orange when medium
                : Colors.white; // White when good

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(36),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withAlpha(89), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _batteryCharging
                    ? Icons.battery_charging_full
                    : _batteryPercent > 80
                        ? Icons.battery_full
                        : _batteryPercent > 50
                            ? Icons.battery_5_bar
                            : _batteryPercent > 20
                                ? Icons.battery_3_bar
                                : Icons.battery_1_bar,
                color: batteryColor,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${_batteryPercent}%',
                style: TextStyle(
                  color: batteryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

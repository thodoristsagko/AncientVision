import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/alert_data.dart';
import '../widgets/safety_widgets.dart';
import '../widgets/full_screen_alert_overlay.dart';
import '../services/vibration_anomaly_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
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

  // PPV history for trend graph (DIN 4150-3)
  final List<Map<String, dynamic>> _ppvHistory = [];

  // Vibration feature log for ML training data
  final List<Map<String, dynamic>> _vibrationFeatureLog = [];

  // ML Anomaly Detection (Tier 2)
  final _anomalyService = VibrationAnomalyService();
  AnomalyResult _lastAnomalyResult = const AnomalyResult(score: 0, level: AnomalyLevel.unknown, rawError: 0);
  bool _mlModelLoaded = false;

  final List<AlertData> _alerts = [];

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  final List<StreamSubscription> _charSubscriptions = [];

  final bool _isSimulating = false;
  Timer? _simulationTimer;
  Timer? _firebaseLogTimer;
  List<Map<String, dynamic>> _sensorHistory = [];

  // Enhanced connection management
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;
  DateTime? _lastDataReceived;
  String? _lastNotifiedAlertLevel; // Prevent duplicate notifications

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
    debugPrint('ML anomaly model loaded: $success');
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
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final name = r.device.platformName;
          final nameLower = name.toLowerCase();

          // Log all devices found for debugging
          if (name.isNotEmpty && devicesFound < 20) {
            debugPrint('BLE Found: "$name" (${r.device.remoteId})');
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
            debugPrint('>>> MATCHED DEVICE: $name (${r.device.remoteId}) - connecting...');
            FlutterBluePlus.stopScan();
            _scanSubscription?.cancel();
            _connectToDevice(r.device);
            return; // Exit the listener
          }
        }
      });

      await Future.delayed(const Duration(seconds: 20));
      if (_connectedDevice == null && mounted) {
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

    _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || _connectedDevice == null) {
        timer.cancel();
        return;
      }

      // Check if we've received data recently
      final now = DateTime.now();
      if (_lastDataReceived != null &&
          now.difference(_lastDataReceived!).inSeconds > 15) {
        // No data for 15 seconds - connection might be stale
        debugPrint('Connection stale - no data for 15s');
        try {
          // Try to read RSSI to verify connection is alive
          await _connectedDevice!.readRssi();
        } catch (e) {
          // Connection is dead, trigger reconnect
          _handleDisconnection();
        }
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
          _connectionStatus = 'Disconnected';
        });
      }
    } catch (e) {
      debugPrint('Disconnect error: $e');
      if (mounted) {
        setState(() {
          _connectedDevice = null;
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

    try {
      // Strip null bytes that C snprintf may include
      final cleaned = value.where((b) => b != 0).toList();
      final jsonStr = String.fromCharCodes(cleaned).trim();
      debugPrint('>>> RAW BLE DATA from $charUuid (${value.length} bytes): "$jsonStr"');
      if (jsonStr.isEmpty) return;

      // Check for truncated JSON (missing closing brace)
      if (!jsonStr.endsWith('}')) {
        debugPrint('>>> WARNING: Truncated BLE data! MTU too small. Raw length=${value.length}');
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
          _ppvSmoothed = 0.3 * _ppv + 0.7 * _ppvSmoothed;

          // 5-second peak hold
          if (_ppv > _ppvPeakHold) {
            _ppvPeakHold = _ppv;
            _ppvPeakTime = DateTime.now();
          } else if (DateTime.now().difference(_ppvPeakTime).inSeconds >= 5) {
            _ppvPeakHold = _ppv;
            _ppvPeakTime = DateTime.now();
          }

          // Add to legacy graph history
          _sensorHistory.add({
            'vibration': _vibration,
            'moisture': _moisturePercent,
            'timestamp': DateTime.now(),
          });
          if (_sensorHistory.length > 30) _sensorHistory.removeAt(0);

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
          if (_ppvHistory.length > 60) _ppvHistory.removeAt(0);

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
          if (_vibrationFeatureLog.length > 500) _vibrationFeatureLog.removeAt(0);

          // Run ML anomaly detection (Tier 2) with v3.0 features
          if (_mlModelLoaded && (_rms > 0 || _ppv > 0)) {
            _lastAnomalyResult = _anomalyService.detect({
              'rms': _rms,
              'ppv': _ppv,
              'freq': _dominantFreq,
              'crest': _crestFactor,
              'cent': _centroid,
              'kurt': _kurtosis,
              'stalta': _staLtaRatio,
            });
          }

          debugPrint('>>> VIBRATION v3.0: PPV=${_ppv}mm/s(smooth=${_ppvSmoothed.toStringAsFixed(1)}) Freq=${_dominantFreq}Hz Crest=$_crestFactor Kurt=$_kurtosis STA/LTA=$_staLtaRatio ML=${_lastAnomalyResult.levelLabel}');
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
        }
      });
    } catch (e) {
      debugPrint('Error parsing BLE data: $e');
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
      } catch (_) {}

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
          _sensorHistory = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'vibration': (data['vibration'] as num?)?.toDouble() ?? 0.0,
              'moisture': (data['moisture'] as num?)?.toInt() ?? 0,
              'timestamp': (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            };
          }).toList().reversed.toList();
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
                    ],
                  ),
                  const SizedBox(height: 8),

              // Connection status and action buttons
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isConnected
                        ? 'Connected to M5StickC Plus 2'
                        : _isConnecting
                          ? 'Scanning for devices...'
                          : _connectionStatus,
                      style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Rescan button - enabled when not connected
                  GestureDetector(
                    onTap: isConnected ? null : _startScan,
                    child: AnimatedOpacity(
                      opacity: isConnected ? 0.3 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Scan',
                          style: TextStyle(color: Color(0xFF0D3A39), fontSize: 12, fontWeight: FontWeight.w600),
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

              // PPV Trend Graph with DIN 4150-3 limit lines
              PPVTrendGraphCard(ppvHistory: _ppvHistory),
              const SizedBox(height: 12),

              // ML Anomaly Detection Indicator (Tier 2)
              if (_mlModelLoaded && (_ppv > 0 || _rms > 0))
                MLAnomalyIndicator(result: _lastAnomalyResult),
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
              SensorHistoryGraphCard(sensorHistory: _sensorHistory),
              const SizedBox(height: 12),

              // Alerts Card
              SafetyAlertsCard(alerts: _alerts),
              const SizedBox(height: 12),

              // Current Alert Banner (if any)
              if (_alertLevel != 'safe' && _alertMessage.isNotEmpty)
                CurrentAlertBanner(level: _alertLevel, message: _alertMessage),

              const SizedBox(height: 12),
              const SafetyInsightCard(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    ),
      ],
    );
  }
}

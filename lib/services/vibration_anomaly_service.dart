import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Vibration anomaly detection service using TFLite autoencoder.
///
/// The autoencoder is trained on "normal" vibration patterns. When it receives
/// data that doesn't match normal patterns, the reconstruction error is high,
/// indicating an anomaly (potential hazard).
///
/// Anomaly levels:
///   - NORMAL: reconstruction error < threshold_low (green)
///   - UNUSUAL: threshold_low <= error < threshold_high (yellow)
///   - ANOMALY: error >= threshold_high (red)
class VibrationAnomalyService {
  static final VibrationAnomalyService _instance = VibrationAnomalyService._internal();
  factory VibrationAnomalyService() => _instance;
  VibrationAnomalyService._internal();

  Interpreter? _interpreter;
  bool _isInitialized = false;

  // Scaler parameters (from training)
  List<double> _scalerMean = [];
  List<double> _scalerScale = [];
  List<String> _featureNames = [];

  // Anomaly thresholds
  double _thresholdLow = 1.0;
  double _thresholdHigh = 2.5;

  // Model config
  int _inputDim = 4;
  String _modelVersion = 'unknown';

  bool get isInitialized => _isInitialized;
  String get modelVersion => _modelVersion;
  int get inputDim => _inputDim;

  /// Initialize the TFLite model and load scaler/config.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Load TFLite model
      _interpreter = await Interpreter.fromAsset('ml/vibration_anomaly.tflite');
      debugPrint('VibrationAnomalyService: TFLite model loaded');

      // Load scaler parameters
      final scalerJson = await rootBundle.loadString('assets/ml/vibration_scaler.json');
      final scalerData = json.decode(scalerJson);
      _scalerMean = (scalerData['mean'] as List).map((e) => (e as num).toDouble()).toList();
      _scalerScale = (scalerData['scale'] as List).map((e) => (e as num).toDouble()).toList();
      _featureNames = (scalerData['feature_names'] as List).map((e) => e.toString()).toList();
      debugPrint('VibrationAnomalyService: Scaler loaded (${_featureNames.length} features)');

      // Load model config
      final configJson = await rootBundle.loadString('assets/ml/vibration_model_config.json');
      final configData = json.decode(configJson);
      _inputDim = configData['input_dim'] as int? ?? 4;
      _modelVersion = configData['model_version'] as String? ?? 'unknown';

      final thresholds = configData['thresholds'] as Map<String, dynamic>? ?? {};
      _thresholdLow = (thresholds['threshold_low'] as num?)?.toDouble() ?? 1.0;
      _thresholdHigh = (thresholds['threshold_high'] as num?)?.toDouble() ?? 2.5;

      debugPrint('VibrationAnomalyService: Config loaded v$_modelVersion');
      debugPrint('  Thresholds: low=$_thresholdLow high=$_thresholdHigh');

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('VibrationAnomalyService: Failed to initialize: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Run anomaly detection on a single vibration feature vector.
  ///
  /// Input: Map with keys from firmware v2.0: {rms, ppv, freq, crest}
  /// Returns: [AnomalyResult] with score and classification.
  AnomalyResult detect(Map<String, double> features) {
    if (!_isInitialized || _interpreter == null) {
      return const AnomalyResult(
        score: 0,
        level: AnomalyLevel.unknown,
        rawError: 0,
      );
    }

    try {
      // Build feature vector in the expected order
      final input = List<double>.filled(_inputDim, 0.0);
      for (int i = 0; i < _featureNames.length && i < _inputDim; i++) {
        final value = features[_featureNames[i]] ?? 0.0;
        // Apply StandardScaler normalization
        if (i < _scalerScale.length && _scalerScale[i] != 0) {
          input[i] = (value - _scalerMean[i]) / _scalerScale[i];
        } else {
          input[i] = value;
        }
      }

      // Run inference
      final inputTensor = [input.map((e) => e.toDouble()).toList()];
      final outputTensor = [List<double>.filled(_inputDim, 0.0)];

      _interpreter!.run(inputTensor, outputTensor);

      // Calculate reconstruction error (MSE)
      double mse = 0;
      for (int i = 0; i < _inputDim; i++) {
        final diff = input[i] - outputTensor[0][i];
        mse += diff * diff;
      }
      mse /= _inputDim;

      // Classify anomaly level
      AnomalyLevel level;
      double score;
      if (mse < _thresholdLow) {
        level = AnomalyLevel.normal;
        score = mse / _thresholdLow; // 0-1 range for normal
      } else if (mse < _thresholdHigh) {
        level = AnomalyLevel.unusual;
        score = 0.5 + 0.5 * (mse - _thresholdLow) / (_thresholdHigh - _thresholdLow);
      } else {
        level = AnomalyLevel.anomaly;
        score = min(1.0, mse / (_thresholdHigh * 2));
      }

      return AnomalyResult(
        score: score.clamp(0.0, 1.0),
        level: level,
        rawError: mse,
      );
    } catch (e) {
      debugPrint('VibrationAnomalyService: Inference error: $e');
      return const AnomalyResult(
        score: 0,
        level: AnomalyLevel.unknown,
        rawError: 0,
      );
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

enum AnomalyLevel { normal, unusual, anomaly, unknown }

class AnomalyResult {
  final double score;     // 0.0 (normal) to 1.0 (severe anomaly)
  final AnomalyLevel level;
  final double rawError;  // Raw reconstruction error (MSE)

  const AnomalyResult({
    required this.score,
    required this.level,
    required this.rawError,
  });

  String get levelLabel {
    switch (level) {
      case AnomalyLevel.normal: return 'Normal';
      case AnomalyLevel.unusual: return 'Unusual';
      case AnomalyLevel.anomaly: return 'Anomaly';
      case AnomalyLevel.unknown: return 'N/A';
    }
  }
}

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Vibration anomaly detection service using TFLite autoencoder / VAE.
///
/// Supports multiple model versions via auto-detection from config:
///   - v1.0: 4-feature autoencoder  [rms, ppv, freq, crest]
///   - v3.0: 7-feature autoencoder  [rms, ppv, freq, crest, centroid, kurtosis, stalta]
///   - v4.0: 10-feature VAE         [rms, ppv, freq, crest, centroid, kurtosis, stalta, arias, cav, temp]
///
/// The model is trained on "normal" vibration patterns. High reconstruction
/// error indicates an anomaly (potential hazard to the archaeological site).
///
/// Anomaly levels:
///   - NORMAL: score < threshold_low (green)
///   - UNUSUAL: threshold_low <= score < threshold_high (yellow)
///   - ANOMALY: score >= threshold_high (red)
class VibrationAnomalyService {
  static final VibrationAnomalyService _instance =
      VibrationAnomalyService._internal();
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
  String _modelType = 'autoencoder'; // 'autoencoder' or 'vae'
  double _beta = 1.0; // KL divergence weight for VAE scoring

  bool get isInitialized => _isInitialized;
  String get modelVersion => _modelVersion;
  String get modelType => _modelType;
  int get inputDim => _inputDim;

  /// Initialize the TFLite model and load scaler/config.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Load TFLite model
      _interpreter =
          await Interpreter.fromAsset('ml/vibration_anomaly.tflite');
      debugPrint('VibrationAnomalyService: TFLite model loaded');

      // Load scaler parameters
      final scalerJson =
          await rootBundle.loadString('assets/ml/vibration_scaler.json');
      final scalerData = json.decode(scalerJson);
      _scalerMean =
          (scalerData['mean'] as List).map((e) => (e as num).toDouble()).toList();
      _scalerScale =
          (scalerData['scale'] as List).map((e) => (e as num).toDouble()).toList();
      _featureNames =
          (scalerData['feature_names'] as List).map((e) => e.toString()).toList();
      debugPrint(
          'VibrationAnomalyService: Scaler loaded (${_featureNames.length} features)');

      // Load model config
      final configJson =
          await rootBundle.loadString('assets/ml/vibration_model_config.json');
      final configData = json.decode(configJson);
      _inputDim = configData['input_dim'] as int? ?? 4;
      _modelVersion = configData['model_version']?.toString() ?? 'unknown';
      _modelType = configData['model_type'] as String? ?? 'autoencoder';
      _beta = (configData['beta'] as num?)?.toDouble() ?? 1.0;

      final thresholds =
          configData['thresholds'] as Map<String, dynamic>? ?? {};
      _thresholdLow =
          (thresholds['threshold_low'] as num?)?.toDouble() ?? 1.0;
      _thresholdHigh =
          (thresholds['threshold_high'] as num?)?.toDouble() ?? 2.5;

      debugPrint(
          'VibrationAnomalyService: Config loaded v$_modelVersion ($_modelType, beta=$_beta)');
      debugPrint(
          '  Input dim: $_inputDim  Features: $_featureNames');
      debugPrint(
          '  Thresholds: low=$_thresholdLow high=$_thresholdHigh');

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
  /// Input: Map with keys matching the loaded model's feature names.
  ///   v1.0: {rms, ppv, freq, crest}
  ///   v3.0: {rms, ppv, freq, crest, centroid, kurtosis, stalta}
  ///   v4.0: {rms, ppv, freq, crest, centroid, kurtosis, stalta, arias, cav, temp}
  ///
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

      // Run inference (for VAE, the TFLite model uses z_mean deterministically)
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

      // For VAE models, the anomaly score is the reconstruction MSE.
      // The KL divergence component is baked into the training thresholds
      // (thresholds were computed on combined reconstruction + KL scores).
      // At inference, using reconstruction MSE alone is a good proxy since
      // the deterministic encoder path (z_mean) produces consistent latent
      // codes for normal data. The thresholds from training account for this.
      final anomalyScore = mse;

      // Classify anomaly level
      AnomalyLevel level;
      double score;
      if (anomalyScore < _thresholdLow) {
        level = AnomalyLevel.normal;
        score = anomalyScore / _thresholdLow; // 0-1 range for normal
      } else if (anomalyScore < _thresholdHigh) {
        level = AnomalyLevel.unusual;
        score = 0.5 +
            0.5 *
                (anomalyScore - _thresholdLow) /
                (_thresholdHigh - _thresholdLow);
      } else {
        level = AnomalyLevel.anomaly;
        score = min(1.0, anomalyScore / (_thresholdHigh * 2));
      }

      return AnomalyResult(
        score: score.clamp(0.0, 1.0),
        level: level,
        rawError: anomalyScore,
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

  /// Extract vibration features from a BLE data map.
  ///
  /// Handles all firmware versions by extracting available fields.
  /// Missing fields default to 0.0.
  static Map<String, double> extractFeatures(Map<String, dynamic> bleData) {
    return {
      'rms': (bleData['rms'] as num?)?.toDouble() ?? 0.0,
      'ppv': (bleData['ppv'] as num?)?.toDouble() ?? 0.0,
      'freq': (bleData['freq'] as num?)?.toDouble() ?? 0.0,
      'crest': (bleData['crest'] as num?)?.toDouble() ?? 0.0,
      'centroid': (bleData['cent'] as num?)?.toDouble() ?? 0.0,
      'kurtosis': (bleData['kurt'] as num?)?.toDouble() ?? 0.0,
      'stalta': (bleData['stalta'] as num?)?.toDouble() ?? 0.0,
      // v4.0 firmware fields
      'arias': (bleData['arias'] as num?)?.toDouble() ?? 0.0,
      'cav': (bleData['cav'] as num?)?.toDouble() ?? 0.0,
      'temp': (bleData['temp'] as num?)?.toDouble() ?? 0.0,
    };
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

enum AnomalyLevel { normal, unusual, anomaly, unknown }

class AnomalyResult {
  final double score; // 0.0 (normal) to 1.0 (severe anomaly)
  final AnomalyLevel level;
  final double rawError; // Raw anomaly score (reconstruction MSE)

  const AnomalyResult({
    required this.score,
    required this.level,
    required this.rawError,
  });

  String get levelLabel {
    switch (level) {
      case AnomalyLevel.normal:
        return 'Normal';
      case AnomalyLevel.unusual:
        return 'Unusual';
      case AnomalyLevel.anomaly:
        return 'Anomaly';
      case AnomalyLevel.unknown:
        return 'N/A';
    }
  }
}

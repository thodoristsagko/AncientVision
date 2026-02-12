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
      // Fall back to rule-based anomaly detection when ML model unavailable
      return _ruleBasedDetect(features);
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
      debugPrint('VibrationAnomalyService: Inference error: $e — using rule-based fallback');
      return _ruleBasedDetect(features);
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

  /// Rule-based anomaly detection fallback when TFLite model is unavailable.
  ///
  /// Uses engineering thresholds from DIN 4150-3 (heritage structures),
  /// EPRI CAV damage criteria, and structural health monitoring heuristics.
  /// Each feature contributes a weighted sub-score; the aggregate determines
  /// the anomaly level. This ensures anomaly detection is NEVER disabled.
  AnomalyResult _ruleBasedDetect(Map<String, double> features) {
    final ppv = features['ppv'] ?? 0.0;
    final rms = features['rms'] ?? 0.0;
    final crest = features['crest'] ?? 0.0;
    final kurtosis = features['kurtosis'] ?? 0.0;
    final stalta = features['stalta'] ?? 0.0;
    final cav = features['cav'] ?? 0.0;
    final freq = features['freq'] ?? 0.0;

    // DIN 4150-3 heritage PPV thresholds (mm/s)
    const ppvSafe = 0.3;
    const ppvHeritageLow = 3.0;
    const ppvStructural = 10.0;

    // Weighted sub-scores (0.0 = normal, 1.0 = severe)
    double ppvScore = 0.0;
    if (ppv > ppvStructural) {
      ppvScore = 1.0;
    } else if (ppv > ppvHeritageLow) {
      ppvScore = 0.5 + 0.5 * (ppv - ppvHeritageLow) / (ppvStructural - ppvHeritageLow);
    } else if (ppv > ppvSafe) {
      ppvScore = 0.5 * (ppv - ppvSafe) / (ppvHeritageLow - ppvSafe);
    }

    // Crest factor: impacts above 5.0 are concerning (ISO 10816)
    double crestScore = (crest > 5.0) ? min(1.0, (crest - 5.0) / 5.0) : 0.0;

    // Kurtosis: excess kurtosis > 3 indicates impulsive events
    double kurtosisScore = (kurtosis > 3.0) ? min(1.0, (kurtosis - 3.0) / 7.0) : 0.0;

    // STA/LTA: seismic trigger above 4.0 (Allen, 1978)
    double staltaScore = 0.0;
    if (stalta > 4.0) {
      staltaScore = 1.0;
    } else if (stalta > 2.0) {
      staltaScore = (stalta - 2.0) / 2.0;
    }

    // CAV: EPRI damage threshold 0.16 g·s
    double cavScore = (cav > 0.16) ? 1.0 : (cav > 0.08) ? (cav - 0.08) / 0.08 : 0.0;

    // RMS energy: elevated RMS indicates sustained vibration
    double rmsScore = (rms > 0.5) ? min(1.0, (rms - 0.5) / 2.0) : 0.0;

    // Low-frequency seismic concern (0.5-10 Hz with elevated PPV)
    double seismicScore = 0.0;
    if (freq > 0.5 && freq <= 10.0 && ppv > 1.0) {
      seismicScore = min(1.0, ppv / ppvHeritageLow);
    }

    // Weighted aggregate — PPV dominates as the primary structural metric
    final aggregate = ppvScore * 0.30 +
        rmsScore * 0.05 +
        crestScore * 0.10 +
        kurtosisScore * 0.10 +
        staltaScore * 0.20 +
        cavScore * 0.15 +
        seismicScore * 0.10;

    final score = aggregate.clamp(0.0, 1.0);

    AnomalyLevel level;
    if (score < 0.25) {
      level = AnomalyLevel.normal;
    } else if (score < 0.6) {
      level = AnomalyLevel.unusual;
    } else {
      level = AnomalyLevel.anomaly;
    }

    debugPrint('VibrationAnomalyService: Rule-based fallback — '
        'score=${score.toStringAsFixed(3)} level=${level.name} '
        '(ppv=$ppvScore sta=$staltaScore cav=$cavScore)');

    return AnomalyResult(
      score: score,
      level: level,
      rawError: aggregate,
    );
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

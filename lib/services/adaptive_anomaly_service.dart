import 'dart:math';
import 'package:flutter/foundation.dart';

/// Adaptive statistical anomaly detector using online learning.
///
/// Phase 1 (calibration, first 5 minutes): Learns baseline vibration profile
/// using Welford's online algorithm for numerically stable running mean/variance.
/// During this phase, falls back to rule-based scoring.
///
/// Phase 2 (detection): Scores new samples by multivariate deviation from
/// the learned baseline — essentially a Mahalanobis-like distance without
/// covariance (assumes feature independence for computational efficiency).
///
/// The baseline adapts continuously via exponential moving average (EMA)
/// with a slow learning rate (alpha=0.01) so it tracks gradual environmental
/// changes but flags sudden anomalies.
///
/// Academic basis:
/// - Welford (1962) "Note on a Method for Calculating Corrected Sums of
///   Squares and Products" — Technometrics 4(3)
/// - Farrar & Worden (2007) "An Introduction to Structural Health Monitoring"
///   — Phil. Trans. Royal Society A
/// - Chandola, Banerjee & Kumar (2009) "Anomaly Detection: A Survey"
///   — ACM Computing Surveys 41(3)
class AdaptiveAnomalyService {
  // Feature names we track (must match extractFeatures output)
  static const List<String> _featureKeys = [
    'ppv', 'rms', 'crest', 'kurtosis', 'stalta', 'cav', 'freq',
  ];

  // Calibration config
  static const int _calibrationSamples = 150; // ~5 min at 0.5Hz BLE rate
  static const double _emaAlpha = 0.01; // Slow adaptation rate

  // Detection thresholds (in standard deviations)
  static const double _thresholdLow = 2.0;   // > 2σ = unusual
  static const double _thresholdHigh = 3.5;  // > 3.5σ = anomaly

  // Per-feature running statistics (Welford's algorithm)
  final Map<String, _WelfordStats> _stats = {};

  // Post-calibration EMA baseline
  final Map<String, double> _emaMean = {};
  final Map<String, double> _emaVariance = {};

  int _sampleCount = 0;
  bool _isCalibrated = false;

  bool get isCalibrated => _isCalibrated;
  int get sampleCount => _sampleCount;
  int get calibrationTarget => _calibrationSamples;
  double get calibrationProgress => (_sampleCount / _calibrationSamples).clamp(0.0, 1.0);
  String get modeLabel => _isCalibrated ? 'Adaptive' : 'Calibrating (${(_sampleCount * 100 / _calibrationSamples).round()}%)';

  AdaptiveAnomalyService() {
    for (final key in _featureKeys) {
      _stats[key] = _WelfordStats();
    }
  }

  /// Feed a new sample to update the baseline model.
  /// Call this for EVERY BLE packet received, even during detection phase.
  void updateBaseline(Map<String, double> features) {
    _sampleCount++;

    for (final key in _featureKeys) {
      final value = features[key] ?? 0.0;
      _stats[key]!.update(value);
    }

    // Transition from calibration to detection
    if (!_isCalibrated && _sampleCount >= _calibrationSamples) {
      _isCalibrated = true;
      // Initialize EMA with calibration statistics
      for (final key in _featureKeys) {
        _emaMean[key] = _stats[key]!.mean;
        _emaVariance[key] = _stats[key]!.variance;
      }
      debugPrint('AdaptiveAnomalyService: Calibration complete after $_sampleCount samples');
      debugPrint('  Baseline: ${_featureKeys.map((k) => "$k: μ=${_emaMean[k]!.toStringAsFixed(3)} σ=${sqrt(_emaVariance[k]!).toStringAsFixed(3)}").join(", ")}');
    }

    // Update EMA baseline (slow drift tracking)
    if (_isCalibrated) {
      for (final key in _featureKeys) {
        final value = features[key] ?? 0.0;
        final oldMean = _emaMean[key]!;
        _emaMean[key] = oldMean + _emaAlpha * (value - oldMean);
        final diff = value - _emaMean[key]!;
        _emaVariance[key] = _emaVariance[key]! + _emaAlpha * (diff * diff - _emaVariance[key]!);
        // Floor variance to prevent division by near-zero
        if (_emaVariance[key]! < 1e-10) _emaVariance[key] = 1e-10;
      }
    }
  }

  /// Score a sample for anomaly detection.
  /// Returns null if not yet calibrated (caller should use rule-based fallback).
  AdaptiveAnomalyResult? detect(Map<String, double> features) {
    if (!_isCalibrated) return null;

    // Compute per-feature z-scores and aggregate
    double sumZSq = 0.0;
    int featureCount = 0;
    final Map<String, double> zScores = {};

    for (final key in _featureKeys) {
      final value = features[key] ?? 0.0;
      final mean = _emaMean[key]!;
      final stdDev = sqrt(_emaVariance[key]!);

      if (stdDev > 1e-8) {
        final z = (value - mean).abs() / stdDev;
        zScores[key] = z;
        sumZSq += z * z;
        featureCount++;
      }
    }

    if (featureCount == 0) return null;

    // Root mean squared z-score (like simplified Mahalanobis distance)
    final rmsZ = sqrt(sumZSq / featureCount);

    // Classify
    AdaptiveAnomalyLevel level;
    double score;
    if (rmsZ < _thresholdLow) {
      level = AdaptiveAnomalyLevel.normal;
      score = rmsZ / _thresholdLow;
    } else if (rmsZ < _thresholdHigh) {
      level = AdaptiveAnomalyLevel.unusual;
      score = 0.5 + 0.5 * (rmsZ - _thresholdLow) / (_thresholdHigh - _thresholdLow);
    } else {
      level = AdaptiveAnomalyLevel.anomaly;
      score = min(1.0, 0.8 + 0.2 * (rmsZ - _thresholdHigh) / _thresholdHigh);
    }

    // Find the dominant contributing feature
    String? dominantFeature;
    double maxZ = 0;
    for (final entry in zScores.entries) {
      if (entry.value > maxZ) {
        maxZ = entry.value;
        dominantFeature = entry.key;
      }
    }

    return AdaptiveAnomalyResult(
      score: score.clamp(0.0, 1.0),
      level: level,
      rmsZScore: rmsZ,
      featureZScores: zScores,
      dominantFeature: dominantFeature,
    );
  }

  /// Reset the baseline (e.g., when moving to a new site)
  void reset() {
    _sampleCount = 0;
    _isCalibrated = false;
    _emaMean.clear();
    _emaVariance.clear();
    for (final key in _featureKeys) {
      _stats[key] = _WelfordStats();
    }
    debugPrint('AdaptiveAnomalyService: Baseline reset');
  }

  /// Get baseline summary for display
  Map<String, Map<String, double>> get baselineSummary {
    if (!_isCalibrated) return {};
    return {
      for (final key in _featureKeys)
        key: {
          'mean': _emaMean[key] ?? 0,
          'stdDev': sqrt(_emaVariance[key] ?? 0),
        },
    };
  }
}

/// Welford's online algorithm for numerically stable running mean/variance.
class _WelfordStats {
  int _count = 0;
  double _mean = 0.0;
  double _m2 = 0.0;

  double get mean => _mean;
  double get variance => _count > 1 ? _m2 / (_count - 1) : 0.0;
  int get count => _count;

  void update(double value) {
    _count++;
    final delta = value - _mean;
    _mean += delta / _count;
    final delta2 = value - _mean;
    _m2 += delta * delta2;
  }
}

enum AdaptiveAnomalyLevel { normal, unusual, anomaly }

class AdaptiveAnomalyResult {
  final double score; // 0.0 (normal) to 1.0 (severe)
  final AdaptiveAnomalyLevel level;
  final double rmsZScore; // Root mean squared z-score
  final Map<String, double> featureZScores; // Per-feature z-scores
  final String? dominantFeature; // Feature contributing most to anomaly

  const AdaptiveAnomalyResult({
    required this.score,
    required this.level,
    required this.rmsZScore,
    required this.featureZScores,
    this.dominantFeature,
  });

  String get levelLabel {
    switch (level) {
      case AdaptiveAnomalyLevel.normal:
        return 'Normal';
      case AdaptiveAnomalyLevel.unusual:
        return 'Unusual';
      case AdaptiveAnomalyLevel.anomaly:
        return 'Anomaly';
    }
  }
}

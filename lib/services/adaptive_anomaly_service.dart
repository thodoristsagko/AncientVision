import 'dart:math';
import 'package:flutter/foundation.dart';

/// Adaptive statistical anomaly detector using online learning + trend analysis.
///
/// Phase 1 (calibration, first 5 minutes): Learns baseline vibration profile
/// using Welford's online algorithm for numerically stable running mean/variance.
/// During this phase, falls back to rule-based scoring.
///
/// Phase 2 (detection): Scores new samples by TWO methods:
///   1. **Instantaneous**: multivariate z-score deviation from baseline
///      (for sudden large events — actual avalanches)
///   2. **Trend**: compares short-term (2 min) vs long-term (10 min) rolling
///      averages to detect slow drift in vibration patterns
///      (for micro-vibration precursors to avalanches)
///
/// The trend detector is the KEY innovation — soil avalanche precursors
/// manifest as gradual increases in low-frequency energy, rising kurtosis
/// (micro-cracks), and slowly climbing STA/LTA over minutes, NOT as
/// sudden spikes. A spike-only detector would miss precursors entirely.
///
/// Academic basis:
/// - Welford (1962) "Note on a Method for Calculating Corrected Sums of
///   Squares and Products" — Technometrics 4(3)
/// - Helmstetter & Garambois (2010) "Seismic monitoring of Séchilienne
///   rockslide" — precursor signals build over minutes to hours
/// - Fäh et al. (2012) "Microseismic activity analysis for stability
///   assessment of soil slopes" — low-frequency drift as instability indicator
class AdaptiveAnomalyService {
  // Feature names we track (must match extractFeatures output)
  static const List<String> _featureKeys = [
    'ppv', 'rms', 'crest', 'kurtosis', 'stalta', 'cav', 'freq',
  ];

  // Features most indicative of pre-avalanche drift
  // Higher weight = more important for trend scoring
  static const Map<String, double> _trendWeights = {
    'ppv': 0.15,
    'rms': 0.10,
    'crest': 0.05,
    'kurtosis': 0.20,   // micro-cracks cause rising kurtosis
    'stalta': 0.25,     // slow STA/LTA rise = key precursor
    'cav': 0.10,
    'freq': 0.15,       // frequency shift toward low band = instability
  };

  // Calibration config
  static const int _calibrationSamples = 150; // ~5 min at 0.5Hz BLE rate
  static const double _emaAlpha = 0.005; // Very slow adaptation — don't adapt away precursors

  // Instantaneous detection thresholds (in standard deviations)
  // Raised high — only trigger on genuinely large events
  static const double _thresholdLow = 3.0;   // > 3σ = unusual
  static const double _thresholdHigh = 5.0;  // > 5σ = anomaly

  // Trend detection config
  static const int _shortWindowSize = 60;    // ~2 min of samples at 0.5Hz
  static const int _longWindowSize = 300;    // ~10 min of samples
  static const double _trendThresholdLow = 1.5;  // Short-term 1.5σ above long-term
  static const double _trendThresholdHigh = 2.5; // Short-term 2.5σ above long-term

  // Sliding window feature matrix for precursor pattern detection
  // ~20 min at 0.5Hz BLE rate
  final List<Map<String, double>> _featureHistory = [];
  static const int _featureHistoryMax = 600;

  // Per-feature running statistics (Welford's algorithm)
  final Map<String, _WelfordStats> _stats = {};

  // Post-calibration EMA baseline
  final Map<String, double> _emaMean = {};
  final Map<String, double> _emaVariance = {};

  // Rolling windows for trend detection
  final Map<String, List<double>> _shortWindow = {};
  final Map<String, List<double>> _longWindow = {};

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
      _shortWindow[key] = [];
      _longWindow[key] = [];
    }
  }

  /// Feed a new sample to update the baseline model.
  /// Call this for EVERY BLE packet received, even during detection phase.
  void updateBaseline(Map<String, double> features) {
    _sampleCount++;

    for (final key in _featureKeys) {
      final value = features[key] ?? 0.0;
      _stats[key]!.update(value);

      // Maintain rolling windows for trend detection
      _shortWindow[key]!.add(value);
      if (_shortWindow[key]!.length > _shortWindowSize) {
        _shortWindow[key]!.removeAt(0);
      }
      _longWindow[key]!.add(value);
      if (_longWindow[key]!.length > _longWindowSize) {
        _longWindow[key]!.removeAt(0);
      }
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

    _featureHistory.add(Map.of(features));
    if (_featureHistory.length > _featureHistoryMax) {
      _featureHistory.removeAt(0);
    }

    // Update EMA baseline (very slow drift tracking)
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
  ///
  /// Uses the HIGHER of instantaneous score and trend score.
  /// This means:
  /// - A sudden massive event (actual avalanche) triggers via instantaneous
  /// - A slow buildup of micro-vibrations triggers via trend
  AdaptiveAnomalyResult? detect(Map<String, double> features) {
    if (!_isCalibrated) return null;

    // --- Instantaneous z-score detection ---
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

    final rmsZ = sqrt(sumZSq / featureCount);

    // Instantaneous classification
    double instantScore;
    if (rmsZ < _thresholdLow) {
      instantScore = rmsZ / _thresholdLow * 0.3; // 0-0.3 range for normal
    } else if (rmsZ < _thresholdHigh) {
      instantScore = 0.3 + 0.4 * (rmsZ - _thresholdLow) / (_thresholdHigh - _thresholdLow);
    } else {
      instantScore = min(1.0, 0.7 + 0.3 * (rmsZ - _thresholdHigh) / _thresholdHigh);
    }

    // --- Trend detection (short-term vs long-term) ---
    double trendScore = 0.0;
    String? trendFeature;
    double maxTrendZ = 0.0;

    // Only compute trend if we have enough long-window data
    if (_longWindow[_featureKeys.first]!.length >= _longWindowSize ~/ 2) {
      double weightedTrendSum = 0.0;
      double weightSum = 0.0;

      for (final key in _featureKeys) {
        final shortAvg = _windowMean(_shortWindow[key]!);
        final longAvg = _windowMean(_longWindow[key]!);
        final longStd = _windowStdDev(_longWindow[key]!, longAvg);

        if (longStd > 1e-8) {
          // How many σ is the short-term average ABOVE the long-term average?
          // Positive = rising trend, negative = falling trend
          // For precursors, we care about RISING trends in most features
          // but FALLING frequency (shift to lower frequencies = instability)
          double trendZ;
          if (key == 'freq') {
            // Frequency dropping = bad sign (shift to low-freq seismic band)
            trendZ = (longAvg - shortAvg) / longStd;
          } else {
            // Everything else rising = bad sign
            trendZ = (shortAvg - longAvg) / longStd;
          }

          // Only count positive trends (rising risk)
          if (trendZ > 0) {
            final weight = _trendWeights[key] ?? 0.1;
            weightedTrendSum += trendZ * weight;
            weightSum += weight;

            if (trendZ > maxTrendZ) {
              maxTrendZ = trendZ;
              trendFeature = key;
            }
          }
        }
      }

      if (weightSum > 0) {
        final weightedTrendZ = weightedTrendSum / weightSum;

        if (weightedTrendZ < _trendThresholdLow) {
          trendScore = weightedTrendZ / _trendThresholdLow * 0.3;
        } else if (weightedTrendZ < _trendThresholdHigh) {
          trendScore = 0.3 + 0.4 * (weightedTrendZ - _trendThresholdLow) /
              (_trendThresholdHigh - _trendThresholdLow);
        } else {
          trendScore = min(1.0, 0.7 + 0.3 * (weightedTrendZ - _trendThresholdHigh) /
              _trendThresholdHigh);
        }
      }
    }

    // --- Physics-informed precursor pattern detection ---
    double precursorScore = 0.0;
    String? precursorPattern;

    if (_featureHistory.length >= 300) { // Need ~10 min of data
      const windowSamples = 150; // ~5 min window

      final ppvDeriv = _computeDerivative('ppv', windowSamples);
      final freqDeriv = _computeDerivative('freq', windowSamples);
      final kurtDeriv = _computeDerivative('kurtosis', windowSamples);
      final staltaDeriv = _computeDerivative('stalta', windowSamples);
      final ppvAccel = _computeAcceleration('ppv', windowSamples);

      // Pattern A: Soil creep — slow PPV rise + frequency drop + kurtosis spikes
      // Physics: soil grains rearranging under load, friction decreasing
      double patternA = 0.0;
      if (ppvDeriv > 0 && freqDeriv < 0 && kurtDeriv > 0) {
        patternA = (ppvDeriv.abs() * 100).clamp(0.0, 1.0) * 0.3 +
                   (freqDeriv.abs() * 50).clamp(0.0, 1.0) * 0.4 +
                   (kurtDeriv.abs() * 20).clamp(0.0, 1.0) * 0.3;
      }

      // Pattern B: Crack propagation — intermittent kurtosis bursts + STA/LTA ratcheting
      // Physics: discrete crack events with increasing frequency
      double patternB = 0.0;
      if (kurtDeriv > 0 && staltaDeriv > 0) {
        patternB = (kurtDeriv.abs() * 30).clamp(0.0, 1.0) * 0.5 +
                   (staltaDeriv.abs() * 20).clamp(0.0, 1.0) * 0.5;
      }

      // Pattern C: Imminent failure — all features rising, frequency collapsed to <5Hz
      // Physics: large-scale mass movement beginning
      double patternC = 0.0;
      final recentFreq = _rangeAverage('freq', _featureHistory.length - 30, _featureHistory.length);
      if (ppvDeriv > 0 && kurtDeriv > 0 && staltaDeriv > 0 && recentFreq > 0 && recentFreq < 5.0) {
        patternC = min(1.0, ppvAccel.abs() * 500 + 0.5); // Accelerating = very bad
      }

      // Take the max pattern match
      precursorScore = max(patternA, max(patternB, patternC));
      if (patternC >= patternA && patternC >= patternB && patternC > 0.3) {
        precursorPattern = 'imminent_failure';
      } else if (patternB >= patternA && patternB > 0.3) {
        precursorPattern = 'crack_propagation';
      } else if (patternA > 0.3) {
        precursorPattern = 'soil_creep';
      }

      // Cross-feature correlation bonus: kurtosis rising WHILE frequency dropping
      if (kurtDeriv > 0 && freqDeriv < 0) {
        precursorScore = min(1.0, precursorScore * 1.3); // 30% confidence bonus
      }

      if (precursorScore > 0.2) {
        debugPrint('Precursor: score=${precursorScore.toStringAsFixed(3)} '
            'pattern=$precursorPattern A=${patternA.toStringAsFixed(2)} '
            'B=${patternB.toStringAsFixed(2)} C=${patternC.toStringAsFixed(2)}');
      }
    }

    // Final score = max of instantaneous, trend, and precursor
    // This way EITHER a sudden event OR a slow buildup OR a physics pattern triggers
    final finalScore = max(instantScore, max(trendScore, precursorScore)).clamp(0.0, 1.0);
    final isTrendDriven = trendScore > instantScore && trendScore >= precursorScore;
    final isPrecursorDriven = precursorScore > instantScore && precursorScore > trendScore;

    // Classify
    AdaptiveAnomalyLevel level;
    if (finalScore < 0.35) {
      level = AdaptiveAnomalyLevel.normal;
    } else if (finalScore < 0.7) {
      level = AdaptiveAnomalyLevel.unusual;
    } else {
      level = AdaptiveAnomalyLevel.anomaly;
    }

    // Find dominant contributing feature
    String? dominantFeature;
    if (isTrendDriven && trendFeature != null) {
      dominantFeature = '$trendFeature (trend↑)';
    } else {
      double maxZ = 0;
      for (final entry in zScores.entries) {
        if (entry.value > maxZ) {
          maxZ = entry.value;
          dominantFeature = entry.key;
        }
      }
    }

    if (isPrecursorDriven && precursorPattern != null) {
      dominantFeature = 'precursor: $precursorPattern';
    }

    if (level != AdaptiveAnomalyLevel.normal) {
      debugPrint('AdaptiveAnomaly: ${level.name} score=${finalScore.toStringAsFixed(3)} '
          '${isPrecursorDriven ? "PRECURSOR($precursorPattern)" : isTrendDriven ? "TREND" : "INSTANT"} '
          'dominant=$dominantFeature '
          'instantZ=${rmsZ.toStringAsFixed(2)} trendScore=${trendScore.toStringAsFixed(3)} '
          'precursorScore=${precursorScore.toStringAsFixed(3)}');
    }

    return AdaptiveAnomalyResult(
      score: finalScore,
      level: level,
      rmsZScore: rmsZ,
      featureZScores: zScores,
      dominantFeature: dominantFeature,
      isTrendDriven: isTrendDriven,
      trendScore: trendScore,
      isPrecursorDriven: isPrecursorDriven,
      precursorScore: precursorScore,
      precursorPattern: precursorPattern,
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
      _shortWindow[key] = [];
      _longWindow[key] = [];
    }
    _featureHistory.clear();
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

  // --- Temporal derivative helpers for precursor detection ---

  /// Compute rate of change (derivative) of a feature over a window.
  /// Returns change per sample. Positive = rising.
  double _computeDerivative(String feature, int windowSamples) {
    if (_featureHistory.length < windowSamples + 1) return 0.0;
    final start = _featureHistory.length - windowSamples;
    final oldAvg = _rangeAverage(feature, start, start + windowSamples ~/ 3);
    final newAvg = _rangeAverage(feature, _featureHistory.length - windowSamples ~/ 3, _featureHistory.length);
    return (newAvg - oldAvg) / windowSamples;
  }

  /// Compute acceleration (2nd derivative) — is the trend speeding up?
  double _computeAcceleration(String feature, int windowSamples) {
    if (_featureHistory.length < windowSamples * 2) return 0.0;
    final d1 = _computeDerivative(feature, windowSamples);
    // Compute derivative from the earlier half
    final halfLen = _featureHistory.length ~/ 2;
    final oldHistory = _featureHistory.sublist(0, halfLen);
    double oldD = 0.0;
    if (oldHistory.length >= windowSamples + 1) {
      final start = oldHistory.length - windowSamples;
      double oldSum = 0.0, newSum = 0.0;
      int oldCount = 0, newCount = 0;
      for (int i = start; i < start + windowSamples ~/ 3; i++) {
        oldSum += oldHistory[i][feature] ?? 0.0;
        oldCount++;
      }
      for (int i = oldHistory.length - windowSamples ~/ 3; i < oldHistory.length; i++) {
        newSum += oldHistory[i][feature] ?? 0.0;
        newCount++;
      }
      if (oldCount > 0 && newCount > 0) {
        oldD = (newSum / newCount - oldSum / oldCount) / windowSamples;
      }
    }
    return d1 - oldD; // Positive = accelerating upward
  }

  double _rangeAverage(String feature, int from, int to) {
    if (from >= to || from < 0) return 0.0;
    final end = to.clamp(0, _featureHistory.length);
    final start = from.clamp(0, end);
    if (start >= end) return 0.0;
    double sum = 0.0;
    for (int i = start; i < end; i++) {
      sum += _featureHistory[i][feature] ?? 0.0;
    }
    return sum / (end - start);
  }

  // --- Utility functions ---

  double _windowMean(List<double> window) {
    if (window.isEmpty) return 0.0;
    double sum = 0.0;
    for (final v in window) {
      sum += v;
    }
    return sum / window.length;
  }

  double _windowStdDev(List<double> window, double mean) {
    if (window.length < 2) return 0.0;
    double sumSq = 0.0;
    for (final v in window) {
      final d = v - mean;
      sumSq += d * d;
    }
    return sqrt(sumSq / (window.length - 1));
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
  final bool isTrendDriven; // True if trend detection triggered (not instantaneous)
  final double trendScore; // Trend-specific score
  final bool isPrecursorDriven; // True if precursor pattern detection triggered
  final double precursorScore; // Precursor-specific score
  final String? precursorPattern; // Detected precursor pattern name

  const AdaptiveAnomalyResult({
    required this.score,
    required this.level,
    required this.rmsZScore,
    required this.featureZScores,
    this.dominantFeature,
    this.isTrendDriven = false,
    this.trendScore = 0.0,
    this.isPrecursorDriven = false,
    this.precursorScore = 0.0,
    this.precursorPattern,
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

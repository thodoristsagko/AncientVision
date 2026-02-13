import 'dart:math';
import 'dart:typed_data';

/// Phone-side DSP engine that processes raw acceleration buffers from BLE.
///
/// Replaces firmware-side FFT, DWT, kurtosis, spectral centroid, Arias
/// intensity, and CAV computations. The phone has orders of magnitude
/// more compute than the ESP32, so we can afford richer analysis.
///
/// Input: 256 tri-axial acceleration samples at 200Hz (1.28s window)
/// Output: Full feature vector for anomaly detection pipeline
class VibrationDspService {
  static const int sampleRate = 200;
  static const int windowSize = 256;
  static const double dt = 1.0 / sampleRate;

  // Running accumulators (persist across windows)
  double ariasIntensity = 0.0;
  double cav = 0.0;
  DateTime _lastAriasReset = DateTime.now();
  static const Duration ariasResetInterval = Duration(seconds: 60);

  /// Process a raw acceleration buffer and return all computed features.
  ///
  /// [accelX], [accelY], [accelZ] are filtered acceleration in g units,
  /// each containing [windowSize] samples.
  DspResult process(List<double> accelX, List<double> accelY, List<double> accelZ) {
    assert(accelX.length == windowSize);
    assert(accelY.length == windowSize);
    assert(accelZ.length == windowSize);

    // 1. Compute magnitude signal
    final magnitude = List<double>.filled(windowSize, 0.0);
    for (int i = 0; i < windowSize; i++) {
      magnitude[i] = sqrt(accelX[i] * accelX[i] + accelY[i] * accelY[i] + accelZ[i] * accelZ[i]);
    }

    // 2. RMS and Peak
    double sumSq = 0.0;
    double peak = 0.0;
    for (int i = 0; i < windowSize; i++) {
      sumSq += magnitude[i] * magnitude[i];
      if (magnitude[i] > peak) peak = magnitude[i];
    }
    final rms = sqrt(sumSq / windowSize);
    final crestFactor = rms > 0.0001 ? peak / rms : 1.0;

    // 3. Kurtosis (excess, on magnitude signal)
    double mean = 0.0;
    for (int i = 0; i < windowSize; i++) mean += magnitude[i];
    mean /= windowSize;
    double m2 = 0.0, m4 = 0.0;
    for (int i = 0; i < windowSize; i++) {
      final d = magnitude[i] - mean;
      m2 += d * d;
      m4 += d * d * d * d;
    }
    m2 /= windowSize;
    m4 /= windowSize;
    final kurtosis = m2 > 0.00001 ? (m4 / (m2 * m2)) - 3.0 : 0.0;

    // 4. FFT (radix-2 DIT) on magnitude signal with Hanning window
    final fftMagnitudes = _computeFFT(magnitude);

    // 5. Dominant frequency and spectral centroid
    final binResolution = sampleRate.toDouble() / windowSize;
    double maxMag = 0.0;
    int maxBin = 1;
    double magRmsSum = 0.0;
    final halfN = windowSize ~/ 2;

    for (int i = 1; i < halfN; i++) {
      magRmsSum += fftMagnitudes[i] * fftMagnitudes[i];
      if (fftMagnitudes[i] > maxMag) {
        maxMag = fftMagnitudes[i];
        maxBin = i;
      }
    }
    final noiseFloor = sqrt(magRmsSum / (halfN - 1)) * 3.0;

    final dominantFreq = maxMag > noiseFloor ? maxBin * binResolution : 0.0;

    double spectralCentroid = 0.0;
    if (maxMag > noiseFloor) {
      double weightedSum = 0.0, magnitudeSum = 0.0;
      for (int i = 1; i < halfN; i++) {
        final freq = i * binResolution;
        weightedSum += freq * fftMagnitudes[i];
        magnitudeSum += fftMagnitudes[i];
      }
      spectralCentroid = magnitudeSum > 0.001 ? weightedSum / magnitudeSum : 0.0;
    }

    // 6. 3-level Haar DWT
    final dwtResult = _computeHaarDWT(magnitude, 3);

    // 7. Arias Intensity accumulation (per window)
    // AI = (pi / 2g) * integral(a^2 dt), a in g
    double windowArias = 0.0;
    double windowCav = 0.0;
    for (int i = 0; i < windowSize; i++) {
      windowArias += (pi / (2.0 * 9.81)) * magnitude[i] * magnitude[i] * dt;
      windowCav += magnitude[i] * dt;
    }
    ariasIntensity += windowArias;
    cav += windowCav;

    // Auto-reset Arias/CAV every 60s
    final now = DateTime.now();
    if (now.difference(_lastAriasReset) >= ariasResetInterval) {
      ariasIntensity = 0.0;
      cav = 0.0;
      _lastAriasReset = now;
    }

    return DspResult(
      rms: rms,
      peak: peak,
      crestFactor: crestFactor,
      kurtosis: kurtosis,
      dominantFreq: dominantFreq,
      spectralCentroid: spectralCentroid,
      fftMagnitudes: fftMagnitudes.sublist(0, halfN),
      dwtEnergy1: dwtResult.energy1,
      dwtEnergy2: dwtResult.energy2,
      dwtEnergy3: dwtResult.energy3,
      ariasIntensity: ariasIntensity,
      cav: cav,
    );
  }

  /// Radix-2 DIT FFT with Hanning window.
  /// Returns magnitude spectrum (full N points, use first N/2).
  List<double> _computeFFT(List<double> signal) {
    final n = signal.length;
    // Apply Hanning window
    final real = Float64List(n);
    final imag = Float64List(n);
    for (int i = 0; i < n; i++) {
      final window = 0.5 * (1.0 - cos(2.0 * pi * i / (n - 1)));
      real[i] = signal[i] * window;
      imag[i] = 0.0;
    }

    // Bit-reversal permutation
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
      if (i < j) {
        final tmpR = real[i]; real[i] = real[j]; real[j] = tmpR;
        final tmpI = imag[i]; imag[i] = imag[j]; imag[j] = tmpI;
      }
      int k = n >> 1;
      while (k <= j) {
        j -= k;
        k >>= 1;
      }
      j += k;
    }

    // FFT butterfly
    for (int len = 2; len <= n; len <<= 1) {
      final halfLen = len >> 1;
      final angle = -2.0 * pi / len;
      final wR = cos(angle);
      final wI = sin(angle);
      for (int i = 0; i < n; i += len) {
        double curR = 1.0, curI = 0.0;
        for (int k = 0; k < halfLen; k++) {
          final tR = curR * real[i + k + halfLen] - curI * imag[i + k + halfLen];
          final tI = curR * imag[i + k + halfLen] + curI * real[i + k + halfLen];
          real[i + k + halfLen] = real[i + k] - tR;
          imag[i + k + halfLen] = imag[i + k] - tI;
          real[i + k] += tR;
          imag[i + k] += tI;
          final newR = curR * wR - curI * wI;
          curI = curR * wI + curI * wR;
          curR = newR;
        }
      }
    }

    // Compute magnitudes
    final magnitudes = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      magnitudes[i] = sqrt(real[i] * real[i] + imag[i] * imag[i]);
    }
    return magnitudes;
  }

  /// 3-level Haar DWT. Returns detail energies per level.
  _DwtResult _computeHaarDWT(List<double> signal, int levels) {
    final temp = List<double>.from(signal);
    final energies = <double>[];

    int len = temp.length;
    for (int level = 0; level < levels; level++) {
      final halfLen = len ~/ 2;
      final approx = List<double>.filled(halfLen, 0.0);
      final detail = List<double>.filled(halfLen, 0.0);
      const invSqrt2 = 0.70710678118;

      for (int i = 0; i < halfLen; i++) {
        approx[i] = (temp[2 * i] + temp[2 * i + 1]) * invSqrt2;
        detail[i] = (temp[2 * i] - temp[2 * i + 1]) * invSqrt2;
      }

      // Compute energy for this detail level
      double energy = 0.0;
      for (int i = 0; i < halfLen; i++) {
        energy += detail[i] * detail[i];
      }
      energies.add(energy);

      // Copy approx back for next level
      for (int i = 0; i < halfLen; i++) {
        temp[i] = approx[i];
      }
      len = halfLen;
    }

    return _DwtResult(
      energy1: energies.length > 0 ? energies[0] : 0.0,
      energy2: energies.length > 1 ? energies[1] : 0.0,
      energy3: energies.length > 2 ? energies[2] : 0.0,
    );
  }

  /// Reset running accumulators (e.g. when reconnecting)
  void reset() {
    ariasIntensity = 0.0;
    cav = 0.0;
    _lastAriasReset = DateTime.now();
  }
}

/// Result of phone-side DSP processing on one acceleration window.
class DspResult {
  final double rms;
  final double peak;
  final double crestFactor;
  final double kurtosis;
  final double dominantFreq;
  final double spectralCentroid;
  final List<double> fftMagnitudes; // First N/2 bins
  final double dwtEnergy1; // 50-100Hz band
  final double dwtEnergy2; // 25-50Hz band
  final double dwtEnergy3; // 12.5-25Hz band
  final double ariasIntensity;
  final double cav;

  const DspResult({
    required this.rms,
    required this.peak,
    required this.crestFactor,
    required this.kurtosis,
    required this.dominantFreq,
    required this.spectralCentroid,
    required this.fftMagnitudes,
    required this.dwtEnergy1,
    required this.dwtEnergy2,
    required this.dwtEnergy3,
    required this.ariasIntensity,
    required this.cav,
  });

  /// Convert to feature map for anomaly detection pipeline.
  Map<String, double> toFeatureMap({
    required double ppv,
    required double stalta,
    required double temp,
  }) {
    return {
      'rms': rms,
      'ppv': ppv,
      'freq': dominantFreq,
      'crest': crestFactor,
      'centroid': spectralCentroid,
      'kurtosis': kurtosis,
      'stalta': stalta,
      'arias': ariasIntensity,
      'cav': cav,
      'temp': temp,
    };
  }
}

class _DwtResult {
  final double energy1;
  final double energy2;
  final double energy3;
  const _DwtResult({required this.energy1, required this.energy2, required this.energy3});
}

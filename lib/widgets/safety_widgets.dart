import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/alert_data.dart';
import '../services/vibration_anomaly_service.dart';
import '../services/vibration_metrics_service.dart';
import '../services/wavelet_service.dart';
import '../services/ppv_prediction_service.dart';

class LiveChip extends StatelessWidget {
  final bool isConnected;
  final String status;

  const LiveChip({super.key, required this.isConnected, required this.status});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: ClipRRect(
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
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? const Color(0xFF4CAF50) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'LIVE' : 'OFFLINE',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SafetyStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String status;
  final Color? statusColor;

  const SafetyStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.status,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 125,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(89), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.white.withAlpha(217), fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(status, style: TextStyle(color: statusColor ?? Colors.white.withAlpha(191), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class LiveSensorsCard extends StatelessWidget {
  final double accX, accY, accZ;
  final int moisturePercent;
  final String lastUpdate;
  final bool isConnected;
  final double vibration;
  final double ppv;
  final double dominantFreq;
  final double crestFactor;
  final double rms;
  final String hazardType;

  const LiveSensorsCard({
    super.key,
    required this.accX, required this.accY, required this.accZ,
    required this.moisturePercent, required this.lastUpdate, required this.isConnected,
    this.vibration = 0.0,
    this.ppv = 0.0,
    this.dominantFreq = 0.0,
    this.crestFactor = 0.0,
    this.rms = 0.0,
    this.hazardType = 'none',
  });

  @override
  Widget build(BuildContext context) {
    // DIN 4150-3 compliant status
    String vibStatus = 'Safe';
    Color vibColor = Colors.green;
    if (ppv > 10.0) {
      vibStatus = 'CRITICAL';
      vibColor = const Color(0xFFE53935);
    } else if (ppv > 3.0) {
      vibStatus = 'DIN EXCEEDED';
      vibColor = const Color(0xFFFF5722);
    } else if (ppv > 2.5) {
      vibStatus = 'Heritage limit';
      vibColor = Colors.orange;
    } else if (ppv > 0.3) {
      vibStatus = 'Perceptible';
      vibColor = const Color(0xFFFFC107);
    } else if (ppv == 0.0 && vibration > 0.5) {
      vibStatus = 'HIGH!';
      vibColor = Colors.red;
    } else if (ppv == 0.0 && vibration > 0.2) {
      vibStatus = 'Moderate';
      vibColor = Colors.orange;
    }

    final bool hasV2Data = ppv > 0 || rms > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(89), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Live sensors', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (hasV2Data)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withAlpha(60),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('v2.0 DSP', style: TextStyle(color: Color(0xFF00BCD4), fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: isConnected ? Colors.green : Colors.grey,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SensorRow(
                label: hasV2Data ? 'PPV (DIN 4150-3)' : 'Vibration (M5StickC)',
                value: hasV2Data
                    ? '${ppv.toStringAsFixed(1)} mm/s   Status: $vibStatus'
                    : '${vibration.toStringAsFixed(2)}g   Status: $vibStatus',
                icon: Icons.vibration,
                valueColor: vibColor,
              ),
              if (hasV2Data) ...[
                const SizedBox(height: 6),
                SensorRow(
                  label: 'Frequency analysis',
                  value: '${dominantFreq.toStringAsFixed(0)} Hz   Crest: ${crestFactor.toStringAsFixed(1)}   RMS: ${rms.toStringAsFixed(4)}g',
                  icon: Icons.graphic_eq,
                ),
              ],
              const SizedBox(height: 6),
              SensorRow(
                label: 'Soil moisture',
                value: '$moisturePercent %   (safe: 30-60%)',
                icon: Icons.water_drop_outlined,
              ),
              const SizedBox(height: 10),
              Text('Last update: $lastUpdate', style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class SensorRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const SensorRow({super.key, required this.label, required this.value, required this.icon, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(89), width: 1),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(color: valueColor ?? Colors.white.withAlpha(204), fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

// ===================== ML ANOMALY INDICATOR =====================
class MLAnomalyIndicator extends StatelessWidget {
  final AnomalyResult result;
  final Map<String, double> features;
  final List<double> anomalyHistory;
  final String modelVersion;

  const MLAnomalyIndicator({
    super.key,
    required this.result,
    this.features = const {},
    this.anomalyHistory = const [],
    this.modelVersion = '4.0',
  });

  Color _getColor() {
    switch (result.level) {
      case AnomalyLevel.normal: return const Color(0xFF4CAF50);
      case AnomalyLevel.unusual: return const Color(0xFFFFC107);
      case AnomalyLevel.anomaly: return const Color(0xFFE53935);
      case AnomalyLevel.unknown: return Colors.grey;
    }
  }

  IconData _getIcon() {
    switch (result.level) {
      case AnomalyLevel.normal: return Icons.check_circle_outline;
      case AnomalyLevel.unusual: return Icons.help_outline;
      case AnomalyLevel.anomaly: return Icons.warning_rounded;
      case AnomalyLevel.unknown: return Icons.device_unknown;
    }
  }

  /// Compute per-feature contribution using absolute z-score.
  List<MapEntry<String, double>> _topContributors() {
    if (features.isEmpty) return [];

    // StandardScaler means/scales from vibration_scaler.json (v4.0)
    const means = {
      'rms': 0.00937, 'ppv': 0.2061, 'freq': 4.668, 'crest': 2.321,
      'centroid': 16.58, 'kurtosis': 3.25, 'stalta': 1.308,
      'arias': 0.00411, 'cav': 0.037, 'temp': 24.95,
    };
    const scales = {
      'rms': 0.00893, 'ppv': 0.1442, 'freq': 3.334, 'crest': 0.6517,
      'centroid': 8.118, 'kurtosis': 0.5421, 'stalta': 0.3652,
      'arias': 0.00368, 'cav': 0.02822, 'temp': 5.716,
    };

    final contributions = <MapEntry<String, double>>[];
    for (final entry in features.entries) {
      final m = means[entry.key] ?? 0.0;
      final s = scales[entry.key] ?? 1.0;
      final zScore = s > 0 ? ((entry.value - m) / s).abs() : 0.0;
      contributions.add(MapEntry(entry.key, zScore));
    }
    contributions.sort((a, b) => b.value.compareTo(a.value));
    return contributions.take(3).toList();
  }

  static const _featureLabels = {
    'rms': 'RMS', 'ppv': 'PPV', 'freq': 'Freq', 'crest': 'Crest',
    'centroid': 'Centroid', 'kurtosis': 'Kurtosis', 'stalta': 'STA/LTA',
    'arias': 'Arias', 'cav': 'CAV', 'temp': 'Temp',
  };

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final topContribs = _topContributors();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(80), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withAlpha(40),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_getIcon(), color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('ML Anomaly Detection', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF9C27B0).withAlpha(40),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'VAE v$modelVersion',
                                style: const TextStyle(color: Color(0xFFCE93D8), fontSize: 9, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withAlpha(50),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                result.levelLabel,
                                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Score bar
                        Row(
                          children: [
                            Text('Score: ', style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: SizedBox(
                                  height: 6,
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(20),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor: result.score.clamp(0.0, 1.0),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(result.score * 100).toStringAsFixed(0)}%',
                              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Reconstruction error detail
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Reconstruction MSE: ', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 10)),
                  Text(
                    result.rawError.toStringAsFixed(4),
                    style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  Text('Features: ', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 10)),
                  Text(
                    '${features.length}/10',
                    style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),

              // Top feature contributors
              if (topContribs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Top contributors (z-score)', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 10)),
                const SizedBox(height: 4),
                Row(
                  children: topContribs.map((entry) {
                    final label = _featureLabels[entry.key] ?? entry.key;
                    final zScore = entry.value;
                    final barColor = zScore > 3.0
                        ? const Color(0xFFE53935)
                        : zScore > 2.0
                            ? const Color(0xFFFF9800)
                            : const Color(0xFF4CAF50);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          children: [
                            Text(label, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 9)),
                            const SizedBox(height: 2),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: SizedBox(
                                height: 4,
                                child: Stack(
                                  children: [
                                    Container(color: Colors.white.withAlpha(15)),
                                    FractionallySizedBox(
                                      widthFactor: (zScore / 5.0).clamp(0.0, 1.0),
                                      child: Container(color: barColor),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(zScore.toStringAsFixed(1), style: TextStyle(color: barColor, fontSize: 8, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Sparkline of recent anomaly scores
              if (anomalyHistory.length >= 2) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Recent scores', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 10)),
                    const Spacer(),
                    Text('${anomalyHistory.length} pts', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 28,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _AnomalySparklinePainter(anomalyHistory, color),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnomalySparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _AnomalySparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final maxVal = data.reduce(max).clamp(0.01, double.infinity);
    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - (size.height * (data[i] / maxVal).clamp(0.0, 1.0));
      points.add(Offset(x, y));
    }

    // Fill under curve
    final fillPath = ui.Path();
    fillPath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      fillPath.lineTo(points[i].dx, points[i].dy);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, size.height),
        [color.withAlpha(60), color.withAlpha(10)],
      ));

    // Line
    final linePath = ui.Path();
    linePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round);

    // Latest point dot
    canvas.drawCircle(points.last, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AnomalySparklinePainter old) =>
      old.data.length != data.length || (data.isNotEmpty && old.data.isNotEmpty && old.data.last != data.last);
}

// ===================== VIBRATION ANALYSIS CARD (v2.0) =====================
class VibrationAnalysisCard extends StatelessWidget {
  final double ppv, rms, dominantFreq, crestFactor;
  final double ppvSmoothed, ppvPeakHold, kurtosis, staLtaRatio, centroid;
  final double arias, cav, temp; // v4.0 fields
  final double dwt1, dwt2, dwt3; // v4.0 wavelet fields
  final String hazardType, hazardLabel;
  final String damageAssessment;
  final Color ppvColor;
  final bool isConnected;
  final VoidCallback? onHistoryTap;

  const VibrationAnalysisCard({
    super.key,
    required this.ppv, required this.rms, required this.dominantFreq,
    required this.crestFactor, required this.hazardType, required this.hazardLabel,
    required this.ppvColor, required this.isConnected,
    this.ppvSmoothed = 0, this.ppvPeakHold = 0, this.kurtosis = 0,
    this.staLtaRatio = 0, this.centroid = 0, this.damageAssessment = '',
    this.arias = 0, this.cav = 0, this.temp = 0, // v4.0 defaults
    this.dwt1 = 0, this.dwt2 = 0, this.dwt3 = 0,
    this.onHistoryTap,
  });

  String _getFreqBandLabel() {
    if (dominantFreq <= 0) return '--';
    if (dominantFreq <= 1.0) return 'Sub-Hz (wind/ambient)';
    if (dominantFreq <= 5.0) return '1-5 Hz (footsteps/sway)';
    if (dominantFreq <= 10.0) return '1-10 Hz (seismic band)';
    if (dominantFreq <= 50.0) return '10-50 Hz (machinery)';
    return '50-100 Hz (structural)';
  }

  Color _getFreqBandColor() {
    if (dominantFreq <= 0) return Colors.grey;
    if (dominantFreq <= 5.0) return const Color(0xFF4CAF50);
    if (dominantFreq <= 10.0) return const Color(0xFFFF5722);
    if (dominantFreq <= 50.0) return const Color(0xFFFF9800);
    return const Color(0xFFFFC107);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData = ppv > 0 || rms > 0;

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
                      color: ppvColor.withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.analytics_rounded, color: ppvColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Vibration Analysis', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ppvColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ppvColor.withAlpha(100), width: 1),
                    ),
                    child: Text(
                      hazardLabel,
                      style: TextStyle(color: ppvColor, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (onHistoryTap != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onHistoryTap,
                      child: Icon(Icons.history, color: Colors.white.withAlpha(180), size: 20),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text('DIN 4150-3 compliant vibration monitoring', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11)),
              const SizedBox(height: 14),

              if (!hasData)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isConnected ? 'Waiting for v2.0 firmware data...' : 'Connect sensor for analysis',
                      style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 12),
                    ),
                  ),
                )
              else ...[
                // PPV Gauge Bar (smoothed value, with peak hold)
                _buildGaugeRow('PPV', ppvSmoothed > 0 ? ppvSmoothed : ppv, 'mm/s', 15.0, ppvColor),
                if (ppvPeakHold > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Peak (5s): ${ppvPeakHold.toStringAsFixed(1)} mm/s',
                      style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 10),
                    ),
                  ),
                const SizedBox(height: 10),

                // DIN 4150-3 threshold markers
                _buildDINThresholdBar(),
                const SizedBox(height: 14),

                // Metrics grid - row 1
                Row(
                  children: [
                    _buildMetricTile('RMS', '${rms.toStringAsFixed(4)}g', Icons.show_chart),
                    const SizedBox(width: 10),
                    _buildMetricTile('Crest', crestFactor.toStringAsFixed(1), Icons.bolt),
                    const SizedBox(width: 10),
                    _buildMetricTile('Freq', '${dominantFreq.toStringAsFixed(0)}Hz', Icons.graphic_eq),
                  ],
                ),
                const SizedBox(height: 8),

                // Metrics grid - row 2 (v3.0 features)
                Row(
                  children: [
                    _buildMetricTile('Kurt', kurtosis.toStringAsFixed(1), Icons.assessment,
                      valueColor: kurtosis > 6 ? const Color(0xFFFF5722) : kurtosis > 3 ? const Color(0xFFFF9800) : null),
                    const SizedBox(width: 10),
                    _buildMetricTile('STA/LTA', staLtaRatio.toStringAsFixed(1), Icons.sensors,
                      valueColor: staLtaRatio > 4.0 ? const Color(0xFFFF5722) : staLtaRatio > 2.0 ? const Color(0xFFFF9800) : null),
                    const SizedBox(width: 10),
                    _buildMetricTile('Cent', '${centroid.toStringAsFixed(0)}Hz', Icons.center_focus_strong),
                  ],
                ),
                const SizedBox(height: 8),

                // Metrics grid - row 3 (v4.0 features) - only show if any v4.0 data present
                if (arias > 0 || cav > 0 || temp > 0) ...[
                  Row(
                    children: [
                      _buildMetricTile('Arias', arias.toStringAsFixed(4), Icons.tsunami,
                        valueColor: arias > 0.01 ? const Color(0xFFFF9800) : null),
                      const SizedBox(width: 10),
                      _buildMetricTile('CAV', '${cav.toStringAsFixed(3)}g·s', Icons.speed,
                        valueColor: cav > 0.16 ? const Color(0xFFFF5722) : cav > 0.1 ? const Color(0xFFFF9800) : null),
                      const SizedBox(width: 10),
                      _buildMetricTile('Temp', '${temp.toStringAsFixed(1)}°C', Icons.thermostat),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // DWT levels (v4.0) - only show if non-zero
                if (dwt1 > 0 || dwt2 > 0 || dwt3 > 0) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2196F3).withAlpha(60), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.graphic_eq, color: Color(0xFF2196F3), size: 14),
                            SizedBox(width: 6),
                            Text('Wavelet Decomposition (DWT)',
                              style: TextStyle(color: Color(0xFF2196F3), fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _buildDwtBar('D1 (50-100Hz)', dwt1, const Color(0xFF4CAF50))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildDwtBar('D2 (25-50Hz)', dwt2, const Color(0xFFFF9800))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildDwtBar('D3 (12-25Hz)', dwt3, const Color(0xFFFF5722))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 2),

                // Frequency band indicator
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getFreqBandColor().withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _getFreqBandColor().withAlpha(60), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.waves, color: _getFreqBandColor(), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _getFreqBandLabel(),
                        style: TextStyle(color: _getFreqBandColor(), fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                // Damage assessment
                if (damageAssessment.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    damageAssessment,
                    style: TextStyle(
                      color: Colors.white.withAlpha(160),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGaugeRow(String label, double value, String unit, double maxValue, Color color) {
    final fraction = (value / maxValue).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12)),
            const Spacer(),
            Text('${value.toStringAsFixed(1)} $unit', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color.withAlpha(200), color]),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(color: color.withAlpha(80), blurRadius: 6)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDINThresholdBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DIN 4150-3 Thresholds', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 10)),
        const SizedBox(height: 4),
        SizedBox(
          height: 20,
          child: Row(
            children: [
              _buildThresholdSegment('Safe', 0.3 / 15.0, const Color(0xFF4CAF50)),
              _buildThresholdSegment('', (2.5 - 0.3) / 15.0, const Color(0xFFFFC107)),
              _buildThresholdSegment('3mm/s', (3.0 - 2.5) / 15.0, const Color(0xFFFF9800)),
              _buildThresholdSegment('Heritage', (8.0 - 3.0) / 15.0, const Color(0xFFFF5722)),
              _buildThresholdSegment('10mm/s', (10.0 - 8.0) / 15.0, const Color(0xFFE53935)),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C).withAlpha(150),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: const Center(child: Text('DMG', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600))),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThresholdSegment(String label, double fraction, Color color) {
    return Expanded(
      flex: (fraction * 100).round().clamp(1, 100),
      child: Container(
        decoration: BoxDecoration(color: color.withAlpha(120)),
        child: Center(
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w600), overflow: TextOverflow.clip, maxLines: 1),
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(40), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white.withAlpha(150), size: 16),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildDwtBar(String label, double value, Color color) {
    const maxDwt = 0.01; // Typical max DWT energy
    final fraction = (value / maxDwt).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 9)),
        const SizedBox(height: 3),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(30),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(value.toStringAsFixed(4), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ===================== PPV TREND GRAPH (DIN 4150-3) =====================
class PPVTrendGraphCard extends StatelessWidget {
  final List<Map<String, dynamic>> ppvHistory;
  final PPVPrediction? prediction;
  final List<double> kalmanHistory;

  const PPVTrendGraphCard({
    super.key,
    required this.ppvHistory,
    this.prediction,
    this.kalmanHistory = const [],
  });

  @override
  Widget build(BuildContext context) {
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5722).withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.trending_up_rounded, color: Color(0xFFFF5722), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('PPV Trend', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5722).withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('DIN 4150-3', style: TextStyle(color: Color(0xFFFF5722), fontSize: 9, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Peak Particle Velocity with heritage limit lines', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11)),
              const SizedBox(height: 12),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem(const Color(0xFFFF5722), 'PPV'),
                  const SizedBox(width: 16),
                  _buildLegendItem(const Color(0xFFE53935).withAlpha(150), '3 mm/s limit'),
                  const SizedBox(width: 16),
                  _buildLegendItem(const Color(0xFFFFC107).withAlpha(150), '2.5 mm/s cont.'),
                  if (prediction != null && prediction!.isTrendingUp) ...[
                    const SizedBox(width: 16),
                    _buildLegendItem(const Color(0xFFFF8F00).withAlpha(150), 'Prediction'),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              if (ppvHistory.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.timeline, color: Colors.white.withAlpha(100), size: 28),
                        const SizedBox(height: 6),
                        Text('Waiting for PPV data...', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Y-axis labels
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('10', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 18),
                        Text('5', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 18),
                        Text('3', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 18),
                        Text('0', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 120,
                        child: CustomPaint(
                          size: const Size(double.infinity, 120),
                          painter: PPVGraphPainter(ppvHistory, prediction: prediction),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14, height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class PPVGraphPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final PPVPrediction? prediction;

  PPVGraphPainter(this.data, {this.prediction});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const double maxPPV = 12.0; // Max Y-axis (mm/s)
    const double topPad = 4.0;
    const double botPad = 2.0;
    final double graphH = size.height - topPad - botPad;

    // Draw grid
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = topPad + graphH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw DIN 4150-3 limit lines
    // 3 mm/s heritage limit (1-10 Hz)
    final limitY3 = topPad + graphH - (graphH * 3.0 / maxPPV);
    final limitPaint3 = Paint()
      ..color = const Color(0xFFE53935).withAlpha(120)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _drawDashedLine(canvas, Offset(0, limitY3), Offset(size.width, limitY3), limitPaint3);

    // 2.5 mm/s continuous limit
    final limitY25 = topPad + graphH - (graphH * 2.5 / maxPPV);
    final limitPaint25 = Paint()
      ..color = const Color(0xFFFFC107).withAlpha(100)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _drawDashedLine(canvas, Offset(0, limitY25), Offset(size.width, limitY25), limitPaint25);

    // Draw PPV line
    if (data.length < 2) return;

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final ppv = ((data[i]['ppv'] as num?)?.toDouble() ?? 0.0).clamp(0.0, maxPPV);
      final y = topPad + graphH - (graphH * ppv / maxPPV);
      points.add(Offset(x, y));
    }

    // Fill
    final fillPath = ui.Path();
    fillPath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      fillPath.lineTo(points[i].dx, points[i].dy);
    }
    fillPath.lineTo(size.width, topPad + graphH);
    fillPath.lineTo(0, topPad + graphH);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, topPad),
        Offset(0, topPad + graphH),
        [const Color(0xFFFF5722).withAlpha(80), const Color(0xFFFF5722).withAlpha(10)],
      );
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePath = ui.Path();
    linePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    final linePaint = Paint()
      ..color = const Color(0xFFFF5722)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // Glow
    final glowPaint = Paint()
      ..color = const Color(0xFFFF5722).withAlpha(40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    canvas.drawPath(linePath, glowPaint);

    // Latest point dot
    if (points.isNotEmpty) {
      final last = points.last;
      canvas.drawCircle(last, 4, Paint()..color = const Color(0xFFFF5722));
      canvas.drawCircle(last, 4, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }

    // Draw prediction line (dashed, amber)
    if (prediction != null && prediction!.isTrendingUp && prediction!.predicted.isNotEmpty) {
      final predPoints = <Offset>[];
      final lastX = points.last.dx;
      final lastY = points.last.dy;
      predPoints.add(Offset(lastX, lastY));

      final predCount = prediction!.predicted.length;
      final extraWidth = size.width * 0.3; // Extend 30% beyond current data
      for (int i = 0; i < predCount; i++) {
        final px = lastX + extraWidth * (i + 1) / predCount;
        if (px > size.width) break;
        final ppv = prediction!.predicted[i].clamp(0.0, maxPPV);
        final py = topPad + graphH - (graphH * ppv / maxPPV);
        predPoints.add(Offset(px, py));
      }

      if (predPoints.length >= 2) {
        final predPaint = Paint()
          ..color = const Color(0xFFFF8F00).withAlpha(180)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;
        _drawDashedLine(canvas, predPoints.first, predPoints.last, predPaint);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = sqrt(dx * dx + dy * dy);
    final unitX = dx / length;
    final unitY = dy / length;

    double drawn = 0;
    while (drawn < length) {
      final segEnd = (drawn + dashWidth).clamp(0.0, length);
      canvas.drawLine(
        Offset(start.dx + unitX * drawn, start.dy + unitY * drawn),
        Offset(start.dx + unitX * segEnd, start.dy + unitY * segEnd),
        paint,
      );
      drawn += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(PPVGraphPainter oldDelegate) =>
      oldDelegate.data.length != data.length || oldDelegate.prediction != prediction;
}

class SensorHistoryGraphCard extends StatelessWidget {
  final List<Map<String, dynamic>> sensorHistory;

  const SensorHistoryGraphCard({super.key, required this.sensorHistory});

  @override
  Widget build(BuildContext context) {
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BCD4).withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.show_chart_rounded, color: Color(0xFF00BCD4), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Sensor History', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.withAlpha(100), Colors.green.withAlpha(50)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withAlpha(150), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        const Text('Live', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Real-time environmental monitoring', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
              const SizedBox(height: 16),
              // Legend row with improved styling
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem(const Color(0xFF42A5F5), 'Moisture'),
                  const SizedBox(width: 24),
                  _buildLegendItem(const Color(0xFFEF5350), 'Vibration'),
                ],
              ),
              const SizedBox(height: 12),
              if (sensorHistory.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        Icon(Icons.sensors_off_rounded, color: Colors.white.withAlpha(100), size: 32),
                        const SizedBox(height: 8),
                        Text('Waiting for sensor data...', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13)),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Y-axis labels
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('100%', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 28),
                        Text('50%', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 28),
                        Text('0%', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 120,
                        child: CustomPaint(
                          size: const Size(double.infinity, 120),
                          painter: SensorGraphPainter(sensorHistory),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: color.withAlpha(100), blurRadius: 4)],
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class SensorGraphPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;

  SensorGraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const double leftPadding = 0;
    const double rightPadding = 0;
    const double topPadding = 8.0;
    const double bottomPadding = 4.0;
    final double graphWidth = size.width - leftPadding - rightPadding;
    final double graphHeight = size.height - topPadding - bottomPadding;

    // Draw subtle grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPadding + (graphHeight * i / 4);
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width - rightPadding, y), gridPaint);
    }

    // Max values for scaling
    const double maxVibration = 1.0;
    const double maxMoisture = 100.0;

    // Colors
    const moistureColor = Color(0xFF42A5F5);
    const vibrationColor = Color(0xFFEF5350);

    // Draw moisture area fill and line
    _drawSmoothLineWithFill(
      canvas, size, data, 'moisture', maxMoisture,
      moistureColor, topPadding, bottomPadding, leftPadding, graphWidth, graphHeight,
    );

    // Draw vibration area fill and line (scaled to percentage)
    _drawSmoothLineWithFill(
      canvas, size, data, 'vibration', maxVibration,
      vibrationColor, topPadding, bottomPadding, leftPadding, graphWidth, graphHeight,
    );

    // Draw data points
    _drawDataPoints(canvas, data, 'moisture', maxMoisture, moistureColor, topPadding, leftPadding, graphWidth, graphHeight);
    _drawDataPoints(canvas, data, 'vibration', maxVibration, vibrationColor, topPadding, leftPadding, graphWidth, graphHeight);
  }

  void _drawSmoothLineWithFill(
    Canvas canvas, Size size, List<Map<String, dynamic>> data, String key, double maxValue,
    Color color, double topPadding, double bottomPadding, double leftPadding, double graphWidth, double graphHeight,
  ) {
    if (data.length < 2) return;

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = leftPadding + (graphWidth * i / (data.length - 1));
      final value = (data[i][key] as num?)?.toDouble() ?? 0.0;
      final y = topPadding + graphHeight - (graphHeight * value / maxValue);
      points.add(Offset(x, y));
    }

    // Create smooth path using quadratic bezier curves
    final linePath = ui.Path();
    linePath.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final midX = (current.dx + next.dx) / 2;
      final midY = (current.dy + next.dy) / 2;

      if (i == 0) {
        linePath.quadraticBezierTo(current.dx, current.dy, midX, midY);
      } else {
        linePath.quadraticBezierTo(current.dx, current.dy, midX, midY);
      }
    }
    linePath.lineTo(points.last.dx, points.last.dy);

    // Draw gradient fill
    final fillPath = ui.Path.from(linePath);
    fillPath.lineTo(leftPadding + graphWidth, topPadding + graphHeight);
    fillPath.lineTo(leftPadding, topPadding + graphHeight);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, topPadding),
        Offset(0, topPadding + graphHeight),
        [color.withAlpha(80), color.withAlpha(10)],
      );
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Draw glow effect
    final glowPaint = Paint()
      ..color = color.withAlpha(50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawPath(linePath, glowPaint);
  }

  void _drawDataPoints(
    Canvas canvas, List<Map<String, dynamic>> data, String key, double maxValue,
    Color color, double topPadding, double leftPadding, double graphWidth, double graphHeight,
  ) {
    final dotPaint = Paint()..color = color;
    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Only draw dots at first, last, and a few middle points to avoid clutter
    final indicesToDraw = <int>{0, data.length - 1};
    if (data.length > 4) {
      indicesToDraw.add(data.length ~/ 2);
    }

    for (final i in indicesToDraw) {
      final x = leftPadding + (graphWidth * i / (data.length - 1));
      final value = (data[i][key] as num?)?.toDouble() ?? 0.0;
      final y = topPadding + graphHeight - (graphHeight * value / maxValue);

      canvas.drawCircle(Offset(x, y), 4, dotPaint);
      canvas.drawCircle(Offset(x, y), 4, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(SensorGraphPainter oldDelegate) => oldDelegate.data.length != data.length;
}

class SafetyAlertsCard extends StatelessWidget {
  final List<AlertData> alerts;

  const SafetyAlertsCard({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(89), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Alerts', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (alerts.isEmpty)
                Text('No alerts yet', style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12))
              else
                ...alerts.take(5).map((alert) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: AlertRow(
                    time: alert.time,
                    level: alert.level,
                    title: alert.title,
                    trench: 'Trench B3',
                    message: alert.message,
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class AlertRow extends StatelessWidget {
  final String time;
  final AlertLevel level;
  final String title;
  final String trench;
  final String message;

  const AlertRow({
    super.key,
    required this.time, required this.level, required this.title,
    required this.trench, required this.message,
  });

  Color _dotColor() {
    switch (level) {
      case AlertLevel.critical: return const Color(0xFFE53935);
      case AlertLevel.warning: return const Color(0xFFFFB300);
      case AlertLevel.ok: return const Color(0xFF43A047);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(time, style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 11)),
        const SizedBox(width: 10),
        Container(
          width: 8, height: 8,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: _dotColor(), shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$title • $trench', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(message, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class SafetyInsightCard extends StatelessWidget {
  const SafetyInsightCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(77), width: 1),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Safety Thresholds', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text(
                '• Soil Moisture: 30-60% is safe range\n'
                '• Vibration: <0.3g stable, >0.8g critical\n'
                '• Connect M5StickC Plus 2 for live monitoring',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================== WAVELET ANALYSIS CARD =====================
class WaveletAnalysisCard extends StatelessWidget {
  final Map<String, double> bandEnergy;
  final List<TransientEvent> transients;
  final bool transientFlash;
  final double bufferFill;

  const WaveletAnalysisCard({
    super.key,
    required this.bandEnergy,
    required this.transients,
    required this.transientFlash,
    this.bufferFill = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // Extract detail-level energies (D1, D2, D3) and approximation
    final d1Entry = bandEnergy.entries.where((e) => e.key.startsWith('D1')).firstOrNull;
    final d2Entry = bandEnergy.entries.where((e) => e.key.startsWith('D2')).firstOrNull;
    final d3Entry = bandEnergy.entries.where((e) => e.key.startsWith('D3')).firstOrNull;

    final d1Energy = d1Entry?.value ?? 0.0;
    final d2Energy = d2Entry?.value ?? 0.0;
    final d3Energy = d3Entry?.value ?? 0.0;
    final totalEnergy = bandEnergy.values.fold(0.0, (a, b) => a + b);
    final maxEnergy = [d1Energy, d2Energy, d3Energy].reduce(max);

    final Color accentColor = transientFlash
        ? const Color(0xFFFF5722)
        : const Color(0xFF7C4DFF);

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
            border: Border.all(
              color: transientFlash
                  ? const Color(0xFFFF5722).withAlpha(150)
                  : Colors.white.withAlpha(90),
              width: transientFlash ? 1.5 : 1,
            ),
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
                      color: accentColor.withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.waves_rounded, color: accentColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Wavelet Analysis',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accentColor.withAlpha(100), width: 1),
                    ),
                    child: Text(
                      'Haar DWT',
                      style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '3-level decomposition / band energy distribution',
                style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11),
              ),
              const SizedBox(height: 14),

              // Transient detection indicator
              if (transientFlash) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5722).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF5722).withAlpha(100), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flash_on_rounded, color: Color(0xFFFF5722), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Transient detected! ${transients.length} event${transients.length != 1 ? 's' : ''} '
                          '(Level ${transients.isNotEmpty ? transients.first.level : "-"})',
                          style: const TextStyle(color: Color(0xFFFF5722), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Band energy horizontal bars
              _buildBandBar(
                d1Entry?.key ?? 'D1: 50-100 Hz',
                d1Energy,
                maxEnergy,
                totalEnergy,
                const Color(0xFF4CAF50),
              ),
              const SizedBox(height: 8),
              _buildBandBar(
                d2Entry?.key ?? 'D2: 25-50 Hz',
                d2Energy,
                maxEnergy,
                totalEnergy,
                const Color(0xFFFF9800),
              ),
              const SizedBox(height: 8),
              _buildBandBar(
                d3Entry?.key ?? 'D3: 12-25 Hz',
                d3Energy,
                maxEnergy,
                totalEnergy,
                const Color(0xFFFF5722),
              ),
              const SizedBox(height: 10),

              // Summary row
              Row(
                children: [
                  _buildMiniStat('Total Energy', totalEnergy.toStringAsFixed(4)),
                  const SizedBox(width: 12),
                  _buildMiniStat('Transients', '${transients.length}'),
                  const SizedBox(width: 12),
                  _buildMiniStat('Buffer', '${(bufferFill * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBandBar(String label, double energy, double maxEnergy, double totalEnergy, Color color) {
    final fraction = maxEnergy > 0 ? (energy / maxEnergy).clamp(0.0, 1.0) : 0.0;
    final percent = totalEnergy > 0 ? (energy / totalEnergy * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 11)),
            ),
            Text(
              '${energy.toStringAsFixed(4)}  (${percent.toStringAsFixed(0)}%)',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withAlpha(200), color]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: color.withAlpha(60), blurRadius: 4)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withAlpha(40), width: 1),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

// ===================== MULTI-STANDARD CLASSIFICATION CARD =====================
class MultiStandardCard extends StatelessWidget {
  final List<StandardClassification> classifications;
  final double damageIndex;
  final double housnerSI;
  final bool isConnected;

  const MultiStandardCard({
    super.key,
    required this.classifications,
    required this.damageIndex,
    required this.housnerSI,
    required this.isConnected,
  });

  static Color _levelColor(String level) {
    switch (level) {
      case 'critical':
        return const Color(0xFFE53935);
      case 'warning':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  static String _levelLabel(String level) {
    switch (level) {
      case 'critical':
        return 'CRITICAL';
      case 'warning':
        return 'WARNING';
      default:
        return 'SAFE';
    }
  }

  static IconData _levelIcon(String level) {
    switch (level) {
      case 'critical':
        return Icons.dangerous_rounded;
      case 'warning':
        return Icons.warning_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  static String _standardLabel(VibrationStandard std) {
    switch (std) {
      case VibrationStandard.din4150:
        return 'DIN 4150-3';
      case VibrationStandard.bs7385:
        return 'BS 7385-2';
      case VibrationStandard.fhwa:
        return 'FHWA';
      case VibrationStandard.sn640312a:
        return 'SN 640 312a';
    }
  }

  Color _damageColor() {
    if (damageIndex >= 1.0) return const Color(0xFFE53935);
    if (damageIndex >= 0.5) return const Color(0xFFFF9800);
    if (damageIndex >= 0.2) return const Color(0xFFFFC107);
    return const Color(0xFF4CAF50);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData = classifications.isNotEmpty;

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
                    child: const Icon(Icons.policy_rounded, color: Color(0xFF9C27B0), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Multi-Standard Classification',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('International heritage vibration standards',
                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11)),
              const SizedBox(height: 14),

              if (!hasData)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isConnected ? 'Waiting for vibration data...' : 'Connect sensor for classification',
                      style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 12),
                    ),
                  ),
                )
              else ...[
                // 2x2 grid of standards
                Row(
                  children: [
                    Expanded(child: _buildStandardTile(classifications[0])),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStandardTile(classifications[1])),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildStandardTile(classifications[2])),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStandardTile(classifications[3])),
                  ],
                ),
                const SizedBox(height: 14),

                // Damage Index gauge
                _buildDamageGauge(),
                const SizedBox(height: 10),

                // Housner SI
                Row(
                  children: [
                    Icon(Icons.speed, color: Colors.white.withAlpha(160), size: 16),
                    const SizedBox(width: 8),
                    Text('Housner SI: ', style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12)),
                    Text('${housnerSI.toStringAsFixed(3)} mm/s-s',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandardTile(StandardClassification c) {
    final color = _levelColor(c.level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(70), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_levelIcon(c.level), color: color, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _standardLabel(c.standard),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _levelLabel(c.level),
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'Limit: ${c.limit.toStringAsFixed(1)} mm/s',
            style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildDamageGauge() {
    final color = _damageColor();
    final fraction = damageIndex.clamp(0.0, 1.5) / 1.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Damage Index', style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12)),
            const Spacer(),
            Text(
              damageIndex.toStringAsFixed(3),
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(40),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                damageIndex >= 1.0
                    ? 'FAILURE'
                    : damageIndex >= 0.5
                        ? 'WARNING'
                        : 'SAFE',
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF4CAF50),
                        Color(0xFFFFC107),
                        Color(0xFFFF9800),
                        Color(0xFFE53935),
                      ],
                      stops: [0.0, 0.33, 0.67, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: (1.0 - fraction).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
            Text('0.5', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
            Text('1.0', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
            Text('1.5', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
          ],
        ),
      ],
    );
  }
}

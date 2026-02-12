import 'package:flutter/material.dart';

/// Quality metrics for a capture session.
class CaptureQualityMetrics {
  /// Estimated overlap with previous image (0-1).
  final double overlap;

  /// Estimated baseline distance (0=too close, 1=ideal).
  final double baselineQuality;

  /// Image sharpness (0=blurry, 1=sharp).
  final double sharpness;

  /// Number of features detected.
  final int featureCount;

  /// Overall quality score (0-1).
  double get overallScore =>
      (overlap * 0.3 + baselineQuality * 0.3 + sharpness * 0.3 + (featureCount > 100 ? 0.1 : featureCount / 1000.0)).clamp(0.0, 1.0);

  /// Quality label.
  String get label {
    if (overallScore > 0.8) return 'Excellent';
    if (overallScore > 0.6) return 'Good';
    if (overallScore > 0.4) return 'Fair';
    return 'Poor';
  }

  const CaptureQualityMetrics({
    this.overlap = 0,
    this.baselineQuality = 0,
    this.sharpness = 0,
    this.featureCount = 0,
  });
}

/// Overlay showing capture quality indicators during photo capture.
class CaptureQualityOverlay extends StatelessWidget {
  final CaptureQualityMetrics metrics;
  final int capturedCount;
  final int targetCount;

  const CaptureQualityOverlay({
    super.key,
    required this.metrics,
    required this.capturedCount,
    required this.targetCount,
  });

  Color _qualityColor(double value) {
    if (value > 0.7) return const Color(0xFF4CAF50);
    if (value > 0.4) return const Color(0xFFFFC107);
    return const Color(0xFFE53935);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress
          Row(
            children: [
              Text(
                '$capturedCount/$targetCount',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: capturedCount / targetCount,
                    backgroundColor: Colors.white.withAlpha(30),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50)),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _qualityColor(metrics.overallScore).withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  metrics.label,
                  style: TextStyle(
                    color: _qualityColor(metrics.overallScore),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Quality indicators
          Row(
            children: [
              _buildIndicator('Overlap', metrics.overlap, Icons.layers),
              const SizedBox(width: 8),
              _buildIndicator('Baseline', metrics.baselineQuality, Icons.straighten),
              const SizedBox(width: 8),
              _buildIndicator('Focus', metrics.sharpness, Icons.center_focus_strong),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(String label, double value, IconData icon) {
    final color = _qualityColor(value);
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 9)),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: value.clamp(0.0, 1.0),
                      backgroundColor: Colors.white.withAlpha(20),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

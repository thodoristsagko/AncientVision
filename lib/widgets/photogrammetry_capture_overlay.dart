import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../utils/quality_analyzer.dart';

/// Photogrammetry Capture Overlay Widget
/// Provides real-time quality feedback, angle coverage tracking, and capture guidance
class PhotogrammetryCaptureOverlay extends StatefulWidget {
  final CameraController? cameraController;
  final int capturedCount;
  final int targetCount;
  final List<double> capturedAngles; // Angles in degrees (0-360)
  final VoidCallback? onCapture;
  final bool isAnalyzing;
  final QualityMetrics? currentQuality;

  const PhotogrammetryCaptureOverlay({
    super.key,
    required this.cameraController,
    required this.capturedCount,
    this.targetCount = 16,
    this.capturedAngles = const [],
    this.onCapture,
    this.isAnalyzing = false,
    this.currentQuality,
  });

  @override
  State<PhotogrammetryCaptureOverlay> createState() => _PhotogrammetryCaptureOverlayState();
}

class _PhotogrammetryCaptureOverlayState extends State<PhotogrammetryCaptureOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _guideController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _guideController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _guideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Angle coverage indicator (top-left)
        Positioned(
          top: 16,
          left: 16,
          child: _buildAngleCoverageIndicator(),
        ),

        // Quality indicator (top-right)
        Positioned(
          top: 16,
          right: 16,
          child: _buildQualityIndicator(),
        ),

        // Center capture guide
        Center(
          child: _buildCaptureGuide(),
        ),

        // Progress bar (bottom)
        Positioned(
          bottom: 140,
          left: 24,
          right: 24,
          child: _buildProgressBar(),
        ),

        // Capture tips
        Positioned(
          bottom: 180,
          left: 24,
          right: 24,
          child: _buildCaptureTips(),
        ),
      ],
    );
  }

  Widget _buildAngleCoverageIndicator() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: CustomPaint(
        painter: _AngleCoveragePainter(
          capturedAngles: widget.capturedAngles,
          targetSegments: widget.targetCount,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.capturedCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '/ ${widget.targetCount}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityIndicator() {
    final quality = widget.currentQuality;
    final color = Color(quality?.scoreColor ?? 0xFF808080);
    final rating = quality != null
        ? QualityAnalyzer.getQualityRating(quality)
        : QualityRating.fair;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = widget.isAnalyzing ? _pulseController.value : 1.0;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(180),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withAlpha((150 * pulse).toInt()),
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getQualityIcon(rating),
                    color: color,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    rating.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (quality != null) ...[
                _buildMetricBar('Sharp', quality.sharpness, const Color(0xFF4CAF50)),
                _buildMetricBar('Light', quality.exposure, const Color(0xFFFFC107)),
                _buildMetricBar('Stable', quality.motionBlur, const Color(0xFF2196F3)),
              ],
              if (widget.isAnalyzing)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: 80,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF00BCD4)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _getQualityIcon(QualityRating rating) {
    switch (rating) {
      case QualityRating.excellent:
        return Icons.check_circle;
      case QualityRating.good:
        return Icons.thumb_up;
      case QualityRating.fair:
        return Icons.remove_circle;
      case QualityRating.poor:
        return Icons.warning;
      case QualityRating.veryPoor:
        return Icons.error;
    }
  }

  Widget _buildMetricBar(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
          Container(
            width: 50,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureGuide() {
    final quality = widget.currentQuality;
    final isGoodQuality = quality != null && quality.overallScore >= 0.7;

    return AnimatedBuilder(
      animation: _guideController,
      builder: (context, child) {
        return Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isGoodQuality
                  ? const Color(0xFF4CAF50).withAlpha(180)
                  : Colors.white.withAlpha(100),
              width: 3,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Corner brackets
              ..._buildCornerBrackets(isGoodQuality),

              // Center crosshair
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isGoodQuality
                        ? const Color(0xFF4CAF50)
                        : Colors.white.withAlpha(150),
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: isGoodQuality
                    ? const Icon(Icons.check, color: Color(0xFF4CAF50), size: 14)
                    : null,
              ),

              // Animated ring when quality is good
              if (isGoodQuality)
                Transform.scale(
                  scale: 1.0 + (_guideController.value * 0.1),
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF4CAF50).withAlpha(
                          ((1 - _guideController.value) * 100).toInt(),
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildCornerBrackets(bool isActive) {
    final color = isActive ? const Color(0xFF4CAF50) : Colors.white.withAlpha(150);
    const size = 30.0;
    const thickness = 3.0;

    return [
      // Top-left
      Positioned(
        top: 20,
        left: 20,
        child: _buildBracket(color, size, thickness, true, true),
      ),
      // Top-right
      Positioned(
        top: 20,
        right: 20,
        child: _buildBracket(color, size, thickness, true, false),
      ),
      // Bottom-left
      Positioned(
        bottom: 20,
        left: 20,
        child: _buildBracket(color, size, thickness, false, true),
      ),
      // Bottom-right
      Positioned(
        bottom: 20,
        right: 20,
        child: _buildBracket(color, size, thickness, false, false),
      ),
    ];
  }

  Widget _buildBracket(Color color, double size, double thickness, bool top, bool left) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BracketPainter(color, thickness, top, left),
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = widget.capturedCount / widget.targetCount;
    final coveragePercent = _calculateCoveragePercent();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress: ${widget.capturedCount}/${widget.targetCount} photos',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Coverage: ${coveragePercent.toStringAsFixed(0)}%',
              style: TextStyle(
                color: coveragePercent >= 80
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFFC107),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(50),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(
                flex: (progress * 100).toInt(),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: progress >= 1.0
                          ? [const Color(0xFF4CAF50), const Color(0xFF8BC34A)]
                          : [const Color(0xFF00BCD4), const Color(0xFF0097A7)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Expanded(
                flex: ((1 - progress) * 100).toInt().clamp(1, 100),
                child: const SizedBox(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _calculateCoveragePercent() {
    if (widget.capturedAngles.isEmpty) return 0;

    // Divide circle into 16 segments
    final segments = List.filled(16, false);
    const segmentSize = 360 / 16;

    for (final angle in widget.capturedAngles) {
      final segmentIndex = (angle / segmentSize).floor() % 16;
      segments[segmentIndex] = true;
    }

    final coveredSegments = segments.where((s) => s).length;
    return (coveredSegments / 16) * 100;
  }

  Widget _buildCaptureTips() {
    final quality = widget.currentQuality;
    String tip;
    IconData icon;
    Color color;

    if (quality == null) {
      tip = 'Position the artifact in the center';
      icon = Icons.center_focus_strong;
      color = Colors.white70;
    } else if (quality.sharpness < 0.6) {
      tip = 'Hold steady - image is blurry';
      icon = Icons.blur_on;
      color = const Color(0xFFFF9800);
    } else if (quality.exposure < 0.5) {
      tip = 'Improve lighting conditions';
      icon = Icons.wb_sunny;
      color = const Color(0xFFFFC107);
    } else if (quality.motionBlur < 0.6) {
      tip = 'Camera moving - stay still';
      icon = Icons.vibration;
      color = const Color(0xFFFF5722);
    } else if (quality.overallScore >= 0.85) {
      tip = 'Perfect! Capture now';
      icon = Icons.check_circle;
      color = const Color(0xFF4CAF50);
    } else if (quality.overallScore >= 0.7) {
      tip = 'Good quality - ready to capture';
      icon = Icons.thumb_up;
      color = const Color(0xFF8BC34A);
    } else {
      tip = 'Improve conditions for better results';
      icon = Icons.info;
      color = const Color(0xFFFFC107);
    }

    // Add angle guidance
    final nextAngle = _suggestNextAngle();
    if (nextAngle != null && widget.capturedCount > 0) {
      tip += '\nRotate ${nextAngle.toStringAsFixed(0)}° for next shot';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              tip,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double? _suggestNextAngle() {
    if (widget.capturedAngles.isEmpty) return null;

    const segmentSize = 360 / 16;
    final segments = List.filled(16, false);

    for (final angle in widget.capturedAngles) {
      final segmentIndex = (angle / segmentSize).floor() % 16;
      segments[segmentIndex] = true;
    }

    // Find first uncovered segment
    for (int i = 0; i < 16; i++) {
      if (!segments[i]) {
        final targetAngle = (i + 0.5) * segmentSize;
        final lastAngle = widget.capturedAngles.last;
        var delta = targetAngle - lastAngle;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        return delta;
      }
    }

    return null;
  }
}

/// Painter for angle coverage indicator
class _AngleCoveragePainter extends CustomPainter {
  final List<double> capturedAngles;
  final int targetSegments;

  _AngleCoveragePainter({
    required this.capturedAngles,
    required this.targetSegments,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final segmentAngle = 2 * math.pi / targetSegments;

    // Track which segments are covered
    final coveredSegments = <int>{};
    for (final angle in capturedAngles) {
      final radians = angle * math.pi / 180;
      final segmentIndex = (radians / segmentAngle).floor() % targetSegments;
      coveredSegments.add(segmentIndex);
    }

    // Draw segments
    for (int i = 0; i < targetSegments; i++) {
      final startAngle = i * segmentAngle - math.pi / 2;
      final isCovered = coveredSegments.contains(i);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = isCovered
            ? const Color(0xFF4CAF50)
            : Colors.white.withAlpha(50);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + 0.02,
        segmentAngle - 0.04,
        false,
        paint,
      );
    }

    // Draw center dot
    final centerPaint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _AngleCoveragePainter oldDelegate) {
    return oldDelegate.capturedAngles.length != capturedAngles.length;
  }
}

/// Painter for corner brackets
class _BracketPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top;
  final bool left;

  _BracketPainter(this.color, this.thickness, this.top, this.left);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Real-time quality analyzer that works with camera stream
class LiveQualityAnalyzer {
  Timer? _analysisTimer;
  QualityMetrics? _lastMetrics;
  bool _isAnalyzing = false;

  QualityMetrics? get lastMetrics => _lastMetrics;
  bool get isAnalyzing => _isAnalyzing;

  /// Start periodic quality analysis
  void startAnalysis(
    CameraController controller,
    void Function(QualityMetrics metrics) onAnalysis,
  ) {
    _analysisTimer?.cancel();

    _analysisTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_isAnalyzing) return;

      _isAnalyzing = true;
      try {
        // Capture a preview frame for analysis
        final image = await controller.takePicture();
        final bytes = await image.readAsBytes();
        final decoded = img.decodeImage(bytes);

        if (decoded != null) {
          // Resize for faster analysis
          final resized = img.copyResize(decoded, width: 256);
          final metrics = await QualityAnalyzer.analyzeImage(resized);
          _lastMetrics = metrics;
          onAnalysis(metrics);
        }
      } catch (e) {
        // Ignore analysis errors
      } finally {
        _isAnalyzing = false;
      }
    });
  }

  /// Stop analysis
  void stopAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer = null;
  }

  void dispose() {
    stopAnalysis();
  }
}

/// Auto-capture controller
class AutoCaptureController {
  Timer? _stableTimer;
  int _stableFrameCount = 0;
  static const int _requiredStableFrames = 3;
  static const double _qualityThreshold = 0.75;

  /// Check if quality is stable enough for auto-capture
  void checkForAutoCapture(
    QualityMetrics metrics,
    VoidCallback onAutoCapture,
  ) {
    if (metrics.overallScore >= _qualityThreshold) {
      _stableFrameCount++;

      if (_stableFrameCount >= _requiredStableFrames) {
        _stableFrameCount = 0;
        HapticFeedback.mediumImpact();
        onAutoCapture();
      }
    } else {
      _stableFrameCount = 0;
    }
  }

  void reset() {
    _stableFrameCount = 0;
    _stableTimer?.cancel();
  }

  void dispose() {
    reset();
  }
}

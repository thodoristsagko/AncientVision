import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../models/point_cloud.dart';
import 'dart:math' as math;

/// Helper class to store projected point data for depth sorting
class _ProjectedPoint {
  final double x;
  final double y;
  final double z;
  final double scale;
  final ({double r, double g, double b, double a}) color;

  _ProjectedPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.scale,
    required this.color,
  });
}

/// Custom painter for rendering point clouds
class PointCloudPainter extends CustomPainter {
  final PointCloud pointCloud;
  final Matrix4 transform;
  final double pointSize;
  final bool showColors;

  PointCloudPainter({
    required this.pointCloud,
    required this.transform,
    this.pointSize = 3.0,
    this.showColors = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pointCloud.points.isEmpty) {
      // Draw "No points" message
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'No points in cloud',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(size.width / 2 - textPainter.width / 2, size.height / 2),
      );
      return;
    }

    // Get center of point cloud for normalization
    final center = pointCloud.getCenter();

    // Project and collect all points with their depth for sorting
    final List<_ProjectedPoint> projectedPoints = [];
    final focalLength = 500.0;

    for (final point in pointCloud.points) {
      // Center the point
      final centeredPoint = vector.Vector3(
        point.position.x - center.x,
        point.position.y - center.y,
        point.position.z - center.z,
      );

      // Apply transformation
      final transformedPoint = transform.transform3(centeredPoint);

      // Simple perspective projection
      final scale = focalLength / (focalLength + transformedPoint.z);

      // Skip points behind camera
      if (scale <= 0) continue;

      // Project to 2D screen coordinates
      final x = size.width / 2 + transformedPoint.x * scale;
      final y = size.height / 2 - transformedPoint.y * scale; // Flip Y

      // Check if point is on screen (with small margin)
      if (x < -pointSize * 2 || x > size.width + pointSize * 2 ||
          y < -pointSize * 2 || y > size.height + pointSize * 2) {
        continue;
      }

      projectedPoints.add(_ProjectedPoint(
        x: x,
        y: y,
        z: transformedPoint.z,
        scale: scale,
        color: (r: point.color.r, g: point.color.g, b: point.color.b, a: point.color.a),
      ));
    }

    // Sort by depth (back to front - painter's algorithm)
    projectedPoints.sort((a, b) => a.z.compareTo(b.z));

    // Draw all points with proper depth ordering
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 1;

    for (final proj in projectedPoints) {
      // Calculate depth-based brightness (simple lighting simulation)
      final depthFactor = 1.0 - (proj.z / (focalLength * 2)).clamp(0.0, 0.5);

      // Set color with depth-based shading
      if (showColors) {
        paint.color = Color.fromRGBO(
          ((proj.color.r * 255) * depthFactor).toInt().clamp(0, 255),
          ((proj.color.g * 255) * depthFactor).toInt().clamp(0, 255),
          ((proj.color.b * 255) * depthFactor).toInt().clamp(0, 255),
          1.0,
        );
      } else {
        // White with depth shading
        final intensity = (255 * depthFactor).toInt().clamp(0, 255);
        paint.color = Color.fromRGBO(intensity, intensity, intensity, 1.0);
      }

      // Adaptive point size based on scale and density
      final adaptiveSize = pointSize * proj.scale.clamp(0.3, 2.5);

      // Draw point with slight glow effect for better visibility
      final baseColor = paint.color;
      canvas.drawCircle(
        Offset(proj.x, proj.y),
        adaptiveSize * 1.2,
        paint..color = Color.fromRGBO(
          baseColor.r.toInt(),
          baseColor.g.toInt(),
          baseColor.b.toInt(),
          0.3,
        ),
      );
      canvas.drawCircle(
        Offset(proj.x, proj.y),
        adaptiveSize,
        paint..color = baseColor,
      );
    }

    final visiblePoints = projectedPoints.length;

    // Draw info overlay
    if (visiblePoints > 0) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$visiblePoints / ${pointCloud.points.length} points',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            shadows: [Shadow(color: Colors.black, blurRadius: 2)],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, const Offset(10, 10));
    }
  }

  @override
  bool shouldRepaint(PointCloudPainter oldDelegate) {
    return oldDelegate.transform != transform ||
        oldDelegate.pointSize != pointSize ||
        oldDelegate.showColors != showColors;
  }
}

/// Interactive point cloud viewer widget
class PointCloudViewer extends StatefulWidget {
  final PointCloud pointCloud;
  final double initialPointSize;
  final bool initialShowColors;

  const PointCloudViewer({
    super.key,
    required this.pointCloud,
    this.initialPointSize = 3.0,
    this.initialShowColors = true,
  });

  @override
  State<PointCloudViewer> createState() => PointCloudViewerState();
}

class PointCloudViewerState extends State<PointCloudViewer>
    with SingleTickerProviderStateMixin {
  late Matrix4 _transform;
  double _rotationX = 0.0;
  double _rotationY = 0.0;
  double _zoom = 1.0;
  Offset _lastFocalPoint = Offset.zero;
  late AnimationController _autoRotateController;
  bool _autoRotate = false;

  @override
  void initState() {
    super.initState();
    _resetTransform();

    // Auto-rotate animation
    _autoRotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addListener(() {
      if (_autoRotate) {
        setState(() {
          _rotationY += 0.01;
          _updateTransform();
        });
      }
    });
  }

  void _resetTransform() {
    _transform = Matrix4.identity();
    _rotationX = -0.3; // Slight downward angle
    _rotationY = 0.0;
    _zoom = 1.0;
    _updateTransform();
  }

  void _updateTransform() {
    _transform = Matrix4.identity()
      ..scale(_zoom)
      ..rotateX(_rotationX)
      ..rotateY(_rotationY);
  }

  @override
  void dispose() {
    _autoRotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (details) {
        _lastFocalPoint = details.focalPoint;
        if (_autoRotate) {
          setState(() => _autoRotate = false);
          _autoRotateController.stop();
        }
      },
      onScaleUpdate: (details) {
        setState(() {
          if (details.scale != 1.0) {
            // Pinch to zoom
            _zoom *= details.scale;
            _zoom = _zoom.clamp(0.5, 5.0);
          } else {
            // Drag to rotate
            final delta = details.focalPoint - _lastFocalPoint;
            _rotationY += delta.dx * 0.01;
            _rotationX += delta.dy * 0.01;
            _rotationX = _rotationX.clamp(-math.pi / 2, math.pi / 2);
          }
          _lastFocalPoint = details.focalPoint;
          _updateTransform();
        });
      },
      child: CustomPaint(
        painter: PointCloudPainter(
          pointCloud: widget.pointCloud,
          transform: _transform,
          pointSize: widget.initialPointSize,
          showColors: widget.initialShowColors,
        ),
        size: Size.infinite,
      ),
    );
  }

  void toggleAutoRotate() {
    setState(() {
      _autoRotate = !_autoRotate;
      if (_autoRotate) {
        _autoRotateController.repeat();
      } else {
        _autoRotateController.stop();
      }
    });
  }

  void resetView() {
    setState(() {
      _resetTransform();
    });
  }
}

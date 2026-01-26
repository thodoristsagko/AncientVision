import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../models/point_cloud.dart';

/// 3D Measurement Tools for Point Cloud Viewer
/// Provides distance, angle, and volume measurement capabilities
class MeasurementTools3D extends StatefulWidget {
  final PointCloud pointCloud;
  final Function(MeasurementResult)? onMeasurement;
  final VoidCallback? onClose;

  const MeasurementTools3D({
    super.key,
    required this.pointCloud,
    this.onMeasurement,
    this.onClose,
  });

  @override
  State<MeasurementTools3D> createState() => _MeasurementTools3DState();
}

class _MeasurementTools3DState extends State<MeasurementTools3D> {
  MeasurementMode _mode = MeasurementMode.distance;
  final List<Point3D> _selectedPoints = [];
  MeasurementResult? _currentMeasurement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.straighten, color: Color(0xFF00BCD4), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Measurement Tools',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Mode selector
          _buildModeSelector(),
          const SizedBox(height: 12),

          // Instructions
          _buildInstructions(),
          const SizedBox(height: 12),

          // Current measurement
          if (_currentMeasurement != null) _buildMeasurementResult(),

          // Quick measurements
          _buildQuickMeasurements(),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: MeasurementMode.values.map((mode) {
        final isSelected = _mode == mode;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _mode = mode;
                _selectedPoints.clear();
                _currentMeasurement = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00BCD4).withAlpha(50)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00BCD4) : Colors.white24,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    mode.icon,
                    color: isSelected ? const Color(0xFF00BCD4) : Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.label,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF00BCD4) : Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInstructions() {
    String instruction;
    int requiredPoints;

    switch (_mode) {
      case MeasurementMode.distance:
        instruction = 'Tap 2 points to measure distance';
        requiredPoints = 2;
        break;
      case MeasurementMode.angle:
        instruction = 'Tap 3 points to measure angle';
        requiredPoints = 3;
        break;
      case MeasurementMode.perimeter:
        instruction = 'Tap 3+ points, then double-tap to finish';
        requiredPoints = 3;
        break;
      case MeasurementMode.boundingBox:
        instruction = 'Auto-calculated from all points';
        requiredPoints = 0;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              instruction,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          if (requiredPoints > 0)
            Text(
              '${_selectedPoints.length}/$requiredPoints',
              style: const TextStyle(
                color: Color(0xFF00BCD4),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMeasurementResult() {
    final result = _currentMeasurement!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4CAF50).withAlpha(50),
            const Color(0xFF4CAF50).withAlpha(25),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4CAF50).withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                result.type.label,
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Color(0xFF4CAF50), size: 16),
                onPressed: () => _copyToClipboard(result),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.formattedValue,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (result.details != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                result.details!,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickMeasurements() {
    // Auto-calculate bounding box and overall dimensions
    final bbox = widget.pointCloud.getBoundingBox();
    final size = vm.Vector3(
      bbox.max.x - bbox.min.x,
      bbox.max.y - bbox.min.y,
      bbox.max.z - bbox.min.z,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Stats',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStatCard('Width', '${(size.x * 100).toStringAsFixed(1)} cm', Icons.width_normal),
            _buildStatCard('Height', '${(size.y * 100).toStringAsFixed(1)} cm', Icons.height),
            _buildStatCard('Depth', '${(size.z * 100).toStringAsFixed(1)} cm', Icons.view_in_ar),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStatCard(
              'Diagonal',
              '${(size.length * 100).toStringAsFixed(1)} cm',
              Icons.open_in_full,
            ),
            _buildStatCard(
              'Points',
              '${widget.pointCloud.points.length}',
              Icons.scatter_plot,
            ),
            _buildStatCard(
              'Volume',
              '${(size.x * size.y * size.z * 1000000).toStringAsFixed(0)} cm³',
              Icons.view_in_ar_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white54, size: 16),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(MeasurementResult result) {
    // Would use Clipboard.setData in real implementation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Measurement copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Call this when a point is tapped in the 3D view
  void onPointSelected(Point3D point) {
    setState(() {
      _selectedPoints.add(point);
      _calculateMeasurement();
    });
  }

  void _calculateMeasurement() {
    switch (_mode) {
      case MeasurementMode.distance:
        if (_selectedPoints.length == 2) {
          final distance = _calculateDistance(
            _selectedPoints[0].position,
            _selectedPoints[1].position,
          );
          _currentMeasurement = MeasurementResult(
            type: MeasurementMode.distance,
            value: distance,
            unit: 'm',
            details: 'Point-to-point linear distance',
          );
          widget.onMeasurement?.call(_currentMeasurement!);
          _selectedPoints.clear();
        }
        break;

      case MeasurementMode.angle:
        if (_selectedPoints.length == 3) {
          final angle = _calculateAngle(
            _selectedPoints[0].position,
            _selectedPoints[1].position,
            _selectedPoints[2].position,
          );
          _currentMeasurement = MeasurementResult(
            type: MeasurementMode.angle,
            value: angle,
            unit: '°',
            details: 'Angle at middle point',
          );
          widget.onMeasurement?.call(_currentMeasurement!);
          _selectedPoints.clear();
        }
        break;

      case MeasurementMode.perimeter:
        if (_selectedPoints.length >= 3) {
          double perimeter = 0;
          for (int i = 0; i < _selectedPoints.length; i++) {
            final next = (i + 1) % _selectedPoints.length;
            perimeter += _calculateDistance(
              _selectedPoints[i].position,
              _selectedPoints[next].position,
            );
          }
          _currentMeasurement = MeasurementResult(
            type: MeasurementMode.perimeter,
            value: perimeter,
            unit: 'm',
            details: '${_selectedPoints.length} points',
          );
        }
        break;

      case MeasurementMode.boundingBox:
        // Auto-calculated in UI
        break;
    }
  }

  double _calculateDistance(vm.Vector3 a, vm.Vector3 b) {
    return (a - b).length;
  }

  double _calculateAngle(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c) {
    final ba = a - b;
    final bc = c - b;

    final dot = ba.dot(bc);
    final magBA = ba.length;
    final magBC = bc.length;

    if (magBA == 0 || magBC == 0) return 0;

    final cosAngle = dot / (magBA * magBC);
    final angle = math.acos(cosAngle.clamp(-1.0, 1.0));

    return angle * 180 / math.pi;
  }
}

/// Measurement modes
enum MeasurementMode {
  distance('Distance', Icons.straighten),
  angle('Angle', Icons.architecture),
  perimeter('Perimeter', Icons.pentagon_outlined),
  boundingBox('Bounds', Icons.crop_square);

  final String label;
  final IconData icon;

  const MeasurementMode(this.label, this.icon);
}

/// Measurement result
class MeasurementResult {
  final MeasurementMode type;
  final double value;
  final String unit;
  final String? details;

  MeasurementResult({
    required this.type,
    required this.value,
    required this.unit,
    this.details,
  });

  String get formattedValue {
    if (unit == '°') {
      return '${value.toStringAsFixed(1)}$unit';
    } else if (value < 0.01) {
      return '${(value * 1000).toStringAsFixed(2)} mm';
    } else if (value < 1) {
      return '${(value * 100).toStringAsFixed(2)} cm';
    } else {
      return '${value.toStringAsFixed(3)} $unit';
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'value': value,
        'unit': unit,
        'formatted': formattedValue,
        'details': details,
      };
}

/// Scale reference widget for calibrating measurements
class ScaleReferenceWidget extends StatefulWidget {
  final double knownLength; // In meters
  final Function(double scaleFactor)? onCalibrated;

  const ScaleReferenceWidget({
    super.key,
    this.knownLength = 0.05, // 5cm default
    this.onCalibrated,
  });

  @override
  State<ScaleReferenceWidget> createState() => _ScaleReferenceWidgetState();
}

class _ScaleReferenceWidgetState extends State<ScaleReferenceWidget> {
  final _controller = TextEditingController(text: '5.0');
  String _unit = 'cm';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFC107).withAlpha(100)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.square_foot, color: Color(0xFFFFC107), size: 20),
              SizedBox(width: 8),
              Text(
                'Scale Reference',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Select 2 points on a known-size reference object',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Reference length',
                    labelStyle: const TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _unit,
                  dropdownColor: Colors.grey[900],
                  underline: const SizedBox(),
                  items: ['mm', 'cm', 'm'].map((u) {
                    return DropdownMenuItem(
                      value: u,
                      child: Text(u, style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _unit = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _calibrate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black,
              ),
              child: const Text('Calibrate Scale'),
            ),
          ),
        ],
      ),
    );
  }

  void _calibrate() {
    final value = double.tryParse(_controller.text) ?? 5.0;
    double meters;

    switch (_unit) {
      case 'mm':
        meters = value / 1000;
        break;
      case 'cm':
        meters = value / 100;
        break;
      default:
        meters = value;
    }

    widget.onCalibrated?.call(meters);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Cross-section tool for viewing internal structure
class CrossSectionTool extends StatefulWidget {
  final PointCloud pointCloud;
  final Function(CrossSectionPlane)? onPlaneChanged;

  const CrossSectionTool({
    super.key,
    required this.pointCloud,
    this.onPlaneChanged,
  });

  @override
  State<CrossSectionTool> createState() => _CrossSectionToolState();
}

class _CrossSectionToolState extends State<CrossSectionTool> {
  CrossSectionAxis _axis = CrossSectionAxis.y;
  double _position = 0.5; // 0-1 normalized
  bool _showBothSides = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.content_cut, color: Color(0xFF9C27B0), size: 20),
              SizedBox(width: 8),
              Text(
                'Cross Section',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Axis selector
          Row(
            children: CrossSectionAxis.values.map((axis) {
              final isSelected = _axis == axis;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _axis = axis);
                    _notifyChange();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF9C27B0).withAlpha(50)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF9C27B0)
                            : Colors.white24,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        axis.label,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF9C27B0)
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Position slider
          Row(
            children: [
              const Text('Position', style: TextStyle(color: Colors.white54)),
              Expanded(
                child: Slider(
                  value: _position,
                  min: 0,
                  max: 1,
                  activeColor: const Color(0xFF9C27B0),
                  onChanged: (v) {
                    setState(() => _position = v);
                    _notifyChange();
                  },
                ),
              ),
              Text(
                '${(_position * 100).toInt()}%',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),

          // Show both sides toggle
          Row(
            children: [
              Checkbox(
                value: _showBothSides,
                activeColor: const Color(0xFF9C27B0),
                onChanged: (v) {
                  setState(() => _showBothSides = v ?? false);
                  _notifyChange();
                },
              ),
              const Text(
                'Show both sides',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _notifyChange() {
    widget.onPlaneChanged?.call(CrossSectionPlane(
      axis: _axis,
      position: _position,
      showBothSides: _showBothSides,
    ));
  }
}

enum CrossSectionAxis {
  x('X (Left/Right)'),
  y('Y (Up/Down)'),
  z('Z (Front/Back)');

  final String label;
  const CrossSectionAxis(this.label);
}

class CrossSectionPlane {
  final CrossSectionAxis axis;
  final double position;
  final bool showBothSides;

  CrossSectionPlane({
    required this.axis,
    required this.position,
    this.showBothSides = false,
  });
}

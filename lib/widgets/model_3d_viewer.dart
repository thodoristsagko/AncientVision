import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/point_cloud.dart';
import '../models/reconstruction_result.dart';
import 'point_cloud_painter.dart';

/// 3D viewer widget for displaying point clouds and meshes
class Model3DViewer extends StatefulWidget {
  final ReconstructionResult result;
  final VoidCallback? onCompleteForm;

  const Model3DViewer({
    super.key,
    required this.result,
    this.onCompleteForm,
  });

  @override
  State<Model3DViewer> createState() => _Model3DViewerState();
}

class _Model3DViewerState extends State<Model3DViewer> {
  bool _showInfo = true;
  double _pointSize = 3.0;
  bool _showColors = true;
  bool _autoRotate = false;
  final GlobalKey<PointCloudViewerState> _viewerKey = GlobalKey();

  PointCloud? get _pointCloud {
    if (widget.result.pointCloud != null) {
      return widget.result.pointCloud;
    } else if (widget.result.mesh != null) {
      return widget.result.mesh!.toPointCloud();
    }
    return null;
  }

  Future<void> _exportPointCloud() async {
    try {
      final pointCloud = widget.result.pointCloud;
      if (pointCloud == null) {
        _showSnackBar('No point cloud available to export');
        return;
      }

      // Export to PLY format
      final plyContent = pointCloud.toPLY();

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'pointcloud_${DateTime.now().millisecondsSinceEpoch}.ply';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(plyContent);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'AncientVision 3D Point Cloud',
        text: 'Generated with AncientVision photogrammetry\n'
            'Points: ${pointCloud.points.length}\n'
            'Method: ${pointCloud.method}',
      );

      _showSnackBar('Point cloud exported successfully');
    } catch (e) {
      _showSnackBar('Export failed: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pointCloud = _pointCloud;

    if (pointCloud == null || pointCloud.points.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('3D Model Viewer'),
          backgroundColor: Colors.black,
        ),
        body: const Center(
          child: Text(
            'No point cloud data available',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final showSparseWarning = pointCloud.points.length < 10;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('3D Model Viewer'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => setState(() => _showInfo = !_showInfo),
            tooltip: 'Toggle info',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportPointCloud,
            tooltip: 'Export & Share',
          ),
          if (widget.onCompleteForm != null)
            IconButton(
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: widget.onCompleteForm,
              tooltip: 'Complete Form',
              color: const Color(0xFF4CAF50),
            ),
        ],
      ),
      body: Stack(
        children: [
          // 3D Viewer
          PointCloudViewer(
            key: _viewerKey,
            pointCloud: pointCloud,
            initialPointSize: _pointSize,
            initialShowColors: _showColors,
          ),

          // Sparse point cloud warning
          if (showSparseWarning)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Very few points reconstructed. Try cloud processing or add more photos with better overlap for improved results.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Info overlay
          if (_showInfo && !showSparseWarning)
            Positioned(
              top: 16,
              left: 16,
              child: _buildInfoPanel(),
            ),
          if (_showInfo && showSparseWarning)
            Positioned(
              top: 80,
              left: 16,
              child: _buildInfoPanel(),
            ),

          // Controls overlay
          Positioned(
            bottom: widget.onCompleteForm != null ? 100 : 16,
            left: 0,
            right: 0,
            child: _buildControlsPanel(),
          ),

          // Instructions
          if (_showInfo)
            Positioned(
              bottom: widget.onCompleteForm != null ? 200 : 120,
              left: 16,
              right: 16,
              child: const Center(
                child: Text(
                  'Drag to rotate • Pinch to zoom',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),

          // Prominent Save Finding button
          if (widget.onCompleteForm != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildSaveButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onCompleteForm,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.save_rounded, color: Colors.white, size: 24),
                SizedBox(width: 12),
                Text(
                  'Save Finding to Database',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    final result = widget.result;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                result.isSparse ? Icons.grain : Icons.view_in_ar,
                color: const Color(0xFF00BCD4),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                result.isSparse ? 'Sparse Preview' : 'Full Model',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.scatter_plot, 'Points', '${result.pointCount}'),
          if (result.faceCount != null)
            _buildInfoRow(Icons.category, 'Faces', '${result.faceCount}'),
          _buildInfoRow(Icons.photo_library, 'Images', '${result.inputImageCount ?? 0}'),
          if (result.processingTimeSeconds != null)
            _buildInfoRow(
              Icons.timer,
              'Time',
              '${result.processingTimeSeconds!.toStringAsFixed(1)}s',
            ),
          if (result.qualityMetrics['average_confidence'] != null)
            _buildInfoRow(
              Icons.verified,
              'Confidence',
              '${(result.qualityMetrics['average_confidence'] * 100).toStringAsFixed(0)}%',
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Point size slider
          Row(
            children: [
              const Icon(Icons.fiber_manual_record, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Point Size',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Expanded(
                child: Slider(
                  value: _pointSize,
                  min: 1.0,
                  max: 10.0,
                  divisions: 9,
                  activeColor: const Color(0xFF00BCD4),
                  onChanged: (value) {
                    setState(() => _pointSize = value);
                  },
                ),
              ),
              Text(
                _pointSize.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                icon: _showColors ? Icons.palette : Icons.palette_outlined,
                label: 'Colors',
                isActive: _showColors,
                onTap: () => setState(() => _showColors = !_showColors),
              ),
              _buildControlButton(
                icon: _autoRotate ? Icons.replay : Icons.replay_outlined,
                label: 'Auto Rotate',
                isActive: _autoRotate,
                onTap: () {
                  setState(() => _autoRotate = !_autoRotate);
                  _viewerKey.currentState?.toggleAutoRotate();
                },
              ),
              _buildControlButton(
                icon: Icons.center_focus_strong,
                label: 'Reset View',
                onTap: () {
                  _viewerKey.currentState?.resetView();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00BCD4).withValues(alpha: 0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFF00BCD4) : Colors.white24,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFF00BCD4) : Colors.white70,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF00BCD4) : Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

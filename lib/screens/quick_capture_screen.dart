import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/artifact_classification.dart';
import '../services/progress_service.dart';
import '../widgets/photogrammetry_capture_overlay.dart';
import '../utils/quality_analyzer.dart';

/// Quick Capture Mode for rapid artifact documentation
class QuickCaptureScreen extends StatefulWidget {
  const QuickCaptureScreen({super.key});

  @override
  State<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends State<QuickCaptureScreen> {
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isCapturing = false;
  List<XFile> _capturedPhotos = [];
  ArtifactType? _selectedType;
  String? _quickNote;
  Position? _currentPosition;
  final _progressService = ProgressService();

  // Camera enhancements
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;
  bool _showGrid = false;
  double _exposureOffset = 0.0;
  double _minExposure = -2.0;
  double _maxExposure = 2.0;
  bool _showExposureSlider = false;
  FlashMode _currentFlashMode = FlashMode.auto;

  // Photogrammetry overlay enhancements
  bool _showQualityOverlay = true;
  final List<double> _capturedAngles = [];
  QualityMetrics? _currentQuality;
  bool _isAnalyzingQuality = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _getCurrentLocation();
    _progressService.initialize();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      // Get zoom limits
      _minZoom = await _cameraController!.getMinZoomLevel();
      _maxZoom = await _cameraController!.getMaxZoomLevel();
      _currentZoom = _minZoom;

      // Get exposure limits
      _minExposure = await _cameraController!.getMinExposureOffset();
      _maxExposure = await _cameraController!.getMaxExposureOffset();

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      _currentPosition = await Geolocator.getCurrentPosition();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview with zoom gesture
            if (_isInitialized && _cameraController != null)
              Positioned.fill(
                child: GestureDetector(
                  onScaleStart: (details) {
                    _baseZoom = _currentZoom;
                  },
                  onScaleUpdate: (details) {
                    _setZoom(_baseZoom * details.scale);
                  },
                  onDoubleTap: () {
                    // Double tap to toggle between 1x and 2x zoom
                    if (_currentZoom > _minZoom) {
                      _setZoom(_minZoom);
                    } else {
                      _setZoom((_maxZoom - _minZoom) / 2 + _minZoom);
                    }
                  },
                  child: Stack(
                    children: [
                      CameraPreview(_cameraController!),
                      // Grid overlay
                      if (_showGrid) _buildGridOverlay(),
                      // Photogrammetry quality overlay
                      if (_showQualityOverlay)
                        PhotogrammetryCaptureOverlay(
                          cameraController: _cameraController,
                          capturedCount: _capturedPhotos.length,
                          targetCount: 16,
                          capturedAngles: _capturedAngles,
                          isAnalyzing: _isAnalyzingQuality,
                          currentQuality: _currentQuality,
                          onCapture: _capturePhoto,
                        ),
                    ],
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Top bar
            _buildTopBar(),

            // Zoom indicator
            if (_currentZoom > _minZoom) _buildZoomIndicator(),

            // Photo counter
            if (_capturedPhotos.isNotEmpty) _buildPhotoCounter(),

            // Quick type selector
            _buildTypeSelector(),

            // Exposure slider
            if (_showExposureSlider) _buildExposureSlider(),

            // Bottom controls
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildGridOverlay() {
    return CustomPaint(
      size: Size.infinite,
      painter: _GridPainter(),
    );
  }

  Widget _buildZoomIndicator() {
    return Positioned(
      top: 140,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(150),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_currentZoom.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExposureSlider() {
    return Positioned(
      right: 20,
      top: 150,
      bottom: 200,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(150),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wb_sunny, color: Colors.yellow, size: 20),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: _exposureOffset,
                  min: _minExposure,
                  max: _maxExposure,
                  activeColor: const Color(0xFFFFC107),
                  onChanged: (value) async {
                    setState(() => _exposureOffset = value);
                    await _cameraController?.setExposureOffset(value);
                  },
                ),
              ),
            ),
            Text(
              _exposureOffset.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withAlpha(179),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => _showExitConfirmation(),
            ),
            Column(
              children: [
                const Text(
                  'QUICK CAPTURE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                if (_currentPosition != null)
                  Text(
                    'GPS: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(179),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quality overlay toggle
                IconButton(
                  icon: Icon(
                    _showQualityOverlay ? Icons.analytics : Icons.analytics_outlined,
                    color: _showQualityOverlay ? const Color(0xFF7C4DFF) : Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    setState(() => _showQualityOverlay = !_showQualityOverlay);
                    HapticFeedback.selectionClick();
                  },
                ),
                // Grid toggle
                IconButton(
                  icon: Icon(
                    _showGrid ? Icons.grid_on : Icons.grid_off,
                    color: _showGrid ? const Color(0xFFFFC107) : Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    setState(() => _showGrid = !_showGrid);
                    HapticFeedback.selectionClick();
                  },
                ),
                // Exposure toggle
                IconButton(
                  icon: Icon(
                    Icons.exposure,
                    color: _showExposureSlider ? const Color(0xFFFFC107) : Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    setState(() => _showExposureSlider = !_showExposureSlider);
                    HapticFeedback.selectionClick();
                  },
                ),
                // Flash toggle
                IconButton(
                  icon: Icon(
                    _getFlashIcon(),
                    color: _currentFlashMode != FlashMode.off
                        ? const Color(0xFFFFC107)
                        : Colors.white,
                    size: 28,
                  ),
                  onPressed: _toggleFlash,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFlashIcon() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }

  Widget _buildPhotoCounter() {
    return Positioned(
      top: 80,
      right: 16,
      child: GestureDetector(
        onTap: _showCapturedPhotos,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC107),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                '${_capturedPhotos.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Positioned(
      top: 80,
      left: 16,
      child: GestureDetector(
        onTap: _showTypeSelector,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _selectedType?.color.withAlpha(204) ?? Colors.white.withAlpha(51),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _selectedType?.icon ?? Icons.category,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _selectedType?.name.split(' ').first ?? 'Type',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withAlpha(204),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom slider
            if (_maxZoom > _minZoom)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_out, color: Colors.white54, size: 20),
                    Expanded(
                      child: Slider(
                        value: _currentZoom,
                        min: _minZoom,
                        max: _maxZoom,
                        activeColor: const Color(0xFFFFC107),
                        inactiveColor: Colors.white24,
                        onChanged: _setZoom,
                      ),
                    ),
                    const Icon(Icons.zoom_in, color: Colors.white54, size: 20),
                  ],
                ),
              ),

            // Quick note input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(26),
                borderRadius: BorderRadius.circular(25),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Quick note (optional)...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                  icon: Icon(Icons.note, color: Colors.white54),
                ),
                onChanged: (value) => _quickNote = value,
              ),
            ),
            const SizedBox(height: 24),

            // Capture buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Gallery button
                _buildControlButton(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: _capturedPhotos.isEmpty ? null : _showCapturedPhotos,
                  isEnabled: _capturedPhotos.isNotEmpty,
                ),

                // Main capture button
                GestureDetector(
                  onTap: _isCapturing ? null : _capturePhoto,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _isCapturing ? Colors.grey : Colors.transparent,
                    ),
                    child: Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: _isCapturing
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Color(0xFFFFC107),
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                                color: Color(0xFFFFC107),
                                size: 32,
                              ),
                      ),
                    ),
                  ),
                ),

                // Save button
                _buildControlButton(
                  icon: Icons.check_circle,
                  label: 'Save',
                  onTap: _capturedPhotos.isEmpty ? null : _saveFinding,
                  isEnabled: _capturedPhotos.isNotEmpty,
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool isEnabled = true,
    Color? color,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled
                  ? (color ?? Colors.white).withAlpha(51)
                  : Colors.white.withAlpha(26),
            ),
            child: Icon(
              icon,
              color: isEnabled ? (color ?? Colors.white) : Colors.white.withAlpha(77),
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isEnabled ? Colors.white : Colors.white.withAlpha(77),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _setZoom(double zoom) async {
    final newZoom = zoom.clamp(_minZoom, _maxZoom);
    setState(() => _currentZoom = newZoom);
    await _cameraController?.setZoomLevel(newZoom);
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || _isCapturing) return;

    setState(() {
      _isCapturing = true;
      _isAnalyzingQuality = true;
    });

    try {
      // Haptic feedback on capture start
      HapticFeedback.mediumImpact();

      final photo = await _cameraController!.takePicture();

      // Haptic feedback on capture complete
      HapticFeedback.lightImpact();

      // Calculate simulated angle based on capture count (360° / 16 angles)
      final captureAngle = (_capturedPhotos.length * 22.5) % 360;

      setState(() {
        _capturedPhotos.add(photo);
        _capturedAngles.add(captureAngle);
        _isCapturing = false;
        _isAnalyzingQuality = false;
      });

      // Show brief feedback with angle info
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo ${_capturedPhotos.length} captured at ${captureAngle.toInt()}°'),
            duration: const Duration(milliseconds: 800),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      setState(() => _isCapturing = false);
      HapticFeedback.heavyImpact(); // Error feedback
    }
  }

  void _toggleFlash() async {
    if (_cameraController == null) return;

    HapticFeedback.selectionClick();

    try {
      FlashMode newMode;

      switch (_currentFlashMode) {
        case FlashMode.off:
          newMode = FlashMode.auto;
          break;
        case FlashMode.auto:
          newMode = FlashMode.always;
          break;
        case FlashMode.always:
          newMode = FlashMode.torch;
          break;
        default:
          newMode = FlashMode.off;
      }

      await _cameraController!.setFlashMode(newMode);
      setState(() => _currentFlashMode = newMode);
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  void _showTypeSelector() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2523),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Artifact Type',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            // Priority types header
            const Text(
              'MOST COMMON',
              style: TextStyle(
                color: Color(0xFFFFC107),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            // Priority: Coins & Fragments (first 2 types - larger buttons)
            Row(
              children: ArtifactClassification.artifactTypes.take(2).map((type) {
                final isSelected = _selectedType == type;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedType = type);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? type.color : type.color.withAlpha(51),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: type.color,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(type.icon, size: 28, color: isSelected ? Colors.white : type.color),
                          const SizedBox(height: 6),
                          Text(
                            type.name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Other types header
            const Text(
              'OTHER TYPES',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            // Other types (skip first 2)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ArtifactClassification.artifactTypes.skip(2).take(8).map((type) {
                final isSelected = _selectedType == type;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedType = type);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? type.color : Colors.white.withAlpha(26),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(type.icon, size: 18, color: isSelected ? Colors.white : type.color),
                        const SizedBox(width: 6),
                        Text(
                          type.name.split(' ').first,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showCapturedPhotos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2523),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Captured Photos (${_capturedPhotos.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _capturedPhotos.clear());
                    Navigator.pop(context);
                  },
                  child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _capturedPhotos.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white.withAlpha(26),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_capturedPhotos[index].path),
                            fit: BoxFit.cover,
                            width: 100,
                            height: 100,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.image, color: Colors.white54),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _capturedPhotos.removeAt(index));
                              Navigator.pop(context);
                              if (_capturedPhotos.isNotEmpty) {
                                _showCapturedPhotos();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 12),
                            ),
                          ),
                        ),
                        // Photo number indicator
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveFinding() async {
    if (_capturedPhotos.isEmpty) return;

    HapticFeedback.mediumImpact();

    // Persist photos to permanent storage before returning
    final List<String> persistedPaths = [];
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${appDir.path}/quick_captures');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < _capturedPhotos.length; i++) {
        final originalFile = File(_capturedPhotos[i].path);
        final extension = path.extension(_capturedPhotos[i].path);
        final newPath = '${photosDir.path}/quick_${timestamp}_$i$extension';
        await originalFile.copy(newPath);
        persistedPaths.add(newPath);
      }
    } catch (e) {
      debugPrint('Error persisting photos: $e');
      // Fall back to original paths if persistence fails
      for (var photo in _capturedPhotos) {
        persistedPaths.add(photo.path);
      }
    }

    // Record finding in progress service
    final achievements = await _progressService.recordFinding();

    // Also record photo count
    await _progressService.recordPhotos(_capturedPhotos.length);

    // Show achievement if earned
    if (achievements.isNotEmpty && mounted) {
      _showAchievementDialog(achievements.first);
    }

    // Return data to parent screen with persisted paths
    if (mounted) {
      Navigator.pop(context, {
        'photos': _capturedPhotos,
        'persistedPaths': persistedPaths,
        'type': _selectedType,
        'note': _quickNote,
        'location': _currentPosition != null
            ? {
                'latitude': _currentPosition!.latitude,
                'longitude': _currentPosition!.longitude,
              }
            : null,
      });
    }
  }

  void _showAchievementDialog(Achievement achievement) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107).withAlpha(50),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                achievement.type.icon,
                color: const Color(0xFFFFC107),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Achievement Unlocked!',
              style: TextStyle(
                color: Color(0xFFFFC107),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              achievement.type.title,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Awesome!'),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmation() {
    if (_capturedPhotos.isEmpty) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        title: const Text('Discard Photos?', style: TextStyle(color: Colors.white)),
        content: Text(
          'You have ${_capturedPhotos.length} unsaved photos. Are you sure you want to exit?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for rule of thirds grid
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(80)
      ..strokeWidth = 1;

    // Vertical lines
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );

    // Horizontal lines
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );

    // Intersection points (stronger)
    final dotPaint = Paint()
      ..color = Colors.white.withAlpha(150)
      ..style = PaintingStyle.fill;

    final points = [
      Offset(size.width / 3, size.height / 3),
      Offset(size.width * 2 / 3, size.height / 3),
      Offset(size.width / 3, size.height * 2 / 3),
      Offset(size.width * 2 / 3, size.height * 2 / 3),
    ];

    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

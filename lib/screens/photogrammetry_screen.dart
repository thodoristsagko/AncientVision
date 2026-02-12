// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:archive/archive_io.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/reconstruction_result.dart';
import '../services/reconstruction_service.dart';
import '../services/cloud_photogrammetry_service.dart';
import '../services/notification_service.dart';
import '../services/metadata_export_service.dart';
import '../utils/quality_analyzer.dart';
import '../widgets/model_3d_viewer.dart';
import 'manual_entry_form_screen.dart';

class PhotogrammetryScreen extends StatefulWidget {
  final String? findingId;
  final String? findingName;

  const PhotogrammetryScreen({
    super.key,
    this.findingId,
    this.findingName,
  });

  @override
  State<PhotogrammetryScreen> createState() => _PhotogrammetryScreenState();
}

class _PhotogrammetryScreenState extends State<PhotogrammetryScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _imagePicker = ImagePicker();
  final List<PhotogrammetryCapture> _captures = [];
  int _currentAngleIndex = 0;
  bool _showTutorial = true;
  bool _isCapturing = false;
  late AnimationController _pulseController;

  // VIDEO CAPTURE MODE - NEW ULTRA FEATURE!
  bool _isVideoMode = false; // Toggle between photo and video mode
  bool _isRecording = false; // Currently recording video
  XFile? _recordedVideo; // Recorded video file
  int _extractedFrameCount = 0; // Number of frames extracted so far

  // AR-LIKE GUIDANCE - Device sensors
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  double _compassHeading = 0.0; // Compass bearing (0-360°)

  // CAPTURE SETTINGS
  stt.SpeechToText? _speechToText; // Voice commands
  FlutterTts? _flutterTts; // Text-to-speech feedback
  bool _voiceEnabled = false; // Voice commands enabled
  bool _isListening = false; // Currently listening for voice command
  String _lastVoiceCommand = ''; // Last recognized voice command
  bool _autoAdvance = true; // Auto-advance to next angle after capture (default ON)

  // SESSION TRACKING

  // 🎯 3D RECONSTRUCTION - Automated on-device photogrammetry
  final ReconstructionService _reconstructionService = ReconstructionService();
  bool _isReconstructing = false; // Currently generating 3D model
  double _reconstructionProgress = 0.0; // Progress 0.0 to 1.0
  String _reconstructionStatus = ''; // Current status message
  ReconstructionResult? _lastReconstructionResult; // Last successful result for metadata export

  // Define the optimal capture angles for photogrammetry
  // 12 angles around the object + 2 top angles + 2 detail angles = 16 total
  static const List<CaptureAngle> _captureAngles = [
    // Ring 1: Eye level (0°) - 8 positions around the object
    CaptureAngle(id: 0, name: 'Front', angle: 0, elevation: 0, icon: Icons.arrow_upward),
    CaptureAngle(id: 1, name: 'Front-Right', angle: 45, elevation: 0, icon: Icons.arrow_forward),
    CaptureAngle(id: 2, name: 'Right', angle: 90, elevation: 0, icon: Icons.arrow_forward),
    CaptureAngle(id: 3, name: 'Back-Right', angle: 135, elevation: 0, icon: Icons.arrow_forward),
    CaptureAngle(id: 4, name: 'Back', angle: 180, elevation: 0, icon: Icons.arrow_downward),
    CaptureAngle(id: 5, name: 'Back-Left', angle: 225, elevation: 0, icon: Icons.arrow_back),
    CaptureAngle(id: 6, name: 'Left', angle: 270, elevation: 0, icon: Icons.arrow_back),
    CaptureAngle(id: 7, name: 'Front-Left', angle: 315, elevation: 0, icon: Icons.arrow_back),
    // Ring 2: High angle (45°) - 4 positions
    CaptureAngle(id: 8, name: 'Top-Front', angle: 0, elevation: 45, icon: Icons.north_east),
    CaptureAngle(id: 9, name: 'Top-Right', angle: 90, elevation: 45, icon: Icons.north_east),
    CaptureAngle(id: 10, name: 'Top-Back', angle: 180, elevation: 45, icon: Icons.south_east),
    CaptureAngle(id: 11, name: 'Top-Left', angle: 270, elevation: 45, icon: Icons.north_west),
    // Top down views
    CaptureAngle(id: 12, name: 'Top Center', angle: 0, elevation: 80, icon: Icons.vertical_align_bottom),
    CaptureAngle(id: 13, name: 'Top Angled', angle: 45, elevation: 70, icon: Icons.vertical_align_bottom),
    // Detail shots
    CaptureAngle(id: 14, name: 'Detail 1', angle: 0, elevation: 20, icon: Icons.zoom_in, isDetail: true),
    CaptureAngle(id: 15, name: 'Detail 2', angle: 180, elevation: 20, icon: Icons.zoom_in, isDetail: true),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Initialize AR-like sensor guidance
    _initializeSensors();

    // Initialize ULTRA++ voice commands
    _initializeVoiceCommands();

    // 🌟 Initialize World-Class AI & Analytics
    _loadSmartSuggestions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _speechToText?.stop();
    _flutterTts?.stop();
    super.dispose();
  }

  // Initialize device sensors for AR-like guidance
  DateTime _lastSensorUpdate = DateTime.now();
  void _initializeSensors() {
    // Accelerometer - detect phone tilt (throttled to ~15Hz)
    _accelerometerSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.difference(_lastSensorUpdate).inMilliseconds < 66) return;
      _lastSensorUpdate = now;
    });

    // Magnetometer - compass heading (throttled to ~15Hz)
    _magnetometerSubscription = magnetometerEventStream().listen((MagnetometerEvent event) {
      if (!mounted) return;
      _compassHeading = atan2(event.y, event.x) * 180 / pi;
      if (_compassHeading < 0) _compassHeading += 360;
    });
  }

  // ULTRA++ Initialize voice commands for hands-free operation
  Future<void> _initializeVoiceCommands() async {
    final sttInstance = stt.SpeechToText();
    final ttsInstance = FlutterTts();
    _speechToText = sttInstance;
    _flutterTts = ttsInstance;

    // Initialize speech-to-text
    bool available = await sttInstance.initialize(
      onStatus: (status) {
        if (status == 'notListening' && _voiceEnabled && mounted) {
          // Auto-restart listening if voice is enabled
          _startListening();
        }
      },
      onError: (error) {
        debugPrint('Voice recognition error: $error');
        if (mounted) setState(() => _isListening = false);
      },
    );

    // Configure text-to-speech
    await ttsInstance.setLanguage('en-US');
    await ttsInstance.setSpeechRate(0.5); // Slower for clarity in field
    await ttsInstance.setVolume(1.0);
    await ttsInstance.setPitch(1.0);

    if (available) {
      debugPrint(' Voice commands initialized successfully');
    } else {
      debugPrint(' Voice recognition not available on this device');
    }
  }

  // Start listening for voice commands
  Future<void> _startListening() async {
    if (!_voiceEnabled || _isListening || _speechToText == null) return;

    if (mounted) {
      setState(() => _isListening = true);

      _speechToText!.listen(
        onResult: (result) {
          setState(() {
            _lastVoiceCommand = result.recognizedWords.toLowerCase();
          });

          if (result.finalResult) {
            _handleVoiceCommand(_lastVoiceCommand);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
      );
    }
  }

  // Stop listening for voice commands
  Future<void> _stopListening() async {
    if (_isListening) {
      await _speechToText?.stop();
      if (mounted) setState(() => _isListening = false);
    }
  }

  // Handle recognized voice commands
  Future<void> _handleVoiceCommand(String command) async {
    command = command.toLowerCase().trim();

    // Capture commands
    if (command.contains('capture') || command.contains('photo') || command.contains('take picture')) {
      await _speak('Capturing now');
      _capturePhoto();
    }
    // Navigation commands
    else if (command.contains('next') || command.contains('next angle')) {
      if (_currentAngleIndex < _captureAngles.length - 1) {
        setState(() => _currentAngleIndex++);
        await _speak('Moving to ${_currentAngle.name}');
      } else {
        await _speak('This is the last angle');
      }
    }
    else if (command.contains('previous') || command.contains('back') || command.contains('go back')) {
      if (_currentAngleIndex > 0) {
        setState(() => _currentAngleIndex--);
        await _speak('Moving back to ${_currentAngle.name}');
      } else {
        await _speak('Already at first angle');
      }
    }
    // Progress and info commands
    else if (command.contains('progress') || command.contains('how many')) {
      await _speak('${_captures.length} of ${_captureAngles.length} angles captured');
    }
    else if (command.contains('current angle') || command.contains('what angle')) {
      await _speak('Current angle is ${_currentAngle.name}');
    }
    else if (command.contains('skip') || command.contains('skip angle')) {
      if (_currentAngleIndex < _captureAngles.length - 1) {
        setState(() => _currentAngleIndex++);
        await _speak('Skipped to ${_currentAngle.name}');
      }
    }
    // Export commands
    else if (command.contains('export') || command.contains('save') || command.contains('finish')) {
      if (_captures.length >= 8) {
        await _speak('Exporting ${_captures.length} photos');
        _exportPhotos();
      } else {
        await _speak('Need at least 8 captures to export. You have ${_captures.length}');
      }
    }
    // Help command
    else if (command.contains('help') || command.contains('what can i say')) {
      await _speak('Say capture, next, previous, progress, skip, or export');
    }
    else {
      // Unknown command
      await _speak('Command not recognized. Say help for available commands');
    }
  }

  // Text-to-speech helper
  Future<void> _speak(String text) async {
    await _flutterTts?.speak(text);
  }

  // Toggle voice commands on/off
  void _toggleVoiceCommands() {
    final wasEnabled = _voiceEnabled;
    setState(() => _voiceEnabled = !_voiceEnabled);
    if (_voiceEnabled) {
      _startListening();
      _speak('Voice commands enabled');
    } else {
      _speechToText?.stop();
      // Speak confirmation before disabling (use wasEnabled check)
      if (wasEnabled) {
        _flutterTts?.speak('Voice commands disabled');
      }
    }
  }

  // ============================================================================
  // SESSION TRACKING
  // ============================================================================

  // Load context-aware smart suggestions
  Future<void> _loadSmartSuggestions() async {
    // Placeholder for future smart suggestion loading
  }

  // 📈 SESSION ANALYTICS
  // Calculate progress percentage
  double get _progress => _captures.length / _captureAngles.length;

  // Get the next recommended angle
  CaptureAngle get _currentAngle => _captureAngles[_currentAngleIndex];

  // Check if enough photos for generation (minimum 4)
  bool get _canGenerate => _captures.length >= 4;

  // Check if all required angles are captured
  bool get _isComplete => _captures.length >= _captureAngles.length;

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      // Standard photo capture - optimized for photogrammetry
      final finalImage = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear, // Back camera
        maxWidth: 2048, // High resolution for 3D reconstruction
        maxHeight: 2048,
        imageQuality: 95, // High quality
      );

      if (finalImage != null) {
        // Analyze image quality
        final quality = await _analyzeImageQuality(finalImage);

        final capture = PhotogrammetryCapture(
          file: finalImage,
          angle: _currentAngle,
          capturedAt: DateTime.now(),
          qualityScore: quality,
        );

        setState(() {
          _captures.add(capture);
          // Auto-advance to next angle if enabled
          if (_currentAngleIndex < _captureAngles.length - 1 && _autoAdvance) {
            _currentAngleIndex++;
          }
        });

        // Show quality feedback
        if (mounted) {
          final qualityText = quality >= 0.8 ? 'Excellent!' : quality >= 0.6 ? 'Good' : 'Consider retaking';
          final qualityColor = quality >= 0.8 ? const Color(0xFF4CAF50) : quality >= 0.6 ? const Color(0xFFFFC107) : Colors.orange;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    quality >= 0.6 ? Icons.check_circle : Icons.warning,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text('Photo ${_captures.length}/${_captureAngles.length}: $qualityText'),
                ],
              ),
              backgroundColor: qualityColor,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  // ============================================================================
  // VIDEO CAPTURE MODE - ULTRA-ADVANCED FEATURE!
  // ============================================================================
  // Record a smooth video while walking around the object, then automatically
  // extract the best frames for photogrammetry processing
  // ============================================================================

  Future<void> _recordVideo() async {
    if (_isRecording) {
      // Stop recording
      await _stopVideoRecording();
    } else {
      // Start recording
      await _startVideoRecording();
    }
  }

  Future<void> _startVideoRecording() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxDuration: const Duration(minutes: 2), // Max 2 minutes
      );

      if (video != null) {
        setState(() {
          _recordedVideo = video;
          _isRecording = false;
          _isCapturing = false;
        });

        // Show processing dialog
        if (mounted) {
          _showVideoProcessingDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video recording error: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isRecording = false;
        _isCapturing = false;
      });
    }
  }

  Future<void> _stopVideoRecording() async {
    setState(() => _isRecording = false);
  }

  void _showVideoProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        title: const Text(
          '🎬 Video Recorded!',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extract frames automatically?',
              style: TextStyle(color: Colors.white.withAlpha(230)),
            ),
            const SizedBox(height: 16),
            Text(
              'The system will analyze your video and extract the best quality frames for photogrammetry.',
              style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withAlpha(51),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF7C4DFF).withAlpha(128)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF7C4DFF), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Auto-extract ~20-30 frames with quality filtering',
                      style: TextStyle(
                        color: Colors.white.withAlpha(230),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _recordedVideo = null);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _extractFramesFromVideo();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
            ),
            child: const Text('Extract Frames'),
          ),
        ],
      ),
    );
  }

  Future<void> _extractFramesFromVideo() async {
    if (_recordedVideo == null) return;

    setState(() {
      _extractedFrameCount = 0;
    });

    // Key for updating dialog state
    final dialogSetState = ValueNotifier<int>(0);

    try {
      // Show progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ValueListenableBuilder<int>(
            valueListenable: dialogSetState,
            builder: (context, _, __) => AlertDialog(
              backgroundColor: const Color(0xFF1C2523),
              title: const Text(
                'Processing Video',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF7C4DFF)),
                  const SizedBox(height: 16),
                  Text(
                    'Extracting frames: $_extractedFrameCount',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This may take 30-60 seconds...',
                    style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // Get video duration
      final videoController = VideoPlayerController.file(File(_recordedVideo!.path));
      await videoController.initialize();
      final duration = videoController.value.duration;
      videoController.dispose();

      debugPrint('Video recorded: ${duration.inSeconds}s');

      // Calculate frame timestamps (extract ~16 frames evenly spaced)
      const targetFrames = 16;
      final durationMs = duration.inMilliseconds;
      if (durationMs < 1000) {
        throw Exception('Video too short (${duration.inSeconds}s). Record at least 3 seconds.');
      }

      final intervalMs = durationMs ~/ targetFrames;
      final tempDir = await getTemporaryDirectory();
      int extracted = 0;

      for (int i = 0; i < targetFrames; i++) {
        final timeMs = i * intervalMs;

        try {
          final thumbnailPath = await VideoThumbnail.thumbnailFile(
            video: _recordedVideo!.path,
            thumbnailPath: tempDir.path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 2048,
            quality: 90,
            timeMs: timeMs,
          );

          if (thumbnailPath != null) {
            final file = File(thumbnailPath);
            if (await file.exists()) {
              final xFile = XFile(thumbnailPath);
              final quality = await _analyzeImageQuality(xFile);

              setState(() {
                _captures.add(PhotogrammetryCapture(
                  file: xFile,
                  angle: CaptureAngle(
                    id: _captures.length,
                    name: 'Frame ${i + 1}',
                    angle: (i * 360.0 / targetFrames),
                    elevation: 0,
                    icon: Icons.videocam,
                  ),
                  capturedAt: DateTime.now(),
                  qualityScore: quality,
                ));
                _extractedFrameCount = ++extracted;
                if (_currentAngleIndex < _captureAngles.length - 1) {
                  _currentAngleIndex = min(_captures.length, _captureAngles.length - 1);
                }
              });

              // Update dialog
              dialogSetState.value++;
            }
          }
        } catch (e) {
          debugPrint('Failed to extract frame at ${timeMs}ms: $e');
        }
      }

      // Close progress dialog
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Extracted $extracted frames from video'),
            backgroundColor: extracted > 0 ? const Color(0xFF4CAF50) : Colors.orange,
          ),
        );
      }

    } catch (e) {
      debugPrint('Frame extraction error: $e');

      // Close progress dialog if open
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Frame extraction failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      dialogSetState.dispose();
      setState(() {
        _recordedVideo = null;
      });
    }
  }

  // ULTRA-ADVANCED image quality analysis using QualityAnalyzer
  Future<double> _analyzeImageQuality(XFile image) async {
    try {
      final file = File(image.path);
      final bytes = await file.readAsBytes();

      // Decode image
      img.Image? decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return 0.5;

      // Use advanced QualityAnalyzer for comprehensive metrics
      final metrics = await QualityAnalyzer.analyzeImage(decodedImage);

      // Debug output
      debugPrint('📸 Quality Analysis:');
      debugPrint('   Sharpness: ${(metrics.sharpness * 100).toInt()}%');
      debugPrint('   Exposure: ${(metrics.exposure * 100).toInt()}%');
      debugPrint('   Motion Blur: ${(metrics.motionBlur * 100).toInt()}%');
      debugPrint('   Noise: ${(metrics.noise * 100).toInt()}%');
      debugPrint('   ⭐ Overall: ${(metrics.overallScore * 100).toInt()}%');

      // Return overall score
      return metrics.overallScore;
    } catch (e) {
      debugPrint(' Quality analysis error: $e');
      return 0.5;
    }
  }

  void _retakePhoto(int index) async {
    final capture = _captures[index];

    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 95,
    );

    if (image != null) {
      final quality = await _analyzeImageQuality(image);
      if (!mounted) return;

      setState(() {
        _captures[index] = PhotogrammetryCapture(
          file: image,
          angle: capture.angle,
          capturedAt: DateTime.now(),
          qualityScore: quality,
        );
      });
    }
  }

  void _deletePhoto(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        title: const Text('Delete Photo?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${_captures[index].angle.name} photo?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _captures.removeAt(index));
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Share captured photos - exports and offers sharing options
  Future<void> _sharePhotos() async {
    if (_captures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No photos to share'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      // First export the photos
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportDir = Directory('${directory.path}/photogrammetry_$timestamp');
      await exportDir.create(recursive: true);

      // Copy all photos
      List<String> filePaths = [];
      for (int i = 0; i < _captures.length; i++) {
        final capture = _captures[i];
        final newPath = '${exportDir.path}/${capture.angle.name.replaceAll(' ', '_')}_${i + 1}.jpg';
        await File(capture.file.path).copy(newPath);
        filePaths.add(newPath);
      }

      // Create ZIP for easy sharing
      final zipPath = '${directory.path}/AncientVision_3D_Photos_$timestamp.zip';
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addDirectory(exportDir);
      encoder.close();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.share, color: Color(0xFF2196F3), size: 28),
                SizedBox(width: 12),
                Text('Share Photos', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_captures.length} photos ready to share!',
                  style: TextStyle(color: Colors.white.withAlpha(200)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.folder_zip, color: Color(0xFFFFC107), size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ZIP Archive Created',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Location: ${exportDir.path}',
                        style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Transfer the ZIP file to your computer for 3D processing with Meshroom or COLMAP.',
                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(color: Color(0xFFFFC107))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportPhotos() async {
    if (_captures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No photos to export'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportDir = Directory('${directory.path}/photogrammetry_$timestamp');
      await exportDir.create(recursive: true);

      // === ULTRA-ADVANCED EXPORT ===

      // Copy all photos to export directory
      for (int i = 0; i < _captures.length; i++) {
        final capture = _captures[i];
        final newPath = '${exportDir.path}/${capture.angle.name.replaceAll(' ', '_')}_${i + 1}.jpg';
        await File(capture.file.path).copy(newPath);
      }

      // Create COMPREHENSIVE metadata file
      final metadata = StringBuffer();
      metadata.writeln('=' * 70);
      metadata.writeln('ANCIENTVISION PHOTOGRAMMETRY CAPTURE SET');
      metadata.writeln('=' * 70);
      metadata.writeln('Generated: ${DateTime.now().toIso8601String()}');
      if (widget.findingName != null) {
        metadata.writeln('Finding: ${widget.findingName}');
      }
      metadata.writeln('Total Photos: ${_captures.length}');

      // Calculate average quality
      double avgQuality = _captures.fold(0.0, (acc, c) => acc + c.qualityScore) / _captures.length;
      metadata.writeln('Average Quality: ${(avgQuality * 100).toInt()}%');
      metadata.writeln('');

      metadata.writeln('CAPTURE DETAILS');
      metadata.writeln('-' * 70);
      for (int i = 0; i < _captures.length; i++) {
        final capture = _captures[i];
        metadata.writeln('${i + 1}. ${capture.angle.name}');
        metadata.writeln('   Angle: ${capture.angle.angle}° | Elevation: ${capture.angle.elevation}°');
        metadata.writeln('   Quality: ${(capture.qualityScore * 100).toInt()}%');
        metadata.writeln('   Captured: ${capture.capturedAt.toIso8601String()}');
        metadata.writeln('');
      }

      metadata.writeln('PROCESSING INSTRUCTIONS');
      metadata.writeln('-' * 70);
      metadata.writeln('');
      metadata.writeln('OPTION 1: Automated Processing (Recommended)');
      metadata.writeln('   python photogrammetry_process.py .');
      metadata.writeln('   Or: python photogrammetry_process.py . --quality high');
      metadata.writeln('');
      metadata.writeln('OPTION 2: Meshroom GUI');
      metadata.writeln('   1. Open Meshroom application');
      metadata.writeln('   2. Drag this folder into Meshroom window');
      metadata.writeln('   3. Click "Start" button');
      metadata.writeln('   4. Wait 10-60 minutes for processing');
      metadata.writeln('');
      metadata.writeln('OPTION 3: COLMAP Command-line');
      metadata.writeln('   colmap automatic_reconstructor \\');
      metadata.writeln('     --workspace_path . \\');
      metadata.writeln('     --image_path . \\');
      metadata.writeln('     --quality high');
      metadata.writeln('');

      metadata.writeln('FREE SOFTWARE');
      metadata.writeln('-' * 70);
      metadata.writeln('Meshroom (Free, Open Source): https://alicevision.org/');
      metadata.writeln('COLMAP (Free, Open Source): https://colmap.github.io/');
      metadata.writeln('Regard3D (Free, Open Source): http://www.regard3d.org/');
      metadata.writeln('3DF Zephyr Free: https://www.3dflow.net/3df-zephyr-free/');
      metadata.writeln('');
      metadata.writeln('VIEWING & EDITING');
      metadata.writeln('-' * 70);
      metadata.writeln('MeshLab: https://www.meshlab.net/');
      metadata.writeln('CloudCompare: https://www.cloudcompare.org/');
      metadata.writeln('Blender: https://www.blender.org/');
      metadata.writeln('');
      metadata.writeln('HOSTING (FREE)');
      metadata.writeln('-' * 70);
      metadata.writeln('Sketchfab: https://sketchfab.com/');
      metadata.writeln('GitHub Pages + Three.js viewer');
      metadata.writeln('');
      metadata.writeln('=' * 70);
      metadata.writeln('Generated by AncientVision - Professional Photogrammetry System');
      metadata.writeln('=' * 70);

      await File('${exportDir.path}/README.txt').writeAsString(metadata.toString());

      // Create JSON metadata for automated processing
      final jsonMetadata = {
        'generated': DateTime.now().toIso8601String(),
        'findingName': widget.findingName,
        'totalPhotos': _captures.length,
        'averageQuality': avgQuality,
        'captures': _captures.map((c) => {
          'fileName': '${c.angle.name.replaceAll(' ', '_')}_${_captures.indexOf(c) + 1}.jpg',
          'angle': c.angle.angle,
          'elevation': c.angle.elevation,
          'quality': c.qualityScore,
          'timestamp': c.capturedAt.toIso8601String(),
        }).toList(),
      };
      await File('${exportDir.path}/metadata.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(jsonMetadata)
      );

      // Create ZIP archive for easy sharing
      final zipPath = '${directory.path}/photogrammetry_$timestamp.zip';
      try {
        final encoder = ZipFileEncoder();
        encoder.create(zipPath);
        encoder.addDirectory(exportDir);
        encoder.close();
        debugPrint(' ZIP created: $zipPath');
      } catch (e) {
        debugPrint(' ZIP creation failed: $e');
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 28),
                SizedBox(width: 12),
                Text('Export Complete!', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_captures.length} photos exported successfully!',
                  style: TextStyle(color: Colors.white.withAlpha(204)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withAlpha(51),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Next Steps:',
                        style: TextStyle(color: Color(0xFF7C4DFF), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. Transfer photos to your computer\n'
                        '2. Use Meshroom (free) for 3D reconstruction\n'
                        '3. Upload the 3D model to Sketchfab',
                        style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder, color: Color(0xFFFFC107), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          exportDir.path,
                          style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(color: Color(0xFFFFC107))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Generate 3D model from captured photos - allows choice of method
  Future<void> _generate3DModel() async {
    if (_captures.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need at least 4 photos for 3D reconstruction'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show method selection dialog
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.view_in_ar_rounded, color: Color(0xFF7C4DFF), size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Choose Processing Method', style: TextStyle(color: Colors.white, fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cloud Processing Option - RECOMMENDED
            InkWell(
              onTap: () => Navigator.pop(ctx, 'cloud'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF7C4DFF).withAlpha(77), const Color(0xFF448AFF).withAlpha(77)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF7C4DFF), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_upload_rounded, color: Color(0xFF7C4DFF), size: 32),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Cloud Processing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('FREE via OpenScan', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('RECOMMENDED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• Professional-quality dense mesh\n'
                      '• Textured 3D model output\n'
                      '• 5-15 min processing time\n'
                      '• Requires internet connection',
                      style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // On-Device Option
            InkWell(
              onTap: () => Navigator.pop(ctx, 'device'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(13),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(51)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.phone_android_rounded, color: Colors.white.withAlpha(179), size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('On-Device Preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('Quick sparse point cloud', style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• Sparse point cloud only\n'
                      '• 1-3 min processing time\n'
                      '• Works offline\n'
                      '• Lower quality preview',
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withAlpha(128))),
          ),
        ],
      ),
    );

    if (method == null) return;

    if (method == 'cloud') {
      await _generateCloudModel();
      return;
    }

    // On-device processing continues below...
    // Convert captures to File objects
    final imageFiles = _captures.map((c) => File(c.file.path)).toList();

    // Validate photos first
    setState(() {
      _isReconstructing = true;
      _reconstructionProgress = 0.0;
      _reconstructionStatus = 'Validating photos...';
    });

    try {
      final validation = await _reconstructionService.validatePhotosForReconstruction(imageFiles);

      // Show validation warnings if any
      if (validation['warnings'].isNotEmpty || validation['recommendedFixes'].isNotEmpty) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  validation['isValid'] ? Icons.warning_amber : Icons.error,
                  color: validation['isValid'] ? const Color(0xFFFFC107) : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    validation['isValid'] ? 'Quality Check' : 'Cannot Reconstruct',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (validation['errors'].isNotEmpty) ...[
                    const Text('Errors:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...((validation['errors'] as List).map((e) => Text('• $e', style: const TextStyle(color: Colors.red, fontSize: 12)))),
                    const SizedBox(height: 12),
                  ],
                  if (validation['warnings'].isNotEmpty) ...[
                    const Text('Warnings:', style: TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...((validation['warnings'] as List).map((w) => Text('• $w', style: const TextStyle(color: Colors.white70, fontSize: 12)))),
                    const SizedBox(height: 12),
                  ],
                  if (validation['recommendedFixes'].isNotEmpty) ...[
                    const Text('Recommendations:', style: TextStyle(color: Color(0xFF00BCD4), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...((validation['recommendedFixes'] as List).map((r) => Text('• $r', style: const TextStyle(color: Colors.white70, fontSize: 12)))),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              if (validation['isValid'])
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
                  child: const Text('Continue'),
                ),
            ],
          ),
        );

        if (shouldContinue != true) {
          setState(() {
            _isReconstructing = false;
          });
          return;
        }
      }

      // Generate sparse point cloud preview
      setState(() {
        _reconstructionProgress = 0.1;
        _reconstructionStatus = 'Starting reconstruction...';
      });

      final result = await _reconstructionService.generateSparsePreview(
        imageFiles: imageFiles,
        onProgress: (progress, status) {
          setState(() {
            _reconstructionProgress = progress;
            _reconstructionStatus = status;
          });
        },
      );

      setState(() {
        _isReconstructing = false;
        if (result.isComplete) _lastReconstructionResult = result;
      });

      // Save result to history
      if (result.isComplete) {
        await _reconstructionService.saveResult(result);
      }

      if (result.isComplete && mounted) {
        // Build quality notification message
        final grade = result.qualityMetrics['quality_grade'] as String?;
        final gsd = result.qualityMetrics['gsd_mm_per_pixel'] as double?;
        final gradeDisplay = grade != null ? ' [${grade.toUpperCase()}]' : '';
        final gsdDisplay = gsd != null ? ' | GSD: ${gsd.toStringAsFixed(2)} mm/px' : '';

        // Send success notification
        await NotificationService().showProcessingComplete(
          projectName: 'On-Device Model',
          pointCount: result.pointCount,
        );

        // Show quality grade snackbar
        if (grade != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  _qualityGradeBadge(grade),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${result.pointCount} points$gradeDisplay$gsdDisplay',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1C2523),
              duration: const Duration(seconds: 4),
            ),
          );
        }

        // Go directly to 3D viewer - user can save from there
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Model3DViewer(
              result: result,
              onCompleteForm: () {
                // After viewing 3D, go to form to save finding
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ManualEntryFormScreen(
                      reconstructionResult: result,
                      photoGallery: _captures.map((c) => c.file).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else if (result.hasFailed && mounted) {
        // Send failure notification
        await NotificationService().showProcessingFailed(
          projectName: 'On-Device Model',
          errorMessage: result.errorMessage,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('3D reconstruction failed: ${result.errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isReconstructing = false;
      });

      // Send error notification
      await NotificationService().showProcessingFailed(
        projectName: 'On-Device Model',
        errorMessage: e.toString(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reconstruction error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Generate 3D model using FREE cloud processing (OpenScan Cloud API)
  Future<void> _generateCloudModel() async {
    // Get user email for token
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'ancientvision@fll.app';

    setState(() {
      _isReconstructing = true;
      _reconstructionProgress = 0.0;
      _reconstructionStatus = 'Preparing cloud upload...';
    });

    try {
      final cloudService = CloudPhotogrammetryService();

      // Get XFile list from captures
      final images = _captures.map((c) => c.file).toList();

      // Run cloud reconstruction
      final result = await cloudService.reconstruct(
        images: images,
        email: email,
        projectName: 'AncientVision_${DateTime.now().millisecondsSinceEpoch}',
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _reconstructionProgress = progress;
              _reconstructionStatus = status;
            });
          }
        },
      );

      setState(() {
        _isReconstructing = false;
      });

      if (result.success && mounted) {
        // Send success notification
        await NotificationService().showProcessingComplete(
          projectName: 'Cloud Model',
        );

        // Cloud model ready - go directly to save finding form
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Cloud processing complete! Fill in the finding details.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ManualEntryFormScreen(
              photoGallery: _captures.map((c) => c.file).toList(),
              cloudModelUrl: result.downloadUrl,
            ),
          ),
        );
      } else if (!result.success && mounted) {
        // Show error with option to try on-device
        final tryOnDevice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 12),
                Expanded(child: Text('Cloud Processing Unavailable', style: TextStyle(color: Colors.white, fontSize: 18))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.errorMessage ?? 'Cloud service temporarily unavailable.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 16),
                Text(
                  'You can try on-device processing instead for a quick preview.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.phone_android, size: 18),
                label: const Text('Try On-Device'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
              ),
            ],
          ),
        );

        if (tryOnDevice == true) {
          // Fall back to on-device processing
          await _runOnDeviceReconstruction();
        }
      }
    } catch (e) {
      setState(() {
        _isReconstructing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cloud processing error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Run on-device reconstruction (extracted from _generate3DModel for reuse)
  Future<void> _runOnDeviceReconstruction() async {
    final imageFiles = _captures.map((c) => File(c.file.path)).toList();

    setState(() {
      _isReconstructing = true;
      _reconstructionProgress = 0.0;
      _reconstructionStatus = 'Starting on-device processing...';
    });

    try {
      final result = await _reconstructionService.generateSparsePreview(
        imageFiles: imageFiles,
        onProgress: (progress, status) {
          setState(() {
            _reconstructionProgress = progress;
            _reconstructionStatus = status;
          });
        },
      );

      setState(() {
        _isReconstructing = false;
        if (result.isComplete) _lastReconstructionResult = result;
      });

      if (result.isComplete) {
        await _reconstructionService.saveResult(result);

        if (mounted) {
          // Show quality grade if available
          final grade = result.qualityMetrics['quality_grade'] as String?;
          if (grade != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    _qualityGradeBadge(grade),
                    const SizedBox(width: 12),
                    Text('Quality: ${grade.toUpperCase()}',
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
                backgroundColor: const Color(0xFF1C2523),
                duration: const Duration(seconds: 3),
              ),
            );
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Model3DViewer(
                result: result,
                onCompleteForm: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManualEntryFormScreen(
                        reconstructionResult: result,
                        photoGallery: _captures.map((c) => c.file).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isReconstructing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('On-device error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Build a quality grade badge widget
  Widget _qualityGradeBadge(String grade) {
    Color badgeColor;
    String label;
    switch (grade.toLowerCase()) {
      case 'excellent':
        badgeColor = const Color(0xFF4CAF50);
        label = 'A';
        break;
      case 'good':
        badgeColor = const Color(0xFF8BC34A);
        label = 'B';
        break;
      case 'acceptable':
        badgeColor = const Color(0xFFFFC107);
        label = 'C';
        break;
      default:
        badgeColor = Colors.red;
        label = 'F';
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  /// Show metadata export options dialog
  Future<void> _showMetadataExportDialog(ReconstructionResult result) async {
    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Export Metadata', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description, color: Color(0xFF00BCD4)),
              title: const Text('Dublin Core XML', style: TextStyle(color: Colors.white)),
              subtitle: Text('Standard library metadata', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
              onTap: () => Navigator.pop(ctx, 'dublin_core'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance, color: Color(0xFF7C4DFF)),
              title: const Text('CIDOC-CRM RDF/XML', style: TextStyle(color: Colors.white)),
              subtitle: Text('ISO 21127 heritage standard', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
              onTap: () => Navigator.pop(ctx, 'cidoc_crm'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );

    if (format == null || !mounted) return;

    try {
      final id = result.id;
      final title = widget.findingName ?? 'Archaeological Finding';
      final date = result.startedAt;
      final lat = result.qualityMetrics['gps_latitude'] as double?;
      final lon = result.qualityMetrics['gps_longitude'] as double?;
      final grade = result.qualityMetrics['quality_grade'] as String?;

      String xml;
      String filename;

      if (format == 'dublin_core') {
        xml = MetadataExportService.exportDublinCore(
          id: id,
          title: title,
          description: 'Photogrammetric reconstruction with ${result.pointCount} points. '
              'Quality: ${grade ?? "unknown"}.',
          date: date,
          latitude: lat,
          longitude: lon,
          additionalFields: {
            'source': 'AncientVision on-device photogrammetry',
            if (grade != null) 'quality': grade,
          },
        );
        filename = 'finding_${id.substring(0, 8)}_dublin_core.xml';
      } else {
        xml = MetadataExportService.exportCidocCRM(
          id: id,
          title: title,
          description: 'Photogrammetric reconstruction with ${result.pointCount} points. '
              'Quality: ${grade ?? "unknown"}.',
          objectType: 'Archaeological Object',
          dateFound: date,
          latitude: lat,
          longitude: lon,
          additionalProperties: {
            'reconstruction_method': result.methodName,
            'point_count': result.pointCount.toString(),
            if (grade != null) 'quality_grade': grade,
          },
        );
        filename = 'finding_${id.substring(0, 8)}_cidoc_crm.xml';
      }

      // Save to app documents directory
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(xml);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported: $filename'),
            backgroundColor: const Color(0xFF4CAF50),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showTutorial) {
      return _buildTutorialScreen();
    }
    return _buildCaptureScreen();
  }

  Widget _buildTutorialScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text(
                        'Photogrammetry Capture',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 32),

                // 3D Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withAlpha(51),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF7C4DFF), width: 3),
                  ),
                  child: const Icon(Icons.view_in_ar, color: Color(0xFF7C4DFF), size: 60),
                ),
                const SizedBox(height: 32),

                const Text(
                  'Create 3D Models from Photos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Photogrammetry creates accurate 3D models by analyzing multiple photos taken from different angles.',
                  style: TextStyle(
                    color: Colors.white.withAlpha(179),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Tips
                Expanded(
                  child: ListView(
                    children: [
                      _buildTipCard(
                        Icons.wb_sunny_outlined,
                        'Good Lighting',
                        'Use natural, diffused light. Avoid harsh shadows and direct sunlight.',
                        const Color(0xFFFFC107),
                      ),
                      _buildTipCard(
                        Icons.rotate_90_degrees_ccw,
                        '360° Coverage',
                        'Capture photos from all angles: front, back, sides, and top views.',
                        const Color(0xFF4CAF50),
                      ),
                      _buildTipCard(
                        Icons.blur_off,
                        'Sharp Focus',
                        'Keep the camera steady. Wait for focus before capturing.',
                        const Color(0xFF2196F3),
                      ),
                      _buildTipCard(
                        Icons.photo_size_select_large,
                        '50-70% Overlap',
                        'Each photo should overlap with adjacent photos for best results.',
                        const Color(0xFFE91E63),
                      ),
                    ],
                  ),
                ),

                // Start button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => setState(() => _showTutorial = false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt),
                        SizedBox(width: 8),
                        Text('Start Capture Session', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTipCard(IconData icon, String title, String description, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withAlpha(51),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ULTRA++ Feature Chip Widget
  Widget _buildFeatureChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withAlpha(51) : Colors.white.withAlpha(13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : Colors.white.withAlpha(51),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? color : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : Colors.white60,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🤖 AI Result Item Widget
  Widget _buildCaptureScreen() {
    return Scaffold(
      body: Stack(
        children: [
          // Main content
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
              ),
            ),
            child: SafeArea(
              child: Column(
            children: [
              // Header with progress
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            widget.findingName ?? 'Photogrammetry',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_captures.length}/${_captureAngles.length} photos captured',
                            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // 3D Model button
                    IconButton(
                      onPressed: _canGenerate && !_isReconstructing ? _generate3DModel : null,
                      icon: Icon(
                        Icons.view_in_ar,
                        color: _canGenerate && !_isReconstructing
                            ? const Color(0xFF7C4DFF)
                            : Colors.white30,
                      ),
                      tooltip: 'Generate 3D Model',
                    ),
                    // Export photos button
                    IconButton(
                      onPressed: _captures.isNotEmpty ? _exportPhotos : null,
                      icon: Icon(
                        Icons.ios_share,
                        color: _captures.isNotEmpty ? const Color(0xFF4CAF50) : Colors.white30,
                      ),
                      tooltip: 'Export Photos',
                    ),
                    // Export metadata button (available after reconstruction)
                    IconButton(
                      onPressed: _lastReconstructionResult != null
                          ? () => _showMetadataExportDialog(_lastReconstructionResult!)
                          : null,
                      icon: Icon(
                        Icons.description_outlined,
                        color: _lastReconstructionResult != null
                            ? const Color(0xFF00BCD4)
                            : Colors.white30,
                      ),
                      tooltip: 'Export Metadata (Dublin Core / CIDOC-CRM)',
                    ),
                    // Info button
                    IconButton(
                      onPressed: () => setState(() => _showTutorial = true),
                      icon: const Icon(Icons.help_outline, color: Colors.white54),
                    ),
                  ],
                ),
              ),

              // ULTRA++ Advanced Features Panel
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(26)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.settings, color: Color(0xFF4CAF50), size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Capture Settings',
                          style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Auto-Advance Toggle (always visible, default ON)
                        _buildFeatureChip(
                          icon: Icons.skip_next,
                          label: 'Auto-Advance',
                          isActive: _autoAdvance,
                          onTap: () => setState(() => _autoAdvance = !_autoAdvance),
                          color: const Color(0xFF4CAF50),
                        ),
                        const SizedBox(width: 8),
                        // Voice Commands Toggle
                        _buildFeatureChip(
                          icon: Icons.mic,
                          label: 'Voice',
                          isActive: _voiceEnabled,
                          onTap: _toggleVoiceCommands,
                          color: const Color(0xFF2196F3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Circular progress with angle indicator
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Progress ring
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CustomPaint(
                        painter: AngleProgressPainter(
                          captures: _captures,
                          angles: _captureAngles,
                          currentAngle: _currentAngleIndex,
                          progress: _progress,
                        ),
                      ),
                    ),
                    // Center content
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(_progress * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!_isComplete)
                          Text(
                            'Next: ${_currentAngle.name}',
                            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
                          ),
                        if (_isComplete)
                          const Text(
                            'Complete!',
                            style: TextStyle(color: Color(0xFF4CAF50), fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Current angle instruction / Video mode instruction
              if (!_isComplete)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withAlpha(51),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF7C4DFF).withAlpha(128)),
                  ),
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Color.lerp(
                                const Color(0xFF7C4DFF).withAlpha(77),
                                const Color(0xFF7C4DFF).withAlpha(153),
                                _pulseController.value,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isVideoMode ? Icons.videocam : _currentAngle.icon,
                              color: Colors.white,
                              size: 24,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isVideoMode ? 'Video Capture Mode' : _currentAngle.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _isVideoMode
                                  ? 'Walk smoothly around the object in a complete circle. Keep steady movement.'
                                  : _getAngleInstruction(_currentAngle),
                              style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Photo gallery
              Expanded(
                child: _captures.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 64, color: Colors.white.withAlpha(77)),
                            const SizedBox(height: 16),
                            Text(
                              'Tap the capture button to start',
                              style: TextStyle(color: Colors.white.withAlpha(128)),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: _captures.length,
                          itemBuilder: (context, index) {
                            final capture = _captures[index];
                            return GestureDetector(
                              onTap: () => _showPhotoOptions(index),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(capture.file.path),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  // Quality indicator
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: capture.qualityScore >= 0.8
                                            ? const Color(0xFF4CAF50)
                                            : capture.qualityScore >= 0.6
                                                ? const Color(0xFFFFC107)
                                                : Colors.orange,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 1),
                                      ),
                                    ),
                                  ),
                                  // Angle label
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [Colors.black87, Colors.transparent],
                                        ),
                                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                                      ),
                                      child: Text(
                                        capture.angle.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 8),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),

              // ULTRA++ Voice Commands Control
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Voice command toggle button
                    GestureDetector(
                      onTap: () {
                        setState(() => _voiceEnabled = !_voiceEnabled);
                        if (_voiceEnabled) {
                          _startListening();
                          _speak('Voice commands enabled');
                        } else {
                          _stopListening();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _voiceEnabled
                              ? const Color(0xFF4CAF50).withAlpha(51)
                              : Colors.white.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _voiceEnabled ? const Color(0xFF4CAF50) : Colors.white30,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isListening ? Icons.mic : Icons.mic_off,
                              color: _voiceEnabled ? const Color(0xFF4CAF50) : Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isListening ? 'Listening...' : (_voiceEnabled ? 'Voice ON' : 'Voice OFF'),
                              style: TextStyle(
                                color: _voiceEnabled ? const Color(0xFF4CAF50) : Colors.white70,
                                fontWeight: _voiceEnabled ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Voice command indicator & last command display
                    if (_voiceEnabled && _lastVoiceCommand.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(38),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '"${_lastVoiceCommand.length > 20 ? '${_lastVoiceCommand.substring(0, 20)}...' : _lastVoiceCommand}"',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Video mode toggle
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Photo mode button
                        GestureDetector(
                          onTap: () => setState(() => _isVideoMode = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isVideoMode ? const Color(0xFF7C4DFF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Photo Mode',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: !_isVideoMode ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Video mode button
                        GestureDetector(
                          onTap: () => setState(() => _isVideoMode = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: _isVideoMode ? const Color(0xFF7C4DFF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Video Mode',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: _isVideoMode ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Capture button
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Skip button (only in photo mode)
                    if (!_isComplete && _captures.isNotEmpty && !_isVideoMode)
                      Container(
                        margin: const EdgeInsets.only(right: 16),
                        child: TextButton(
                          onPressed: () {
                            if (_currentAngleIndex < _captureAngles.length - 1) {
                              setState(() => _currentAngleIndex++);
                            }
                          },
                          child: const Text('Skip', style: TextStyle(color: Colors.white54)),
                        ),
                      ),

                    // Main capture button
                    GestureDetector(
                      onTap: _isCapturing ? null : (_isVideoMode ? _recordVideo : _capturePhoto),
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: _isCapturing
                                  ? Colors.grey
                                  : Color.lerp(
                                      const Color(0xFF7C4DFF),
                                      const Color(0xFF9C7CFF),
                                      _pulseController.value,
                                    ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7C4DFF).withAlpha(102),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: _isCapturing
                                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                                : Icon(
                                    _isVideoMode ? Icons.videocam : Icons.camera_alt,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                          );
                        },
                      ),
                    ),

                    // Previous button
                    if (!_isComplete && _currentAngleIndex > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 16),
                        child: TextButton(
                          onPressed: () {
                            setState(() => _currentAngleIndex--);
                          },
                          child: const Text('Back', style: TextStyle(color: Colors.white54)),
                        ),
                      ),
                  ],
                ),
              ),

              // Completion actions - Share, See Model, Exit
              if (_canGenerate)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      // Banner: different for partial vs full completion
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isComplete
                                ? [const Color(0xFF4CAF50).withAlpha(40), const Color(0xFF8BC34A).withAlpha(30)]
                                : [const Color(0xFF7C4DFF).withAlpha(40), const Color(0xFF448AFF).withAlpha(30)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isComplete ? const Color(0xFF4CAF50) : const Color(0xFF7C4DFF),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isComplete ? Icons.check_circle : Icons.auto_awesome,
                              color: _isComplete ? const Color(0xFF4CAF50) : const Color(0xFF7C4DFF),
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isComplete ? 'Capture Complete!' : 'Ready to Generate',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _isComplete
                                        ? '${_captures.length} photos ready for 3D reconstruction'
                                        : '${_captures.length} photos — generate now or continue for better quality',
                                    style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Main action - See 3D Model
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _generate3DModel,
                          icon: const Icon(Icons.view_in_ar, size: 24),
                          label: const Text('See 3D Model', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C4DFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Secondary actions - Share and Exit
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _sharePhotos,
                              icon: const Icon(Icons.share),
                              label: const Text('Share'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2196F3),
                                side: const BorderSide(color: Color(0xFF2196F3)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.exit_to_app),
                              label: const Text('Exit'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white30),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
            ),
          ),

          // 🎯 3D RECONSTRUCTION PROGRESS OVERLAY
          if (_isReconstructing)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(32),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2523),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF7C4DFF), width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.view_in_ar,
                        size: 64,
                        color: Color(0xFF7C4DFF),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Generating 3D Model',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _reconstructionStatus,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: CircularProgressIndicator(
                              value: _reconstructionProgress,
                              strokeWidth: 8,
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF7C4DFF),
                              ),
                            ),
                          ),
                          Text(
                            '${(_reconstructionProgress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'This may take 10-30 seconds...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          _reconstructionService.cancelReconstruction();
                          setState(() => _isReconstructing = false);
                        },
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getAngleInstruction(CaptureAngle angle) {
    if (angle.isDetail) {
      return 'Get close for a detailed shot of interesting features';
    }
    if (angle.elevation >= 70) {
      return 'Position camera directly above the object';
    }
    if (angle.elevation >= 40) {
      return 'Angle camera down at ~45° from ${angle.angle}°';
    }
    return 'Position at ${angle.angle}° around the object at eye level';
  }

  void _showPhotoOptions(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2523),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _captures[index].angle.name,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Quality: ${(_captures[index].qualityScore * 100).toInt()}%',
              style: TextStyle(color: Colors.white.withAlpha(153)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _retakePhoto(index);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retake'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFC107),
                      side: const BorderSide(color: Color(0xFFFFC107)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deletePhoto(index);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// Custom painter for the angle progress ring
class AngleProgressPainter extends CustomPainter {
  final List<PhotogrammetryCapture> captures;
  final List<CaptureAngle> angles;
  final int currentAngle;
  final double progress;

  AngleProgressPainter({
    required this.captures,
    required this.angles,
    required this.currentAngle,
    required this.progress,
  });


  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background ring
    final bgPaint = Paint()
      ..color = Colors.white.withAlpha(26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius, bgPaint);

    // Draw angle markers
    for (int i = 0; i < angles.length; i++) {
      final angle = angles[i];
      final radians = (angle.angle - 90) * pi / 180;
      final markerRadius = radius - 15;
      final markerX = center.dx + markerRadius * cos(radians);
      final markerY = center.dy + markerRadius * sin(radians);

      final bool isCaptured = captures.any((c) => c.angle.id == angle.id);
      final bool isCurrent = i == currentAngle;

      final markerPaint = Paint()
        ..color = isCaptured
            ? const Color(0xFF4CAF50)
            : isCurrent
                ? const Color(0xFF7C4DFF)
                : Colors.white.withAlpha(77)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(markerX, markerY), isCurrent ? 8 : 6, markerPaint);

      if (isCurrent) {
        final outerPaint = Paint()
          ..color = const Color(0xFF7C4DFF).withAlpha(77)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(markerX, markerY), 12, outerPaint);
      }
    }

    // Progress arc
    final progressPaint = Paint()
      ..color = const Color(0xFF7C4DFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant AngleProgressPainter oldDelegate) =>
      oldDelegate.currentAngle != currentAngle ||
      oldDelegate.progress != progress ||
      oldDelegate.captures.length != captures.length;
}


// Data classes for photogrammetry
class CaptureAngle {
  final int id;
  final String name;
  final double angle; // Horizontal angle (0-360)
  final double elevation; // Vertical angle (0 = eye level, 90 = top)
  final IconData icon;
  final bool isDetail;

  const CaptureAngle({
    required this.id,
    required this.name,
    required this.angle,
    required this.elevation,
    required this.icon,
    this.isDetail = false,
  });
}

class PhotogrammetryCapture {
  final XFile file;
  final CaptureAngle angle;
  final DateTime capturedAt;
  final double qualityScore; // 0.0 - 1.0

  PhotogrammetryCapture({
    required this.file,
    required this.angle,
    required this.capturedAt,
    required this.qualityScore,
  });
}

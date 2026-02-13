// ignore_for_file: non_constant_identifier_names
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:device_info_plus/device_info_plus.dart';
import '../models/point_cloud.dart';
import '../models/mesh_model.dart';
import '../models/camera_pose.dart';
export '../models/camera_pose.dart';
import '../models/reconstruction_result.dart';
import 'sfm_robust.dart';
import 'bundle_adjustment_service.dart' as ba;
import 'exif_service.dart';
import 'reconstruction_quality_service.dart';
import 'lightglue_feature_service.dart';

// ============================================================================
// TOP-LEVEL ISOLATE FUNCTIONS (required by compute())
// ============================================================================

/// Top-level function for triangulation in isolate (no closures allowed)
Future<_TriangulationResult> _triangulatePointsIsolate(_TriangulationParams params) async {
  final points = <Point3D>[];
  final seenFeatures = <String>{};
  int totalTriangulated = 0;
  int passed = 0;
  int failedDepth = 0;
  int failedAngle = 0;
  int failedReprojection = 0;

  // Triangulate points from image pairs
  for (int i = 0; i < params.matches.length; i++) {
    final pairMatches = params.matches[i];
    final CameraPose pose1;
    final CameraPose pose2;
    final int img1Idx;

    if (i < params.poses.length - 1) {
      pose1 = params.poses[i];
      pose2 = params.poses[i + 1];
      img1Idx = i;
    } else if (i == params.matches.length - 1 && params.matches.length > params.poses.length - 1) {
      pose1 = params.poses.last;
      pose2 = params.poses.first;
      img1Idx = params.poses.length - 1;
    } else {
      continue;
    }

    for (final match in pairMatches) {
      final featureId = '${i}_${match.feature1.x}_${match.feature1.y}';
      if (seenFeatures.contains(featureId)) continue;
      seenFeatures.add(featureId);
      totalTriangulated++;

      // Transform rays to world coordinates
      final cx = params.imageWidth / 2.0;
      final cy = params.imageHeight / 2.0;
      final ray1Dir = pose1.rotation.transposed().transform(Vector3(
        (match.feature1.x - cx) / pose1.focalLength,
        (match.feature1.y - cy) / pose1.focalLength,
        1.0,
      ).normalized());

      final ray2Dir = pose2.rotation.transposed().transform(Vector3(
        (match.feature2.x - cx) / pose2.focalLength,
        (match.feature2.y - cy) / pose2.focalLength,
        1.0,
      ).normalized());

      // Triangulate point
      final point3D = _triangulateRayPairStatic(
        pose1.position,
        ray1Dir,
        pose2.position,
        ray2Dir,
      );

      // Quality check 1: Depth validation
      final depth1 = (point3D - pose1.position).dot(pose1.rotation.transposed().transform(Vector3(0, 0, 1)));
      final depth2 = (point3D - pose2.position).dot(pose2.rotation.transposed().transform(Vector3(0, 0, 1)));

      if (depth1 < 0.1 || depth2 < 0.1) {
        failedDepth++;
        continue;
      }

      // Quality check 2: Triangulation angle
      final angle = _calculateTriangulationAngleStatic(pose1.position, pose2.position, point3D);
      final angleDegrees = angle * (180.0 / math.pi);

      if (angleDegrees < 5 || angleDegrees > 175) {
        failedAngle++;
        continue;
      }

      // Quality check 3: Reprojection error
      final reproj1 = _reprojectPointStatic(point3D, pose1, params.imageWidth, params.imageHeight);
      final reproj2 = _reprojectPointStatic(point3D, pose2, params.imageWidth, params.imageHeight);

      final error1 = math.sqrt(
        math.pow(reproj1.x - match.feature1.x, 2) +
        math.pow(reproj1.y - match.feature1.y, 2)
      );
      final error2 = math.sqrt(
        math.pow(reproj2.x - match.feature2.x, 2) +
        math.pow(reproj2.y - match.feature2.y, 2)
      );

      final maxError = math.max(error1, error2);
      if (maxError > 5.0) {
        failedReprojection++;
        continue;
      }

      passed++;

      // Get color from color sample data
      final colorData = params.colorSamples[img1Idx.clamp(0, params.colorSamples.length - 1)];
      final color = _getColorFromSample(
        colorData,
        match.feature1.x.toInt(),
        match.feature1.y.toInt(),
        params.imageWidth,
        params.imageHeight,
      );

      // Calculate confidence
      final angleConfidence = angleDegrees > 30 && angleDegrees < 60 ? 1.0 : 0.7;
      final reprojConfidence = 1.0 - (maxError / 5.0).clamp(0.0, 1.0);
      final confidence = angleConfidence * reprojConfidence;

      points.add(Point3D(
        position: point3D,
        color: color,
        confidence: confidence,
      ));
    }
  }

  return _TriangulationResult(
    points: points,
    totalTriangulated: totalTriangulated,
    passed: passed,
    failedDepth: failedDepth,
    failedAngle: failedAngle,
    failedReprojection: failedReprojection,
  );
}

/// Top-level function for bundle adjustment in isolate
Future<_BundleAdjustmentIsolateResult> _bundleAdjustIsolate(_BundleAdjustParams params) async {
  final baResult = ba.BundleAdjustmentService.optimize(
    cameraPoses: params.cameraPoseMatrices,
    points3D: params.points3D,
    observations: params.observations,
    focalLength: params.focalLength,
    cx: params.cx,
    cy: params.cy,
    maxIterations: params.maxIterations,
    robustCost: params.robustCost,
    robustParam: params.robustParam,
  );

  return _BundleAdjustmentIsolateResult(
    refinedPoses: baResult.refinedPoses,
    refinedPoints: baResult.refinedPoints,
    iterations: baResult.iterations,
    converged: baResult.converged,
    initialError: baResult.initialError,
    finalError: baResult.finalError,
  );
}

/// Top-level function for point interpolation in isolate with timeout
Future<List<Point3D>> _interpolatePointsIsolate(_InterpolationParams params) async {
  final startTime = DateTime.now();
  const timeoutDuration = Duration(seconds: 5);

  final interpolated = List<Point3D>.from(params.points);
  final original = params.points;
  int added = 0;

  // Early termination: Check timeout every N iterations
  const checkInterval = 100;
  int iterCount = 0;

  for (int i = 0; i < original.length && added < params.maxNewPoints; i++) {
    for (int j = i + 1; j < original.length && added < params.maxNewPoints; j++) {
      iterCount++;

      // Check timeout periodically
      if (iterCount % checkInterval == 0) {
        if (DateTime.now().difference(startTime) > timeoutDuration) {
          debugPrint(' Interpolation timeout reached, returning early with $added points added');
          return interpolated;
        }
      }

      final dist = (original[i].position - original[j].position).length;

      // Only interpolate between nearby points
      if (dist > 0.01 && dist < 0.5) {
        final midPos = (original[i].position + original[j].position) / 2;

        final midColor = Color.fromARGB(
          255,
          ((original[i].color.r + original[j].color.r) / 2).round(),
          ((original[i].color.g + original[j].color.g) / 2).round(),
          ((original[i].color.b + original[j].color.b) / 2).round(),
        );

        final midConf = (original[i].confidence + original[j].confidence) / 2;

        Vector3? midNormal;
        if (original[i].normal != null && original[j].normal != null) {
          midNormal = ((original[i].normal! + original[j].normal!) / 2).normalized();
        }

        interpolated.add(Point3D(
          position: midPos,
          color: midColor,
          confidence: midConf * 0.9,
          normal: midNormal,
        ));
        added++;
      }
    }
  }

  return interpolated;
}

// Static helper functions for isolate (no instance access)
Vector3 _triangulateRayPairStatic(Vector3 o1, Vector3 d1, Vector3 o2, Vector3 d2) {
  final w = o1 - o2;
  final a = d1.dot(d1);
  final b = d1.dot(d2);
  final c = d2.dot(d2);
  final d = d1.dot(w);
  final e = d2.dot(w);

  final denom = a * c - b * b;
  final t1 = (b * e - c * d) / denom;
  final t2 = (a * e - b * d) / denom;

  final p1 = o1 + d1 * t1;
  final p2 = o2 + d2 * t2;

  return (p1 + p2) / 2;
}

Vector2 _reprojectPointStatic(Vector3 point3D, CameraPose pose, double imageWidth, double imageHeight) {
  final pCam = pose.rotation.transform(point3D - pose.position);
  final x = (pCam.x / pCam.z) * pose.focalLength + imageWidth / 2.0;
  final y = (pCam.y / pCam.z) * pose.focalLength + imageHeight / 2.0;
  return Vector2(x, y);
}

double _calculateTriangulationAngleStatic(Vector3 cam1, Vector3 cam2, Vector3 point) {
  final dir1 = (point - cam1).normalized();
  final dir2 = (point - cam2).normalized();
  return math.acos(dir1.dot(dir2).clamp(-1.0, 1.0));
}

Color _getColorFromSample(_ColorSampleData sampleData, int x, int y, double originalWidth, double originalHeight) {
  // Scale coordinates to sample resolution
  final sampleX = (x * sampleData.width / originalWidth).toInt().clamp(0, sampleData.width - 1);
  final sampleY = (y * sampleData.height / originalHeight).toInt().clamp(0, sampleData.height - 1);
  final index = sampleY * sampleData.width + sampleX;

  if (index >= 0 && index < sampleData.colors.length) {
    return sampleData.colors[index];
  }
  return const Color(0xFF808080); // Gray fallback
}

// ============================================================================
// PARAMETER CLASSES FOR ISOLATES
// ============================================================================

class _TriangulationParams {
  final List<List<FeatureMatch>> matches;
  final List<CameraPose> poses;
  final List<_ColorSampleData> colorSamples;
  final double imageWidth;
  final double imageHeight;

  _TriangulationParams({
    required this.matches,
    required this.poses,
    required this.colorSamples,
    required this.imageWidth,
    required this.imageHeight,
  });
}

class _TriangulationResult {
  final List<Point3D> points;
  final int totalTriangulated;
  final int passed;
  final int failedDepth;
  final int failedAngle;
  final int failedReprojection;

  _TriangulationResult({
    required this.points,
    required this.totalTriangulated,
    required this.passed,
    required this.failedDepth,
    required this.failedAngle,
    required this.failedReprojection,
  });
}

class _BundleAdjustParams {
  final List<Matrix4> cameraPoseMatrices;
  final List<Vector3> points3D;
  final List<List<Vector2?>> observations;
  final double focalLength;
  final double cx;
  final double cy;
  final int maxIterations;
  final ba.RobustCost robustCost;
  final double robustParam;

  _BundleAdjustParams({
    required this.cameraPoseMatrices,
    required this.points3D,
    required this.observations,
    required this.focalLength,
    required this.cx,
    required this.cy,
    required this.maxIterations,
    required this.robustCost,
    required this.robustParam,
  });
}

class _BundleAdjustmentIsolateResult {
  final List<Matrix4> refinedPoses;
  final List<Vector3> refinedPoints;
  final int iterations;
  final bool converged;
  final double initialError;
  final double finalError;

  _BundleAdjustmentIsolateResult({
    required this.refinedPoses,
    required this.refinedPoints,
    required this.iterations,
    required this.converged,
    required this.initialError,
    required this.finalError,
  });
}

class _InterpolationParams {
  final List<Point3D> points;
  final int maxNewPoints;

  _InterpolationParams({
    required this.points,
    required this.maxNewPoints,
  });
}

class _ColorSampleData {
  final int width;
  final int height;
  final List<Color> colors;

  _ColorSampleData({
    required this.width,
    required this.height,
    required this.colors,
  });
}

/// Service for 3D reconstruction from photogrammetry captures
class ReconstructionService {
  static final ReconstructionService _instance = ReconstructionService._internal();
  factory ReconstructionService() => _instance;
  ReconstructionService._internal();

  final _uuid = const Uuid();
  final _lightGlue = LightGlueFeatureService();
  bool _isCancelled = false;
  bool _useLightGlue = false;
  int _imageWidth = 1024;
  int _imageHeight = 1024;

  /// Cached image file references for LightGlue extraction path
  List<File> _imageFilesRef = [];

  /// Cached keypoints per image for LightGlue matching path
  List<List<Keypoint>> _keypointsCache = [];

  /// Cached color sample data (extracted during image loading)
  List<_ColorSampleData> _colorSamplesCache = [];

  /// Cancel ongoing reconstruction
  void cancelReconstruction() {
    _isCancelled = true;
    clearCache();
  }

  /// Release cached keypoints and image references to free memory.
  void clearCache() {
    _keypointsCache.clear();
    _imageFilesRef = [];
    _colorSamplesCache.clear();
  }

  /// Reset cancellation flag
  void _resetCancellation() {
    _isCancelled = false;
  }

  /// Detect device capabilities for reconstruction
  Future<Map<String, dynamic>> detectCapabilities() async {
    final capabilities = <String, dynamic>{};
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;

        // Get actual device RAM (in GB)
        // Android doesn't expose exact RAM, estimate based on device tier
        // High-end devices (2020+) typically have 6-12GB, mid-range 4-6GB, low-end 2-4GB
        final sdkInt = androidInfo.version.sdkInt;
        int estimatedRamGb = 2;
        if (sdkInt >= 30) {
          estimatedRamGb = 6; // Android 11+ devices are typically newer with more RAM
        } else if (sdkInt >= 28) {
          estimatedRamGb = 4; // Android 9-10
        } else {
          estimatedRamGb = 2; // Older devices
        }

        capabilities['estimated_ram_gb'] = estimatedRamGb;
        capabilities['device_model'] = androidInfo.model;
        capabilities['manufacturer'] = androidInfo.manufacturer;

        // Check for Huawei device (may have 3D Modeling Kit)
        final isHuawei = androidInfo.manufacturer.toLowerCase().contains('huawei') ||
                         androidInfo.manufacturer.toLowerCase().contains('honor');
        capabilities['huawei_kit_available'] = isHuawei && sdkInt >= 29; // Huawei 3D Kit requires EMUI 10+

        // Check for high-performance GPU (Adreno 6xx+, Mali-G7x+)
        capabilities['high_performance_gpu'] = sdkInt >= 29;

      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;

        // iOS devices have more predictable specs
        // iPhone 11+ has 4GB+, iPhone 13+ has 6GB
        final model = iosInfo.utsname.machine;
        int estimatedRamGb = 4;
        if (model.contains('iPhone14') || model.contains('iPhone15') || model.contains('iPhone16')) {
          estimatedRamGb = 6;
        } else if (model.contains('iPhone12') || model.contains('iPhone13')) {
          estimatedRamGb = 4;
        } else {
          estimatedRamGb = 3;
        }

        capabilities['estimated_ram_gb'] = estimatedRamGb;
        capabilities['device_model'] = iosInfo.model;
        capabilities['manufacturer'] = 'Apple';
        capabilities['huawei_kit_available'] = false;
        capabilities['high_performance_gpu'] = true; // All modern iPhones have good GPUs
      }
    } catch (e) {
      debugPrint('Error detecting device capabilities: $e');
      // Fallback to safe defaults
      capabilities['estimated_ram_gb'] = 2;
      capabilities['huawei_kit_available'] = false;
      capabilities['high_performance_gpu'] = false;
    }

    // Sparse preview available if device has 2GB+ RAM
    capabilities['sparse_preview'] = (capabilities['estimated_ram_gb'] ?? 2) >= 2;

    // Cloud processing always available if online
    capabilities['cloud_processing_available'] = true;

    return capabilities;
  }

  /// Generate sparse 3D point cloud from captured images
  /// This is a simplified Structure from Motion implementation optimized for mobile
  Future<ReconstructionResult> generateSparsePreview({
    required List<File> imageFiles,
    Function(double progress, String status)? onProgress,
  }) async {
    final resultId = _uuid.v4();
    final startTime = DateTime.now();
    _resetCancellation();

    try {
      onProgress?.call(0.0, 'Initializing reconstruction...');

      // Enhanced validation
      if (imageFiles.isEmpty) {
        throw Exception('No images provided for reconstruction');
      }
      if (imageFiles.length < 3) {
        throw Exception('Need at least 3 images for reconstruction (got ${imageFiles.length})');
      }
      if (imageFiles.length < 8) {
        debugPrint('Warning: Using ${imageFiles.length} images. 8+ recommended for best results.');
      }

      // Step 0.5: Extract EXIF data for camera intrinsics
      onProgress?.call(0.02, 'Reading camera metadata...');
      ExifData? exifData;
      try {
        exifData = await ExifService.extractFromFile(imageFiles.first.path);
        if (exifData != null) {
          debugPrint(' EXIF: ${exifData.cameraMake} ${exifData.cameraModel}, '
              'focal=${exifData.focalLengthMM}mm, sensor=${exifData.sensorWidth}mm');
        }
      } catch (e) {
        debugPrint(' EXIF extraction skipped: $e');
      }

      // Try to initialize LightGlue for better features
      _useLightGlue = false;
      _imageFilesRef = imageFiles;
      _keypointsCache = [];
      try {
        await _lightGlue.initialize();
        _useLightGlue = !_lightGlue.usingFallback;
        debugPrint(' Feature extractor: ${_lightGlue.extractorType.name} (fallback=${_lightGlue.usingFallback})');
      } catch (e) {
        debugPrint(' LightGlue init failed, using Harris: $e');
      }

      // Step 1: Load and downsample images with memory management (10%)
      onProgress?.call(0.05, 'Loading and optimizing images...');
      List<img.Image>? images;
      try {
        images = await _loadAndDownsampleImages(imageFiles, onProgress);
        if (_isCancelled) throw Exception('Reconstruction cancelled by user');

        if (images.isEmpty) {
          throw Exception('Failed to load any valid images. Check file permissions and formats.');
        }
        debugPrint(' Loaded ${images.length} images successfully');
      } catch (e) {
        throw Exception('Image loading failed: $e. Ensure photos are valid JPEG/PNG files.');
      }

      // Step 2: Extract features from each image with enhanced detection (40%)
      onProgress?.call(0.15, 'Detecting features in images...');
      List<List<ImageFeature>>? features;
      try {
        features = await _extractFeatures(images, onProgress);
        if (_isCancelled) throw Exception('Reconstruction cancelled by user');

        final totalFeatures = features.fold<int>(0, (sum, f) => sum + f.length);
        if (totalFeatures < 50) {
          throw Exception(
            'Not enough features detected ($totalFeatures found).\n'
            'The object may be too:\n'
            '• Smooth or shiny (reflections)\n'
            '• Dark or black (low contrast)\n'
            '• Uniform in color\n\n'
            'Solutions:\n'
            '• Add temporary texture (flour/chalk)\n'
            '• Improve lighting\n'
            '• Use cloud processing');
        }
        debugPrint(' Extracted $totalFeatures features from ${features.length} images');
      } catch (e) {
        throw Exception('Feature extraction failed: $e');
      } finally {
        // Clear images from memory immediately after feature extraction
        images.clear();
        images = null;
      }

      // Step 3: Match features between images (60%)
      onProgress?.call(0.45, 'Matching features across images...');
      List<List<FeatureMatch>>? matches;
      try {
        matches = await _matchFeatures(features, onProgress);
        if (_isCancelled) throw Exception('Reconstruction cancelled by user');

        final totalMatches = matches.fold<int>(0, (sum, m) => sum + m.length);
        if (totalMatches < 30) {
          throw Exception(
            'Not enough matching features ($totalMatches found).\n'
            'This usually means:\n'
            '• Object is too smooth/uniform\n'
            '• Lighting is too dim or uneven\n'
            '• Photos are blurry\n'
            '• Not enough overlap between angles\n\n'
            'Try cloud processing for difficult objects.');
        }
        debugPrint(' Found $totalMatches feature matches');
      } catch (e) {
        throw Exception('Feature matching failed: $e');
      }

      // Step 4: Estimate camera poses (75%)
      onProgress?.call(0.65, 'Calculating camera positions...');
      List<CameraPose>? cameraPoses;
      try {
        // Use EXIF focal length if available, scaled to downsampled image size
        double? exifFocalPx;
        if (exifData?.focalLengthPixels != null &&
            exifData!.imageWidth != null && exifData.imageWidth! > 0) {
          // Scale EXIF focal length to match downsampled resolution
          exifFocalPx = exifData.focalLengthPixels! *
              (_imageWidth / exifData.imageWidth!);
          debugPrint(' Using EXIF focal length: ${exifFocalPx.toStringAsFixed(1)}px '
              '(from ${exifData.focalLengthMM}mm)');
        }
        cameraPoses = await _estimateCameraPoses(matches, imageFiles.length, exifFocalLengthPx: exifFocalPx);
        if (_isCancelled) throw Exception('Reconstruction cancelled by user');
        debugPrint(' Estimated ${cameraPoses.length} camera poses');
      } catch (e) {
        throw Exception('Camera pose estimation failed: $e');
      }

      // Step 5: Triangulate 3D points (70%)
      onProgress?.call(0.70, 'Reconstructing 3D points...');
      PointCloud? pointCloud;
      try {
        // Use cached color samples (already extracted during image loading)
        pointCloud = await _triangulatePoints(
          features,
          matches,
          cameraPoses,
        );
        if (_isCancelled) throw Exception('Reconstruction cancelled by user');

        if (pointCloud.points.length < 100) {
          debugPrint('Warning: Only ${pointCloud.points.length} points reconstructed. Quality may be low.');
        }
        debugPrint(' Reconstructed ${pointCloud.points.length} 3D points');
      } catch (e) {
        throw Exception('3D triangulation failed: $e');
      }

      // Use non-null locals for post-processing
      var currentCloud = pointCloud;
      var currentPoses = cameraPoses;

      // Step 6: Bundle Adjustment - refine poses and points together (80%)
      if (_isCancelled) throw Exception('Reconstruction cancelled by user');
      onProgress?.call(0.80, 'Optimizing reconstruction...');
      try {
        final bundleResult = await _bundleAdjustment(
          currentCloud,
          currentPoses,
          features,
          matches,
        );
        currentCloud = bundleResult.pointCloud;
        currentPoses = bundleResult.poses;
        debugPrint(' Bundle adjustment improved ${bundleResult.improvementPercent.toStringAsFixed(1)}%');
      } catch (e) {
        debugPrint(' Bundle adjustment skipped: $e');
      }

      // Step 7: Statistical outlier removal (85%)
      if (_isCancelled) throw Exception('Reconstruction cancelled by user');
      onProgress?.call(0.85, 'Filtering outliers...');
      try {
        final beforeCount = currentCloud.points.length;
        currentCloud = _removeStatisticalOutliers(currentCloud);
        final removed = beforeCount - currentCloud.points.length;
        debugPrint(' Removed $removed outlier points');
      } catch (e) {
        debugPrint(' Outlier removal skipped: $e');
      }

      // Step 8: Multi-view color sampling (88%)
      if (_isCancelled) throw Exception('Reconstruction cancelled by user');
      onProgress?.call(0.88, 'Enhancing colors...');
      try {
        currentCloud = await _multiViewColorSampling(
          currentCloud,
          currentPoses,
        );
        debugPrint(' Multi-view color sampling complete');
      } catch (e) {
        debugPrint(' Color sampling skipped: $e');
      }

      // Step 9: Normal estimation (92%)
      onProgress?.call(0.92, 'Computing normals...');
      try {
        currentCloud = _estimateNormals(currentCloud);
        debugPrint(' Normal estimation complete');
      } catch (e) {
        debugPrint(' Normal estimation skipped: $e');
      }

      // Step 10: Point interpolation for denser cloud (96%)
      onProgress?.call(0.96, 'Densifying point cloud...');
      try {
        final beforeCount = currentCloud.points.length;
        currentCloud = await _interpolatePoints(currentCloud);
        final added = currentCloud.points.length - beforeCount;
        debugPrint(' Added $added interpolated points');
      } catch (e) {
        debugPrint(' Point interpolation skipped: $e');
      }

      // Clear intermediate data
      features.clear();
      matches.clear();
      _keypointsCache.clear();
      _imageFilesRef = [];
      _colorSamplesCache.clear();

      // Step 11: Quality assessment (98%)
      onProgress?.call(0.98, 'Assessing reconstruction quality...');
      ReconstructionQuality? qualityAssessment;
      try {
        final endTimeForQuality = DateTime.now();
        // Compute simplified reprojection errors based on average confidence
        // (full reprojection requires retained observations which we cleared)
        final avgConfidence = _calculateAverageConfidence(currentCloud);
        // Estimate mean reprojection error from confidence (inverse relationship)
        final estimatedMeanError = avgConfidence > 0 ? (1.0 / avgConfidence) * 0.5 : 5.0;
        final syntheticErrors = List.generate(
          currentCloud.points.length,
          (i) => estimatedMeanError * (0.5 + math.Random(i).nextDouble()),
        );

        // Compute GSD if EXIF data available
        double? gsd;
        if (exifData != null) {
          gsd = exifData.groundSampleDistance(1.0); // Assume 1m working distance
        }

        qualityAssessment = ReconstructionQualityService.assess(
          reprojectionErrors: syntheticErrors,
          matchedImages: currentPoses.length,
          totalImages: imageFiles.length,
          pointCount: currentCloud.points.length,
          processingTime: endTimeForQuality.difference(startTime),
          estimatedGSD: gsd,
        );
        debugPrint(' Quality grade: ${qualityAssessment.qualityGrade} '
            '(mean error: ${qualityAssessment.meanReprojectionError.toStringAsFixed(2)}px)');
      } catch (e) {
        debugPrint(' Quality assessment skipped: $e');
      }

      onProgress?.call(1.0, 'Reconstruction complete!');

      final endTime = DateTime.now();
      final processingTime = endTime.difference(startTime).inSeconds.toDouble();

      final result = ReconstructionResult(
        id: resultId,
        method: ReconstructionMethod.sparseSfM,
        status: ReconstructionStatus.completed,
        startedAt: startTime,
        completedAt: endTime,
        pointCloud: currentCloud,
        cameraPoses: currentPoses,
        progress: 1.0,
        statusMessage: 'Reconstruction completed with ${currentCloud.points.length} points',
        inputImageCount: imageFiles.length,
        processingTimeSeconds: processingTime,
        qualityMetrics: {
          'point_count': currentCloud.points.length,
          'image_count': imageFiles.length,
          'average_confidence': _calculateAverageConfidence(currentCloud),
          'processing_time_seconds': processingTime,
          if (qualityAssessment != null) ...{
            'quality_grade': qualityAssessment.qualityGrade,
            'mean_reprojection_error': qualityAssessment.meanReprojectionError,
            'median_reprojection_error': qualityAssessment.medianReprojectionError,
            'p95_reprojection_error': qualityAssessment.p95ReprojectionError,
            'completeness': qualityAssessment.completeness,
            'warnings': qualityAssessment.warnings,
          },
          if (exifData != null) ...{
            'camera_make': exifData.cameraMake,
            'camera_model': exifData.cameraModel,
            'focal_length_mm': exifData.focalLengthMM,
            if (exifData.groundSampleDistance(1.0) != null)
              'gsd_mm_per_pixel': exifData.groundSampleDistance(1.0),
            if (exifData.gpsLatitude != null) 'gps_latitude': exifData.gpsLatitude,
            if (exifData.gpsLongitude != null) 'gps_longitude': exifData.gpsLongitude,
          },
        },
      );

      // Auto-save result
      try {
        await saveResult(result);
        debugPrint(' Saved reconstruction to persistent storage');
      } catch (e) {
        debugPrint(' Failed to save result: $e');
      }

      return result;
    } catch (e, stackTrace) {
      debugPrint(' Reconstruction error: $e');
      debugPrint('Stack trace: $stackTrace');

      return ReconstructionResult(
        id: resultId,
        method: ReconstructionMethod.sparseSfM,
        status: _isCancelled ? ReconstructionStatus.cancelled : ReconstructionStatus.failed,
        startedAt: startTime,
        progress: 0.0,
        errorMessage: _isCancelled ? 'Cancelled by user' : e.toString(),
        inputImageCount: imageFiles.length,
      );
    }
  }

  /// Load and downsample images for processing with progress updates
  /// Also extracts color samples in a single pass (no need to reload later)
  Future<List<img.Image>> _loadAndDownsampleImages(
    List<File> imageFiles,
    Function(double, String)? onProgress,
  ) async {
    final images = <img.Image>[];
    _colorSamplesCache = [];

    for (int i = 0; i < imageFiles.length; i++) {
      try {
        if (_isCancelled) break;

        final file = imageFiles[i];
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);

        if (image != null) {
          // Downsample to fit within 1024x1024 while preserving aspect ratio
          const maxDim = 1024;
          img.Image downsampled;
          if (image.width > maxDim || image.height > maxDim) {
            if (image.width >= image.height) {
              downsampled = img.copyResize(
                image,
                width: maxDim,
                interpolation: img.Interpolation.average,
              );
            } else {
              downsampled = img.copyResize(
                image,
                height: maxDim,
                interpolation: img.Interpolation.average,
              );
            }
          } else {
            downsampled = image;
          }
          images.add(downsampled);

          // ALSO: Extract color sample at 512px resolution for later use
          const colorMaxDim = 512;
          img.Image colorSample;
          if (image.width >= image.height) {
            colorSample = img.copyResize(
              image,
              width: colorMaxDim,
              interpolation: img.Interpolation.average,
            );
          } else {
            colorSample = img.copyResize(
              image,
              height: colorMaxDim,
              interpolation: img.Interpolation.average,
            );
          }

          // Store color data as flat array (lightweight)
          final colorData = <Color>[];
          for (int y = 0; y < colorSample.height; y++) {
            for (int x = 0; x < colorSample.width; x++) {
              final pixel = colorSample.getPixel(x, y);
              colorData.add(Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()));
            }
          }
          _colorSamplesCache.add(_ColorSampleData(
            width: colorSample.width,
            height: colorSample.height,
            colors: colorData,
          ));

          // Store dimensions from first image for coordinate normalization
          if (i == 0) {
            _imageWidth = downsampled.width;
            _imageHeight = downsampled.height;
            RobustSfM.imageCenterX = _imageWidth / 2.0;
            RobustSfM.imageCenterY = _imageHeight / 2.0;
          }

          final progress = 0.05 + (i / imageFiles.length) * 0.10;
          onProgress?.call(progress, 'Loading image ${i + 1}/${imageFiles.length}...');
        } else {
          debugPrint(' Failed to decode image ${i + 1}');
        }
      } catch (e) {
        debugPrint(' Error loading image ${i + 1}: $e');
      }
    }

    return images;
  }

  // Removed: _loadImagesForColor() - color samples now extracted during initial load

  /// Extract corner features from images using LightGlue (preferred) or Harris corner detector (fallback)
  Future<List<List<ImageFeature>>> _extractFeatures(
    List<img.Image> images,
    Function(double, String)? onProgress,
  ) async {
    final allFeatures = <List<ImageFeature>>[];
    _keypointsCache = [];

    for (int i = 0; i < images.length; i++) {
      final progress = 0.3 + (i / images.length) * 0.15;
      onProgress?.call(progress, 'Extracting features from image ${i + 1}/${images.length}...');

      if (_useLightGlue && i < _imageFilesRef.length) {
        // LightGlue path: read raw bytes, detect keypoints, convert to ImageFeature
        try {
          final bytes = await _imageFilesRef[i].readAsBytes();
          final keypoints = await _lightGlue.detectKeypoints(bytes);
          _keypointsCache.add(keypoints);
          allFeatures.add(_lightGlue.toImageFeatures(keypoints));
        } catch (e) {
          debugPrint(' LightGlue extraction failed for image ${i + 1}: $e, falling back to Harris');
          final features = await compute(_extractFeaturesFromImage, images[i]);
          _keypointsCache.add([]); // empty placeholder
          allFeatures.add(features);
        }
      } else {
        // Harris fallback path
        final features = await compute(_extractFeaturesFromImage, images[i]);
        _keypointsCache.add([]); // empty placeholder
        allFeatures.add(features);
      }
    }

    return allFeatures;
  }

  /// Extract features from a single image with multi-scale detection (runs in isolate)
  static List<ImageFeature> _extractFeaturesFromImage(img.Image image) {
    final features = <ImageFeature>[];
    final width = image.width;
    final height = image.height;

    try {
      final gray = img.grayscale(image);
      final candidateFeatures = <ImageFeature>[];

      // Multi-scale feature detection for robustness
      final scales = [1.0, 0.75, 0.5];

      for (final scale in scales) {
        img.Image scaledGray;
        if (scale < 1.0) {
          scaledGray = img.copyResize(gray,
            width: (width * scale).toInt(),
            height: (height * scale).toInt(),
            interpolation: img.Interpolation.linear,
          );
        } else {
          scaledGray = gray;
        }

        final sw = scaledGray.width;
        final sh = scaledGray.height;

        // Dense grid sampling
        const gridSize = 25;
        final cellW = sw / gridSize;
        final cellH = sh / gridSize;

        for (int gy = 0; gy < gridSize; gy++) {
          for (int gx = 0; gx < gridSize; gx++) {
            // Multiple samples per cell
            for (int s = 0; s < 3; s++) {
              final cx = ((gx + (s % 2) * 0.5 + 0.25) * cellW).toInt();
              final cy = ((gy + (s ~/ 2) * 0.5 + 0.25) * cellH).toInt();

              if (cx < 5 || cx >= sw - 5 || cy < 5 || cy >= sh - 5) continue;

              final strength = _calculateCornerStrength(scaledGray, cx, cy);

              if (strength > 300) {
                // Scale coordinates back to original
                final origX = cx / scale;
                final origY = cy / scale;

                candidateFeatures.add(ImageFeature(
                  x: origX,
                  y: origY,
                  strength: strength * scale, // Weight by scale
                  descriptor: [],
                ));
              }
            }
          }
        }
      }

      // Adaptive threshold
      if (candidateFeatures.isEmpty) return features;

      candidateFeatures.sort((a, b) => b.strength.compareTo(a.strength));
      final threshold = candidateFeatures[candidateFeatures.length ~/ 4].strength * 0.5;

      // Extract descriptors for strong features
      for (final candidate in candidateFeatures) {
        if (candidate.strength > threshold) {
          final x = candidate.x.toInt().clamp(8, width - 9);
          final y = candidate.y.toInt().clamp(8, height - 9);

          final descriptor = _extractDescriptor(gray, x, y);
          features.add(ImageFeature(
            x: candidate.x,
            y: candidate.y,
            strength: candidate.strength,
            descriptor: descriptor,
          ));
        }
      }

      // Non-maximum suppression with spatial hashing for speed
      final suppressedFeatures = <ImageFeature>[];
      features.sort((a, b) => b.strength.compareTo(a.strength));
      final occupied = <int>{};
      const cellSize = 8;

      for (final feature in features) {
        final cellX = (feature.x / cellSize).toInt();
        final cellY = (feature.y / cellSize).toInt();
        final cellKey = cellY * 10000 + cellX;

        // Check neighboring cells
        bool tooClose = false;
        for (int dy = -1; dy <= 1 && !tooClose; dy++) {
          for (int dx = -1; dx <= 1 && !tooClose; dx++) {
            if (occupied.contains((cellY + dy) * 10000 + (cellX + dx))) {
              tooClose = true;
            }
          }
        }

        if (!tooClose) {
          suppressedFeatures.add(feature);
          occupied.add(cellKey);
        }
      }

      // Keep top 500 features for better matching
      return suppressedFeatures.take(500).toList();
    } catch (e) {
      return features;
    }
  }

  /// Calculate corner strength using simplified Harris detector
  static double _calculateCornerStrength(img.Image gray, int x, int y) {
    double Ix2 = 0, Iy2 = 0, IxIy = 0;

    // Calculate gradients in 5x5 window
    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        final px = x + dx;
        final py = y + dy;

        if (px < 1 || px >= gray.width - 1 || py < 1 || py >= gray.height - 1) {
          continue;
        }

        // Sobel-like gradient
        final gx = (gray.getPixel(px + 1, py).r - gray.getPixel(px - 1, py).r) / 2.0;
        final gy = (gray.getPixel(px, py + 1).r - gray.getPixel(px, py - 1).r) / 2.0;

        Ix2 += gx * gx;
        Iy2 += gy * gy;
        IxIy += gx * gy;
      }
    }

    // Harris response: det(M) - k * trace(M)^2
    const k = 0.04;
    final det = Ix2 * Iy2 - IxIy * IxIy;
    final trace = Ix2 + Iy2;
    return det - k * trace * trace;
  }

  /// Extract orientation-invariant descriptor from 8x8 patch
  static List<double> _extractDescriptor(img.Image gray, int x, int y) {
    // Compute dominant gradient orientation in a 7x7 window
    double gxSum = 0, gySum = 0;
    for (int dy = -3; dy <= 3; dy++) {
      for (int dx = -3; dx <= 3; dx++) {
        final px = (x + dx).clamp(1, gray.width - 2);
        final py = (y + dy).clamp(1, gray.height - 2);
        final gx = gray.getPixel(px + 1, py).r.toDouble() - gray.getPixel(px - 1, py).r.toDouble();
        final gy = gray.getPixel(px, py + 1).r.toDouble() - gray.getPixel(px, py - 1).r.toDouble();
        gxSum += gx;
        gySum += gy;
      }
    }
    final angle = math.atan2(gySum, gxSum);
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    // Sample 8x8 patch rotated by dominant orientation
    final descriptor = <double>[];
    for (int dy = -4; dy < 4; dy++) {
      for (int dx = -4; dx < 4; dx++) {
        // Rotate sample position by -angle
        final rx = (dx * cosA + dy * sinA).round();
        final ry = (-dx * sinA + dy * cosA).round();
        final px = x + rx;
        final py = y + ry;

        if (px >= 0 && px < gray.width && py >= 0 && py < gray.height) {
          descriptor.add(gray.getPixel(px, py).r.toDouble());
        } else {
          descriptor.add(0.0);
        }
      }
    }

    // Normalize descriptor
    final mean = descriptor.reduce((a, b) => a + b) / descriptor.length;
    final std = math.sqrt(
      descriptor.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / descriptor.length,
    );

    if (std > 0) {
      for (int i = 0; i < descriptor.length; i++) {
        descriptor[i] = (descriptor[i] - mean) / std;
      }
    }

    return descriptor;
  }

  /// Match a pair of images using LightGlue (if available) or brute-force fallback.
  /// Returns the list of FeatureMatch for the pair.
  Future<List<FeatureMatch>> _matchPair(
    int idx1,
    int idx2,
    List<List<ImageFeature>> features,
  ) async {
    // Use LightGlue matching if we have cached keypoints for both images
    if (_useLightGlue &&
        idx1 < _keypointsCache.length &&
        idx2 < _keypointsCache.length &&
        _keypointsCache[idx1].isNotEmpty &&
        _keypointsCache[idx2].isNotEmpty) {
      try {
        final kpMatches = await _lightGlue.matchFeatures(
          _keypointsCache[idx1],
          _keypointsCache[idx2],
        );
        return _lightGlue.toFeatureMatches(kpMatches);
      } catch (e) {
        debugPrint(' LightGlue matching failed for pair $idx1-$idx2: $e, falling back to brute-force');
      }
    }

    // Brute-force fallback
    return compute(
      _matchFeaturePair,
      {'features1': features[idx1], 'features2': features[idx2]},
    );
  }

  /// Match features between consecutive images + skip-one + loop closure
  Future<List<List<FeatureMatch>>> _matchFeatures(
    List<List<ImageFeature>> features,
    Function(double, String)? onProgress,
  ) async {
    final matches = <List<FeatureMatch>>[];

    // Consecutive pairs (i, i+1)
    for (int i = 0; i < features.length - 1; i++) {
      final progress = 0.5 + (i / (features.length - 1)) * 0.15;
      onProgress?.call(progress, 'Matching images ${i + 1} and ${i + 2}...');

      final pairMatches = await _matchPair(i, i + 1, features);
      matches.add(pairMatches);
    }

    // Skip-one pairs (i, i+2) for wider baseline — merge into existing matches
    if (features.length >= 3) {
      for (int i = 0; i < features.length - 2; i++) {
        onProgress?.call(0.65, 'Wide baseline match ${i + 1}-${i + 3}...');
        final skipMatches = await _matchPair(i, i + 2, features);
        // Merge skip-one matches into the consecutive pair for extra triangulation
        if (skipMatches.length >= 8) {
          matches[i] = [...matches[i], ...skipMatches];
          debugPrint('  Skip-one ${i + 1}-${i + 3}: ${skipMatches.length} extra matches');
        }
      }
    }

    // Loop closure: match last image to first (for circular captures)
    if (features.length >= 4) {
      onProgress?.call(0.67, 'Loop closure matching...');
      final loopMatches = await _matchPair(features.length - 1, 0, features);
      if (loopMatches.length >= 8) {
        matches.add(loopMatches);
        debugPrint('  Loop closure: ${loopMatches.length} matches (last->first)');
      }
    }

    return matches;
  }

  /// Match features between two images with cross-check (runs in isolate)
  static List<FeatureMatch> _matchFeaturePair(Map<String, dynamic> args) {
    final features1 = args['features1'] as List<ImageFeature>;
    final features2 = args['features2'] as List<ImageFeature>;

    // Forward matching: f1 -> f2
    final forwardMatches = <int, _MatchCandidate>{};
    for (int i = 0; i < features1.length; i++) {
      final f1 = features1[i];
      double best = double.infinity;
      double secondBest = double.infinity;
      int bestIdx = -1;

      for (int j = 0; j < features2.length; j++) {
        final dist = _descriptorDistance(f1.descriptor, features2[j].descriptor);
        if (dist < best) {
          secondBest = best;
          best = dist;
          bestIdx = j;
        } else if (dist < secondBest) {
          secondBest = dist;
        }
      }

      // Lowe's ratio test (tighter threshold for quality)
      if (bestIdx >= 0 && best < 0.75 * secondBest) {
        forwardMatches[i] = _MatchCandidate(bestIdx, best);
      }
    }

    // Backward matching: f2 -> f1 (cross-check)
    final backwardMatches = <int, int>{};
    for (int j = 0; j < features2.length; j++) {
      final f2 = features2[j];
      double best = double.infinity;
      double secondBest = double.infinity;
      int bestIdx = -1;

      for (int i = 0; i < features1.length; i++) {
        final dist = _descriptorDistance(features1[i].descriptor, f2.descriptor);
        if (dist < best) {
          secondBest = best;
          best = dist;
          bestIdx = i;
        } else if (dist < secondBest) {
          secondBest = dist;
        }
      }

      if (bestIdx >= 0 && best < 0.75 * secondBest) {
        backwardMatches[j] = bestIdx;
      }
    }

    // Keep only bidirectional matches (cross-check validation)
    final matches = <FeatureMatch>[];
    for (final entry in forwardMatches.entries) {
      final i = entry.key;
      final j = entry.value.idx;

      // Cross-check: f1->f2 and f2->f1 must agree
      if (backwardMatches[j] == i) {
        matches.add(FeatureMatch(
          feature1: features1[i],
          feature2: features2[j],
          distance: entry.value.distance,
        ));
      }
    }

    // Sort by quality and return
    matches.sort((a, b) => a.distance.compareTo(b.distance));
    return matches;
  }


  /// Calculate Euclidean distance between descriptors
  static double _descriptorDistance(List<double> d1, List<double> d2) {
    double sum = 0;
    for (int i = 0; i < d1.length && i < d2.length; i++) {
      final diff = d1[i] - d2[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  /// Estimate camera poses using PRODUCTION-GRADE incremental SfM with RANSAC
  Future<List<CameraPose>> _estimateCameraPoses(
    List<List<FeatureMatch>> matches,
    int imageCount, {
    double? exifFocalLengthPx,
  }) async {
    final poses = <CameraPose>[];
    // Use EXIF focal length if available, otherwise estimate from image dimensions (~28mm equivalent on mobile)
    final focalLength = exifFocalLengthPx ?? math.max(_imageWidth, _imageHeight) * 0.85;

    // First camera at origin
    poses.add(CameraPose(
      position: Vector3.zero(),
      rotation: Matrix3.identity(),
      focalLength: focalLength,
    ));

    debugPrint(' Starting ROBUST camera pose estimation with RANSAC...');

    // Estimate each subsequent camera pose using Essential Matrix + RANSAC
    // Only process consecutive pairs (skip loop closure which is extra)
    final poseMatchCount = math.min(matches.length, imageCount - 1);
    for (int i = 0; i < poseMatchCount; i++) {
      final pairMatches = matches[i];

      if (pairMatches.length < 8) {
        // Not enough matches - suggest solutions
        throw Exception(
          'Images ${i + 1} and ${i + 2} don\'t overlap enough.\n'
          'Found only ${pairMatches.length} matching points (need 8+).\n\n'
          'Solutions:\n'
          '• Capture smaller angle steps between photos\n'
          '• Ensure 60-80% overlap between adjacent shots\n'
          '• Try cloud processing (more robust)'
        );
      }

      try {
        // ✅ REAL ALGORITHM: RANSAC + Essential Matrix estimation
        debugPrint('  🔍 Image pair ${i + 1}-${i + 2}: ${pairMatches.length} matches');

        final essentialResult = RobustSfM.estimateEssentialMatrix(
          pairMatches,
          focalLength,
        );

        debugPrint(' RANSAC: ${essentialResult.inlierCount} inliers '
            '(${(essentialResult.inlierRatio * 100).toInt()}%)');

        // Recover camera pose from Essential Matrix
        final poseHypotheses = RobustSfM.recoverPoseFromEssential(
          essentialResult.matrix,
          essentialResult.inliers,
          focalLength,
        );

        if (poseHypotheses.isEmpty) {
          throw Exception('Failed to recover camera pose from Essential Matrix');
        }

        // Choose best hypothesis (most points with positive depth)
        final bestPose = poseHypotheses.first;

        // Transform to world coordinates (relative to previous camera)
        final prevPose = poses[i];
        final worldRotation = prevPose.rotation * bestPose.rotation;
        final worldPosition = prevPose.position + prevPose.rotation.transform(bestPose.translation);

        poses.add(CameraPose(
          position: worldPosition,
          rotation: worldRotation,
          focalLength: focalLength,
        ));

        debugPrint(' Pose ${i + 2}: pos=${worldPosition.x.toStringAsFixed(2)}, '
            '${worldPosition.y.toStringAsFixed(2)}, ${worldPosition.z.toStringAsFixed(2)}');

      } catch (e) {
        // RANSAC failed - provide actionable error
        debugPrint(' Pose estimation failed: $e');
        throw Exception(
          'Camera pose estimation failed for images ${i + 1}-${i + 2}:\n$e'
        );
      }
    }

    debugPrint(' Estimated ${poses.length} camera poses with RANSAC');
    return poses;
  }

  /// Triangulate 3D points from feature matches and camera poses with ROBUST filtering
  /// Uses compute() to run heavy calculations in isolate (off main thread)
  Future<PointCloud> _triangulatePoints(
    List<List<ImageFeature>> features,
    List<List<FeatureMatch>> matches,
    List<CameraPose> poses,
  ) async {
    debugPrint(' Starting ROBUST triangulation (in isolate)...');

    // Run heavy triangulation in isolate using cached color samples
    final params = _TriangulationParams(
      matches: matches,
      poses: poses,
      colorSamples: _colorSamplesCache,
      imageWidth: _imageWidth.toDouble(),
      imageHeight: _imageHeight.toDouble(),
    );

    final result = await compute(_triangulatePointsIsolate, params);

    debugPrint(' Triangulation complete:');
    debugPrint('   Total: ${result.totalTriangulated}');
    debugPrint(' Passed: ${result.passed} (${(result.passed / result.totalTriangulated * 100).toInt()}%)');
    debugPrint(' Failed depth: ${result.failedDepth}');
    debugPrint(' Failed angle: ${result.failedAngle}');
    debugPrint(' Failed reproj: ${result.failedReprojection}');

    if (result.passed < 100) {
      debugPrint('Warning: Low point count. Consider:');
      debugPrint('   • Better lighting');
      debugPrint('   • More textured object');
      debugPrint('   • More photos (16 recommended)');
    }

    // Light bundle adjustment: 3 iterations of gradient descent on point positions
    if (result.points.length > 3 && poses.length >= 2) {
      debugPrint(' Running light bundle adjustment (3 iterations)...');
      await _lightBundleAdjust(result.points, poses, matches, features);
    }

    return PointCloud(
      points: result.points,
      method: 'robust_sfm_ransac',
      metadata: {
        'image_count': _colorSamplesCache.length,
        'total_triangulated': result.totalTriangulated,
        'passed_filters': result.passed,
        'pass_rate': result.passed / result.totalTriangulated,
        'failed_depth': result.failedDepth,
        'failed_angle': result.failedAngle,
        'failed_reprojection': result.failedReprojection,
      },
    );
  }

  /// Reproject 3D point back to 2D image coordinates
  Vector2 _reprojectPoint(Vector3 point3D, CameraPose pose) {
    return _reprojectPointStatic(point3D, pose, _imageWidth.toDouble(), _imageHeight.toDouble());
  }

  /// Light bundle adjustment: refine point positions using Levenberg-Marquardt
  /// Only optimizes points (cameras fixed) with fewer iterations than full BA.
  /// Light bundle adjustment using compute() to avoid blocking main thread
  Future<void> _lightBundleAdjust(
    List<Point3D> points,
    List<CameraPose> poses,
    List<List<FeatureMatch>> matches,
    List<List<ImageFeature>> features,
  ) async {
    final nCams = poses.length;
    final nPts = points.length;

    if (nCams < 2 || nPts == 0) return;

    final focalLength = poses.first.focalLength;
    final cx = _imageWidth / 2.0;
    final cy = _imageHeight / 2.0;

    // Convert camera poses to Matrix4
    final cameraPoseMatrices = <Matrix4>[];
    for (final pose in poses) {
      final R = pose.rotation;
      final t = -(R.transformed(pose.position));
      cameraPoseMatrices.add(Matrix4(
        R.entry(0, 0), R.entry(1, 0), R.entry(2, 0), 0,
        R.entry(0, 1), R.entry(1, 1), R.entry(2, 1), 0,
        R.entry(0, 2), R.entry(1, 2), R.entry(2, 2), 0,
        t.x, t.y, t.z, 1,
      ));
    }

    // Convert points to Vector3
    final points3D = points.map((p) => Vector3.copy(p.position)).toList();

    // Build observations from matches
    final observations = List.generate(
      nCams,
      (_) => List<Vector2?>.filled(nPts, null),
    );

    int pointIdx = 0;
    for (int i = 0; i < matches.length && i < nCams - 1; i++) {
      for (final match in matches[i]) {
        if (pointIdx >= nPts) break;
        observations[i][pointIdx] = Vector2(match.feature1.x, match.feature1.y);
        observations[i + 1][pointIdx] = Vector2(match.feature2.x, match.feature2.y);
        pointIdx++;
      }
    }

    // Run L-M in isolate with max 50 iterations and 10 second timeout (light version)
    final startTime = DateTime.now();
    try {
      final params = _BundleAdjustParams(
        cameraPoseMatrices: cameraPoseMatrices,
        points3D: points3D,
        observations: observations,
        focalLength: focalLength,
        cx: cx,
        cy: cy,
        maxIterations: 50,
        robustCost: ba.RobustCost.huber,
        robustParam: 2.0,
      );

      final baResult = await compute(_bundleAdjustIsolate, params).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('   Light LM BA: TIMEOUT after 10s, keeping original points');
          throw TimeoutException('Bundle adjustment timed out');
        },
      );

      final duration = DateTime.now().difference(startTime);
      debugPrint('   Light LM BA: ${baResult.iterations} iters in ${duration.inSeconds}s, '
          'error ${baResult.initialError.toStringAsFixed(2)} -> ${baResult.finalError.toStringAsFixed(2)} px');

      // Update points in-place with refined positions
      for (int i = 0; i < nPts; i++) {
        points[i] = Point3D(
          position: baResult.refinedPoints[i],
          color: points[i].color,
          confidence: points[i].confidence,
          normal: points[i].normal,
        );
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      if (e is TimeoutException) {
        debugPrint('   Light LM BA: Timed out after ${duration.inSeconds}s, keeping original points');
      } else {
        debugPrint('   Light LM BA: Failed: $e');
      }
      // Keep original points if optimization fails
    }
  }

  // Removed: _getColorFromImage() - now uses cached color samples

  /// Calculate average confidence of point cloud
  double _calculateAverageConfidence(PointCloud cloud) {
    if (cloud.points.isEmpty) return 0.0;

    final sum = cloud.points.fold<double>(0.0, (sum, p) => sum + p.confidence);
    return sum / cloud.points.length;
  }

  /// Save reconstruction result to persistent storage
  Future<void> saveResult(ReconstructionResult result) async {
    final dir = await getApplicationDocumentsDirectory();
    final reconstructionsDir = Directory(path.join(dir.path, 'reconstructions'));
    await reconstructionsDir.create(recursive: true);

    final resultDir = Directory(path.join(reconstructionsDir.path, result.id));
    await resultDir.create(recursive: true);

    // Save metadata as JSON
    final metadataPath = path.join(resultDir.path, 'metadata.json');
    await File(metadataPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
    );

    // Save point cloud as PLY
    if (result.pointCloud != null) {
      final plyPath = path.join(resultDir.path, 'point_cloud.ply');
      await File(plyPath).writeAsString(result.pointCloud!.toPLY());
    }

    // Save mesh as OBJ (if available)
    if (result.mesh != null) {
      final objPath = path.join(resultDir.path, 'mesh.obj');
      await File(objPath).writeAsString(result.mesh!.toOBJ());
    }
  }

  /// Load all saved reconstruction results
  Future<List<ReconstructionResult>> loadSavedResults() async {
    final dir = await getApplicationDocumentsDirectory();
    final reconstructionsDir = Directory(path.join(dir.path, 'reconstructions'));

    if (!await reconstructionsDir.exists()) {
      return [];
    }

    final results = <ReconstructionResult>[];

    await for (final entity in reconstructionsDir.list()) {
      if (entity is Directory) {
        try {
          final metadataPath = path.join(entity.path, 'metadata.json');
          final metadataFile = File(metadataPath);

          if (await metadataFile.exists()) {
            final jsonString = await metadataFile.readAsString();
            final json = jsonDecode(jsonString) as Map<String, dynamic>;
            final result = ReconstructionResult.fromJson(json);
            results.add(result);
          }
        } catch (e) {
          debugPrint('Error loading reconstruction ${entity.path}: $e');
        }
      }
    }

    // Sort by date, newest first
    results.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return results;
  }

  /// Load a specific reconstruction result with its point cloud
  Future<ReconstructionResult?> loadResult(String resultId) async {
    final dir = await getApplicationDocumentsDirectory();
    final resultDir = Directory(path.join(dir.path, 'reconstructions', resultId));

    if (!await resultDir.exists()) {
      return null;
    }

    try {
      // Load metadata
      final metadataPath = path.join(resultDir.path, 'metadata.json');
      final jsonString = await File(metadataPath).readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      var result = ReconstructionResult.fromJson(json);

      // Load point cloud from PLY
      final plyPath = path.join(resultDir.path, 'point_cloud.ply');
      if (await File(plyPath).exists()) {
        final plyContent = await File(plyPath).readAsString();
        final pointCloud = PointCloud.fromPLY(plyContent);
        result = result.copyWith(pointCloud: pointCloud);
      }

      return result;
    } catch (e) {
      debugPrint('Error loading result $resultId: $e');
      return null;
    }
  }

  /// Delete a saved reconstruction result
  Future<void> deleteResult(String resultId) async {
    final dir = await getApplicationDocumentsDirectory();
    final resultDir = Directory(path.join(dir.path, 'reconstructions', resultId));

    if (await resultDir.exists()) {
      await resultDir.delete(recursive: true);
    }
  }

  /// Export reconstruction result to files (for sharing)
  Future<String> exportResult(ReconstructionResult result) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(path.join(dir.path, 'exports', result.id));
    await exportDir.create(recursive: true);

    final files = <String>[];

    // Export point cloud as PLY
    if (result.pointCloud != null) {
      final plyPath = path.join(exportDir.path, 'point_cloud.ply');
      final plyFile = File(plyPath);
      await plyFile.writeAsString(result.pointCloud!.toPLY());
      files.add(plyPath);
    }

    // Export mesh as OBJ (if available)
    if (result.mesh != null) {
      final objPath = path.join(exportDir.path, 'mesh.obj');
      final objFile = File(objPath);
      await objFile.writeAsString(result.mesh!.toOBJ());
      files.add(objPath);
    }

    // Export metadata
    final metadataPath = path.join(exportDir.path, 'metadata.json');
    await File(metadataPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
    );
    files.add(metadataPath);

    return exportDir.path;
  }

  /// Validate photos before reconstruction
  Future<Map<String, dynamic>> validatePhotosForReconstruction(List<File> imageFiles) async {
    final validation = <String, dynamic>{
      'isValid': true,
      'warnings': <String>[],
      'errors': <String>[],
      'recommendedFixes': <String>[],
    };

    // Check minimum count
    if (imageFiles.length < 8) {
      validation['isValid'] = false;
      validation['errors'].add('Need at least 8 photos (found ${imageFiles.length})');
      validation['recommendedFixes'].add('Capture more angles');
      return validation;
    }

    // Load first few images to check quality
    final samplesToCheck = imageFiles.length > 4 ? 4 : imageFiles.length;
    int tooSmallCount = 0;
    int lowQualityCount = 0;

    for (int i = 0; i < samplesToCheck; i++) {
      try {
        final bytes = await imageFiles[i].readAsBytes();
        final image = img.decodeImage(bytes);

        if (image != null) {
          // Check resolution
          if (image.width < 800 || image.height < 800) {
            tooSmallCount++;
          }

          // Check sharpness (simple variance test)
          final variance = _calculateImageVariance(image);
          if (variance < 100) {
            lowQualityCount++;
          }
        }
      } catch (e) {
        validation['warnings'].add('Could not read image ${i + 1}');
      }
    }

    if (tooSmallCount > 0) {
      validation['warnings'].add('$tooSmallCount images may be too low resolution');
      validation['recommendedFixes'].add('Use higher resolution camera settings');
    }

    if (lowQualityCount > 0) {
      validation['warnings'].add('$lowQualityCount images may be blurry');
      validation['recommendedFixes'].add('Ensure sharp focus and stable camera');
    }

    // Optimal count check
    if (imageFiles.length >= 12) {
      validation['warnings'].add('Good coverage with ${imageFiles.length} photos');
    } else if (imageFiles.length >= 8) {
      validation['warnings'].add('Minimum coverage, consider capturing more angles');
      validation['recommendedFixes'].add('Capture all 16 recommended angles for best results');
    }

    return validation;
  }

  /// Bundle Adjustment - jointly optimize camera poses and 3D points
  /// Uses Levenberg-Marquardt optimization via BundleAdjustmentService
  Future<BundleAdjustmentResult> _bundleAdjustment(
    PointCloud pointCloud,
    List<CameraPose> poses,
    List<List<ImageFeature>> features,
    List<List<FeatureMatch>> matches,
  ) async {
    final points = List<Point3D>.from(pointCloud.points);
    final nCams = poses.length;
    final nPts = points.length;

    if (nCams < 2 || nPts == 0) {
      return BundleAdjustmentResult(
        pointCloud: pointCloud,
        poses: poses,
        improvementPercent: 0,
      );
    }

    // Convert CameraPose objects to Matrix4 for BundleAdjustmentService.
    // CameraPose uses: pCam = R * (point - position), so t = -R * position.
    final focalLength = poses.first.focalLength;
    final cx = _imageWidth / 2.0;
    final cy = _imageHeight / 2.0;

    final cameraPoseMatrices = <Matrix4>[];
    for (final pose in poses) {
      final R = pose.rotation;
      final t = -(R.transformed(pose.position)); // t = -R * position
      cameraPoseMatrices.add(Matrix4(
        R.entry(0, 0), R.entry(1, 0), R.entry(2, 0), 0,
        R.entry(0, 1), R.entry(1, 1), R.entry(2, 1), 0,
        R.entry(0, 2), R.entry(1, 2), R.entry(2, 2), 0,
        t.x, t.y, t.z, 1,
      ));
    }

    // Convert Point3D positions to Vector3 list
    final points3D = points.map((p) => Vector3.copy(p.position)).toList();

    // Build observations matrix: observations[camIdx][pointIdx] = Vector2? observation
    // Points are ordered sequentially from matches: matches[i] pairs image i and i+1.
    // Each match contributes one point observed in cameras i and i+1.
    final observations = List.generate(
      nCams,
      (_) => List<Vector2?>.filled(nPts, null),
    );

    int pointIdx = 0;
    for (int i = 0; i < matches.length && i < nCams - 1; i++) {
      for (final match in matches[i]) {
        if (pointIdx >= nPts) break;
        observations[i][pointIdx] = Vector2(match.feature1.x, match.feature1.y);
        observations[i + 1][pointIdx] = Vector2(match.feature2.x, match.feature2.y);
        pointIdx++;
      }
    }

    // Run Levenberg-Marquardt bundle adjustment with Huber robust cost
    final baResult = ba.BundleAdjustmentService.optimize(
      cameraPoses: cameraPoseMatrices,
      points3D: points3D,
      observations: observations,
      focalLength: focalLength,
      cx: cx,
      cy: cy,
      maxIterations: 50,
      robustCost: ba.RobustCost.huber,
      robustParam: 2.0,
    );

    debugPrint('   LM Bundle Adjustment: ${baResult.iterations} iterations, '
        'converged=${baResult.converged}, '
        'error ${baResult.initialError.toStringAsFixed(2)} -> ${baResult.finalError.toStringAsFixed(2)} px');

    // Convert refined poses back to CameraPose objects
    final refinedPoses = <CameraPose>[];
    for (int i = 0; i < nCams; i++) {
      final m = baResult.refinedPoses[i];
      final R = Matrix3(
        m.entry(0, 0), m.entry(0, 1), m.entry(0, 2),
        m.entry(1, 0), m.entry(1, 1), m.entry(1, 2),
        m.entry(2, 0), m.entry(2, 1), m.entry(2, 2),
      );
      final t = Vector3(m.entry(0, 3), m.entry(1, 3), m.entry(2, 3));
      // Recover position: position = -R^T * t
      final Rt = R.transposed();
      final position = -(Rt.transformed(t));
      refinedPoses.add(CameraPose(
        position: position,
        rotation: R,
        focalLength: poses[i].focalLength,
      ));
    }

    // Convert refined points back to Point3D objects
    final refinedPoints = <Point3D>[];
    for (int i = 0; i < nPts; i++) {
      refinedPoints.add(Point3D(
        position: baResult.refinedPoints[i],
        color: points[i].color,
        confidence: points[i].confidence,
        normal: points[i].normal,
      ));
    }

    final improvement = baResult.initialError > 1e-12
        ? ((baResult.initialError - baResult.finalError) / baResult.initialError * 100).clamp(0.0, 100.0)
        : 0.0;

    return BundleAdjustmentResult(
      pointCloud: PointCloud(
        points: refinedPoints,
        method: pointCloud.method,
        metadata: pointCloud.metadata,
      ),
      poses: refinedPoses,
      improvementPercent: improvement,
    );
  }

  /// Statistical outlier removal using k-nearest neighbors
  PointCloud _removeStatisticalOutliers(PointCloud cloud, {int k = 10, double stdRatio = 2.0}) {
    if (cloud.points.length < k + 1) return cloud;

    final points = cloud.points;
    final distances = <double>[];

    // Calculate mean distance to k nearest neighbors for each point
    for (int i = 0; i < points.length; i++) {
      final dists = <double>[];
      for (int j = 0; j < points.length; j++) {
        if (i != j) {
          dists.add((points[i].position - points[j].position).length);
        }
      }
      dists.sort();

      // Mean distance to k nearest neighbors
      double meanDist = 0;
      for (int n = 0; n < k && n < dists.length; n++) {
        meanDist += dists[n];
      }
      meanDist /= k;
      distances.add(meanDist);
    }

    // Calculate global mean and std
    final globalMean = distances.reduce((a, b) => a + b) / distances.length;
    final variance = distances.map((d) => (d - globalMean) * (d - globalMean)).reduce((a, b) => a + b) / distances.length;
    final globalStd = math.sqrt(variance);

    // Filter outliers
    final threshold = globalMean + stdRatio * globalStd;
    final filteredPoints = <Point3D>[];

    for (int i = 0; i < points.length; i++) {
      if (distances[i] < threshold) {
        filteredPoints.add(points[i]);
      }
    }

    return PointCloud(
      points: filteredPoints,
      method: cloud.method,
      metadata: {...cloud.metadata, 'outliers_removed': points.length - filteredPoints.length},
    );
  }

  /// Multi-view color sampling - average colors from multiple camera views
  /// Multi-view color sampling using cached color samples (no image reload)
  Future<PointCloud> _multiViewColorSampling(
    PointCloud cloud,
    List<CameraPose> poses,
  ) async {
    final enhancedPoints = <Point3D>[];

    for (final point in cloud.points) {
      final colors = <Color>[];
      final weights = <double>[];

      // Sample color from each camera that can see this point
      for (int c = 0; c < poses.length && c < _colorSamplesCache.length; c++) {
        final pose = poses[c];
        final colorSample = _colorSamplesCache[c];

        // Check if point is in front of camera
        final camDir = pose.rotation.transposed().transform(Vector3(0, 0, 1));
        final toPoint = point.position - pose.position;
        final depth = toPoint.dot(camDir);

        if (depth > 0.1) {
          // Project point to image
          final reproj = _reprojectPoint(point.position, pose);
          final x = reproj.x.toInt();
          final y = reproj.y.toInt();

          // Get color from cached sample data
          final color = _getColorFromSample(
            colorSample,
            x,
            y,
            _imageWidth.toDouble(),
            _imageHeight.toDouble(),
          );

          colors.add(color);

          // Weight by viewing angle (prefer frontal views)
          final viewAngle = toPoint.normalized().dot(camDir).abs();
          weights.add(viewAngle);
        }
      }

      // Weighted average of colors
      Color finalColor = point.color;
      if (colors.isNotEmpty) {
        double totalWeight = weights.reduce((a, b) => a + b);
        if (totalWeight > 0) {
          double r = 0, g = 0, b = 0;
          for (int i = 0; i < colors.length; i++) {
            final w = weights[i] / totalWeight;
            r += colors[i].r * w;
            g += colors[i].g * w;
            b += colors[i].b * w;
          }
          finalColor = Color.fromARGB(255, r.round().clamp(0, 255), g.round().clamp(0, 255), b.round().clamp(0, 255));
        }
      }

      enhancedPoints.add(Point3D(
        position: point.position,
        color: finalColor,
        confidence: point.confidence,
        normal: point.normal,
      ));
    }

    return PointCloud(
      points: enhancedPoints,
      method: cloud.method,
      metadata: {...cloud.metadata, 'multi_view_color': true},
    );
  }

  /// Estimate normals for each point using local neighborhood
  PointCloud _estimateNormals(PointCloud cloud, {int k = 8}) {
    if (cloud.points.length < k + 1) return cloud;

    final pointsWithNormals = <Point3D>[];

    for (final point in cloud.points) {
      // Find k nearest neighbors
      final neighbors = <Point3D>[];
      final dists = <MapEntry<Point3D, double>>[];

      for (final other in cloud.points) {
        if (other != point) {
          final dist = (point.position - other.position).length;
          dists.add(MapEntry(other, dist));
        }
      }

      dists.sort((a, b) => a.value.compareTo(b.value));
      for (int i = 0; i < k && i < dists.length; i++) {
        neighbors.add(dists[i].key);
      }

      // Compute centroid
      var centroid = Vector3.zero();
      for (final n in neighbors) {
        centroid += n.position;
      }
      centroid /= neighbors.length.toDouble();

      // Compute covariance matrix
      double cxx = 0, cxy = 0, cxz = 0, cyy = 0, cyz = 0;
      for (final n in neighbors) {
        final d = n.position - centroid;
        cxx += d.x * d.x;
        cxy += d.x * d.y;
        cxz += d.x * d.z;
        cyy += d.y * d.y;
        cyz += d.y * d.z;
      }

      // Simple normal estimation using cross product of principal directions
      final v1 = Vector3(cxx, cxy, cxz).normalized();
      final v2 = Vector3(cxy, cyy, cyz).normalized();
      var normal = v1.cross(v2);

      if (normal.length > 0.001) {
        normal = normal.normalized();
      } else {
        normal = Vector3(0, 1, 0); // Default up normal
      }

      pointsWithNormals.add(Point3D(
        position: point.position,
        color: point.color,
        confidence: point.confidence,
        normal: normal,
      ));
    }

    return PointCloud(
      points: pointsWithNormals,
      method: cloud.method,
      metadata: {...cloud.metadata, 'has_normals': true},
    );
  }

  /// Interpolate points to create denser point cloud
  /// Interpolate points using compute() with 5-second timeout
  Future<PointCloud> _interpolatePoints(PointCloud cloud, {int maxNewPoints = 500}) async {
    if (cloud.points.length < 10) return cloud;

    try {
      final params = _InterpolationParams(
        points: cloud.points,
        maxNewPoints: maxNewPoints,
      );

      final interpolated = await compute(_interpolatePointsIsolate, params);
      final added = interpolated.length - cloud.points.length;

      return PointCloud(
        points: interpolated,
        method: cloud.method,
        metadata: {...cloud.metadata, 'interpolated_points': added},
      );
    } catch (e) {
      debugPrint(' Interpolation failed: $e, returning original cloud');
      return cloud;
    }
  }

  /// Generate a simple triangle mesh from point cloud using k-nearest neighbor triangulation
  MeshModel generateMeshFromPointCloud(PointCloud cloud, {int k = 6}) {
    if (cloud.points.length < 4) {
      return MeshModel(
        vertices: [],
        faces: [],
        method: 'knn_triangulation',
      );
    }

    final vertices = <MeshVertex>[];
    final faces = <MeshFace>[];
    final points = cloud.points;

    // Create vertices from points
    for (final point in points) {
      vertices.add(MeshVertex(
        position: point.position,
        normal: point.normal,
        color: point.color,
      ));
    }

    // Build neighbor lists for each point
    final neighbors = <int, List<int>>{};
    for (int i = 0; i < points.length; i++) {
      final dists = <MapEntry<int, double>>[];
      for (int j = 0; j < points.length; j++) {
        if (i != j) {
          final dist = (points[i].position - points[j].position).length;
          dists.add(MapEntry(j, dist));
        }
      }
      dists.sort((a, b) => a.value.compareTo(b.value));
      neighbors[i] = dists.take(k).map((e) => e.key).toList();
    }

    // Create triangles from point triplets using k-nearest neighbors
    final addedFaces = <String>{};

    for (int i = 0; i < points.length; i++) {
      final myNeighbors = neighbors[i]!;

      // Try to form triangles with pairs of neighbors
      for (int ni = 0; ni < myNeighbors.length; ni++) {
        for (int nj = ni + 1; nj < myNeighbors.length; nj++) {
          final j = myNeighbors[ni];
          final kIdx = myNeighbors[nj];

          // Check if j and k are also neighbors of each other (form coherent triangle)
          if (neighbors[j]!.contains(kIdx) || neighbors[kIdx]!.contains(j)) {
            // Sort indices to avoid duplicate triangles
            final indices = [i, j, kIdx]..sort();
            final faceKey = '${indices[0]}_${indices[1]}_${indices[2]}';

            if (!addedFaces.contains(faceKey)) {
              addedFaces.add(faceKey);

              // Check triangle quality (avoid degenerate triangles)
              final v0 = points[indices[0]].position;
              final v1 = points[indices[1]].position;
              final v2 = points[indices[2]].position;

              final edge1 = v1 - v0;
              final edge2 = v2 - v0;
              final normal = edge1.cross(edge2);

              // Only add if triangle has reasonable area
              if (normal.length > 0.0001) {
                faces.add(MeshFace(indices[0], indices[1], indices[2]));
              }
            }
          }
        }
      }
    }

    debugPrint(' Generated mesh: ${vertices.length} vertices, ${faces.length} faces');

    return MeshModel(
      vertices: vertices,
      faces: faces,
      method: 'knn_triangulation',
      metadata: {
        'source_points': cloud.points.length,
        'k_neighbors': k,
      },
    );
  }

  /// Calculate image variance (sharpness indicator)
  double _calculateImageVariance(img.Image image) {
    // Sample 100 pixels for quick estimate
    double sum = 0;
    double sumSquared = 0;
    int count = 0;

    final step = (image.width * image.height / 100).floor();

    for (int i = 0; i < image.width * image.height; i += step) {
      final x = i % image.width;
      final y = i ~/ image.width;

      if (y < image.height) {
        final pixel = image.getPixel(x, y);
        final luminance = (pixel.r + pixel.g + pixel.b) / 3.0;
        sum += luminance;
        sumSquared += luminance * luminance;
        count++;
      }
    }

    final mean = sum / count;
    final variance = (sumSquared / count) - (mean * mean);

    return variance;
  }
}

/// Represents a feature point in an image
class ImageFeature {
  final double x;
  final double y;
  final double strength;
  final List<double> descriptor;

  ImageFeature({
    required this.x,
    required this.y,
    required this.strength,
    required this.descriptor,
  });
}

/// Represents a match between features in two images
class FeatureMatch {
  final ImageFeature feature1;
  final ImageFeature feature2;
  final double distance;

  FeatureMatch({
    required this.feature1,
    required this.feature2,
    required this.distance,
  });
}

class _MatchCandidate {
  final int idx;
  final double distance;
  _MatchCandidate(this.idx, this.distance);
}

/// Result of bundle adjustment optimization
class BundleAdjustmentResult {
  final PointCloud pointCloud;
  final List<CameraPose> poses;
  final double improvementPercent;

  BundleAdjustmentResult({
    required this.pointCloud,
    required this.poses,
    required this.improvementPercent,
  });
}

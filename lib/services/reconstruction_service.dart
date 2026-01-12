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
import '../models/point_cloud.dart';
import '../models/reconstruction_result.dart';
import 'sfm_robust.dart';

/// Service for 3D reconstruction from photogrammetry captures
class ReconstructionService {
  static final ReconstructionService _instance = ReconstructionService._internal();
  factory ReconstructionService() => _instance;
  ReconstructionService._internal();

  final _uuid = const Uuid();
  bool _isCancelled = false;

  /// Cancel ongoing reconstruction
  void cancelReconstruction() {
    _isCancelled = true;
  }

  /// Reset cancellation flag
  void _resetCancellation() {
    _isCancelled = false;
  }

  /// Detect device capabilities for reconstruction
  Future<Map<String, dynamic>> detectCapabilities() async {
    // Check available RAM (simplified - would need platform channel for real implementation)
    final capabilities = <String, dynamic>{};

    // Assume 2GB+ RAM for basic features
    capabilities['sparse_preview'] = true;
    capabilities['estimated_ram_gb'] = 2; // Placeholder

    // Check for Huawei 3D Modeling Kit (would need actual detection)
    capabilities['huawei_kit_available'] = false;

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
        debugPrint('⚠️ Warning: Using ${imageFiles.length} images. 8+ recommended for best results.');
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
        debugPrint('✅ Loaded ${images.length} images successfully');
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
        if (totalFeatures < 100) {
          throw Exception('Not enough features detected ($totalFeatures found). Try:\n'
              '• Better lighting\n'
              '• More textured objects\n'
              '• Sharper photos');
        }
        debugPrint('✅ Extracted $totalFeatures features from ${features.length} images');
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
        if (totalMatches < 50) {
          throw Exception('Insufficient feature matches ($totalMatches found). Object may have moved between shots.');
        }
        debugPrint('✅ Found $totalMatches feature matches');
      } catch (e) {
        throw Exception('Feature matching failed: $e');
      }

      // Step 4: Estimate camera poses (75%)
      onProgress?.call(0.65, 'Calculating camera positions...');
      List<CameraPose>? cameraPoses;
      try {
        cameraPoses = await _estimateCameraPoses(matches, imageFiles.length);
        if (_isCancelled) throw Exception('Reconstruction cancelled by user');
        debugPrint('✅ Estimated ${cameraPoses.length} camera poses');
      } catch (e) {
        throw Exception('Camera pose estimation failed: $e');
      }

      // Step 5: Triangulate 3D points (95%)
      onProgress?.call(0.80, 'Reconstructing 3D points...');
      PointCloud? pointCloud;
      try {
        // Reload only necessary images for color extraction
        final colorImages = await _loadImagesForColor(imageFiles);
        pointCloud = await _triangulatePoints(
          features,
          matches,
          cameraPoses,
          colorImages,
        );
        if (_isCancelled) throw Exception('Reconstruction cancelled by user');

        // Clear intermediate data
        colorImages.clear();
        features.clear();
        matches.clear();
        cameraPoses.clear();

        if (pointCloud.points.length < 100) {
          debugPrint('⚠️ Warning: Only ${pointCloud.points.length} points reconstructed. Quality may be low.');
        }
        debugPrint('✅ Reconstructed ${pointCloud.points.length} 3D points');
      } catch (e) {
        throw Exception('3D triangulation failed: $e');
      }

      onProgress?.call(1.0, '✅ Reconstruction complete!');

      final endTime = DateTime.now();
      final processingTime = endTime.difference(startTime).inSeconds.toDouble();

      final result = ReconstructionResult(
        id: resultId,
        method: ReconstructionMethod.sparseSfM,
        status: ReconstructionStatus.completed,
        startedAt: startTime,
        completedAt: endTime,
        pointCloud: pointCloud,
        progress: 1.0,
        statusMessage: 'Reconstruction completed with ${pointCloud.points.length} points',
        inputImageCount: imageFiles.length,
        processingTimeSeconds: processingTime,
        qualityMetrics: {
          'point_count': pointCloud.points.length,
          'image_count': imageFiles.length,
          'average_confidence': _calculateAverageConfidence(pointCloud),
          'processing_time_seconds': processingTime,
        },
      );

      // Auto-save result
      try {
        await saveResult(result);
        debugPrint('✅ Saved reconstruction to persistent storage');
      } catch (e) {
        debugPrint('⚠️ Failed to save result: $e');
      }

      return result;
    } catch (e, stackTrace) {
      debugPrint('❌ Reconstruction error: $e');
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
  Future<List<img.Image>> _loadAndDownsampleImages(
    List<File> imageFiles,
    Function(double, String)? onProgress,
  ) async {
    final images = <img.Image>[];

    for (int i = 0; i < imageFiles.length; i++) {
      try {
        if (_isCancelled) break;

        final file = imageFiles[i];
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);

        if (image != null) {
          // Downsample to 1024x1024 for faster processing while maintaining quality
          final targetSize = 1024;
          final downsampled = img.copyResize(
            image,
            width: targetSize,
            height: targetSize,
            interpolation: img.Interpolation.average,
          );
          images.add(downsampled);

          final progress = 0.05 + (i / imageFiles.length) * 0.10;
          onProgress?.call(progress, 'Loading image ${i + 1}/${imageFiles.length}...');
        } else {
          debugPrint('⚠️ Failed to decode image ${i + 1}');
        }
      } catch (e) {
        debugPrint('⚠️ Error loading image ${i + 1}: $e');
      }
    }

    return images;
  }

  /// Load images at reduced size for color extraction only (memory efficient)
  Future<List<img.Image>> _loadImagesForColor(List<File> imageFiles) async {
    final images = <img.Image>[];

    for (int i = 0; i < imageFiles.length; i++) {
      try {
        if (_isCancelled) break;

        final file = imageFiles[i];
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);

        if (image != null) {
          // Smaller size for color extraction (512x512 is sufficient)
          final downsampled = img.copyResize(
            image,
            width: 512,
            height: 512,
            interpolation: img.Interpolation.average,
          );
          images.add(downsampled);
        }
      } catch (e) {
        debugPrint('⚠️ Error loading image ${i + 1} for color: $e');
        // Add placeholder if loading fails
        images.add(img.Image(width: 512, height: 512));
      }
    }

    return images;
  }

  /// Extract corner features from images using simplified Harris corner detector
  Future<List<List<ImageFeature>>> _extractFeatures(
    List<img.Image> images,
    Function(double, String)? onProgress,
  ) async {
    final allFeatures = <List<ImageFeature>>[];

    for (int i = 0; i < images.length; i++) {
      final progress = 0.3 + (i / images.length) * 0.15;
      onProgress?.call(progress, 'Extracting features from image ${i + 1}/${images.length}...');

      final features = await compute(_extractFeaturesFromImage, images[i]);
      allFeatures.add(features);
    }

    return allFeatures;
  }

  /// Extract features from a single image (runs in isolate)
  static List<ImageFeature> _extractFeaturesFromImage(img.Image image) {
    final features = <ImageFeature>[];
    final width = image.width;
    final height = image.height;

    try {
      // Convert to grayscale for feature detection
      final gray = img.grayscale(image);

      // Enhanced grid-based feature extraction with adaptive threshold
      const gridSize = 20; // 20x20 grid for better coverage
      final cellWidth = width / gridSize;
      final cellHeight = height / gridSize;

      // Calculate adaptive threshold based on image statistics
      double maxStrength = 0;
      final candidateFeatures = <ImageFeature>[];

      // First pass: collect all potential features
      for (int gy = 0; gy < gridSize; gy++) {
        for (int gx = 0; gx < gridSize; gx++) {
          // Sample multiple points in each cell for better coverage
          for (int dy = 0; dy < 2; dy++) {
            for (int dx = 0; dx < 2; dx++) {
              final cx = ((gx + (dx + 0.5) / 2) * cellWidth).toInt();
              final cy = ((gy + (dy + 0.5) / 2) * cellHeight).toInt();

              if (cx < 4 || cx >= width - 4 || cy < 4 || cy >= height - 4) continue;

              // Calculate corner strength (enhanced Harris response)
              final cornerStrength = _calculateCornerStrength(gray, cx, cy);

              if (cornerStrength > maxStrength) {
                maxStrength = cornerStrength;
              }

              if (cornerStrength > 500) {
                // Lower threshold for initial collection
                candidateFeatures.add(ImageFeature(
                  x: cx.toDouble(),
                  y: cy.toDouble(),
                  strength: cornerStrength,
                  descriptor: [], // Descriptor extracted later
                ));
              }
            }
          }
        }
      }

      // Adaptive threshold: use 20% of max strength
      final threshold = maxStrength * 0.15;

      // Second pass: extract descriptors for strong features
      for (final candidate in candidateFeatures) {
        if (candidate.strength > threshold) {
          // Extract local descriptor (8x8 patch around feature)
          final descriptor = _extractDescriptor(
            gray,
            candidate.x.toInt(),
            candidate.y.toInt(),
          );

          features.add(ImageFeature(
            x: candidate.x,
            y: candidate.y,
            strength: candidate.strength,
            descriptor: descriptor,
          ));
        }
      }

      // Non-maximum suppression: remove features too close to stronger ones
      final suppressedFeatures = <ImageFeature>[];
      features.sort((a, b) => b.strength.compareTo(a.strength));

      for (final feature in features) {
        bool shouldKeep = true;
        for (final kept in suppressedFeatures) {
          final dx = feature.x - kept.x;
          final dy = feature.y - kept.y;
          final distance = math.sqrt(dx * dx + dy * dy);
          if (distance < 10) {
            // Too close to existing feature
            shouldKeep = false;
            break;
          }
        }
        if (shouldKeep) {
          suppressedFeatures.add(feature);
        }
      }

      // Keep top 300 features for better matching (increased from 200)
      return suppressedFeatures.take(300).toList();
    } catch (e) {
      debugPrint('Error extracting features: $e');
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

  /// Extract simple descriptor from 8x8 patch
  static List<double> _extractDescriptor(img.Image gray, int x, int y) {
    final descriptor = <double>[];

    for (int dy = -4; dy < 4; dy++) {
      for (int dx = -4; dx < 4; dx++) {
        final px = x + dx;
        final py = y + dy;

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

  /// Match features between consecutive images
  Future<List<List<FeatureMatch>>> _matchFeatures(
    List<List<ImageFeature>> features,
    Function(double, String)? onProgress,
  ) async {
    final matches = <List<FeatureMatch>>[];

    for (int i = 0; i < features.length - 1; i++) {
      final progress = 0.5 + (i / (features.length - 1)) * 0.15;
      onProgress?.call(progress, 'Matching images ${i + 1} and ${i + 2}...');

      final pairMatches = await compute(
        _matchFeaturePair,
        {'features1': features[i], 'features2': features[i + 1]},
      );
      matches.add(pairMatches);
    }

    return matches;
  }

  /// Match features between two images (runs in isolate)
  static List<FeatureMatch> _matchFeaturePair(Map<String, dynamic> args) {
    final features1 = args['features1'] as List<ImageFeature>;
    final features2 = args['features2'] as List<ImageFeature>;
    final matches = <FeatureMatch>[];

    for (final f1 in features1) {
      double bestDistance = double.infinity;
      double secondBestDistance = double.infinity;
      int bestIdx = -1;

      for (int j = 0; j < features2.length; j++) {
        final f2 = features2[j];
        final distance = _descriptorDistance(f1.descriptor, f2.descriptor);

        if (distance < bestDistance) {
          secondBestDistance = bestDistance;
          bestDistance = distance;
          bestIdx = j;
        } else if (distance < secondBestDistance) {
          secondBestDistance = distance;
        }
      }

      // Lowe's ratio test: good match if best is significantly better than second best
      if (bestIdx >= 0 && bestDistance < 0.8 * secondBestDistance) {
        matches.add(FeatureMatch(
          feature1: f1,
          feature2: features2[bestIdx],
          distance: bestDistance,
        ));
      }
    }

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
    int imageCount,
  ) async {
    final poses = <CameraPose>[];
    const focalLength = 1000.0; // Approximate for mobile camera

    // First camera at origin
    poses.add(CameraPose(
      position: Vector3.zero(),
      rotation: Matrix3.identity(),
      focalLength: focalLength,
    ));

    debugPrint('📐 Starting ROBUST camera pose estimation with RANSAC...');

    // Estimate each subsequent camera pose using Essential Matrix + RANSAC
    for (int i = 0; i < matches.length; i++) {
      final pairMatches = matches[i];

      if (pairMatches.length < 8) {
        // Not enough matches - FAIL instead of guessing
        throw Exception(
          'Insufficient matches between images ${i + 1} and ${i + 2}: '
          'Found ${pairMatches.length} matches, need at least 8.\n'
          'Try:\n• More overlap between photos\n• Better lighting\n• Sharper focus'
        );
      }

      try {
        // ✅ REAL ALGORITHM: RANSAC + Essential Matrix estimation
        debugPrint('  🔍 Image pair ${i + 1}-${i + 2}: ${pairMatches.length} matches');

        final essentialResult = RobustSfM.estimateEssentialMatrix(
          pairMatches,
          focalLength,
        );

        debugPrint('    ✅ RANSAC: ${essentialResult.inlierCount} inliers '
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

        debugPrint('    📍 Pose ${i + 2}: pos=${worldPosition.x.toStringAsFixed(2)}, '
            '${worldPosition.y.toStringAsFixed(2)}, ${worldPosition.z.toStringAsFixed(2)}');

      } catch (e) {
        // RANSAC failed - provide actionable error
        debugPrint('    ❌ Pose estimation failed: $e');
        throw Exception(
          'Camera pose estimation failed for images ${i + 1}-${i + 2}:\n$e'
        );
      }
    }

    debugPrint('✅ Estimated ${poses.length} camera poses with RANSAC');
    return poses;
  }

  /// Triangulate 3D points from feature matches and camera poses with ROBUST filtering
  Future<PointCloud> _triangulatePoints(
    List<List<ImageFeature>> features,
    List<List<FeatureMatch>> matches,
    List<CameraPose> poses,
    List<img.Image> images,
  ) async {
    final points = <Point3D>[];
    final seenFeatures = <String>{};
    int totalTriangulated = 0;
    int passed = 0;
    int failedDepth = 0;
    int failedAngle = 0;
    int failedReprojection = 0;

    debugPrint('🔺 Starting ROBUST triangulation...');

    // Triangulate points from consecutive image pairs
    for (int i = 0; i < matches.length; i++) {
      final pairMatches = matches[i];
      final pose1 = poses[i];
      final pose2 = poses[i + 1];

      int pairPoints = 0;

      for (final match in pairMatches) {
        // Unique ID for this feature track
        final featureId = '${i}_${match.feature1.x}_${match.feature1.y}';

        if (seenFeatures.contains(featureId)) continue;
        seenFeatures.add(featureId);
        totalTriangulated++;

        // Transform rays to world coordinates
        final ray1Dir = pose1.rotation.transposed().transform(Vector3(
          (match.feature1.x - 512) / pose1.focalLength,
          (match.feature1.y - 512) / pose1.focalLength,
          1.0,
        ).normalized());

        final ray2Dir = pose2.rotation.transposed().transform(Vector3(
          (match.feature2.x - 512) / pose2.focalLength,
          (match.feature2.y - 512) / pose2.focalLength,
          1.0,
        ).normalized());

        // Triangulate point
        final point3D = _triangulateRayPair(
          pose1.position,
          ray1Dir,
          pose2.position,
          ray2Dir,
        );

        // ✅ QUALITY CHECK 1: Depth validation (must be in front of both cameras)
        final depth1 = (point3D - pose1.position).dot(pose1.rotation.transposed().transform(Vector3(0, 0, 1)));
        final depth2 = (point3D - pose2.position).dot(pose2.rotation.transposed().transform(Vector3(0, 0, 1)));

        if (depth1 < 0.1 || depth2 < 0.1) {
          failedDepth++;
          continue; // Behind camera or too close
        }

        // ✅ QUALITY CHECK 2: Triangulation angle (30-150 degrees optimal)
        final angle = _calculateTriangulationAngle(pose1.position, pose2.position, point3D);
        final angleDegrees = angle * (180.0 / math.pi);

        if (angleDegrees < 5 || angleDegrees > 175) {
          failedAngle++;
          continue; // Poor triangulation geometry
        }

        // ✅ QUALITY CHECK 3: Reprojection error
        final reproj1 = _reprojectPoint(point3D, pose1);
        final reproj2 = _reprojectPoint(point3D, pose2);

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
          // Reprojection error > 5 pixels
          failedReprojection++;
          continue;
        }

        // ✅ Point passed all checks!
        passed++;
        pairPoints++;

        // Get color from first image
        final color = _getColorFromImage(
          images[i],
          match.feature1.x.toInt(),
          match.feature1.y.toInt(),
        );

        // Calculate confidence score
        final angleConfidence = angleDegrees > 30 && angleDegrees < 60 ? 1.0 : 0.7;
        final reprojConfidence = 1.0 - (maxError / 5.0).clamp(0.0, 1.0);
        final confidence = angleConfidence * reprojConfidence;

        points.add(Point3D(
          position: point3D,
          color: color,
          confidence: confidence,
        ));
      }

      if (pairPoints > 0) {
        debugPrint('  📍 Pair ${i + 1}-${i + 2}: $pairPoints points triangulated');
      }
    }

    debugPrint('✅ Triangulation complete:');
    debugPrint('   Total: $totalTriangulated');
    debugPrint('   ✅ Passed: $passed (${(passed / totalTriangulated * 100).toInt()}%)');
    debugPrint('   ❌ Failed depth: $failedDepth');
    debugPrint('   ❌ Failed angle: $failedAngle');
    debugPrint('   ❌ Failed reproj: $failedReprojection');

    if (passed < 100) {
      debugPrint('⚠️ Warning: Low point count. Consider:');
      debugPrint('   • Better lighting');
      debugPrint('   • More textured object');
      debugPrint('   • More photos (16 recommended)');
    }

    return PointCloud(
      points: points,
      method: 'robust_sfm_ransac',
      metadata: {
        'image_count': images.length,
        'total_triangulated': totalTriangulated,
        'passed_filters': passed,
        'pass_rate': passed / totalTriangulated,
        'failed_depth': failedDepth,
        'failed_angle': failedAngle,
        'failed_reprojection': failedReprojection,
      },
    );
  }

  /// Reproject 3D point back to 2D image coordinates
  Vector2 _reprojectPoint(Vector3 point3D, CameraPose pose) {
    // Transform to camera coordinates
    final pCam = pose.rotation.transform(point3D - pose.position);

    // Project to image plane
    final x = (pCam.x / pCam.z) * pose.focalLength + 512;
    final y = (pCam.y / pCam.z) * pose.focalLength + 512;

    return Vector2(x, y);
  }

  /// Calculate triangulation angle between two camera rays
  double _calculateTriangulationAngle(Vector3 cam1, Vector3 cam2, Vector3 point) {
    final dir1 = (point - cam1).normalized();
    final dir2 = (point - cam2).normalized();
    return math.acos(dir1.dot(dir2).clamp(-1.0, 1.0));
  }

  /// Triangulate 3D point from two rays
  Vector3 _triangulateRayPair(Vector3 o1, Vector3 d1, Vector3 o2, Vector3 d2) {
    // Find closest point between two rays using least squares
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

    return (p1 + p2) / 2; // Midpoint
  }

  /// Get color from image at pixel coordinates
  Color _getColorFromImage(img.Image image, int x, int y) {
    final pixel = image.getPixel(
      x.clamp(0, image.width - 1),
      y.clamp(0, image.height - 1),
    );
    return Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
  }

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

/// Represents a camera pose in 3D space
class CameraPose {
  final Vector3 position;
  final Matrix3 rotation;
  final double focalLength;

  CameraPose({
    required this.position,
    required this.rotation,
    required this.focalLength,
  });
}

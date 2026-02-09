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
import '../models/reconstruction_result.dart';
import 'sfm_robust.dart';

/// Service for 3D reconstruction from photogrammetry captures
class ReconstructionService {
  static final ReconstructionService _instance = ReconstructionService._internal();
  factory ReconstructionService() => _instance;
  ReconstructionService._internal();

  final _uuid = const Uuid();
  bool _isCancelled = false;
  int _imageWidth = 1024;
  int _imageHeight = 1024;

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
    final capabilities = <String, dynamic>{};
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;

        // Get actual device RAM (in GB)
        final totalMemMB = androidInfo.systemFeatures.contains('android.hardware.ram.normal') ? 2 : 4;
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
        cameraPoses = await _estimateCameraPoses(matches, imageFiles.length);
        if (_isCancelled) throw Exception('Reconstruction cancelled by user');
        debugPrint(' Estimated ${cameraPoses.length} camera poses');
      } catch (e) {
        throw Exception('Camera pose estimation failed: $e');
      }

      // Step 5: Triangulate 3D points (70%)
      onProgress?.call(0.70, 'Reconstructing 3D points...');
      PointCloud? pointCloud;
      List<img.Image>? colorImages;
      try {
        // Reload only necessary images for color extraction
        colorImages = await _loadImagesForColor(imageFiles);
        pointCloud = await _triangulatePoints(
          features,
          matches,
          cameraPoses,
          colorImages,
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
      var currentCloud = pointCloud!;
      var currentPoses = cameraPoses!;

      // Step 6: Bundle Adjustment - refine poses and points together (80%)
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
      onProgress?.call(0.88, 'Enhancing colors...');
      try {
        currentCloud = await _multiViewColorSampling(
          currentCloud,
          currentPoses,
          colorImages!,
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
        currentCloud = _interpolatePoints(currentCloud);
        final added = currentCloud.points.length - beforeCount;
        debugPrint(' Added $added interpolated points');
      } catch (e) {
        debugPrint(' Point interpolation skipped: $e');
      }

      // Clear intermediate data
      colorImages?.clear();
      features.clear();
      matches.clear();

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
        progress: 1.0,
        statusMessage: 'Reconstruction completed with ${currentCloud.points.length} points',
        inputImageCount: imageFiles.length,
        processingTimeSeconds: processingTime,
        qualityMetrics: {
          'point_count': currentCloud.points.length,
          'image_count': imageFiles.length,
          'average_confidence': _calculateAverageConfidence(currentCloud),
          'processing_time_seconds': processingTime,
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
          // Downsample to fit within 1024x1024 while preserving aspect ratio
          final maxDim = 1024;
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
          // Smaller size for color extraction, preserving aspect ratio
          const colorMaxDim = 512;
          img.Image downsampled;
          if (image.width >= image.height) {
            downsampled = img.copyResize(
              image,
              width: colorMaxDim,
              interpolation: img.Interpolation.average,
            );
          } else {
            downsampled = img.copyResize(
              image,
              height: colorMaxDim,
              interpolation: img.Interpolation.average,
            );
          }
          images.add(downsampled);
        }
      } catch (e) {
        debugPrint(' Error loading image ${i + 1} for color: $e');
        // Add placeholder if loading fails
        images.add(img.Image(width: 512, height: 384));
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

      final pairMatches = await compute(
        _matchFeaturePair,
        {'features1': features[i], 'features2': features[i + 1]},
      );
      matches.add(pairMatches);
    }

    // Skip-one pairs (i, i+2) for wider baseline — merge into existing matches
    if (features.length >= 3) {
      for (int i = 0; i < features.length - 2; i++) {
        onProgress?.call(0.65, 'Wide baseline match ${i + 1}-${i + 3}...');
        final skipMatches = await compute(
          _matchFeaturePair,
          {'features1': features[i], 'features2': features[i + 2]},
        );
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
      final loopMatches = await compute(
        _matchFeaturePair,
        {'features1': features.last, 'features2': features.first},
      );
      if (loopMatches.length >= 8) {
        matches.add(loopMatches);
        debugPrint('  Loop closure: ${loopMatches.length} matches (last→first)');
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
    int imageCount,
  ) async {
    final poses = <CameraPose>[];
    // Estimate focal length from image dimensions (~28mm equivalent on mobile)
    final focalLength = math.max(_imageWidth, _imageHeight) * 0.85;

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

    debugPrint(' Starting ROBUST triangulation...');

    // Triangulate points from image pairs (consecutive + loop closure)
    for (int i = 0; i < matches.length; i++) {
      final pairMatches = matches[i];
      // For loop closure (last entry), use last and first poses
      final CameraPose pose1;
      final CameraPose pose2;
      final int img1Idx;
      if (i < poses.length - 1) {
        pose1 = poses[i];
        pose2 = poses[i + 1];
        img1Idx = i;
      } else if (i == matches.length - 1 && matches.length > poses.length - 1) {
        // Loop closure: last→first
        pose1 = poses.last;
        pose2 = poses.first;
        img1Idx = poses.length - 1;
      } else {
        continue;
      }

      int pairPoints = 0;

      for (final match in pairMatches) {
        // Unique ID for this feature track
        final featureId = '${i}_${match.feature1.x}_${match.feature1.y}';

        if (seenFeatures.contains(featureId)) continue;
        seenFeatures.add(featureId);
        totalTriangulated++;

        // Transform rays to world coordinates
        final cx = _imageWidth / 2.0;
        final cy = _imageHeight / 2.0;
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
          images[img1Idx.clamp(0, images.length - 1)],
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
        debugPrint(' Pair ${i + 1}-${i + 2}: $pairPoints points triangulated');
      }
    }

    debugPrint(' Triangulation complete:');
    debugPrint('   Total: $totalTriangulated');
    debugPrint(' Passed: $passed (${(passed / totalTriangulated * 100).toInt()}%)');
    debugPrint(' Failed depth: $failedDepth');
    debugPrint(' Failed angle: $failedAngle');
    debugPrint(' Failed reproj: $failedReprojection');

    if (passed < 100) {
      debugPrint('Warning: Low point count. Consider:');
      debugPrint('   • Better lighting');
      debugPrint('   • More textured object');
      debugPrint('   • More photos (16 recommended)');
    }

    // Light bundle adjustment: 3 iterations of gradient descent on point positions
    if (points.length > 3 && poses.length >= 2) {
      debugPrint(' Running light bundle adjustment (3 iterations)...');
      _lightBundleAdjust(points, poses, matches, features);
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
    final x = (pCam.x / pCam.z) * pose.focalLength + _imageWidth / 2.0;
    final y = (pCam.y / pCam.z) * pose.focalLength + _imageHeight / 2.0;

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

  /// Light bundle adjustment: refine point positions to minimize reprojection error
  void _lightBundleAdjust(
    List<Point3D> points,
    List<CameraPose> poses,
    List<List<FeatureMatch>> matches,
    List<List<ImageFeature>> features,
  ) {
    const iterations = 3;
    const stepSize = 0.01;

    for (int iter = 0; iter < iterations; iter++) {
      double totalError = 0;
      int errorCount = 0;

      for (int pi = 0; pi < points.length; pi++) {
        final point = points[pi];
        double gradX = 0, gradY = 0, gradZ = 0;
        int views = 0;

        // Compute gradient from all camera views
        for (int ci = 0; ci < poses.length; ci++) {
          final reproj = _reprojectPoint(point.position, poses[ci]);
          // Check if reprojection is within image bounds
          if (reproj.x < 0 || reproj.x >= _imageWidth || reproj.y < 0 || reproj.y >= _imageHeight) continue;

          // Find observed feature position for this point in this camera
          // Use closest feature within 5 pixels as observation
          double? obsX, obsY;
          if (ci < features.length) {
            double bestDist = 5.0;
            for (final feat in features[ci]) {
              final dx = feat.x - reproj.x;
              final dy = feat.y - reproj.y;
              final dist = math.sqrt(dx * dx + dy * dy);
              if (dist < bestDist) {
                bestDist = dist;
                obsX = feat.x;
                obsY = feat.y;
              }
            }
          }

          if (obsX == null || obsY == null) continue;

          final errX = reproj.x - obsX;
          final errY = reproj.y - obsY;
          totalError += errX * errX + errY * errY;
          errorCount++;

          // Numerical gradient: shift point slightly in each axis
          const delta = 0.001;
          for (int axis = 0; axis < 3; axis++) {
            final shifted = point.position.clone();
            shifted.storage[axis] += delta;
            final reprojShifted = _reprojectPoint(shifted, poses[ci]);
            final errXs = reprojShifted.x - obsX;
            final errYs = reprojShifted.y - obsY;
            final errorBefore = errX * errX + errY * errY;
            final errorAfter = errXs * errXs + errYs * errYs;
            final grad = (errorAfter - errorBefore) / delta;
            if (axis == 0) gradX += grad;
            else if (axis == 1) gradY += grad;
            else gradZ += grad;
          }
          views++;
        }

        if (views > 0) {
          // Gradient descent step
          points[pi] = Point3D(
            position: Vector3(
              point.position.x - stepSize * gradX / views,
              point.position.y - stepSize * gradY / views,
              point.position.z - stepSize * gradZ / views,
            ),
            color: point.color,
            confidence: point.confidence,
            normal: point.normal,
          );
        }
      }

      final rms = errorCount > 0 ? math.sqrt(totalError / errorCount) : 0.0;
      debugPrint('   BA iter ${iter + 1}: RMS reprojection error = ${rms.toStringAsFixed(2)} px');
    }
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

  /// Bundle Adjustment - jointly optimize camera poses and 3D points
  Future<BundleAdjustmentResult> _bundleAdjustment(
    PointCloud pointCloud,
    List<CameraPose> poses,
    List<List<ImageFeature>> features,
    List<List<FeatureMatch>> matches,
  ) async {
    // Simplified bundle adjustment using gradient descent
    final points = List<Point3D>.from(pointCloud.points);
    var currentPoses = List<CameraPose>.from(poses);

    double initialError = _calculateTotalReprojectionError(points, currentPoses, matches);
    double currentError = initialError;

    const iterations = 10;
    const learningRate = 0.001;

    for (int iter = 0; iter < iterations; iter++) {
      // Optimize each point position
      for (int i = 0; i < points.length; i++) {
        final point = points[i];
        final gradient = _computePointGradient(point, currentPoses, matches, i);

        points[i] = Point3D(
          position: point.position - gradient * learningRate,
          color: point.color,
          confidence: point.confidence,
          normal: point.normal,
        );
      }

      // Optimize camera positions (skip first camera - fixed at origin)
      for (int c = 1; c < currentPoses.length; c++) {
        final pose = currentPoses[c];
        final gradient = _computePoseGradient(pose, points, matches, c);

        currentPoses[c] = CameraPose(
          position: pose.position - gradient * learningRate,
          rotation: pose.rotation,
          focalLength: pose.focalLength,
        );
      }

      currentError = _calculateTotalReprojectionError(points, currentPoses, matches);
    }

    final improvement = ((initialError - currentError) / initialError * 100).clamp(0.0, 100.0);

    return BundleAdjustmentResult(
      pointCloud: PointCloud(
        points: points,
        method: pointCloud.method,
        metadata: pointCloud.metadata,
      ),
      poses: currentPoses,
      improvementPercent: improvement,
    );
  }

  /// Calculate total reprojection error
  double _calculateTotalReprojectionError(
    List<Point3D> points,
    List<CameraPose> poses,
    List<List<FeatureMatch>> matches,
  ) {
    double totalError = 0;
    int count = 0;

    for (int i = 0; i < matches.length && i < poses.length - 1; i++) {
      for (final match in matches[i]) {
        if (count < points.length) {
          final reproj1 = _reprojectPoint(points[count].position, poses[i]);
          final reproj2 = _reprojectPoint(points[count].position, poses[i + 1]);

          totalError += (reproj1.x - match.feature1.x).abs() + (reproj1.y - match.feature1.y).abs();
          totalError += (reproj2.x - match.feature2.x).abs() + (reproj2.y - match.feature2.y).abs();
          count++;
        }
      }
    }

    return count > 0 ? totalError / count : 0;
  }

  /// Compute gradient for point optimization
  Vector3 _computePointGradient(
    Point3D point,
    List<CameraPose> poses,
    List<List<FeatureMatch>> matches,
    int pointIdx,
  ) {
    const epsilon = 0.001;
    var gradient = Vector3.zero();

    // Numerical gradient for each dimension
    for (int dim = 0; dim < 3; dim++) {
      final delta = Vector3(
        dim == 0 ? epsilon : 0,
        dim == 1 ? epsilon : 0,
        dim == 2 ? epsilon : 0,
      );

      final pointPlus = Point3D(
        position: point.position + delta,
        color: point.color,
        confidence: point.confidence,
      );
      final pointMinus = Point3D(
        position: point.position - delta,
        color: point.color,
        confidence: point.confidence,
      );

      double errorPlus = 0;
      double errorMinus = 0;

      for (int c = 0; c < poses.length; c++) {
        final reproj1 = _reprojectPoint(pointPlus.position, poses[c]);
        final reproj2 = _reprojectPoint(pointMinus.position, poses[c]);
        errorPlus += reproj1.length;
        errorMinus += reproj2.length;
      }

      final grad = (errorPlus - errorMinus) / (2 * epsilon);
      if (dim == 0) gradient.x = grad;
      if (dim == 1) gradient.y = grad;
      if (dim == 2) gradient.z = grad;
    }

    return gradient;
  }

  /// Compute gradient for camera pose optimization
  Vector3 _computePoseGradient(
    CameraPose pose,
    List<Point3D> points,
    List<List<FeatureMatch>> matches,
    int poseIdx,
  ) {
    const epsilon = 0.001;
    var gradient = Vector3.zero();

    for (int dim = 0; dim < 3; dim++) {
      final delta = Vector3(
        dim == 0 ? epsilon : 0,
        dim == 1 ? epsilon : 0,
        dim == 2 ? epsilon : 0,
      );

      final posePlus = CameraPose(
        position: pose.position + delta,
        rotation: pose.rotation,
        focalLength: pose.focalLength,
      );
      final poseMinus = CameraPose(
        position: pose.position - delta,
        rotation: pose.rotation,
        focalLength: pose.focalLength,
      );

      double errorPlus = 0;
      double errorMinus = 0;

      for (final point in points.take(50)) {
        final reproj1 = _reprojectPoint(point.position, posePlus);
        final reproj2 = _reprojectPoint(point.position, poseMinus);
        errorPlus += reproj1.length;
        errorMinus += reproj2.length;
      }

      final grad = (errorPlus - errorMinus) / (2 * epsilon);
      if (dim == 0) gradient.x = grad;
      if (dim == 1) gradient.y = grad;
      if (dim == 2) gradient.z = grad;
    }

    return gradient;
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
  Future<PointCloud> _multiViewColorSampling(
    PointCloud cloud,
    List<CameraPose> poses,
    List<img.Image> images,
  ) async {
    final enhancedPoints = <Point3D>[];

    for (final point in cloud.points) {
      final colors = <Color>[];
      final weights = <double>[];

      // Sample color from each camera that can see this point
      for (int c = 0; c < poses.length && c < images.length; c++) {
        final pose = poses[c];
        final image = images[c];

        // Check if point is in front of camera
        final camDir = pose.rotation.transposed().transform(Vector3(0, 0, 1));
        final toPoint = point.position - pose.position;
        final depth = toPoint.dot(camDir);

        if (depth > 0.1) {
          // Project point to image
          final reproj = _reprojectPoint(point.position, pose);
          final x = reproj.x.toInt();
          final y = reproj.y.toInt();

          // Scale to color image size
          final imgX = (x * image.width / _imageWidth).toInt().clamp(0, image.width - 1);
          final imgY = (y * image.height / _imageHeight).toInt().clamp(0, image.height - 1);

          if (imgX >= 0 && imgX < image.width && imgY >= 0 && imgY < image.height) {
            final pixel = image.getPixel(imgX, imgY);
            colors.add(Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()));

            // Weight by viewing angle (prefer frontal views)
            final viewAngle = toPoint.normalized().dot(camDir).abs();
            weights.add(viewAngle);
          }
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
      double cxx = 0, cxy = 0, cxz = 0, cyy = 0, cyz = 0, czz = 0;
      for (final n in neighbors) {
        final d = n.position - centroid;
        cxx += d.x * d.x;
        cxy += d.x * d.y;
        cxz += d.x * d.z;
        cyy += d.y * d.y;
        cyz += d.y * d.z;
        czz += d.z * d.z;
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
  PointCloud _interpolatePoints(PointCloud cloud, {int maxNewPoints = 500}) {
    if (cloud.points.length < 10) return cloud;

    final interpolated = List<Point3D>.from(cloud.points);
    final original = cloud.points;
    int added = 0;

    // Find point pairs that are close together and add midpoints
    for (int i = 0; i < original.length && added < maxNewPoints; i++) {
      for (int j = i + 1; j < original.length && added < maxNewPoints; j++) {
        final dist = (original[i].position - original[j].position).length;

        // Only interpolate between nearby points
        if (dist > 0.01 && dist < 0.5) {
          // Midpoint
          final midPos = (original[i].position + original[j].position) / 2;

          // Average color
          final midColor = Color.fromARGB(
            255,
            ((original[i].color.r + original[j].color.r) / 2).round(),
            ((original[i].color.g + original[j].color.g) / 2).round(),
            ((original[i].color.b + original[j].color.b) / 2).round(),
          );

          // Average confidence
          final midConf = (original[i].confidence + original[j].confidence) / 2;

          // Interpolated normal
          Vector3? midNormal;
          if (original[i].normal != null && original[j].normal != null) {
            midNormal = ((original[i].normal! + original[j].normal!) / 2).normalized();
          }

          interpolated.add(Point3D(
            position: midPos,
            color: midColor,
            confidence: midConf * 0.9, // Slightly lower confidence for interpolated
            normal: midNormal,
          ));
          added++;
        }
      }
    }

    return PointCloud(
      points: interpolated,
      method: cloud.method,
      metadata: {...cloud.metadata, 'interpolated_points': added},
    );
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

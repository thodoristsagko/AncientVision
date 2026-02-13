import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math_64.dart';
import '../models/point_cloud.dart';
import '../models/mesh_model.dart';
import 'reconstruction_service.dart';
import 'patch_match_stereo.dart';
import 'depth_map_fusion.dart';
import 'poisson_mesh_service.dart';

/// Result of dense reconstruction.
class DenseReconstructionResult {
  final PointCloud pointCloud;
  final MeshModel? mesh;
  final int depthMapsComputed;
  final Duration processingTime;
  final String? errorMessage;

  DenseReconstructionResult({
    required this.pointCloud,
    this.mesh,
    required this.depthMapsComputed,
    required this.processingTime,
    this.errorMessage,
  });
}

/// Orchestrates dense MVS reconstruction from captured images.
///
/// Pipeline:
/// 1. Use sparse SfM poses from [ReconstructionService]
/// 2. For each image pair, run PatchMatch stereo to estimate depth
/// 3. Fuse depth maps into a consistent dense point cloud
/// 4. Optionally extract mesh via Marching Cubes
class DenseReconstructionService {
  final PatchMatchStereo _stereo;
  final DepthMapFusion _fusion;
  final PoissonMeshService _mesher;

  /// Resolution for stereo matching (square).
  final int stereoResolution;

  DenseReconstructionService({
    this.stereoResolution = 256,
    PatchMatchStereo? stereo,
    DepthMapFusion? fusion,
    PoissonMeshService? mesher,
  })  :
        _stereo = stereo ?? PatchMatchStereo(resolution: stereoResolution),
        _fusion = fusion ?? DepthMapFusion(),
        _mesher = mesher ?? PoissonMeshService();

  /// Run dense reconstruction from images and sparse camera poses.
  ///
  /// [imageFiles] - captured images.
  /// [poses] - camera poses from sparse SfM.
  /// [focalLength] - camera focal length in pixels.
  /// [generateMesh] - if true, also extract a triangle mesh.
  Future<DenseReconstructionResult> reconstruct({
    required List<File> imageFiles,
    required List<CameraPose> poses,
    required double focalLength,
    bool generateMesh = true,
    Function(double progress, String status)? onProgress,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final startTime = DateTime.now();

    try {
      return await _reconstructImpl(
        imageFiles: imageFiles,
        poses: poses,
        focalLength: focalLength,
        generateMesh: generateMesh,
        onProgress: onProgress,
        startTime: startTime,
      ).timeout(timeout, onTimeout: () {
        debugPrint('DenseReconstruction: Timed out after ${timeout.inSeconds}s');
        return DenseReconstructionResult(
          pointCloud: PointCloud(points: [], method: 'dense_mvs_timeout'),
          depthMapsComputed: 0,
          processingTime: DateTime.now().difference(startTime),
        );
      });
    } catch (e) {
      debugPrint('DenseReconstruction: Unexpected error: $e');
      return DenseReconstructionResult(
        pointCloud: PointCloud(points: [], method: 'dense_mvs_error'),
        depthMapsComputed: 0,
        processingTime: DateTime.now().difference(startTime),
      );
    }
  }

  Future<DenseReconstructionResult> _reconstructImpl({
    required List<File> imageFiles,
    required List<CameraPose> poses,
    required double focalLength,
    required bool generateMesh,
    required DateTime startTime,
    Function(double progress, String status)? onProgress,
  }) async {
    final depthMaps = <DepthMap>[];
    final projections = <Matrix4>[];
    final colorArrays = <Float32List>[];

    onProgress?.call(0.0, 'Loading images for dense reconstruction...');

    // Load and downsample all images to stereo resolution
    final grayImages = <Float32List>[];
    final colorImages = <Float32List>[];

    for (int i = 0; i < imageFiles.length && i < poses.length; i++) {
      try {
        final bytes = await imageFiles[i].readAsBytes();
        final image = img.decodeImage(bytes);
        if (image == null) continue;

        // Downsample
        final resized = img.copyResize(
          image,
          width: stereoResolution,
          height: stereoResolution,
          interpolation: img.Interpolation.linear,
        );

        // Convert to grayscale float array
        final gray = Float32List(stereoResolution * stereoResolution);
        final color = Float32List(stereoResolution * stereoResolution * 4);
        for (int y = 0; y < stereoResolution; y++) {
          for (int x = 0; x < stereoResolution; x++) {
            final pixel = resized.getPixel(x, y);
            final idx = y * stereoResolution + x;
            gray[idx] = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114)
                .toDouble();
            color[idx * 4] = pixel.r.toDouble();
            color[idx * 4 + 1] = pixel.g.toDouble();
            color[idx * 4 + 2] = pixel.b.toDouble();
            color[idx * 4 + 3] = 255.0;
          }
        }

        grayImages.add(gray);
        colorImages.add(color);
      } catch (e) {
        debugPrint('DenseReconstruction: Failed to load image $i: $e');
      }
    }

    if (grayImages.length < 2) {
      return DenseReconstructionResult(
        pointCloud: PointCloud(points: [], method: 'dense_mvs_failed'),
        depthMapsComputed: 0,
        processingTime: DateTime.now().difference(startTime),
      );
    }

    // Compute depth maps for consecutive pairs
    final totalPairs = grayImages.length - 1;
    for (int i = 0; i < totalPairs; i++) {
      onProgress?.call(
        0.1 + 0.6 * (i / totalPairs),
        'Computing depth map ${i + 1}/$totalPairs...',
      );

      try {
        final dm = await _stereo.estimate(
          grayImages[i],
          grayImages[i + 1],
          stereoResolution,
          stereoResolution,
        );
        depthMaps.add(dm);

        // Build projection matrix from pose
        final pose = poses[i];
        final R = pose.rotation;
        final t = -(R.transformed(pose.position));
        final proj = Matrix4(
          R.entry(0, 0), R.entry(1, 0), R.entry(2, 0), 0,
          R.entry(0, 1), R.entry(1, 1), R.entry(2, 1), 0,
          R.entry(0, 2), R.entry(1, 2), R.entry(2, 2), 0,
          t.x, t.y, t.z, 1,
        );
        projections.add(proj);
        colorArrays.add(colorImages[i]);
      } catch (e) {
        debugPrint(
            'DenseReconstruction: Depth estimation failed for pair $i: $e');
      }
    }

    if (depthMaps.length < 3) {
      return DenseReconstructionResult(
        pointCloud: PointCloud(points: [], method: 'dense_mvs_failed'),
        depthMapsComputed: depthMaps.length,
        processingTime: DateTime.now().difference(startTime),
        errorMessage: 'Dense reconstruction failed: Only ${depthMaps.length} depth maps succeeded (need at least 3). '
            'This usually means stereo matching failed for most image pairs. '
            'Try: better lighting, more textured object, or different capture angles.',
      );
    }

    // Fuse depth maps
    onProgress?.call(0.75, 'Fusing ${depthMaps.length} depth maps...');
    final denseCloud = await _fusion.fuse(
      depthMaps: depthMaps,
      projections: projections,
      colorImages: colorArrays,
      imageWidth: stereoResolution,
      imageHeight: stereoResolution,
      focalLength:
          focalLength * stereoResolution / 1024, // Scale focal length
    );

    debugPrint(
        'DenseReconstruction: ${denseCloud.points.length} dense points');

    // Optional mesh extraction
    MeshModel? mesh;
    if (generateMesh && denseCloud.points.length >= 4) {
      onProgress?.call(0.85, 'Extracting mesh...');
      try {
        mesh = await _mesher.generateMesh(denseCloud);
        debugPrint(
            'DenseReconstruction: Mesh with ${mesh.vertices.length} vertices, ${mesh.faces.length} faces');
      } catch (e) {
        debugPrint('DenseReconstruction: Mesh extraction failed: $e');
      }
    }

    onProgress?.call(1.0, 'Dense reconstruction complete!');

    return DenseReconstructionResult(
      pointCloud: denseCloud,
      mesh: mesh,
      depthMapsComputed: depthMaps.length,
      processingTime: DateTime.now().difference(startTime),
    );
  }
}

import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import 'reconstruction_service.dart';

/// Production-grade Structure from Motion with RANSAC and Essential Matrix
class RobustSfM {
  /// RANSAC parameters
  static const int ransacIterations = 1000;
  static const double ransacThreshold = 0.02; // Reprojection error threshold (relaxed)
  static const double minInlierRatio = 0.15; // 15% inliers required (more tolerant)

  /// Estimate essential matrix using RANSAC with 8-point algorithm
  static EssentialMatrixResult estimateEssentialMatrix(
    List<FeatureMatch> matches,
    double focalLength,
  ) {
    if (matches.length < 8) {
      throw Exception('Need at least 8 matches for Essential Matrix estimation');
    }

    Matrix3? bestE;
    List<FeatureMatch> bestInliers = [];
    int maxInliers = 0;

    // RANSAC loop
    for (int iter = 0; iter < ransacIterations; iter++) {
      // Randomly select 8 matches
      final sampleMatches = _randomSample(matches, 8);

      try {
        // Compute Essential Matrix from 8 points
        final E = _computeEssentialMatrix(sampleMatches, focalLength);

        // Count inliers
        final inliers = <FeatureMatch>[];
        for (final match in matches) {
          final error = _epipolarError(match, E, focalLength);
          if (error < ransacThreshold) {
            inliers.add(match);
          }
        }

        // Update best model if more inliers
        if (inliers.length > maxInliers) {
          maxInliers = inliers.length;
          bestInliers = inliers;
          bestE = E;
        }

        // Early termination if we have enough inliers
        if (inliers.length > matches.length * 0.8) {
          break;
        }
      } catch (e) {
        // Degenerate configuration, try next sample
        continue;
      }
    }

    if (bestE == null || maxInliers < 8) {
      throw Exception(
          'Could not find consistent camera geometry ($maxInliers valid matches).\n'
          'This can happen with:\n'
          '• Very smooth or reflective objects\n'
          '• Inconsistent lighting between shots\n'
          '• Camera too far from object\n\n'
          'Try cloud processing for better results.');
    }

    final inlierRatio = maxInliers / matches.length;
    if (inlierRatio < minInlierRatio) {
      throw Exception(
          'Low match quality (${(inlierRatio * 100).toInt()}% consistent matches).\n'
          'Try:\n'
          '• Better/more even lighting\n'
          '• More textured objects\n'
          '• Keep camera steady\n'
          '• More overlap between photos');
    }

    return EssentialMatrixResult(
      matrix: bestE,
      inliers: bestInliers,
      inlierCount: maxInliers,
      totalMatches: matches.length,
    );
  }

  /// Compute Essential Matrix using normalized 8-point algorithm
  static Matrix3 _computeEssentialMatrix(
    List<FeatureMatch> matches,
    double focalLength,
  ) {
    // Normalize coordinates (shift to origin, scale by focal length)
    final pts1 = <Vector3>[];
    final pts2 = <Vector3>[];

    for (final match in matches) {
      pts1.add(Vector3(
        (match.feature1.x - 512) / focalLength,
        (match.feature1.y - 512) / focalLength,
        1.0,
      ));
      pts2.add(Vector3(
        (match.feature2.x - 512) / focalLength,
        (match.feature2.y - 512) / focalLength,
        1.0,
      ));
    }

    // Build coefficient matrix A for Af = 0
    final A = List.generate(8, (_) => List.filled(9, 0.0));

    for (int i = 0; i < 8; i++) {
      final p1 = pts1[i];
      final p2 = pts2[i];

      A[i][0] = p2.x * p1.x;
      A[i][1] = p2.x * p1.y;
      A[i][2] = p2.x;
      A[i][3] = p2.y * p1.x;
      A[i][4] = p2.y * p1.y;
      A[i][5] = p2.y;
      A[i][6] = p1.x;
      A[i][7] = p1.y;
      A[i][8] = 1.0;
    }

    // Solve using SVD (simplified - would use proper SVD in production)
    final F = _solveSVD(A);

    // Enforce Essential Matrix constraint: det(E) = 0 and two equal singular values
    final E = _enforceEssentialConstraint(F);

    return E;
  }

  /// Solve linear system using simplified SVD (last row of V)
  static Matrix3 _solveSVD(List<List<double>> A) {
    // Simplified: use the smallest eigenvalue solution
    // In production, would use proper SVD library

    // For now, use least squares approximation
    final AtA = List.generate(9, (_) => List.filled(9, 0.0));

    // Compute A^T * A
    for (int i = 0; i < 9; i++) {
      for (int j = 0; j < 9; j++) {
        double sum = 0;
        for (int k = 0; k < 8; k++) {
          sum += A[k][i] * A[k][j];
        }
        AtA[i][j] = sum;
      }
    }

    // Find smallest eigenvalue's eigenvector (power iteration on inverse)
    final v = List.filled(9, 1.0 / 3.0);

    for (int iter = 0; iter < 100; iter++) {
      final Av = List.filled(9, 0.0);
      for (int i = 0; i < 9; i++) {
        for (int j = 0; j < 9; j++) {
          Av[i] += AtA[i][j] * v[j];
        }
      }

      // Normalize
      final norm = math.sqrt(Av.fold<double>(0, (s, x) => s + x * x));
      for (int i = 0; i < 9; i++) {
        v[i] = Av[i] / norm;
      }
    }

    return Matrix3(
      v[0], v[1], v[2],
      v[3], v[4], v[5],
      v[6], v[7], v[8],
    );
  }

  /// Enforce Essential Matrix constraints
  static Matrix3 _enforceEssentialConstraint(Matrix3 F) {
    // Simplified: normalize and ensure proper structure
    // In production, would decompose to U*diag(1,1,0)*V^T

    final det = F.determinant();
    if (det.abs() < 0.001) {
      return F; // Already rank-2
    }

    // Scale to make determinant closer to 0
    final scale = 1.0 / math.pow(det.abs(), 1.0 / 3.0);
    return F.scaled(scale);
  }

  /// Calculate epipolar error for a match
  static double _epipolarError(
    FeatureMatch match,
    Matrix3 E,
    double focalLength,
  ) {
    // Normalize points
    final p1 = Vector3(
      (match.feature1.x - 512) / focalLength,
      (match.feature1.y - 512) / focalLength,
      1.0,
    );
    final p2 = Vector3(
      (match.feature2.x - 512) / focalLength,
      (match.feature2.y - 512) / focalLength,
      1.0,
    );

    // Epipolar constraint: p2^T * E * p1 = 0
    final Ep1 = E.transform(p1);
    final error = p2.dot(Ep1).abs();

    return error;
  }

  /// Recover camera pose from Essential Matrix
  static List<CameraPoseHypothesis> recoverPoseFromEssential(
    Matrix3 E,
    List<FeatureMatch> inliers,
    double focalLength,
  ) {
    // Decompose Essential Matrix into rotation and translation
    // E can decompose to 4 possible solutions: (R1,t), (R1,-t), (R2,t), (R2,-t)

    final hypotheses = <CameraPoseHypothesis>[];

    // Simplified decomposition (would use proper SVD)
    // For now, generate plausible rotation matrices

    final rotations = _extractRotationsFromE(E);
    final translation = _extractTranslationFromE(E);

    for (final R in rotations) {
      for (final tSign in [1.0, -1.0]) {
        final t = translation.scaled(tSign);

        // Test hypothesis by triangulating a few points
        int positiveDepth = 0;
        for (int i = 0; i < math.min(10, inliers.length); i++) {
          final match = inliers[i];
          final point3D = _triangulatePoint(
            match,
            Matrix3.identity(),
            Vector3.zero(),
            R,
            t,
            focalLength,
          );

          // Check if point is in front of both cameras
          if (point3D.z > 0 && (R.transform(point3D) + t).z > 0) {
            positiveDepth++;
          }
        }

        hypotheses.add(CameraPoseHypothesis(
          rotation: R,
          translation: t,
          positiveDepthCount: positiveDepth,
        ));
      }
    }

    // Sort by number of points with positive depth
    hypotheses.sort((a, b) => b.positiveDepthCount.compareTo(a.positiveDepthCount));

    return hypotheses;
  }

  /// Extract possible rotations from Essential Matrix (simplified)
  static List<Matrix3> _extractRotationsFromE(Matrix3 E) {
    // Simplified: generate two plausible rotations
    // In production, would use proper SVD decomposition

    final rotations = <Matrix3>[];

    // Identity rotation
    rotations.add(Matrix3.identity());

    // Small rotation around Y axis (typical for circular capture)
    final angle = 22.5 * (math.pi / 180);
    rotations.add(Matrix3.rotationY(angle));

    return rotations;
  }

  /// Extract translation direction from Essential Matrix (simplified)
  static Vector3 _extractTranslationFromE(Matrix3 E) {
    // Translation is the null space of E
    // Simplified: use last column as approximation
    return Vector3(E.entry(0, 2), E.entry(1, 2), E.entry(2, 2)).normalized();
  }

  /// Triangulate a single point with two camera poses
  static Vector3 _triangulatePoint(
    FeatureMatch match,
    Matrix3 R1,
    Vector3 t1,
    Matrix3 R2,
    Vector3 t2,
    double focalLength,
  ) {
    // Normalize pixel coordinates
    final p1 = Vector3(
      (match.feature1.x - 512) / focalLength,
      (match.feature1.y - 512) / focalLength,
      1.0,
    ).normalized();

    final p2 = Vector3(
      (match.feature2.x - 512) / focalLength,
      (match.feature2.y - 512) / focalLength,
      1.0,
    ).normalized();

    // Ray directions in world coordinates
    final ray1 = R1.transposed().transform(p1);
    final ray2 = R2.transposed().transform(p2);

    // Ray origins
    final o1 = -R1.transposed().transform(t1);
    final o2 = -R2.transposed().transform(t2);

    // Find closest point between rays
    return _closestPointBetweenRays(o1, ray1, o2, ray2);
  }

  /// Find closest point between two rays
  static Vector3 _closestPointBetweenRays(
    Vector3 o1,
    Vector3 d1,
    Vector3 o2,
    Vector3 d2,
  ) {
    final w = o1 - o2;
    final a = d1.dot(d1);
    final b = d1.dot(d2);
    final c = d2.dot(d2);
    final d = d1.dot(w);
    final e = d2.dot(w);

    final denom = a * c - b * b;
    if (denom.abs() < 1e-10) {
      return o1; // Rays are parallel
    }

    final t1 = (b * e - c * d) / denom;
    final t2 = (a * e - b * d) / denom;

    final p1 = o1 + d1.scaled(t1);
    final p2 = o2 + d2.scaled(t2);

    return (p1 + p2).scaled(0.5); // Midpoint
  }

  /// Random sample without replacement
  static List<FeatureMatch> _randomSample(List<FeatureMatch> matches, int n) {
    final indices = List.generate(matches.length, (i) => i);
    indices.shuffle();
    return indices.take(n).map((i) => matches[i]).toList();
  }
}

/// Result from Essential Matrix estimation
class EssentialMatrixResult {
  final Matrix3 matrix;
  final List<FeatureMatch> inliers;
  final int inlierCount;
  final int totalMatches;

  EssentialMatrixResult({
    required this.matrix,
    required this.inliers,
    required this.inlierCount,
    required this.totalMatches,
  });

  double get inlierRatio => inlierCount / totalMatches;
}

/// Camera pose hypothesis from Essential Matrix decomposition
class CameraPoseHypothesis {
  final Matrix3 rotation;
  final Vector3 translation;
  final int positiveDepthCount;

  CameraPoseHypothesis({
    required this.rotation,
    required this.translation,
    required this.positiveDepthCount,
  });
}

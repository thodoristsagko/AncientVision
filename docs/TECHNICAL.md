# AncientVision Technical Architecture

Deep dive into system design, algorithms, and implementation details.

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [3D Reconstruction Algorithms](#3d-reconstruction-algorithms)
3. [Services Layer](#services-layer)
4. [Data Models](#data-models)
5. [Firebase Integration](#firebase-integration)
6. [Performance Optimizations](#performance-optimizations)
7. [Dependencies](#dependencies)

---

## System Architecture

### Layer Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                       │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │Dashboard│ │Findings │ │  Tools  │ │ Safety  │           │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘           │
│       │           │           │           │                  │
│  ┌────┴───────────┴───────────┴───────────┴────┐           │
│  │              Widget Library                   │           │
│  │  LiquidGlass | PointCloudPainter | Model3D   │           │
│  └──────────────────────┬───────────────────────┘           │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                  BUSINESS LOGIC LAYER                        │
│  ┌──────────────────────┴───────────────────────┐           │
│  │                 Services                       │           │
│  │  AuthService | FirebaseService | ImageService │           │
│  │  ReconstructionService | LocalStorageService  │           │
│  │  PDFReportService | RobustSfM                 │           │
│  └──────────────────────┬───────────────────────┘           │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                     DATA LAYER                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │ Firebase │  │  ImgBB   │  │  Local   │                   │
│  │Firestore │  │   API    │  │ Storage  │                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                  HARDWARE LAYER                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │  Camera  │  │   BLE    │  │   GPS    │                   │
│  │  Sensor  │  │ M5StickC │  │  Sensor  │                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

### File Structure

```
lib/
├── main.dart                    # 10,000+ lines - Core application
│   ├── MyApp                    # Root widget
│   ├── AuthScreen               # Login/register
│   ├── MainScreen               # Navigation scaffold
│   ├── _DashboardHomeView       # Statistics & overview
│   ├── _FindingsView            # Gallery & map
│   ├── _ToolsView               # Feature hub
│   ├── _SafetyView              # Sensor monitoring
│   ├── ManualEntryFormScreen    # Documentation form
│   ├── PhotogrammetryScreen     # 3D capture
│   ├── PDFExportScreen          # Report generation
│   └── ExportDataScreen         # Data export
│
├── services/
│   ├── auth_service.dart        # Firebase Auth wrapper
│   ├── firebase_service.dart    # Firestore operations
│   ├── reconstruction_service.dart  # 3D pipeline
│   ├── sfm_robust.dart          # SfM algorithms
│   ├── image_service.dart       # Compression & analysis
│   ├── pdf_report_service.dart  # PDF generation
│   └── local_storage_service.dart   # Offline support
│
├── models/
│   ├── point_cloud.dart         # PointCloud, Point3D
│   ├── mesh_model.dart          # MeshModel, MeshVertex, MeshFace
│   └── reconstruction_result.dart   # Processing results
│
├── widgets/
│   ├── point_cloud_painter.dart # 3D rendering
│   ├── model_3d_viewer.dart     # Interactive viewer
│   └── liquid_glass.dart        # Glassmorphism UI
│
└── utils/
    └── quality_analyzer.dart    # Image quality metrics
```

---

## 3D Reconstruction Algorithms

### Overview

AncientVision implements real Structure from Motion (SfM) - not simulation. The pipeline uses established computer vision algorithms.

### Pipeline Steps

```
Input Images (8-16 photos)
        │
        ▼
┌───────────────────────┐
│  1. PREPROCESSING     │
│  - Load images        │
│  - Downsample if >4MP │
│  - Convert to gray    │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  2. FEATURE DETECTION │
│  - Harris corners     │
│  - Non-max suppression│
│  - Top 300 features   │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  3. FEATURE MATCHING  │
│  - Cross-correlation  │
│  - Distance threshold │
│  - Ratio test         │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  4. ESSENTIAL MATRIX  │
│  - 8-point algorithm  │
│  - Normalized coords  │
│  - SVD decomposition  │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  5. RANSAC FILTERING  │
│  - 1000 iterations    │
│  - Inlier threshold   │
│  - Best model select  │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  6. POSE RECOVERY     │
│  - Decompose E matrix │
│  - Cheirality check   │
│  - R, t extraction    │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  7. TRIANGULATION     │
│  - Linear method      │
│  - Point projection   │
│  - Depth validation   │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  8. BUNDLE ADJUSTMENT │
│  - Optimize poses     │
│  - Refine 3D points   │
│  - Minimize reproj.   │
└───────────┬───────────┘
            │
            ▼
    Point Cloud Output
```

### Algorithm Details

#### Harris Corner Detection

Detects interest points by computing the corner response function:

```
R = det(M) - k * trace(M)²

where M = [Ix²    IxIy]
          [IxIy   Iy² ]
```

**Implementation:** `lib/services/sfm_robust.dart:_extractFeatures()`

```dart
List<FeaturePoint> _extractFeatures(img.Image image) {
  final gray = _toGrayscale(image);
  final List<FeaturePoint> features = [];

  // Compute gradients
  for (int y = 1; y < height - 1; y++) {
    for (int x = 1; x < width - 1; x++) {
      final ix = gray[y][x + 1] - gray[y][x - 1];
      final iy = gray[y + 1][x] - gray[y - 1][x];

      // Harris matrix elements
      final ix2 = ix * ix;
      final iy2 = iy * iy;
      final ixy = ix * iy;

      // Corner response
      final det = ix2 * iy2 - ixy * ixy;
      final trace = ix2 + iy2;
      final response = det - 0.04 * trace * trace;

      if (response > threshold) {
        features.add(FeaturePoint(x, y, response));
      }
    }
  }

  // Non-maximum suppression
  return _nonMaxSuppression(features, 300);
}
```

#### 8-Point Algorithm

Estimates the Essential Matrix from point correspondences:

```
x'ᵀ E x = 0

where E = [e1 e2 e3]
          [e4 e5 e6]
          [e7 e8 e9]
```

**Implementation:** `lib/services/sfm_robust.dart:_computeEssentialMatrix()`

```dart
List<List<double>> _computeEssentialMatrix(
  List<FeatureMatch> matches,
  double fx, double fy, double cx, double cy,
) {
  // Normalize coordinates
  final List<List<double>> normalizedPts1 = [];
  final List<List<double>> normalizedPts2 = [];

  for (final match in matches) {
    normalizedPts1.add([
      (match.pt1.x - cx) / fx,
      (match.pt1.y - cy) / fy,
    ]);
    normalizedPts2.add([
      (match.pt2.x - cx) / fx,
      (match.pt2.y - cy) / fy,
    ]);
  }

  // Build constraint matrix A
  // Each match contributes one row
  final A = List.generate(matches.length, (i) {
    final x1 = normalizedPts1[i][0];
    final y1 = normalizedPts1[i][1];
    final x2 = normalizedPts2[i][0];
    final y2 = normalizedPts2[i][1];

    return [
      x2*x1, x2*y1, x2,
      y2*x1, y2*y1, y2,
      x1, y1, 1.0,
    ];
  });

  // Solve Ae = 0 using SVD
  final svd = _computeSVD(A);
  final e = svd.vt.last; // Last row of Vᵀ

  // Reshape to 3x3 matrix
  return _reshapeTo3x3(e);
}
```

#### RANSAC (Random Sample Consensus)

Robustly estimates Essential Matrix despite outliers:

```
Parameters:
- Iterations: 1000
- Sample size: 8 points
- Inlier threshold: 0.01 (normalized coordinates)
- Min inlier ratio: 30%
```

**Implementation:** `lib/services/sfm_robust.dart:_ransacEssentialMatrix()`

```dart
Map<String, dynamic> _ransacEssentialMatrix(
  List<FeatureMatch> matches,
  double fx, double fy, double cx, double cy,
) {
  List<List<double>>? bestE;
  List<FeatureMatch> bestInliers = [];

  for (int iter = 0; iter < 1000; iter++) {
    // Random 8-point sample
    final sample = _randomSample(matches, 8);

    // Compute E from sample
    final E = _computeEssentialMatrix(sample, fx, fy, cx, cy);

    // Count inliers
    final inliers = <FeatureMatch>[];
    for (final match in matches) {
      final error = _sampsonError(match, E, fx, fy, cx, cy);
      if (error < 0.01) {
        inliers.add(match);
      }
    }

    // Update best
    if (inliers.length > bestInliers.length) {
      bestE = E;
      bestInliers = inliers;
    }
  }

  return {'E': bestE, 'inliers': bestInliers};
}
```

#### Triangulation

Computes 3D points from matched 2D points and camera poses:

```
Linear triangulation:
A * X = 0

where A = [x(P₃ᵀ) - P₁ᵀ]
          [y(P₃ᵀ) - P₂ᵀ]
          [x'(P'₃ᵀ) - P'₁ᵀ]
          [y'(P'₃ᵀ) - P'₂ᵀ]
```

**Implementation:** `lib/services/sfm_robust.dart:_triangulatePoint()`

```dart
Vector3? _triangulatePoint(
  FeatureMatch match,
  Matrix4 P1,
  Matrix4 P2,
) {
  // Build 4x4 matrix A
  final A = [
    _subtractRows(match.pt1.x * P1.row2, P1.row0),
    _subtractRows(match.pt1.y * P1.row2, P1.row1),
    _subtractRows(match.pt2.x * P2.row2, P2.row0),
    _subtractRows(match.pt2.y * P2.row2, P2.row1),
  ];

  // Solve via SVD
  final svd = _computeSVD(A);
  final X = svd.vt.last;

  // Homogeneous to 3D
  if (X[3].abs() < 1e-10) return null;

  return Vector3(
    X[0] / X[3],
    X[1] / X[3],
    X[2] / X[3],
  );
}
```

### Quality Metrics

#### Reprojection Error

Measures how well 3D points project back to 2D:

```dart
double _computeReprojectionError(
  Vector3 point3D,
  FeaturePoint observed,
  Matrix4 P,
) {
  // Project 3D point
  final projected = P.transform3(point3D);
  final x = projected.x / projected.z;
  final y = projected.y / projected.z;

  // Euclidean distance
  return sqrt(pow(x - observed.x, 2) + pow(y - observed.y, 2));
}
```

**Target:** <2.0 pixels average

#### Coverage

Percentage of input images contributing to reconstruction:

```dart
double coverage = validPairs / totalPairs * 100;
```

**Target:** >60%

---

## Services Layer

### AuthService

**File:** `lib/services/auth_service.dart`

```dart
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Email/password registration
  Future<UserCredential> registerWithEmail(
    String email,
    String password,
    String fullName,
  );

  // Email/password login
  Future<UserCredential> signInWithEmail(String email, String password);

  // Google OAuth
  Future<UserCredential> signInWithGoogle();

  // Sign out
  Future<void> signOut();

  // Log activity to Firestore
  Future<void> logActivity(String action, Map<String, dynamic> details);
}
```

### ReconstructionService

**File:** `lib/services/reconstruction_service.dart`

```dart
class ReconstructionService {
  // Detect device capabilities
  Future<ReconstructionCapabilities> detectCapabilities();

  // Get available methods
  List<ReconstructionMethod> getAvailableMethods();

  // Run reconstruction
  Future<ReconstructionResult> reconstruct({
    required List<XFile> images,
    ReconstructionMethod? preferredMethod,
    Function(double progress, String status)? onProgress,
  });

  // Cancel ongoing reconstruction
  void cancel();

  // Export point cloud
  Future<String> exportToPLY(PointCloud pointCloud);
}
```

### ImageService

**File:** `lib/services/image_service.dart`

```dart
class ImageService {
  // Compress image (10x reduction)
  Future<File> compressImage(
    File imageFile, {
    int maxWidth = 1920,
    int maxHeight = 1920,
    int quality = 85,
  });

  // Generate thumbnail
  Future<File> compressForThumbnail(
    File imageFile, {
    int size = 400,
    int quality = 70,
  });

  // Analyze image quality
  Future<ImageQualityResult> analyzeQuality(File imageFile);
}
```

### LocalStorageService

**File:** `lib/services/local_storage_service.dart`

```dart
class LocalStorageService {
  // Form drafts
  Future<void> saveFormDraft({
    required String formId,
    required Map<String, dynamic> data,
  });
  Future<Map<String, dynamic>?> getFormDraft(String formId);
  Future<void> clearFormDraft(String formId);

  // Finding cache
  Future<void> cacheFinding({
    required String findingId,
    required Map<String, dynamic> data,
  });
  Map<String, dynamic>? getCachedFinding(String findingId);

  // Upload queue
  Future<void> queueForUpload({
    required String findingId,
    required Map<String, dynamic> data,
  });
  List<String> getPendingUploads();
  Future<int> syncPendingUploads();
}
```

---

## Data Models

### Point3D

```dart
class Point3D {
  final Vector3 position;  // XYZ coordinates
  final Color color;       // RGBA color
  final double confidence; // 0.0-1.0

  Map<String, dynamic> toJson();
  factory Point3D.fromJson(Map<String, dynamic> json);
}
```

### PointCloud

```dart
class PointCloud {
  final List<Point3D> points;
  final String method;           // 'sparse_sfm', 'dense_mvs'
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  // Computed properties
  ({Vector3 min, Vector3 max}) getBoundingBox();
  Vector3 getCenter();

  // Export
  String toPLY();
  Map<String, dynamic> toJson();
}
```

### ReconstructionResult

```dart
class ReconstructionResult {
  final String id;
  final ReconstructionMethod method;
  final ReconstructionStatus status;
  final PointCloud? pointCloud;
  final MeshModel? mesh;
  final double progress;           // 0.0-1.0
  final String? statusMessage;
  final String? errorMessage;
  final int? inputImageCount;
  final double? processingTimeSeconds;
  final Map<String, dynamic> qualityMetrics;
  final String? exportPath;
  final List<String> exportedFiles;
}

enum ReconstructionMethod {
  sparseSfm,
  cloudProcessing,
  huawei3DKit,
  automatic,
}

enum ReconstructionStatus {
  idle,
  loading,
  extractingFeatures,
  matchingFeatures,
  estimatingPoses,
  triangulating,
  bundleAdjusting,
  generatingMesh,
  texturing,
  completed,
  failed,
  cancelled,
}
```

---

## Firebase Integration

### Firestore Schema

```
┌─────────────────────────────────────────────────────────────┐
│                       FIRESTORE                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  findings/                                                   │
│  └── {findingId}                                            │
│      ├── name: string                                       │
│      ├── type: string                                       │
│      ├── site: string                                       │
│      ├── date: string                                       │
│      ├── description: string                                │
│      ├── latitude: number                                   │
│      ├── longitude: number                                  │
│      ├── imageUrl: string                                   │
│      ├── photoGallery: string[]                             │
│      ├── model3dUrl: string                                 │
│      ├── findNumber: string                                 │
│      ├── excavationUnit: string                             │
│      ├── stratigraphicLayer: string                         │
│      ├── depthBelowSurface: string                          │
│      ├── depthBelowDatum: string                            │
│      ├── lengthMm: string                                   │
│      ├── widthMm: string                                    │
│      ├── heightMm: string                                   │
│      ├── weightGrams: string                                │
│      ├── material: string                                   │
│      ├── condition: string                                  │
│      ├── datingMethod: string                               │
│      ├── culturalPeriod: string                             │
│      ├── soilType: string                                   │
│      ├── munsellColor: string                               │
│      ├── associatedFinds: string                            │
│      ├── fieldNotes: string                                 │
│      ├── excavatorName: string                              │
│      ├── weatheringDegree: string                           │
│      ├── reconstructionData: map                            │
│      └── createdAt: timestamp                               │
│                                                              │
│  account_logs/                                               │
│  └── {logId}                                                │
│      ├── action: string                                     │
│      ├── userId: string                                     │
│      ├── email: string                                      │
│      ├── timestamp: timestamp                               │
│      └── details: string                                    │
│                                                              │
│  safety_alerts/                                              │
│  └── {alertId}                                              │
│      ├── level: string                                      │
│      ├── message: string                                    │
│      ├── vibration: number                                  │
│      ├── moisture: number                                   │
│      ├── timestamp: timestamp                               │
│      └── source: string                                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Security Rules

```javascript
// firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Findings - authenticated users only
    match /findings/{findingId} {
      allow read, write: if request.auth != null;
    }

    // Account logs - write only, no read
    match /account_logs/{logId} {
      allow create: if request.auth != null;
      allow read: if false;
    }

    // Safety alerts - authenticated users
    match /safety_alerts/{alertId} {
      allow read, write: if request.auth != null;
    }
  }
}
```

---

## Performance Optimizations

### Image Compression

**Before:** 5 MB per photo
**After:** 500 KB per photo (90% reduction)

```dart
// Compression strategy
final compressedFile = await imageService.compressImage(
  originalFile,
  maxWidth: 1920,    // Max dimension
  maxHeight: 1920,
  quality: 85,       // JPEG quality
);
```

### Memory Management

```dart
// Downsample large images for reconstruction
img.Image _downsampleIfNeeded(img.Image image) {
  const maxDimension = 1024;
  if (image.width > maxDimension || image.height > maxDimension) {
    final scale = maxDimension / max(image.width, image.height);
    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
    );
  }
  return image;
}
```

### Parallel Processing

```dart
// Feature extraction in parallel
final futures = images.map((img) => compute(_extractFeatures, img));
final allFeatures = await Future.wait(futures);
```

### Offline Queue

```dart
// Save locally if offline
try {
  await FirebaseFirestore.instance
      .collection('findings')
      .doc(id)
      .set(data)
      .timeout(Duration(seconds: 15));
} catch (e) {
  await LocalStorageService().queueForUpload(
    findingId: id,
    data: data,
  );
}
```

---

## Dependencies

### Core Flutter

| Package | Version | Purpose |
|---------|---------|---------|
| flutter | SDK | Framework |
| cupertino_icons | ^1.0.6 | iOS icons |

### Firebase

| Package | Version | Purpose |
|---------|---------|---------|
| firebase_core | ^2.24.2 | Firebase init |
| cloud_firestore | ^4.14.0 | Database |
| firebase_auth | ^4.16.0 | Authentication |
| firebase_storage | ^11.6.0 | File storage |

### Authentication

| Package | Version | Purpose |
|---------|---------|---------|
| google_sign_in | ^6.2.1 | Google OAuth |

### Maps & Location

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_map | ^6.1.0 | Map widget |
| latlong2 | ^0.9.0 | Coordinates |

### Camera & Media

| Package | Version | Purpose |
|---------|---------|---------|
| image_picker | ^1.0.7 | Photo capture |
| camera | ^0.10.5+9 | Camera control |
| video_player | ^2.8.2 | Video playback |
| image | ^4.1.7 | Image processing |

### 3D & Math

| Package | Version | Purpose |
|---------|---------|---------|
| vector_math | ^2.1.4 | 3D math |
| model_viewer_plus | ^1.7.0 | 3D viewer |

### Sensors & BLE

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_blue_plus | ^1.31.0 | Bluetooth |
| sensors_plus | ^4.0.2 | IMU, compass |

### Voice

| Package | Version | Purpose |
|---------|---------|---------|
| speech_to_text | ^6.6.0 | Voice input |
| flutter_tts | ^4.0.2 | Voice output |

### Storage & Files

| Package | Version | Purpose |
|---------|---------|---------|
| shared_preferences | ^2.2.2 | Local KV store |
| path_provider | ^2.1.1 | File paths |
| archive | ^3.4.10 | ZIP files |

### Export & Sharing

| Package | Version | Purpose |
|---------|---------|---------|
| pdf | ^3.10.7 | PDF creation |
| share_plus | ^7.2.1 | Share dialog |

### Utilities

| Package | Version | Purpose |
|---------|---------|---------|
| http | ^1.1.0 | HTTP requests |
| uuid | ^4.2.2 | UUID generation |
| intl | ^0.19.0 | Date formatting |

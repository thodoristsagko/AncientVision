# AncientVision API Reference

Complete reference for all services, models, and interfaces.

---

## Table of Contents

1. [Services](#services)
2. [Data Models](#data-models)
3. [Widgets](#widgets)
4. [Firebase Collections](#firebase-collections)
5. [External APIs](#external-apis)

---

## Services

### AuthService

**File:** `lib/services/auth_service.dart`

Authentication and user management.

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `registerWithEmail` | `email`, `password`, `fullName` | `Future<UserCredential>` | Create new account |
| `signInWithEmail` | `email`, `password` | `Future<UserCredential>` | Email login |
| `signInWithGoogle` | - | `Future<UserCredential>` | Google OAuth login |
| `signOut` | - | `Future<void>` | Sign out current user |
| `logActivity` | `action`, `details` | `Future<void>` | Log user activity |

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `authStateChanges` | `Stream<User?>` | Auth state stream |
| `currentUser` | `User?` | Current Firebase user |

#### Example

```dart
final auth = AuthService();

// Register
await auth.registerWithEmail(
  'user@example.com',
  'password123',
  'John Doe',
);

// Login
await auth.signInWithEmail('user@example.com', 'password123');

// Google Sign-In
await auth.signInWithGoogle();

// Listen to auth changes
auth.authStateChanges.listen((user) {
  if (user != null) {
    print('Logged in as ${user.email}');
  }
});
```

---

### FirebaseService

**File:** `lib/services/firebase_service.dart`

Firestore database operations.

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getFindings` | - | `Future<List<Finding>>` | Get all findings |
| `getFinding` | `id` | `Future<Finding?>` | Get single finding |
| `addFinding` | `finding` | `Future<String>` | Add new finding |
| `updateFinding` | `id`, `data` | `Future<void>` | Update finding |
| `deleteFinding` | `id` | `Future<void>` | Delete finding |
| `getNextId` | - | `Future<String>` | Get auto-increment ID |
| `findingsStream` | - | `Stream<List<Finding>>` | Real-time stream |

#### Example

```dart
final firebase = FirebaseService();

// Get all findings
final findings = await firebase.getFindings();

// Add finding
final id = await firebase.addFinding(Finding(
  name: 'Bronze Fibula',
  type: 'Metal Object',
  site: 'Amphipolis',
));

// Real-time updates
firebase.findingsStream.listen((findings) {
  print('Total findings: ${findings.length}');
});
```

---

### ReconstructionService

**File:** `lib/services/reconstruction_service.dart`

3D reconstruction pipeline.

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `detectCapabilities` | - | `Future<ReconstructionCapabilities>` | Check device support |
| `getAvailableMethods` | - | `List<ReconstructionMethod>` | List methods |
| `reconstruct` | `images`, `method?`, `onProgress?` | `Future<ReconstructionResult>` | Run reconstruction |
| `cancel` | - | `void` | Cancel processing |
| `exportToPLY` | `pointCloud` | `Future<String>` | Export to PLY file |

#### Enums

```dart
enum ReconstructionMethod {
  sparseSfm,        // On-device SfM
  cloudProcessing,  // Cloud API
  huawei3DKit,      // Huawei devices
  automatic,        // Auto-select best
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

#### Example

```dart
final service = ReconstructionService();

// Check capabilities
final caps = await service.detectCapabilities();
print('Sparse SfM: ${caps.supportsSparsePreview}');

// Run reconstruction
final result = await service.reconstruct(
  images: photoList,
  preferredMethod: ReconstructionMethod.sparseSfm,
  onProgress: (progress, status) {
    print('${(progress * 100).toInt()}% - $status');
  },
);

if (result.status == ReconstructionStatus.completed) {
  print('Points: ${result.pointCloud?.points.length}');

  // Export
  final path = await service.exportToPLY(result.pointCloud!);
  print('Exported to: $path');
}
```

---

### ImageService

**File:** `lib/services/image_service.dart`

Image processing and compression.

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `compressImage` | `file`, `maxWidth?`, `maxHeight?`, `quality?` | `Future<File>` | Compress image |
| `compressForThumbnail` | `file`, `size?`, `quality?` | `Future<File>` | Generate thumbnail |
| `analyzeQuality` | `file` | `Future<ImageQualityResult>` | Analyze quality |

#### Default Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `maxWidth` | 1920 | Max width in pixels |
| `maxHeight` | 1920 | Max height in pixels |
| `quality` | 85 | JPEG quality (0-100) |
| `size` | 400 | Thumbnail size |

#### Example

```dart
final imageService = ImageService();

// Compress for upload (10x smaller)
final compressed = await imageService.compressImage(
  originalFile,
  maxWidth: 1920,
  maxHeight: 1920,
  quality: 85,
);
print('Compressed: ${compressed.lengthSync()} bytes');

// Generate thumbnail
final thumb = await imageService.compressForThumbnail(
  originalFile,
  size: 200,
  quality: 70,
);

// Analyze quality
final quality = await imageService.analyzeQuality(originalFile);
print('Sharpness: ${quality.sharpness}');
print('Brightness: ${quality.brightness}');
print('Warnings: ${quality.warnings}');
```

---

### LocalStorageService

**File:** `lib/services/local_storage_service.dart`

Offline storage and sync.

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `saveFormDraft` | `formId`, `data` | `Future<void>` | Save form draft |
| `getFormDraft` | `formId` | `Future<Map?>` | Load form draft |
| `clearFormDraft` | `formId` | `Future<void>` | Delete draft |
| `cacheFinding` | `findingId`, `data` | `Future<void>` | Cache finding locally |
| `getCachedFinding` | `findingId` | `Map?` | Get cached finding |
| `queueForUpload` | `findingId`, `data` | `Future<void>` | Add to sync queue |
| `getPendingUploads` | - | `List<String>` | Get pending IDs |
| `syncPendingUploads` | - | `Future<int>` | Sync all pending |

#### Example

```dart
final storage = LocalStorageService();

// Auto-save form draft
await storage.saveFormDraft(
  formId: 'manual_entry',
  data: {
    'name': 'Bronze Coin',
    'type': 'Numismatic',
    'site': 'Delphi',
  },
);

// Recover draft on app restart
final draft = await storage.getFormDraft('manual_entry');
if (draft != null) {
  _nameController.text = draft['name'];
  // ... restore other fields
}

// Queue for offline upload
await storage.queueForUpload(
  findingId: '00042',
  data: findingData,
);

// Sync when online
final synced = await storage.syncPendingUploads();
print('Synced $synced findings');
```

---

### PDFReportService

**File:** `lib/services/pdf_report_service.dart`

PDF report generation.

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `generateReport` | `finding`, `photos?` | `Future<File>` | Generate PDF |
| `generateBatchReport` | `findings` | `Future<File>` | Multiple findings |

#### Example

```dart
final pdfService = PDFReportService();

// Generate single report
final pdfFile = await pdfService.generateReport(
  finding,
  photos: photoUrls,
);

// Share
await Share.shareXFiles([XFile(pdfFile.path)]);
```

---

### RobustSfM

**File:** `lib/services/sfm_robust.dart`

Low-level Structure from Motion algorithms.

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `processImages` | `images`, `onProgress?` | `Future<PointCloud?>` | Full SfM pipeline |

#### Internal Methods

| Method | Description |
|--------|-------------|
| `_extractFeatures` | Harris corner detection |
| `_matchFeatures` | Cross-correlation matching |
| `_computeEssentialMatrix` | 8-point algorithm |
| `_ransacEssentialMatrix` | RANSAC robust estimation |
| `_triangulatePoint` | Linear triangulation |
| `_bundleAdjust` | Optimize poses & points |

---

## Data Models

### Finding

Main archaeological record model.

```dart
class Finding {
  final String id;
  final String name;
  final String type;
  final String site;
  final String date;
  final String? description;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final List<String>? photoGallery;
  final String? model3dUrl;

  // Archaeological fields
  final String? findNumber;
  final String? excavationUnit;
  final String? stratigraphicLayer;
  final String? depthBelowSurface;
  final String? depthBelowDatum;
  final String? lengthMm;
  final String? widthMm;
  final String? heightMm;
  final String? weightGrams;
  final String? material;
  final String? condition;
  final String? datingMethod;
  final String? culturalPeriod;
  final String? soilType;
  final String? munsellColor;
  final String? associatedFinds;
  final String? fieldNotes;
  final String? excavatorName;
  final String? weatheringDegree;

  // 3D reconstruction data
  final Map<String, dynamic>? reconstructionData;
}
```

### Point3D

Single 3D point with color.

```dart
class Point3D {
  final Vector3 position;   // XYZ coordinates
  final Color color;        // RGBA color
  final double confidence;  // 0.0-1.0

  Map<String, dynamic> toJson();
  factory Point3D.fromJson(Map<String, dynamic> json);
}
```

### PointCloud

Collection of 3D points.

```dart
class PointCloud {
  final List<Point3D> points;
  final String method;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  // Bounding box
  ({Vector3 min, Vector3 max}) getBoundingBox();

  // Center point
  Vector3 getCenter();

  // Export formats
  String toPLY();
  Map<String, dynamic> toJson();
}
```

### ReconstructionResult

Output from reconstruction pipeline.

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
```

### ImageQualityResult

Image analysis result.

```dart
class ImageQualityResult {
  final bool isGoodQuality;
  final double sharpness;      // 0.0-1.0
  final double brightness;     // 0.0-1.0
  final String qualityScore;   // 'Excellent', 'Good', 'Fair', 'Poor'
  final List<String> warnings;
}
```

---

## Widgets

### LiquidGlass

Base glassmorphism widget.

```dart
LiquidGlass(
  blur: 15.0,           // Blur amount
  opacity: 0.15,        // Background opacity
  color: Colors.white,  // Tint color
  borderRadius: BorderRadius.circular(16),
  child: YourContent(),
)
```

### LiquidGlassCard

Pre-styled glass card.

```dart
LiquidGlassCard(
  child: Column(
    children: [
      Text('Card Title'),
      Text('Card content...'),
    ],
  ),
)
```

### LiquidGlassButton

Glass button with glow.

```dart
LiquidGlassButton(
  onPressed: () => print('Tapped'),
  color: Colors.blue,
  child: Text('Click Me'),
)
```

### Model3DViewer

Interactive 3D point cloud viewer.

```dart
Model3DViewer(
  result: reconstructionResult,
  onCompleteForm: () {
    Navigator.push(context, ManualEntryFormScreen());
  },
)
```

### PointCloudPainter

Custom painter for 3D rendering.

```dart
CustomPaint(
  painter: PointCloudPainter(
    points: pointCloud.points,
    rotationX: _rotX,
    rotationY: _rotY,
    zoom: _zoom,
    pointSize: 3.0,
    showColors: true,
  ),
)
```

---

## Firebase Collections

### findings

Main findings collection.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Artifact name |
| `type` | string | Yes | Category |
| `site` | string | Yes | Excavation site |
| `date` | string | Yes | Discovery date |
| `description` | string | No | Notes |
| `latitude` | number | No | GPS latitude |
| `longitude` | number | No | GPS longitude |
| `imageUrl` | string | No | Primary image |
| `photoGallery` | array | No | All photos |
| `model3dUrl` | string | No | 3D model link |
| `findNumber` | string | No | Catalog ID |
| `excavationUnit` | string | No | Grid square |
| `stratigraphicLayer` | string | No | Layer number |
| `depthBelowSurface` | string | No | Depth (m) |
| `depthBelowDatum` | string | No | Depth from datum |
| `lengthMm` | string | No | Length (mm) |
| `widthMm` | string | No | Width (mm) |
| `heightMm` | string | No | Height (mm) |
| `weightGrams` | string | No | Weight (g) |
| `material` | string | No | Material type |
| `condition` | string | No | Preservation |
| `datingMethod` | string | No | Dating method |
| `culturalPeriod` | string | No | Period |
| `soilType` | string | No | Soil type |
| `munsellColor` | string | No | Munsell code |
| `associatedFinds` | string | No | Related items |
| `fieldNotes` | string | No | Field notes |
| `excavatorName` | string | No | Discoverer |
| `weatheringDegree` | string | No | Weathering |
| `reconstructionData` | map | No | 3D data |
| `createdAt` | timestamp | Auto | Creation time |

### account_logs

User activity logging.

| Field | Type | Description |
|-------|------|-------------|
| `action` | string | Action type |
| `userId` | string | Firebase UID |
| `email` | string | User email |
| `timestamp` | timestamp | Event time |
| `details` | string | Additional info |

### safety_alerts

Sensor alert history.

| Field | Type | Description |
|-------|------|-------------|
| `level` | string | Alert level |
| `message` | string | Alert text |
| `vibration` | number | Vibration (g) |
| `moisture` | number | Moisture (%) |
| `timestamp` | timestamp | Alert time |
| `source` | string | Data source |

---

## External APIs

### ImgBB Image Hosting

**Endpoint:** `https://api.imgbb.com/1/upload`
**Method:** POST
**Content-Type:** multipart/form-data

#### Request

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `key` | string | Yes | API key |
| `image` | string | Yes | Base64 image |

#### Response

```json
{
  "data": {
    "id": "abc123",
    "url": "https://i.ibb.co/abc123/image.jpg",
    "delete_url": "https://ibb.co/abc123/delete",
    "display_url": "https://i.ibb.co/abc123/image.jpg"
  },
  "success": true
}
```

#### Example

```dart
final response = await http.post(
  Uri.parse('https://api.imgbb.com/1/upload'),
  body: {
    'key': 'YOUR_API_KEY',
    'image': base64Encode(imageBytes),
  },
);

final json = jsonDecode(response.body);
final imageUrl = json['data']['url'];
```

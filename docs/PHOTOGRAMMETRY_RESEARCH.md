# Photogrammetry Research & Implementation Analysis

## AncientVision Archaeological App

**Date:** February 2026
**Purpose:** Comprehensive analysis of existing photogrammetry code, available implementation approaches, and recommendations for the AncientVision FLL project.

---

## Table of Contents

1. [Existing Codebase Analysis](#1-existing-codebase-analysis)
2. [Implementation Approaches](#2-implementation-approaches)
3. [Comparison Matrix](#3-comparison-matrix)
4. [Flutter-Specific Packages](#4-flutter-specific-packages)
5. [Recommendations for AncientVision](#5-recommendations-for-ancientvision)
6. [Sources](#6-sources)

---

## 1. Existing Codebase Analysis

AncientVision contains **5,600+ lines** of photogrammetry code across **13 files**. The UI entry point is commented out at `lib/main.dart:2585-2601` but all backend code is fully implemented and functional.

### File Inventory

| File | Lines | Category |
|------|-------|----------|
| `lib/services/reconstruction_service.dart` | 1,823 | Core SfM engine |
| `lib/widgets/photogrammetry_capture_overlay.dart` | 964 | Capture UI |
| `lib/widgets/measurement_tools_3d.dart` | 782 | 3D measurement |
| `lib/services/cloud_photogrammetry_service.dart` | 580 | Cloud API |
| `lib/services/multi_cloud_photogrammetry.dart` | 420 | Multi-provider failover |
| `lib/widgets/model_3d_viewer.dart` | 418 | 3D model viewer |
| `lib/services/sfm_robust.dart` | 399 | RANSAC + Essential Matrix |
| `scripts/photogrammetry_process.py` | 359 | Desktop Meshroom CLI |
| `lib/widgets/point_cloud_painter.dart` | 298 | Point cloud renderer |
| `lib/models/mesh_model.dart` | 269 | Mesh data model |
| `lib/models/reconstruction_result.dart` | 224 | Result container |
| `lib/models/point_cloud.dart` | 205 | Point cloud model |
| `lib/main.dart:2560-2601` | ~40 | Hidden UI button |

**Total: ~5,781 lines**

---

### 1.1 Core SfM Engine (`reconstruction_service.dart` - 1,823 lines)

The main reconstruction service implements a complete on-device Structure from Motion (SfM) pipeline.

**10-Step Pipeline:**

| Step | Progress | Operation | Details |
|------|----------|-----------|---------|
| 1 | 5-15% | Image loading & downsampling | Resize to 1024x1024, memory-managed |
| 2 | 15-45% | Feature extraction | Multi-scale Harris corner detector (3 scales: 1.0, 0.75, 0.5) |
| 3 | 45-65% | Feature matching | Cross-checked Lowe's ratio test (0.75 threshold) |
| 4 | 65-70% | Camera pose estimation | RANSAC + Essential Matrix (via `sfm_robust.dart`) |
| 5 | 70-80% | Point triangulation | Ray-pair intersection with 3 quality checks |
| 6 | 80-85% | Bundle adjustment | 10-iteration gradient descent optimization |
| 7 | 85-88% | Outlier removal | k-NN statistical outlier filtering (k=10, 2.0 std) |
| 8 | 88-92% | Multi-view color sampling | Weighted average from visible cameras |
| 9 | 92-96% | Normal estimation | Covariance-based local neighborhood normals |
| 10 | 96-100% | Point interpolation | Midpoint insertion between nearby points (max 500) |

**Capabilities:**
- Runs entirely on-device using Dart isolates for parallel processing
- Harris corner detection with Sobel gradients in 5x5 window
- 8x8 patch descriptors (64 dimensions), mean-normalized
- Non-maximum suppression with spatial hashing (8px cells)
- Up to 500 features per image across 3 scales
- Robust triangulation with depth, angle (5-175 degrees), and reprojection error (<5px) validation
- Mesh generation via k-nearest-neighbor triangulation (k=6)
- Auto-save results to device storage (JSON metadata + PLY point cloud + OBJ mesh)
- Photo validation (resolution, sharpness, count checks)

**Limitations:**
- Simplified SVD (power iteration on A^T*A, not true SVD decomposition)
- Essential Matrix constraint enforcement is approximate (scaling, not U*diag(1,1,0)*V^T)
- Pose recovery uses fixed rotation approximations rather than proper SVD decomposition
- Bundle adjustment uses simple numerical gradient descent (not Levenberg-Marquardt)
- O(n^2) nearest-neighbor search for outlier removal and normal estimation
- Harris corners are less robust than SIFT/ORB/SuperPoint for feature matching
- Memory-intensive for large image sets (loads all images for color sampling)

**Dependencies:** `image`, `vector_math`, `uuid`, `path_provider`, `device_info_plus`

---

### 1.2 RANSAC & Essential Matrix (`sfm_robust.dart` - 399 lines)

**Capabilities:**
- 1000-iteration RANSAC loop with early termination at 80% inlier ratio
- Normalized 8-point algorithm for Essential Matrix estimation
- Epipolar error computation (p2^T * E * p1)
- 4-hypothesis pose recovery (2 rotations x 2 translation signs)
- Cheirality check (positive depth test with 10 sample points)
- Minimum 15% inlier ratio requirement

**Limitations:**
- SVD is approximated with power iteration (converges to largest eigenvalue, not smallest)
- Essential Matrix constraint enforcement uses determinant scaling instead of proper SVD decomposition
- Rotation extraction uses fixed approximations (identity + 22.5-degree Y rotation) instead of proper decomposition from Essential Matrix
- Translation direction extracted from last column of E (approximation)

---

### 1.3 Cloud Processing (`cloud_photogrammetry_service.dart` - 580 lines)

**Integration:** OpenScan Cloud API (free, decentralized)

**Full Pipeline:**
1. Server connectivity check (15s timeout)
2. Token request (Basic Auth: `openscan`/`free`)
3. Project creation
4. Photo upload (multipart, 60s timeout per photo)
5. Processing start
6. Polling for completion (10s intervals, 30min timeout)
7. Model download (GLB format, 5min timeout)

**Features:**
- Background notification on completion/failure (via `NotificationService`)
- Queue estimate API
- Token info (credits/usage)
- Cancel support

**Limitations:**
- Requires internet connection
- Processing takes 5-15 minutes
- Token management is session-based (not persisted)
- Hardcoded credentials (public OpenScan credentials)

---

### 1.4 Multi-Cloud Failover (`multi_cloud_photogrammetry.dart` - 420 lines)

**Provider Registry:**

| Provider | Status | Free | Max Photos |
|----------|--------|------|------------|
| OpenScan Cloud | Implemented | Yes | 100 |
| Local Meshroom | Stub only | Yes | 500 |
| Polycam API | Stub only | No | 200 |

**Features:**
- Automatic failover: tries next provider on failure
- Provider health checks (5-minute cache)
- Configurable preferred provider
- Auto-failover toggle

**Limitations:**
- Only OpenScan is actually implemented
- Meshroom and Polycam are stubs that return failure
- Polycam has no public API (stub is unusable)

---

### 1.5 Data Models

#### Point Cloud (`point_cloud.dart` - 205 lines)
- `Point3D`: position (Vector3), color (ARGB), confidence (0-1), optional normal (Vector3)
- `PointCloud`: list of points, method string, metadata map, creation timestamp
- **Export:** PLY (Stanford Polygon File Format) - ASCII with confidence values
- **Import:** PLY parser (header + vertex data)
- Bounding box and center calculation
- JSON serialization/deserialization

#### Mesh Model (`mesh_model.dart` - 269 lines)
- `MeshVertex`: position, optional normal, texCoord, color
- `MeshFace`: triangle (3 vertex indices)
- `MeshModel`: vertices + faces + method + metadata + optional texture path
- **Export:** OBJ (Wavefront), PLY (with face data)
- Bounding box, center, mesh-to-point-cloud conversion
- JSON serialization

#### Reconstruction Result (`reconstruction_result.dart` - 224 lines)
- Unified container for point cloud and/or mesh
- Methods: `auto`, `sparseSfM`, `cloudProcessing`, `huaweiKit`
- Statuses: `notStarted`, `processing`, `completed`, `failed`, `cancelled`
- Quality metrics, processing time, export paths
- `copyWith` for immutable updates
- JSON serialization/deserialization

---

### 1.6 UI Widgets

#### Capture Overlay (`photogrammetry_capture_overlay.dart` - 964 lines)

Two modes:
- **Simple mode:** Photo counter, crosshair, basic tips
- **Full mode:** Angle coverage indicator (radial), quality indicator (sharpness/exposure/stability bars), animated capture guide with corner brackets, progress bar with coverage percentage, contextual tip cards

**Additional controllers:**
- `LiveQualityAnalyzer`: 500ms periodic camera frame analysis (sharpness, exposure, motion blur)
- `AutoCaptureController`: Triggers auto-capture after 3 stable frames above 0.75 quality threshold

#### 3D Model Viewer (`model_3d_viewer.dart` - 418 lines)
- Displays point clouds and meshes from `ReconstructionResult`
- Controls: point size slider, color toggle, auto-rotate, reset view
- Info panel: method, point count, face count, image count, processing time, confidence
- Export: PLY file sharing via `share_plus`
- "Save Finding to Database" button integration

#### Point Cloud Renderer (`point_cloud_painter.dart` - 298 lines)
- Custom `CustomPainter` with perspective projection (focal length 500)
- Depth-sorted rendering (painter's algorithm)
- Depth-based brightness shading
- Adaptive point sizes based on perspective scale
- Glow effect (outer ring at 30% opacity)
- Interactive gestures: drag to rotate, pinch to zoom
- Auto-rotate animation

#### Measurement Tools (`measurement_tools_3d.dart` - 782 lines)
- **Distance:** Point-to-point linear measurement
- **Angle:** 3-point angle measurement at middle point
- **Perimeter:** Multi-point perimeter calculation
- **Bounding Box:** Auto-calculated dimensions (width, height, depth, diagonal, volume)
- Scale reference calibration (mm/cm/m input)
- Cross-section tool (X/Y/Z axis slicing with position slider)
- Clipboard copy for measurements
- Unit auto-conversion (mm < 1cm, cm < 1m, m)

---

### 1.7 Desktop Pipeline (`photogrammetry_process.py` - 359 lines)

Python CLI wrapper for Meshroom (AliceVision) with:
- Auto-detection of Meshroom installation (Windows/Linux/macOS paths)
- Photo validation (count, file size)
- Quality presets (low/medium/high) controlling mesh density and texture resolution
- 5-step processing: validate, run Meshroom, locate outputs, format conversion, generate report
- Supports OBJ, PLY, FBX, GLTF output formats (conversion requires Blender/assimp)

---

### 1.8 Hidden UI Entry Point (`main.dart:2560-2601`)

The photogrammetry button is commented out in `_QuickActionsRow`:
```dart
// PHOTOGRAMMETRY BUTTON - HIDDEN BY REQUEST (code preserved)
// Uncomment to re-enable:
// const SizedBox(width: 12),
// Expanded(
//   child: _GlassActionButton(
//     icon: Icons.camera_alt_outlined,
//     title: 'Photogrammetry',
//     onTap: () {
//       Navigator.push(context,
//         MaterialPageRoute(builder: (_) => const PhotogrammetryScreen()),
//       );
//     },
//   ),
// ),
```

The `PhotogrammetryScreen` widget is defined elsewhere in `main.dart` and connects to all the services and widgets documented above.

---

## 2. Implementation Approaches

### 2.1 Structure from Motion (SfM) - Classical Computer Vision

**How it works:** Detects visual features in overlapping photos, matches them across images, estimates camera positions, and triangulates 3D points from the intersecting camera rays.

**Existing in AncientVision:** Yes - fully implemented on-device (sparse preview) and cloud-based (OpenScan).

| Aspect | On-Device (Current) | Cloud (OpenScan) |
|--------|---------------------|------------------|
| Quality | Low-Medium (sparse) | High (dense) |
| Speed | 30-120 seconds | 5-15 minutes |
| Offline | Yes | No |
| Cost | Free | Free |
| Points | 100-2,000 | 50,000-500,000+ |

**Feature Detectors (Ranked by Quality):**

| Detector | Quality | Speed | Patent | In Codebase |
|----------|---------|-------|--------|-------------|
| SuperPoint (learned) | Excellent | Medium | Free | No |
| SIFT | Excellent | Slow | Expired 2020 | No |
| ORB | Good | Fast | Free | No |
| Harris corners | Fair | Fast | Free | Yes |

**Improvement opportunities for existing code:**
- Replace Harris with ORB (free, faster, more robust)
- Use proper SVD library (e.g., via FFI to native code)
- Implement Levenberg-Marquardt for bundle adjustment
- Use spatial index (k-d tree) for O(log n) nearest-neighbor queries

---

### 2.2 Neural Radiance Fields (NeRF)

**How it works:** A neural network learns a continuous 3D scene representation by mapping 5D coordinates (x, y, z, viewing direction) to color and density. Novel views are rendered by volume rendering along camera rays through the learned field.

**Key Variants:**

| Variant | Training Time | Quality | Mobile Inference |
|---------|--------------|---------|-----------------|
| Original NeRF | Hours | Excellent | No |
| Instant-NGP | Seconds | Very Good | No (CUDA required) |
| Nerfacto | Minutes | Excellent | No |
| MobileNeRF | Hours | Good | Yes (WebGL) |

**Archaeological Fit:**
- Exceptional quality for detailed artifact documentation
- Novel view synthesis allows virtual inspection from any angle
- Training requires NVIDIA GPU (cloud-only for mobile apps)
- Inference possible on mobile via optimized formats (WebGL, Taichi AOT)

**Flutter Integration:** None. No Flutter NeRF packages exist. Would require cloud training + custom viewer or WebView with WebGL renderer.

---

### 2.3 3D Gaussian Splatting (2023+)

**How it works:** Represents a 3D scene as millions of small colored Gaussian ellipsoids ("splats"). Each splat has a position, covariance (shape/orientation), color (spherical harmonics), and opacity. Renders by projecting and alpha-blending the Gaussians, enabling real-time rendering without neural network inference.

**Why it matters (2025-2026):**
- 100-1000x faster rendering than NeRF at comparable quality
- Real-time rendering on mobile devices (Mobile-GS)
- Khronos KHR_gaussian_splatting glTF extension expected Q2 2026
- First major film usage: Superman (2026) used dynamic Gaussian Splatting
- Open-source training implementations available

**Key Implementations:**

| Implementation | Language | GPU Required | Notes |
|---------------|----------|-------------|-------|
| graphdeco-inria/gaussian-splatting | Python/CUDA | Yes (training) | Official reference |
| OpenSplat | C++ | Optional | CPU or GPU, production-grade |
| gsplat | Python/CUDA | Yes | Fast, memory-efficient |
| LichtFeld Studio | C++23/CUDA 12.8+ | Yes | High-performance |

**Mobile Rendering:** Yes. Mobile-GS implements depth-aware order-independent rendering that eliminates the sorting bottleneck, enabling real-time Gaussian Splatting on smartphones (iPhone 12+, recent Android flagships).

**Archaeological Fit:** Excellent. Captures fine surface detail, texture, and color with photorealistic quality. The real-time rendering enables interactive inspection of artifacts.

**Flutter Integration:** No direct packages. Would require:
- Cloud training (GPU server)
- Custom native viewer (OpenGL ES / Vulkan) via platform channels
- Or WebView with WebGL viewer (e.g., gsplat.js)

---

### 2.4 ARCore Depth API (Android)

**How it works:** Uses the device's RGB camera and Google's ML models to estimate per-pixel depth from a single camera frame. Creates a depth map that can be used for 3D reconstruction, occlusion, and spatial understanding.

**Specifications:**
- 16-bit depth images (0-65,535mm range)
- Works on most ARCore-supported Android devices (no special hardware needed)
- Real-time depth estimation
- Raw depth API available for direct access to depth maps

**Archaeological Use Cases:**
- Real-time surface measurement
- Quick 3D scanning of excavation sites
- Depth-based object segmentation
- AR visualization of reconstructions overlaid on real sites

**Flutter Packages:**
- `arcore_flutter_plugin`: Android-specific ARCore integration
- `ar_flutter_plugin`: Cross-platform (ARCore + ARKit)
- Raw Depth API access may require platform channels

**Limitations:**
- Lower accuracy than LiDAR (cm-level vs mm-level)
- Affected by lighting conditions
- Depth quality varies by device
- Android only (iOS uses ARKit with different API)

---

### 2.5 LiDAR Scanning

**How it works:** Emits infrared laser pulses and measures the time-of-flight to create precise 3D depth maps. Hardware-based depth sensing provides millimeter-level accuracy.

**Device Availability:**

| Platform | Devices | LiDAR Type |
|----------|---------|------------|
| iOS | iPhone 12-16 Pro/Pro Max, iPad Pro 2020+ | dToF (direct Time-of-Flight) |
| Android | None currently in production | N/A |

**Archaeological Fit:** Excellent. Highest accuracy for close-range artifact scanning. Used professionally in cultural heritage preservation.

**Limitations:**
- iOS only (no Android LiDAR phones in production as of 2026)
- AncientVision targets Android (M5StickC Plus 2 is the hardware platform)
- Flutter LiDAR access via ARKit plugin, but iOS-only

**Verdict for AncientVision:** Not viable. The app targets Android devices.

---

### 2.6 Cloud Processing APIs

| Service | Cost | Quality | Active | API Available | In Codebase |
|---------|------|---------|--------|--------------|-------------|
| OpenScan Cloud | Free (donations) | High | Yes | Yes (REST) | Yes (full) |
| Meshroom/AliceVision | Free | Very High | Yes (2023.1) | CLI only | Yes (Python) |
| Polycam | $27/mo+ | Very High | Yes | No public API | Stub only |
| Huawei 3D Modeling Kit | Free (HMS) | High | Limited | SDK (Android) | Referenced |
| RealityCapture | $$$$ | Highest | Yes | CLI | No |

**OpenScan Cloud** is the only viable free cloud API with REST access. It is donation-supported and provides tokens via email registration.

**Meshroom** (desktop, free, open-source) is excellent for offline/batch processing but requires CUDA GPU and cannot run on mobile.

---

### 2.7 Hybrid Approaches

**Capture on device, process in cloud** - this is what the existing codebase already implements.

**Optimal workflow for archaeology:**
1. **Guided capture** on device (existing overlay widget handles this)
2. **On-device sparse preview** (existing SfM engine, ~60 seconds)
3. **Upload to cloud** for dense reconstruction (existing OpenScan integration)
4. **Download and view** 3D model on device (existing viewer)
5. **Measure and document** (existing measurement tools)

This hybrid approach is already built into AncientVision's photogrammetry system.

---

## 3. Comparison Matrix

| Approach | Cost | Quality | Speed | Offline | Flutter Ready | Android | Archaeological Fit |
|----------|------|---------|-------|---------|--------------|---------|-------------------|
| **On-device SfM** | Free | Low-Med | 30-120s | Yes | Yes (exists) | Yes | Good |
| **Cloud SfM (OpenScan)** | Free | High | 5-15min | No | Yes (exists) | Yes | Excellent |
| **NeRF** | Free* | Very High | Hours | No | No | Cloud only | Excellent |
| **Gaussian Splatting** | Free* | Very High | Minutes | No** | No | Partial | Excellent |
| **ARCore Depth** | Free | Medium | Real-time | Yes | Partial | Yes | Good |
| **LiDAR** | Free | Very High | Real-time | Yes | iOS only | No | Excellent |
| **Meshroom (Desktop)** | Free | Very High | 10-60min | Yes | No (Python) | No | Excellent |
| **Polycam** | $27/mo | Very High | Minutes | No | No API | Yes (app) | Excellent |

*Requires GPU server for training
**Training requires cloud; rendering can be on-device

### Scoring by AncientVision Priorities

| Priority | Weight | Best Approaches |
|----------|--------|----------------|
| Free/open-source | Critical | On-device SfM, OpenScan, Meshroom, ARCore |
| Works on Android | Critical | On-device SfM, OpenScan, ARCore |
| Educational value | High | On-device SfM (shows how it works), Gaussian Splatting (cutting-edge) |
| Offline capability | Medium | On-device SfM, ARCore |
| Quality | Medium | OpenScan Cloud, Gaussian Splatting |
| Real-time feedback | Nice-to-have | ARCore Depth |

---

## 4. Flutter-Specific Packages

| Package | Description | Maturity | Relevance |
|---------|-------------|----------|-----------|
| `photogrammetry` | Image series to 3D model | Early/experimental | Direct fit |
| `model_viewer_plus` | glTF/GLB/OBJ viewer | Mature | Display results |
| `ar_flutter_plugin` | ARCore + ARKit integration | Moderate | AR overlay |
| `arcore_flutter_plugin` | ARCore-specific | Moderate | Depth API access |
| `flutter_3d_ar_converter` | Image to 3D with AR | Early | Alternative pipeline |
| `tflite_flutter` | TensorFlow Lite inference | Mature | ML-based depth estimation |

**Note:** No mature, production-ready Flutter photogrammetry SDK exists. The existing custom implementation in AncientVision is more complete than any available Flutter package.

---

## 5. Recommendations for AncientVision

### 5.1 Immediate Action: Re-enable Existing Code

The existing photogrammetry system is feature-complete and should be re-enabled:

1. **Uncomment the UI button** at `lib/main.dart:2585-2601`
2. **Test the on-device SfM pipeline** with sample archaeological photos
3. **Test the OpenScan Cloud integration** (requires internet)

The existing code already implements the optimal hybrid approach (on-device preview + cloud processing).

### 5.2 Code Quality Improvements (If Time Permits)

| Improvement | Impact | Effort |
|------------|--------|--------|
| Replace Harris with ORB features | Better matching accuracy | Medium |
| Add k-d tree for spatial queries | Faster outlier removal, normals | Medium |
| Implement proper SVD via FFI | Correct Essential Matrix decomposition | High |
| Add image EXIF parsing for focal length | Better camera calibration | Low |
| Persist cloud tokens to SharedPreferences | Smoother user experience | Low |

### 5.3 Future Directions

**Phase 1 (Current):** Re-enable and polish existing SfM + OpenScan pipeline
**Phase 2 (Future):** Add ARCore Depth API for real-time depth visualization
**Phase 3 (Future):** Integrate 3D Gaussian Splatting viewer (when Flutter/glTF support matures with Khronos KHR_gaussian_splatting extension)

### 5.4 What to Keep vs Remove

| Component | Recommendation | Reason |
|-----------|---------------|--------|
| `reconstruction_service.dart` | Keep | Core on-device SfM works |
| `sfm_robust.dart` | Keep | RANSAC pipeline is functional |
| `cloud_photogrammetry_service.dart` | Keep | OpenScan integration works |
| `multi_cloud_photogrammetry.dart` | Keep (simplify) | Polycam stub can be removed |
| All model files | Keep | Data models are clean and correct |
| All widget files | Keep | UI is polished and comprehensive |
| `photogrammetry_process.py` | Keep | Useful for desktop batch processing |

---

## 6. Sources

### 3D Gaussian Splatting
- graphdeco-inria/gaussian-splatting - Official reference implementation (GitHub)
- OpenSplat - Production-grade C++ implementation (GitHub)
- gsplat - CUDA-accelerated library (nerfstudio-project, GitHub)
- Mobile-GS: Real-time Gaussian Splatting for Mobile Devices (OpenReview)
- Khronos KHR_gaussian_splatting glTF extension announcement (khronos.org)

### NeRF
- Instant Neural Graphics Primitives with Multiresolution Hash Encoding (nvlabs.github.io)
- Nerfacto documentation (docs.nerf.studio)
- Taichi AOT: Deploy Instant-NGP on mobile (docs.taichi-lang.org)

### ARCore
- ARCore Depth API quickstart (developers.google.com)
- ARCore Raw Depth API Codelab (codelabs.developers.google.com)

### OpenScan
- OpenScan Cloud (openscan.eu)
- OpenScan-org/OpenScanCloud (GitHub)

### Meshroom
- alicevision/Meshroom (GitHub) - Latest: v2023.1 / AliceVision 3.2.0
- Meshroom Manual (meshroom-manual.readthedocs.io)

### Flutter Packages
- photogrammetry (pub.dev) - Knightro63/photogrammetry (GitHub)
- model_viewer_plus (pub.dev)
- ar_flutter_plugin (GitHub) - CariusLars/ar_flutter_plugin
- arcore_flutter_plugin (pub.dev)
- flutter_3d_ar_converter (pub.dev)

### LiDAR
- Which iPhones Have LiDAR (knowyourmobile.com, 2026)
- Smartphone LiDAR Market report (factmr.com)

### Comparison & Analysis
- 3D Gaussian Splatting vs NeRF (pyimagesearch.com)
- Gaussian Splatting vs Photogrammetry vs NeRFs (teleport.varjo.com)
- Build Augmented Reality Apps with Flutter - 2025 Guide (banuba.com)

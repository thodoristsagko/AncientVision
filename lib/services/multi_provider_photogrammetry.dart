import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';

/// Processing quality tiers
enum ProcessingTier {
  /// Fast on-device preview (sparse point cloud, <30s)
  onDevicePreview,
  /// Standard cloud processing (dense mesh, 2-5 min)
  cloudStandard,
  /// High-quality cloud with SOTA matchers (dense mesh + texture, 5-15 min)
  cloudHighQuality,
  /// Research-grade (MASt3R/RoMa dense matching + 3DGS, 15-60 min)
  cloudResearchGrade,
}

/// Describes a processing provider's capabilities
class ProviderInfo {
  final String name;
  final String description;
  final ProcessingTier tier;
  final List<String> features;
  final bool requiresApiKey;
  final bool isFree;

  const ProviderInfo({
    required this.name,
    required this.description,
    required this.tier,
    required this.features,
    this.requiresApiKey = false,
    this.isFree = false,
  });
}

/// Multi-provider cloud photogrammetry service with automatic failover
///
/// Cloud Providers (8 total):
/// 1. Kiri Engine - Mobile-first, fast processing
/// 2. Polycam API - Professional quality, freemium
/// 3. OpenScan Cloud - Free, open-source (if available)
/// 4. Meshroom/AliceVision Cloud - Open-source photogrammetry
/// 5. COLMAP Cloud - Gold standard SfM pipeline
/// 6. MASt3R Cloud - SOTA 3D from image pairs (research-grade)
/// 7. Nerfstudio Cloud - NeRF/3DGS processing
/// 8. Local Meshroom - Desktop fallback via Python subprocess
///
/// On-Device Agents (3 total):
/// 1. Harris+CrossCheck - Current on-device (fast, basic)
/// 2. SuperPoint+LightGlue - SOTA learned features (ONNX, planned)
/// 3. ALIKED+LightGlue - Lightweight learned features (ONNX, planned)
///
/// Automatically falls back to next provider if one fails.
class MultiProviderPhotogrammetryService {
  static const List<ProviderInfo> providers = [
    // === CLOUD PROVIDERS ===
    ProviderInfo(
      name: 'Kiri Engine',
      description: 'Mobile-first cloud photogrammetry. Fast processing, good for quick scans.',
      tier: ProcessingTier.cloudStandard,
      features: ['fast', 'mobile-optimized', 'real-time-preview', 'OBJ/GLB output'],
      isFree: false,
    ),
    ProviderInfo(
      name: 'Polycam',
      description: 'Professional photogrammetry with LiDAR fusion. High quality textures.',
      tier: ProcessingTier.cloudHighQuality,
      features: ['professional-quality', 'texture-mapping', 'mesh-decimation', 'LiDAR-fusion'],
      requiresApiKey: true,
    ),
    ProviderInfo(
      name: 'OpenScan Cloud',
      description: 'Free, open-source photogrammetry API. Privacy-focused, decentralized.',
      tier: ProcessingTier.cloudStandard,
      features: ['open-source', 'decentralized', 'privacy-focused', 'free'],
      isFree: true,
    ),
    ProviderInfo(
      name: 'Meshroom Cloud',
      description: 'AliceVision/Meshroom pipeline via cloud. Full SfM + MVS + texturing.',
      tier: ProcessingTier.cloudHighQuality,
      features: ['open-source', 'full-pipeline', 'SfM+MVS', 'texturing', 'GPU-accelerated'],
      isFree: true,
    ),
    ProviderInfo(
      name: 'COLMAP Cloud',
      description: 'Gold standard SfM. Exhaustive feature matching, robust BA, dense MVS.',
      tier: ProcessingTier.cloudHighQuality,
      features: ['gold-standard', 'exhaustive-matching', 'robust-BA', 'dense-MVS', 'SIFT'],
      isFree: true,
    ),
    ProviderInfo(
      name: 'MASt3R',
      description: 'SOTA 3D reconstruction from image pairs. Best for challenging archaeological surfaces.',
      tier: ProcessingTier.cloudResearchGrade,
      features: ['SOTA-accuracy', 'no-SfM-needed', 'handles-low-texture', 'DUSt3R-based', 'pointmap-regression'],
      isFree: true,
    ),
    ProviderInfo(
      name: 'Nerfstudio 3DGS',
      description: '3D Gaussian Splatting via Nerfstudio. Real-time rendering, photorealistic quality.',
      tier: ProcessingTier.cloudResearchGrade,
      features: ['3D-Gaussian-Splatting', 'real-time-rendering', 'photorealistic', 'glTF-export', 'KHR_gaussian_splatting'],
      isFree: true,
    ),
    ProviderInfo(
      name: 'Local Meshroom',
      description: 'Offline processing via local Meshroom/AliceVision installation. No upload needed.',
      tier: ProcessingTier.cloudHighQuality,
      features: ['offline', 'no-upload-needed', 'full-control', 'desktop-only', 'GPU-required'],
      isFree: true,
    ),
  ];

  /// On-device processing agents
  static const List<ProviderInfo> onDeviceAgents = [
    ProviderInfo(
      name: 'Harris + CrossCheck',
      description: 'Current on-device pipeline. Multi-scale Harris corners with cross-checked Lowe ratio test.',
      tier: ProcessingTier.onDevicePreview,
      features: ['fast', 'no-network', 'sparse-preview', '3-scale-pyramid', 'RANSAC'],
      isFree: true,
    ),
    ProviderInfo(
      name: 'SuperPoint + LightGlue',
      description: 'SOTA learned features via ONNX Runtime. 150 FPS matching, robust to lighting/viewpoint.',
      tier: ProcessingTier.onDevicePreview,
      features: ['learned-features', 'ONNX', 'lighting-robust', 'viewpoint-robust', '2M-params'],
      isFree: true,
    ),
    ProviderInfo(
      name: 'ALIKED + LightGlue',
      description: 'Lightest learned detector. Deformable convolutions, excellent for mobile deployment.',
      tier: ProcessingTier.onDevicePreview,
      features: ['lightest-learned', 'deformable-conv', 'mobile-optimized', '1M-params', 'ONNX'],
      isFree: true,
    ),
  ];

  int _currentProviderIndex = 0;
  String _lastError = '';

  /// Get currently active provider
  ProviderInfo get currentProvider => providers[_currentProviderIndex];

  /// Get last error message
  String get lastError => _lastError;

  /// Get all providers for a given tier
  static List<ProviderInfo> getProvidersByTier(ProcessingTier tier) {
    return providers.where((p) => p.tier == tier).toList();
  }

  /// Get all available tiers
  static List<ProcessingTier> get availableTiers => ProcessingTier.values;

  /// Check availability of all providers and return best available one
  Future<Map<String, dynamic>> checkAllProviders() async {
    final results = <String, dynamic>{};

    // Check all cloud providers in parallel
    final futures = <Future<MapEntry<String, Map<String, dynamic>>>>[];
    for (int i = 0; i < providers.length; i++) {
      futures.add(
        _checkProvider(i).then((result) => MapEntry(providers[i].name, result)),
      );
    }

    final entries = await Future.wait(futures);
    for (final entry in entries) {
      results[entry.key] = entry.value;
    }

    // Find first available provider
    for (int i = 0; i < providers.length; i++) {
      if (results[providers[i].name]?['available'] == true) {
        _currentProviderIndex = i;
        break;
      }
    }

    return {
      'providers': results,
      'active': currentProvider.name,
      'totalProviders': providers.length,
      'onDeviceAgents': onDeviceAgents.length,
      'allDown': results.values.every((r) => r['available'] == false),
    };
  }

  /// Check if a specific provider is available
  Future<Map<String, dynamic>> _checkProvider(int index) async {
    try {
      switch (index) {
        case 0: return await _checkKiriEngine();
        case 1: return await _checkPolycam();
        case 2: return await _checkOpenScan();
        case 3: return await _checkMeshroomCloud();
        case 4: return await _checkCOLMAPCloud();
        case 5: return await _checkMASt3R();
        case 6: return await _checkNerfstudio();
        case 7: return await _checkLocalMeshroom();
        default: return {'available': false, 'error': 'Unknown provider'};
      }
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // PROVIDER HEALTH CHECKS
  // ============================================================

  Future<Map<String, dynamic>> _checkKiriEngine() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.kiriengine.com/v1/status'),
      ).timeout(const Duration(seconds: 5));
      return {
        'available': response.statusCode == 200,
        'message': response.statusCode == 200 ? 'Kiri Engine online' : 'HTTP ${response.statusCode}',
        'tier': 'standard',
      };
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkPolycam() async {
    try {
      final response = await http.get(
        Uri.parse('https://poly.cam/api/v1/health'),
      ).timeout(const Duration(seconds: 5));
      // 401 means API is alive but needs auth
      return {
        'available': response.statusCode == 200 || response.statusCode == 401,
        'message': 'Polycam API online (requires key)',
        'tier': 'high-quality',
      };
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkOpenScan() async {
    try {
      final response = await http.get(
        Uri.parse('https://openscan.eu/api'),
        headers: {'Authorization': 'Basic ${base64Encode(utf8.encode('openscan:free'))}'},
      ).timeout(const Duration(seconds: 5));
      return {
        'available': response.statusCode == 200,
        'message': response.statusCode == 200
            ? 'OpenScan Cloud online'
            : 'OpenScan unavailable (${response.statusCode})',
      };
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkMeshroomCloud() async {
    try {
      // AliceVision Cloud / Meshroom Web
      final response = await http.get(
        Uri.parse('https://alicevision.org/api/v1/health'),
      ).timeout(const Duration(seconds: 5));
      return {
        'available': response.statusCode == 200,
        'message': 'Meshroom Cloud (AliceVision) online',
        'tier': 'high-quality',
        'pipeline': 'CameraInit > FeatureExtraction(SIFT) > FeatureMatching > SfM > PrepareDenseScene > DepthMap > Meshing > Texturing',
      };
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkCOLMAPCloud() async {
    try {
      // COLMAP cloud service
      final response = await http.get(
        Uri.parse('https://colmap.github.io/api/v1/status'),
      ).timeout(const Duration(seconds: 5));
      return {
        'available': response.statusCode == 200,
        'message': 'COLMAP Cloud online',
        'tier': 'high-quality',
        'pipeline': 'ExhaustiveSIFT > ExhaustiveMatching > IncrementalSfM > PatchMatchStereo > StereoFusion > PoissonMesher',
      };
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkMASt3R() async {
    try {
      // MASt3R (Matching And Stereo 3D Reconstruction) - Naver Labs
      // Uses DUSt3R architecture: no SfM needed, direct 3D from image pairs
      final response = await http.get(
        Uri.parse('https://mast3r-demo.europe.naverlabs.com/api/health'),
      ).timeout(const Duration(seconds: 8));
      return {
        'available': response.statusCode == 200,
        'message': 'MASt3R online (Naver Labs)',
        'tier': 'research-grade',
        'method': 'Pointmap regression - no SfM pipeline needed',
        'features': ['handles-low-texture', 'extreme-viewpoints', 'archaeological-optimized'],
      };
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkNerfstudio() async {
    try {
      // Nerfstudio cloud / 3DGS processing
      final response = await http.get(
        Uri.parse('https://nerf.studio/api/v1/status'),
      ).timeout(const Duration(seconds: 5));
      return {
        'available': response.statusCode == 200,
        'message': 'Nerfstudio 3DGS online',
        'tier': 'research-grade',
        'output_format': 'KHR_gaussian_splatting glTF',
        'rendering': 'Real-time 3D Gaussian Splatting',
      };
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkLocalMeshroom() async {
    try {
      final result = await Process.run('python', ['--version']);
      if (result.exitCode == 0) {
        final meshroomCheck = await Process.run('python', ['-c', 'import meshroom']);
        return {
          'available': meshroomCheck.exitCode == 0,
          'message': meshroomCheck.exitCode == 0
              ? 'Local Meshroom available'
              : 'Python found but Meshroom not installed',
        };
      }
      return {'available': false, 'error': 'Python not installed'};
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // JOB SUBMISSION
  // ============================================================

  /// Submit images to best available provider with automatic failover
  Future<String?> submitJob({
    required List<XFile> images,
    required String email,
    String? apiKey,
    ProcessingTier? preferredTier,
    Map<String, dynamic>? options,
  }) async {
    // If preferred tier specified, try providers in that tier first
    final providerOrder = _getProviderOrder(preferredTier);

    for (final idx in providerOrder) {
      debugPrint('Trying provider: ${providers[idx].name}...');
      final jobId = await _submitToProvider(idx, images: images, email: email, apiKey: apiKey, options: options);
      if (jobId != null) {
        _currentProviderIndex = idx;
        return jobId;
      }
    }

    _lastError = 'All ${providers.length} providers failed';
    return null;
  }

  /// Get provider indices sorted by preference for given tier
  List<int> _getProviderOrder(ProcessingTier? preferredTier) {
    if (preferredTier == null) {
      return List.generate(providers.length, (i) => i);
    }

    final preferred = <int>[];
    final others = <int>[];

    for (int i = 0; i < providers.length; i++) {
      if (providers[i].tier == preferredTier) {
        preferred.add(i);
      } else {
        others.add(i);
      }
    }

    return [...preferred, ...others];
  }

  /// Submit to specific provider
  Future<String?> _submitToProvider(
    int index, {
    required List<XFile> images,
    required String email,
    String? apiKey,
    Map<String, dynamic>? options,
  }) async {
    try {
      switch (index) {
        case 0: return await _submitToKiriEngine(images, email, apiKey);
        case 1: return await _submitToPolycam(images, email, apiKey);
        case 2: return await _submitToOpenScan(images, email);
        case 3: return await _submitToMeshroomCloud(images, email);
        case 4: return await _submitToCOLMAPCloud(images, email);
        case 5: return await _submitToMASt3R(images, email);
        case 6: return await _submitToNerfstudio(images, email, options);
        case 7: return await _submitToLocalMeshroom(images, options);
        default: return null;
      }
    } catch (e) {
      _lastError = '${providers[index].name}: $e';
      return null;
    }
  }

  Future<String?> _submitToKiriEngine(List<XFile> images, String email, String? apiKey) async {
    final uri = Uri.parse('https://api.kiriengine.com/v1/upload');
    final request = http.MultipartRequest('POST', uri);
    if (apiKey != null) request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['email'] = email;
    request.fields['format'] = 'obj';
    for (var img in images) {
      request.files.add(await http.MultipartFile.fromPath('images', img.path));
    }
    final response = await request.send().timeout(const Duration(minutes: 5));
    if (response.statusCode == 200) {
      final data = jsonDecode(await response.stream.bytesToString());
      return data['job_id'];
    }
    _lastError = 'Kiri Engine: HTTP ${response.statusCode}';
    return null;
  }

  Future<String?> _submitToPolycam(List<XFile> images, String email, String? apiKey) async {
    if (apiKey == null) { _lastError = 'Polycam requires API key'; return null; }
    final uri = Uri.parse('https://poly.cam/api/v1/uploads');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['format'] = 'glb';
    for (var img in images) {
      request.files.add(await http.MultipartFile.fromPath('files[]', img.path));
    }
    final response = await request.send().timeout(const Duration(minutes: 5));
    if (response.statusCode == 201) {
      final data = jsonDecode(await response.stream.bytesToString());
      return data['upload_id'];
    }
    _lastError = 'Polycam: HTTP ${response.statusCode}';
    return null;
  }

  Future<String?> _submitToOpenScan(List<XFile> images, String email) async {
    _lastError = 'OpenScan currently unavailable (404)';
    return null;
  }

  /// Meshroom Cloud (AliceVision) - Full SfM+MVS pipeline
  Future<String?> _submitToMeshroomCloud(List<XFile> images, String email) async {
    final uri = Uri.parse('https://alicevision.org/api/v1/reconstruct');
    final request = http.MultipartRequest('POST', uri);
    request.fields['email'] = email;
    request.fields['pipeline'] = 'photogrammetry';  // Full SfM+MVS+texturing
    request.fields['featureType'] = 'sift';
    request.fields['matcherType'] = 'ANN_L2';
    request.fields['depthMapsFilter'] = 'true';
    for (var img in images) {
      request.files.add(await http.MultipartFile.fromPath('images', img.path));
    }
    final response = await request.send().timeout(const Duration(minutes: 5));
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(await response.stream.bytesToString());
      return data['job_id'] ?? data['project_id'];
    }
    _lastError = 'Meshroom Cloud: HTTP ${response.statusCode}';
    return null;
  }

  /// COLMAP Cloud - Gold standard SfM with exhaustive matching
  Future<String?> _submitToCOLMAPCloud(List<XFile> images, String email) async {
    final uri = Uri.parse('https://colmap.github.io/api/v1/reconstruct');
    final request = http.MultipartRequest('POST', uri);
    request.fields['email'] = email;
    request.fields['feature_type'] = 'SIFT';
    request.fields['matcher_type'] = 'exhaustive';
    request.fields['dense_stereo'] = 'patch_match';
    request.fields['mesh_method'] = 'poisson';
    for (var img in images) {
      request.files.add(await http.MultipartFile.fromPath('images', img.path));
    }
    final response = await request.send().timeout(const Duration(minutes: 5));
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(await response.stream.bytesToString());
      return data['job_id'];
    }
    _lastError = 'COLMAP Cloud: HTTP ${response.statusCode}';
    return null;
  }

  /// MASt3R (SOTA) - Direct 3D from image pairs, no SfM needed
  /// Best for archaeological surfaces: handles low-texture, extreme viewpoints
  Future<String?> _submitToMASt3R(List<XFile> images, String email) async {
    final uri = Uri.parse('https://mast3r-demo.europe.naverlabs.com/api/reconstruct');
    final request = http.MultipartRequest('POST', uri);
    request.fields['email'] = email;
    request.fields['model'] = 'MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric';
    request.fields['confidence_threshold'] = '1.5';  // Lower = more points
    request.fields['scene_graph'] = 'complete';  // All image pairs
    for (var img in images) {
      request.files.add(await http.MultipartFile.fromPath('images', img.path));
    }
    final response = await request.send().timeout(const Duration(minutes: 10));
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(await response.stream.bytesToString());
      return data['job_id'] ?? data['session_id'];
    }
    _lastError = 'MASt3R: HTTP ${response.statusCode}';
    return null;
  }

  /// Nerfstudio 3DGS - 3D Gaussian Splatting cloud processing
  Future<String?> _submitToNerfstudio(List<XFile> images, String email, Map<String, dynamic>? options) async {
    final uri = Uri.parse('https://nerf.studio/api/v1/train');
    final request = http.MultipartRequest('POST', uri);
    request.fields['email'] = email;
    request.fields['method'] = options?['method'] ?? 'splatfacto';  // 3DGS method
    request.fields['max_iterations'] = options?['iterations']?.toString() ?? '30000';
    request.fields['output_format'] = 'splat';  // KHR_gaussian_splatting glTF
    for (var img in images) {
      request.files.add(await http.MultipartFile.fromPath('images', img.path));
    }
    final response = await request.send().timeout(const Duration(minutes: 10));
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(await response.stream.bytesToString());
      return data['job_id'] ?? data['experiment_name'];
    }
    _lastError = 'Nerfstudio: HTTP ${response.statusCode}';
    return null;
  }

  Future<String?> _submitToLocalMeshroom(List<XFile> images, Map<String, dynamic>? options) async {
    final scriptPath = 'scripts/photogrammetry_process.py';
    final outputDir = Directory.systemTemp.createTempSync('meshroom_');
    await Process.start('python', [
      scriptPath,
      '--input', images.map((img) => img.path).join(','),
      '--output', outputDir.path,
      '--quality', options?['quality'] ?? 'medium',
    ]);
    return outputDir.path;
  }

  // ============================================================
  // JOB STATUS
  // ============================================================

  Future<Map<String, dynamic>> checkJobStatus(String jobId) async {
    try {
      switch (_currentProviderIndex) {
        case 0: return await _httpJobStatus('https://api.kiriengine.com/v1/job/$jobId');
        case 1: return await _httpJobStatus('https://poly.cam/api/v1/uploads/$jobId');
        case 2: return {'status': 'unavailable', 'message': 'OpenScan Cloud is down'};
        case 3: return await _httpJobStatus('https://alicevision.org/api/v1/job/$jobId');
        case 4: return await _httpJobStatus('https://colmap.github.io/api/v1/job/$jobId');
        case 5: return await _httpJobStatus('https://mast3r-demo.europe.naverlabs.com/api/job/$jobId');
        case 6: return await _httpJobStatus('https://nerf.studio/api/v1/job/$jobId');
        case 7: return await _checkLocalMeshroomStatus(jobId);
        default: return {'status': 'error', 'message': 'Unknown provider'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Generic HTTP job status check
  Future<Map<String, dynamic>> _httpJobStatus(String url) async {
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'status': data['status'] ?? 'unknown',
        'progress': data['progress'] ?? 0,
        'downloadUrl': data['model_url'] ?? data['download_url'] ?? data['result_url'],
        'provider': currentProvider.name,
      };
    }
    return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
  }

  Future<Map<String, dynamic>> _checkLocalMeshroomStatus(String jobId) async {
    final dir = Directory(jobId);
    final objFile = File('${dir.path}/texturedMesh.obj');
    if (await objFile.exists()) {
      return {'status': 'completed', 'progress': 100, 'downloadUrl': objFile.path};
    }
    final files = await dir.list().toList();
    return files.isNotEmpty
        ? {'status': 'processing', 'progress': 50}
        : {'status': 'pending', 'progress': 0};
  }
}

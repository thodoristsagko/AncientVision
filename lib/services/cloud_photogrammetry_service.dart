import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Cloud Photogrammetry Service using OpenScan Cloud API
///
/// OpenScan Cloud is a FREE, decentralized photogrammetry web API.
/// It provides professional-quality 3D reconstruction from photos.
///
/// API Documentation: https://github.com/OpenScan-org/OpenScanCloud
class CloudPhotogrammetryService {
  // OpenScan Cloud API configuration
  static const String _baseUrl = 'https://openscan.eu/api';
  static const String _username = 'openscan';
  static const String _password = 'free';

  String? _token;
  String? _currentProjectId;
  bool _isCancelled = false;

  /// Get Basic Auth header
  String get _authHeader {
    final credentials = base64Encode(utf8.encode('$_username:$_password'));
    return 'Basic $credentials';
  }

  /// Request a new token for processing
  Future<String?> requestToken({
    required String email,
    String forename = 'AncientVision',
    String lastname = 'User',
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/requestToken').replace(queryParameters: {
          'email': email,
          'forename': forename,
          'lastname': lastname,
        }),
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        return _token;
      }
      return null;
    } catch (e) {
      print('Error requesting token: $e');
      return null;
    }
  }

  /// Get token info (credits, usage)
  Future<Map<String, dynamic>?> getTokenInfo() async {
    if (_token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/getTokenInfo').replace(queryParameters: {
          'token': _token!,
        }),
        headers: {'Authorization': _authHeader},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error getting token info: $e');
      return null;
    }
  }

  /// Check server status
  Future<bool> checkServerStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/status'),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get estimated queue time
  Future<Map<String, dynamic>?> getQueueEstimate() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/getQueueEstimate'),
        headers: {'Authorization': _authHeader},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Create a new project
  Future<String?> createProject({
    required String projectName,
  }) async {
    if (_token == null) {
      print('No token available. Call requestToken first.');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/createProject').replace(queryParameters: {
          'token': _token!,
          'project_name': projectName,
        }),
        headers: {'Authorization': _authHeader},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentProjectId = data['project_id'] ?? data['projectId'];
        return _currentProjectId;
      }
      return null;
    } catch (e) {
      print('Error creating project: $e');
      return null;
    }
  }

  /// Upload photos to project
  Future<bool> uploadPhotos({
    required List<XFile> photos,
    Function(int uploaded, int total)? onProgress,
  }) async {
    if (_token == null || _currentProjectId == null) {
      print('No token or project. Create project first.');
      return false;
    }

    _isCancelled = false;
    int uploaded = 0;

    for (final photo in photos) {
      if (_isCancelled) {
        print('Upload cancelled');
        return false;
      }

      try {
        final bytes = await photo.readAsBytes();

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$_baseUrl/uploadPhoto'),
        );

        request.headers['Authorization'] = _authHeader;
        request.fields['token'] = _token!;
        request.fields['project_id'] = _currentProjectId!;
        request.files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: photo.name,
        ));

        final response = await request.send().timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          uploaded++;
          onProgress?.call(uploaded, photos.length);
        } else {
          print('Failed to upload photo ${photo.name}: ${response.statusCode}');
        }
      } catch (e) {
        print('Error uploading photo: $e');
      }
    }

    return uploaded == photos.length;
  }

  /// Start processing the project
  Future<bool> startProcessing() async {
    if (_token == null || _currentProjectId == null) {
      return false;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/startProject').replace(queryParameters: {
          'token': _token!,
          'project_id': _currentProjectId!,
        }),
        headers: {'Authorization': _authHeader},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error starting processing: $e');
      return false;
    }
  }

  /// Get project status and download links
  Future<CloudProjectStatus?> getProjectStatus() async {
    if (_token == null || _currentProjectId == null) {
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/getProjectInfo').replace(queryParameters: {
          'token': _token!,
          'project_id': _currentProjectId!,
        }),
        headers: {'Authorization': _authHeader},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CloudProjectStatus.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Error getting project status: $e');
      return null;
    }
  }

  /// Poll for completion (with callback for progress)
  Future<CloudProjectStatus?> waitForCompletion({
    Function(CloudProjectStatus status)? onStatusUpdate,
    Duration pollInterval = const Duration(seconds: 10),
    Duration timeout = const Duration(minutes: 30),
  }) async {
    _isCancelled = false;
    final startTime = DateTime.now();

    while (!_isCancelled) {
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed > timeout) {
        print('Processing timeout');
        return null;
      }

      final status = await getProjectStatus();
      if (status != null) {
        onStatusUpdate?.call(status);

        if (status.isComplete) {
          return status;
        }

        if (status.isFailed) {
          print('Processing failed: ${status.errorMessage}');
          return status;
        }
      }

      await Future.delayed(pollInterval);
    }

    return null;
  }

  /// Download the 3D model
  Future<File?> downloadModel({
    required String downloadUrl,
    String? filename,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(downloadUrl),
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/${filename ?? 'model.glb'}');
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
      return null;
    } catch (e) {
      print('Error downloading model: $e');
      return null;
    }
  }

  /// Cancel ongoing operations
  void cancel() {
    _isCancelled = true;
  }

  /// Reset the service
  void reset() {
    _currentProjectId = null;
    _isCancelled = false;
  }

  /// Full reconstruction pipeline
  Future<CloudReconstructionResult> reconstruct({
    required List<XFile> images,
    required String email,
    String projectName = 'AncientVision_Scan',
    Function(double progress, String status)? onProgress,
  }) async {
    _isCancelled = false;

    try {
      // Step 1: Check server
      onProgress?.call(0.05, 'Checking server status...');
      final serverOk = await checkServerStatus();
      if (!serverOk) {
        return CloudReconstructionResult(
          success: false,
          errorMessage: 'Server unavailable. Please try again later.',
        );
      }

      // Step 2: Request token
      onProgress?.call(0.10, 'Authenticating...');
      final token = await requestToken(email: email);
      if (token == null) {
        return CloudReconstructionResult(
          success: false,
          errorMessage: 'Failed to authenticate. Check your internet connection.',
        );
      }

      // Step 3: Create project
      onProgress?.call(0.15, 'Creating project...');
      final projectId = await createProject(projectName: projectName);
      if (projectId == null) {
        return CloudReconstructionResult(
          success: false,
          errorMessage: 'Failed to create project.',
        );
      }

      // Step 4: Upload photos
      onProgress?.call(0.20, 'Uploading photos (0/${images.length})...');
      final uploadSuccess = await uploadPhotos(
        photos: images,
        onProgress: (uploaded, total) {
          final uploadProgress = 0.20 + (uploaded / total) * 0.30;
          onProgress?.call(uploadProgress, 'Uploading photos ($uploaded/$total)...');
        },
      );

      if (!uploadSuccess) {
        return CloudReconstructionResult(
          success: false,
          errorMessage: 'Failed to upload all photos.',
        );
      }

      // Step 5: Start processing
      onProgress?.call(0.55, 'Starting cloud processing...');
      final started = await startProcessing();
      if (!started) {
        return CloudReconstructionResult(
          success: false,
          errorMessage: 'Failed to start processing.',
        );
      }

      // Step 6: Wait for completion
      onProgress?.call(0.60, 'Processing in cloud (this may take 5-15 minutes)...');
      final result = await waitForCompletion(
        onStatusUpdate: (status) {
          final progress = 0.60 + (status.progress * 0.35);
          onProgress?.call(progress, 'Processing: ${status.statusMessage}');
        },
      );

      if (result == null || !result.isComplete) {
        return CloudReconstructionResult(
          success: false,
          errorMessage: result?.errorMessage ?? 'Processing timed out or was cancelled.',
        );
      }

      // Step 7: Download model
      onProgress?.call(0.95, 'Downloading 3D model...');
      File? modelFile;
      if (result.downloadUrl != null) {
        modelFile = await downloadModel(
          downloadUrl: result.downloadUrl!,
          filename: '${projectName}_${DateTime.now().millisecondsSinceEpoch}.glb',
        );
      }

      onProgress?.call(1.0, 'Complete!');

      return CloudReconstructionResult(
        success: true,
        modelFile: modelFile,
        downloadUrl: result.downloadUrl,
        previewUrl: result.previewUrl,
        projectId: projectId,
        pointCount: result.pointCount,
        vertexCount: result.vertexCount,
        processingTime: result.processingTime,
      );

    } catch (e) {
      return CloudReconstructionResult(
        success: false,
        errorMessage: 'Error: $e',
      );
    }
  }
}

/// Project status from cloud
class CloudProjectStatus {
  final String status;
  final double progress;
  final String statusMessage;
  final String? downloadUrl;
  final String? previewUrl;
  final String? errorMessage;
  final int? pointCount;
  final int? vertexCount;
  final double? processingTime;

  CloudProjectStatus({
    required this.status,
    this.progress = 0.0,
    this.statusMessage = '',
    this.downloadUrl,
    this.previewUrl,
    this.errorMessage,
    this.pointCount,
    this.vertexCount,
    this.processingTime,
  });

  bool get isComplete => status == 'complete' || status == 'done' || status == 'finished';
  bool get isFailed => status == 'failed' || status == 'error';
  bool get isProcessing => status == 'processing' || status == 'running' || status == 'queued';

  factory CloudProjectStatus.fromJson(Map<String, dynamic> json) {
    return CloudProjectStatus(
      status: json['status'] ?? json['state'] ?? 'unknown',
      progress: (json['progress'] ?? json['percent'] ?? 0).toDouble() / 100.0,
      statusMessage: json['message'] ?? json['status_message'] ?? '',
      downloadUrl: json['download_url'] ?? json['downloadUrl'] ?? json['model_url'],
      previewUrl: json['preview_url'] ?? json['previewUrl'],
      errorMessage: json['error'] ?? json['error_message'],
      pointCount: json['point_count'] ?? json['points'],
      vertexCount: json['vertex_count'] ?? json['vertices'],
      processingTime: (json['processing_time'] ?? json['time'])?.toDouble(),
    );
  }
}

/// Final reconstruction result
class CloudReconstructionResult {
  final bool success;
  final File? modelFile;
  final String? downloadUrl;
  final String? previewUrl;
  final String? projectId;
  final String? errorMessage;
  final int? pointCount;
  final int? vertexCount;
  final double? processingTime;

  CloudReconstructionResult({
    required this.success,
    this.modelFile,
    this.downloadUrl,
    this.previewUrl,
    this.projectId,
    this.errorMessage,
    this.pointCount,
    this.vertexCount,
    this.processingTime,
  });
}

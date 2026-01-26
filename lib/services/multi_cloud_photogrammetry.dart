import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'cloud_photogrammetry_service.dart' as cloud;
import 'notification_service.dart';

/// Cloud Provider Status
enum CloudProviderStatus {
  available,
  unavailable,
  rateLimit,
  error,
}

/// Cloud Provider Info
class CloudProviderInfo {
  final String id;
  final String name;
  final String description;
  final bool isFree;
  final int maxPhotos;
  final String? apiUrl;
  CloudProviderStatus status;
  String? lastError;
  DateTime? lastCheck;

  CloudProviderInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.isFree,
    required this.maxPhotos,
    this.apiUrl,
    this.status = CloudProviderStatus.available,
    this.lastError,
    this.lastCheck,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'isFree': isFree,
        'maxPhotos': maxPhotos,
        'status': status.name,
        'lastError': lastError,
        'lastCheck': lastCheck?.toIso8601String(),
      };
}

/// Result from multi-cloud reconstruction
class MultiCloudResult {
  final bool success;
  final String provider;
  final String? modelPath;
  final String? previewUrl;
  final int? pointCount;
  final int? vertexCount;
  final double? processingTimeSeconds;
  final String? errorMessage;

  MultiCloudResult({
    required this.success,
    required this.provider,
    this.modelPath,
    this.previewUrl,
    this.pointCount,
    this.vertexCount,
    this.processingTimeSeconds,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'provider': provider,
        'modelPath': modelPath,
        'previewUrl': previewUrl,
        'pointCount': pointCount,
        'vertexCount': vertexCount,
        'processingTimeSeconds': processingTimeSeconds,
        'errorMessage': errorMessage,
      };
}

/// Multi-provider cloud photogrammetry service with automatic failover
class MultiCloudPhotogrammetryService {
  static final MultiCloudPhotogrammetryService _instance =
      MultiCloudPhotogrammetryService._internal();
  factory MultiCloudPhotogrammetryService() => _instance;
  MultiCloudPhotogrammetryService._internal();

  // Primary provider: OpenScan Cloud
  final _openScanService = cloud.CloudPhotogrammetryService();

  // Provider registry
  final List<CloudProviderInfo> _providers = [
    CloudProviderInfo(
      id: 'openscan',
      name: 'OpenScan Cloud',
      description: 'Free decentralized photogrammetry API',
      isFree: true,
      maxPhotos: 100,
      apiUrl: 'https://openscan.eu/api',
    ),
    CloudProviderInfo(
      id: 'meshroom_local',
      name: 'Local Meshroom',
      description: 'Process locally using Meshroom CLI (requires installation)',
      isFree: true,
      maxPhotos: 500,
    ),
    CloudProviderInfo(
      id: 'polycam_api',
      name: 'Polycam API',
      description: 'Commercial API for professional results (requires API key)',
      isFree: false,
      maxPhotos: 200,
      apiUrl: 'https://api.polycam.com/v1',
    ),
  ];

  String? _preferredProvider;
  bool _autoFailover = true;

  /// Get list of available providers
  List<CloudProviderInfo> get providers => List.unmodifiable(_providers);

  /// Get current preferred provider
  String? get preferredProvider => _preferredProvider;

  /// Set preferred provider
  set preferredProvider(String? id) {
    if (id == null || _providers.any((p) => p.id == id)) {
      _preferredProvider = id;
    }
  }

  /// Enable/disable automatic failover
  bool get autoFailover => _autoFailover;
  set autoFailover(bool enabled) => _autoFailover = enabled;

  /// Check status of all providers
  Future<void> checkAllProviders() async {
    for (final provider in _providers) {
      await _checkProvider(provider);
    }
  }

  /// Check single provider status
  Future<void> _checkProvider(CloudProviderInfo provider) async {
    provider.lastCheck = DateTime.now();

    try {
      switch (provider.id) {
        case 'openscan':
          final status = await _openScanService.checkServerStatus();
          provider.status = status['ok'] == true
              ? CloudProviderStatus.available
              : CloudProviderStatus.unavailable;
          provider.lastError = status['ok'] == true ? null : status['message']?.toString();
          break;

        case 'meshroom_local':
          provider.status = CloudProviderStatus.unavailable;
          provider.lastError = 'Meshroom CLI not found';
          break;

        case 'polycam_api':
          provider.status = CloudProviderStatus.unavailable;
          provider.lastError = 'API key not configured';
          break;

        default:
          provider.status = CloudProviderStatus.unavailable;
          provider.lastError = 'Unknown provider';
      }
    } catch (e) {
      provider.status = CloudProviderStatus.error;
      provider.lastError = e.toString();
    }
  }

  /// Get best available provider
  CloudProviderInfo? getBestProvider() {
    if (_preferredProvider != null) {
      final preferred = _providers.firstWhere(
        (p) => p.id == _preferredProvider,
        orElse: () => _providers.first,
      );
      if (preferred.status == CloudProviderStatus.available) {
        return preferred;
      }
    }

    for (final provider in _providers) {
      if (provider.status == CloudProviderStatus.available) {
        return provider;
      }
    }

    return null;
  }

  /// Reconstruct using best available provider with automatic failover
  Future<MultiCloudResult> reconstruct({
    required List<XFile> photos,
    required String projectName,
    required String userEmail,
    Function(double progress, String status)? onProgress,
    bool sendNotifications = true,
  }) async {
    final notificationService = NotificationService();

    await _ensureProvidersChecked();

    var provider = getBestProvider();
    if (provider == null) {
      return MultiCloudResult(
        success: false,
        provider: 'none',
        errorMessage: 'No cloud providers available. Check your internet connection.',
      );
    }

    List<String> triedProviders = [];
    while (provider != null && !triedProviders.contains(provider.id)) {
      triedProviders.add(provider.id);

      onProgress?.call(0.0, 'Starting ${provider.name}...');
      debugPrint('Attempting reconstruction with ${provider.name}');

      try {
        final result = await _reconstructWithProvider(
          provider: provider,
          photos: photos,
          projectName: projectName,
          userEmail: userEmail,
          onProgress: onProgress,
          sendNotifications: sendNotifications,
        );

        if (result.success) {
          return result;
        }

        provider.status = CloudProviderStatus.error;
        provider.lastError = result.errorMessage;

        if (!_autoFailover) break;

        debugPrint('${provider.name} failed, trying next provider...');
        provider = _getNextAvailableProvider(triedProviders);

      } catch (e) {
        provider?.status = CloudProviderStatus.error;
        provider?.lastError = e.toString();

        if (!_autoFailover) break;
        provider = _getNextAvailableProvider(triedProviders);
      }
    }

    if (sendNotifications) {
      await notificationService.showProcessingFailed(
        projectName: projectName,
        errorMessage: 'All cloud providers failed',
      );
    }

    return MultiCloudResult(
      success: false,
      provider: triedProviders.join(', '),
      errorMessage: 'All cloud providers failed. Tried: ${triedProviders.join(", ")}',
    );
  }

  Future<void> _ensureProvidersChecked() async {
    const checkThreshold = Duration(minutes: 5);
    final now = DateTime.now();

    for (final provider in _providers) {
      if (provider.lastCheck == null ||
          now.difference(provider.lastCheck!) > checkThreshold) {
        await _checkProvider(provider);
      }
    }
  }

  CloudProviderInfo? _getNextAvailableProvider(List<String> excludeIds) {
    for (final provider in _providers) {
      if (!excludeIds.contains(provider.id) &&
          provider.status == CloudProviderStatus.available) {
        return provider;
      }
    }
    return null;
  }

  Future<MultiCloudResult> _reconstructWithProvider({
    required CloudProviderInfo provider,
    required List<XFile> photos,
    required String projectName,
    required String userEmail,
    Function(double progress, String status)? onProgress,
    bool sendNotifications = true,
  }) async {
    switch (provider.id) {
      case 'openscan':
        return await _reconstructWithOpenScan(
          photos: photos,
          projectName: projectName,
          userEmail: userEmail,
          onProgress: onProgress,
          sendNotifications: sendNotifications,
        );

      case 'meshroom_local':
        return MultiCloudResult(
          success: false,
          provider: provider.id,
          errorMessage: 'Meshroom local processing not implemented yet',
        );

      case 'polycam_api':
        return MultiCloudResult(
          success: false,
          provider: provider.id,
          errorMessage: 'Polycam API not configured',
        );

      default:
        return MultiCloudResult(
          success: false,
          provider: provider.id,
          errorMessage: 'Unknown provider: ${provider.id}',
        );
    }
  }

  Future<MultiCloudResult> _reconstructWithOpenScan({
    required List<XFile> photos,
    required String projectName,
    required String userEmail,
    Function(double progress, String status)? onProgress,
    bool sendNotifications = true,
  }) async {
    try {
      final result = await _openScanService.reconstruct(
        images: photos,
        email: userEmail,
        projectName: projectName,
        onProgress: onProgress,
        sendNotifications: sendNotifications,
      );

      return MultiCloudResult(
        success: result.success,
        provider: 'openscan',
        modelPath: result.modelFile?.path,
        previewUrl: result.previewUrl,
        pointCount: result.pointCount,
        vertexCount: result.vertexCount,
        processingTimeSeconds: result.processingTime?.toDouble(),
        errorMessage: result.errorMessage,
      );
    } catch (e) {
      return MultiCloudResult(
        success: false,
        provider: 'openscan',
        errorMessage: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>?> getQueueEstimate() async {
    final provider = getBestProvider();
    if (provider == null) return null;

    switch (provider.id) {
      case 'openscan':
        return await _openScanService.getQueueEstimate();
      default:
        return null;
    }
  }

  void cancelReconstruction() {
    _openScanService.cancel();
  }
}

/// Provider selection widget helper
class CloudProviderSelector {
  static String getStatusIcon(CloudProviderStatus status) {
    switch (status) {
      case CloudProviderStatus.available:
        return 'check_circle';
      case CloudProviderStatus.unavailable:
        return 'cancel';
      case CloudProviderStatus.rateLimit:
        return 'hourglass_empty';
      case CloudProviderStatus.error:
        return 'error';
    }
  }

  static int getStatusColor(CloudProviderStatus status) {
    switch (status) {
      case CloudProviderStatus.available:
        return 0xFF4CAF50;
      case CloudProviderStatus.unavailable:
        return 0xFF9E9E9E;
      case CloudProviderStatus.rateLimit:
        return 0xFFFFC107;
      case CloudProviderStatus.error:
        return 0xFFF44336;
    }
  }
}

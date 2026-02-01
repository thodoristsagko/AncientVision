import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// High-performance image compression and optimization service
class PerformanceService {
  static final PerformanceService _instance = PerformanceService._internal();
  factory PerformanceService() => _instance;
  PerformanceService._internal();

  // LRU Cache for processed images
  final _imageCache = <String, Uint8List>{};
  final _cacheOrder = <String>[];
  static const _maxCacheEntries = 20;
  static const _maxCacheSizeBytes = 30 * 1024 * 1024; // 30MB
  int _currentCacheSize = 0;

  /// Compress image for upload with quality optimization
  /// Returns compressed bytes and estimated quality score
  Future<({Uint8List bytes, int quality, int originalSize, int compressedSize})> compressImageForUpload(
    File imageFile, {
    int maxWidth = 1920,
    int maxHeight = 1920,
    int quality = 85,
  }) async {
    return compute(_compressInIsolate, {
      'path': imageFile.path,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
      'quality': quality,
    });
  }

  static ({Uint8List bytes, int quality, int originalSize, int compressedSize}) _compressInIsolate(
    Map<String, dynamic> params,
  ) {
    final imagePath = params['path'] as String;
    final maxWidth = params['maxWidth'] as int;
    final maxHeight = params['maxHeight'] as int;
    final targetQuality = params['quality'] as int;

    final originalBytes = File(imagePath).readAsBytesSync();
    final originalSize = originalBytes.length;

    final image = img.decodeImage(originalBytes);
    if (image == null) {
      return (bytes: originalBytes, quality: 0, originalSize: originalSize, compressedSize: originalSize);
    }

    // Calculate resize dimensions maintaining aspect ratio
    int newWidth = image.width;
    int newHeight = image.height;

    if (image.width > maxWidth || image.height > maxHeight) {
      final aspectRatio = image.width / image.height;
      if (aspectRatio > 1) {
        newWidth = maxWidth;
        newHeight = (maxWidth / aspectRatio).round();
      } else {
        newHeight = maxHeight;
        newWidth = (maxHeight * aspectRatio).round();
      }
    }

    // Resize with high-quality interpolation
    final resized = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.cubic,
    );

    // Adaptive quality based on image complexity
    int adaptiveQuality = targetQuality;
    final pixelCount = newWidth * newHeight;
    if (pixelCount > 2000000) {
      adaptiveQuality = (targetQuality * 0.9).round(); // Reduce quality for very large images
    }

    // Encode to JPEG with optimized settings
    final compressed = img.encodeJpg(resized, quality: adaptiveQuality);
    final compressedBytes = Uint8List.fromList(compressed);

    return (
      bytes: compressedBytes,
      quality: adaptiveQuality,
      originalSize: originalSize,
      compressedSize: compressedBytes.length,
    );
  }

  /// Compress multiple images in parallel batches
  Future<List<Uint8List>> compressImageBatch(
    List<File> images, {
    int maxWidth = 1920,
    int maxHeight = 1920,
    int quality = 85,
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <Uint8List>[];
    final total = images.length;

    // Process in batches of 3 for optimal CPU/memory balance
    const batchSize = 3;
    for (int i = 0; i < images.length; i += batchSize) {
      final batch = images.skip(i).take(batchSize).toList();
      final futures = batch.map((file) => compressImageForUpload(
        file,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality,
      ));

      final batchResults = await Future.wait(futures);
      results.addAll(batchResults.map((r) => r.bytes));

      onProgress?.call((i + batch.length).clamp(0, total), total);
    }

    return results;
  }

  /// Generate thumbnail for preview
  Future<Uint8List> generateThumbnail(File imageFile, {int size = 200}) async {
    final cacheKey = '${imageFile.path}_thumb_$size';

    // Check cache first
    if (_imageCache.containsKey(cacheKey)) {
      _updateCacheOrder(cacheKey);
      return _imageCache[cacheKey]!;
    }

    final thumbnail = await compute(_generateThumbnailInIsolate, {
      'path': imageFile.path,
      'size': size,
    });

    // Cache the result
    _addToCache(cacheKey, thumbnail);

    return thumbnail;
  }

  static Uint8List _generateThumbnailInIsolate(Map<String, dynamic> params) {
    final imagePath = params['path'] as String;
    final size = params['size'] as int;

    final bytes = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return Uint8List(0);

    // Create square thumbnail with center crop
    final minDim = image.width < image.height ? image.width : image.height;
    final x = (image.width - minDim) ~/ 2;
    final y = (image.height - minDim) ~/ 2;

    final cropped = img.copyCrop(image, x: x, y: y, width: minDim, height: minDim);
    final thumbnail = img.copyResize(cropped, width: size, height: size);

    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80));
  }

  /// Optimize image for 3D reconstruction (higher quality needed)
  Future<File> optimizeForReconstruction(File imageFile) async {
    final result = await compute(_optimizeForReconstructionInIsolate, {
      'path': imageFile.path,
    });

    // Save to temp directory
    final tempDir = await getTemporaryDirectory();
    final outputPath = path.join(tempDir.path, 'recon_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(result);

    return outputFile;
  }

  static Uint8List _optimizeForReconstructionInIsolate(Map<String, dynamic> params) {
    final imagePath = params['path'] as String;

    final bytes = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // Target 2048x2048 max for reconstruction (balance of quality and performance)
    const maxDim = 2048;
    int newWidth = image.width;
    int newHeight = image.height;

    if (image.width > maxDim || image.height > maxDim) {
      final aspectRatio = image.width / image.height;
      if (aspectRatio > 1) {
        newWidth = maxDim;
        newHeight = (maxDim / aspectRatio).round();
      } else {
        newHeight = maxDim;
        newWidth = (maxDim * aspectRatio).round();
      }
    }

    final resized = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.cubic,
    );

    // Apply slight sharpening to enhance features for SfM
    final sharpened = img.convolution(resized, filter: [
      0, -0.5, 0,
      -0.5, 3, -0.5,
      0, -0.5, 0,
    ]);

    // High quality for reconstruction
    return Uint8List.fromList(img.encodeJpg(sharpened, quality: 95));
  }

  /// Clean up temporary files and caches
  Future<int> cleanupTempFiles() async {
    int deletedCount = 0;

    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();

      for (final file in files) {
        if (file is File) {
          final name = path.basename(file.path);
          // Delete old reconstruction and thumbnail files
          if (name.startsWith('recon_') || name.startsWith('thumb_')) {
            final stat = await file.stat();
            final age = DateTime.now().difference(stat.modified);
            if (age.inHours > 24) {
              await file.delete();
              deletedCount++;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }

    // Clear image cache
    clearCache();

    return deletedCount;
  }

  /// Get memory usage statistics
  Map<String, dynamic> getMemoryStats() {
    return {
      'cacheEntries': _imageCache.length,
      'cacheSizeBytes': _currentCacheSize,
      'cacheSizeMB': (_currentCacheSize / (1024 * 1024)).toStringAsFixed(2),
      'maxCacheMB': (_maxCacheSizeBytes / (1024 * 1024)).toStringAsFixed(0),
    };
  }

  void _addToCache(String key, Uint8List data) {
    // Evict old entries if needed
    while (_currentCacheSize + data.length > _maxCacheSizeBytes && _cacheOrder.isNotEmpty) {
      final oldest = _cacheOrder.removeAt(0);
      final removed = _imageCache.remove(oldest);
      if (removed != null) {
        _currentCacheSize -= removed.length;
      }
    }

    // Evict if too many entries
    while (_imageCache.length >= _maxCacheEntries && _cacheOrder.isNotEmpty) {
      final oldest = _cacheOrder.removeAt(0);
      final removed = _imageCache.remove(oldest);
      if (removed != null) {
        _currentCacheSize -= removed.length;
      }
    }

    _imageCache[key] = data;
    _cacheOrder.add(key);
    _currentCacheSize += data.length;
  }

  void _updateCacheOrder(String key) {
    _cacheOrder.remove(key);
    _cacheOrder.add(key);
  }

  void clearCache() {
    _imageCache.clear();
    _cacheOrder.clear();
    _currentCacheSize = 0;
  }
}

/// Firestore query optimizer with smart caching
class FirestoreCacheService {
  static final FirestoreCacheService _instance = FirestoreCacheService._internal();
  factory FirestoreCacheService() => _instance;
  FirestoreCacheService._internal();

  final _queryCache = <String, ({dynamic data, DateTime timestamp})>{};
  static const _cacheDuration = Duration(minutes: 5);

  /// Get cached data or null if expired/missing
  T? getCached<T>(String queryKey) {
    final cached = _queryCache[queryKey];
    if (cached == null) return null;

    if (DateTime.now().difference(cached.timestamp) > _cacheDuration) {
      _queryCache.remove(queryKey);
      return null;
    }

    return cached.data as T?;
  }

  /// Cache query result
  void cache<T>(String queryKey, T data) {
    _queryCache[queryKey] = (data: data, timestamp: DateTime.now());

    // Limit cache size
    if (_queryCache.length > 100) {
      // Remove oldest entries
      final sortedKeys = _queryCache.entries
          .toList()
          ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));

      for (int i = 0; i < 20; i++) {
        _queryCache.remove(sortedKeys[i].key);
      }
    }
  }

  /// Invalidate specific cache entry
  void invalidate(String queryKey) {
    _queryCache.remove(queryKey);
  }

  /// Invalidate all cache entries matching a pattern
  void invalidatePattern(String pattern) {
    _queryCache.removeWhere((key, _) => key.contains(pattern));
  }

  /// Clear all cache
  void clearAll() {
    _queryCache.clear();
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'entries': _queryCache.length,
      'oldestEntry': _queryCache.isEmpty
          ? null
          : _queryCache.values.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b),
    };
  }
}

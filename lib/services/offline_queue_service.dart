import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._();

  static const _queueKey = 'offline_write_queue';
  static const _maxItems = 100;
  static const _maxRetries = 5;
  static const _batchSize = 500; // Firestore WriteBatch limit

  bool _listening = false;
  StreamSubscription? _connectivitySubscription;

  /// Start listening for connectivity changes and process queue when online.
  void startListening() {
    if (_listening) return;
    _listening = true;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        processQueue();
      }
    });
  }

  /// Stop listening and dispose the connectivity subscription.
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _listening = false;
  }

  /// Enqueue a failed write for later retry.
  Future<void> enqueue(String collection, String operation, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _loadQueue(prefs);
    if (queue.length >= _maxItems) {
      final overflow = queue.length - _maxItems + 1;
      debugPrint('OfflineQueue: Queue full (${queue.length} items), dropping $overflow oldest');
      queue.removeRange(0, overflow);
    }
    queue.add({
      'collection': collection,
      'operation': operation,
      'data': data,
      'retries': 0,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_queueKey, jsonEncode(queue));
    debugPrint('OfflineQueue: Enqueued $operation to $collection (${queue.length} pending)');
  }

  /// Process all queued writes using Firestore WriteBatch for efficiency.
  /// Uses truncated binary exponential backoff between batch retries.
  Future<void> processQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _loadQueue(prefs);
    if (queue.isEmpty) return;

    debugPrint('OfflineQueue: Processing ${queue.length} queued writes...');
    final remaining = <Map<String, dynamic>>[];

    // Process in batches of up to 500 (Firestore WriteBatch limit)
    for (int start = 0; start < queue.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, queue.length);
      final chunk = queue.sublist(start, end);

      try {
        final batch = FirebaseFirestore.instance.batch();
        final batchItems = <Map<String, dynamic>>[];

        for (final item in chunk) {
          final collection = item['collection'] as String;
          final operation = item['operation'] as String;
          final data = Map<String, dynamic>.from(item['data'] as Map);

          final ref = FirebaseFirestore.instance.collection(collection);
          if (operation == 'add') {
            batch.set(ref.doc(), data);
          } else if (operation == 'set' && data.containsKey('__docId')) {
            final docId = data.remove('__docId') as String;
            batch.set(ref.doc(docId), data);
          } else if (operation == 'update' && data.containsKey('__docId')) {
            final docId = data.remove('__docId') as String;
            batch.update(ref.doc(docId), data);
          }
          batchItems.add(item);
        }

        await batch.commit();
        debugPrint('OfflineQueue: Committed batch of ${batchItems.length} writes');
      } catch (e) {
        // Batch failed — increment retries with exponential backoff
        for (final item in chunk) {
          final retries = (item['retries'] as int? ?? 0) + 1;
          if (retries < _maxRetries) {
            item['retries'] = retries;
            remaining.add(item);
            debugPrint('OfflineQueue: Retry $retries/$_maxRetries for ${item['collection']}');
          } else {
            debugPrint('OfflineQueue: Dropping item after $_maxRetries retries: $e');
          }
        }

        // Truncated binary exponential backoff before next batch
        // Metcalfe & Boggs (1976) IEEE 802.3 CSMA/CD
        final attempt = remaining.isNotEmpty
            ? (remaining.last['retries'] as int? ?? 1)
            : 1;
        final maxSlots = min(1 << attempt, 1024); // 2^attempt capped at 1024
        final slots = Random().nextInt(maxSlots);
        final backoffMs = slots * 10; // 10ms slot time
        if (backoffMs > 0) {
          await Future.delayed(Duration(milliseconds: backoffMs));
        }
      }
    }

    await prefs.setString(_queueKey, jsonEncode(remaining));
    if (remaining.isNotEmpty) {
      debugPrint('OfflineQueue: ${remaining.length} items still pending');
    }
  }

  List<Map<String, dynamic>> _loadQueue(SharedPreferences prefs) {
    final raw = prefs.getString(_queueKey);
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } catch (_) {
      return [];
    }
  }
}

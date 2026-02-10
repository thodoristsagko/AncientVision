import 'dart:convert';
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
  static const _maxRetries = 3;

  bool _listening = false;

  /// Start listening for connectivity changes and process queue when online.
  void startListening() {
    if (_listening) return;
    _listening = true;
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        processQueue();
      }
    });
  }

  /// Enqueue a failed write for later retry.
  Future<void> enqueue(String collection, String operation, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _loadQueue(prefs);
    if (queue.length >= _maxItems) {
      debugPrint('OfflineQueue: Queue full ($queue.length items), dropping oldest');
      queue.removeAt(0);
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

  /// Process all queued writes, retrying each up to [_maxRetries] times.
  Future<void> processQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _loadQueue(prefs);
    if (queue.isEmpty) return;

    debugPrint('OfflineQueue: Processing ${queue.length} queued writes...');
    final remaining = <Map<String, dynamic>>[];

    for (final item in queue) {
      try {
        final collection = item['collection'] as String;
        final operation = item['operation'] as String;
        final data = Map<String, dynamic>.from(item['data'] as Map);

        final ref = FirebaseFirestore.instance.collection(collection);
        if (operation == 'add') {
          await ref.add(data);
        } else if (operation == 'set' && data.containsKey('__docId')) {
          final docId = data.remove('__docId') as String;
          await ref.doc(docId).set(data);
        } else if (operation == 'update' && data.containsKey('__docId')) {
          final docId = data.remove('__docId') as String;
          await ref.doc(docId).update(data);
        }
        debugPrint('OfflineQueue: Successfully synced $operation to $collection');
      } catch (e) {
        final retries = (item['retries'] as int? ?? 0) + 1;
        if (retries < _maxRetries) {
          item['retries'] = retries;
          remaining.add(item);
          debugPrint('OfflineQueue: Retry $retries/$_maxRetries for ${item['collection']}');
        } else {
          debugPrint('OfflineQueue: Dropping item after $_maxRetries retries: $e');
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

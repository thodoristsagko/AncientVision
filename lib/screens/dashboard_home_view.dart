// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/dashboard_home_widgets.dart';
import '../services/auth_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import 'notifications_screen.dart';
import 'qr_scanner_screen.dart';

class DashboardHomeView extends StatefulWidget {
  const DashboardHomeView({super.key});

  @override
  State<DashboardHomeView> createState() => DashboardHomeViewState();
}

class DashboardHomeViewState extends State<DashboardHomeView> {
  int _totalFindings = 0;
  int _todayFindings = 0;
  String _userName = '';
  List<Map<String, dynamic>> _lastFindings = [];
  int _offlineDataCount = 0;
  bool _isSyncing = false;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadFindingsCounts();
    _loadUserName();
    _loadLastFindings();
    _checkOfflineData();
    _loadUnreadNotifications();
  }

  Future<void> _loadUnreadNotifications() async {
    final count = await NotificationService().getUnreadCount();
    if (mounted) setState(() => _unreadNotifications = count);
  }

  Future<void> _checkOfflineData() async {
    final storage = LocalStorageService();
    await storage.initialize();
    if (mounted) setState(() => _offlineDataCount = storage.offlineDataCount);
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    final storage = LocalStorageService();
    final synced = await storage.syncPendingUploads();
    if (mounted) {
      setState(() {
        _isSyncing = false;
        _offlineDataCount = storage.offlineDataCount;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced > 0 ? 'Synced $synced finding${synced > 1 ? 's' : ''}' : 'Up to date'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
      _loadFindingsCounts();
      _loadLastFindings();
    }
  }

  Future<void> _loadLastFindings() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get();
      if (mounted) {
        setState(() {
          _lastFindings = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'type': data['type'] ?? 'Unknown',
              'site': data['site'] ?? 'Unknown',
              'createdAt': data['createdAt'],
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading last findings: $e');
    }
  }

  Future<void> _loadUserName() async {
    final user = AuthService.currentUser;
    if (user == null) {
      setState(() => _userName = 'Guest');
      return;
    }
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      setState(() => _userName = user.displayName!.split(' ').first);
      return;
    }
    try {
      final profile = await AuthService.getUserProfile(user.uid);
      if (profile != null && profile['fullName'] != null && (profile['fullName'] as String).isNotEmpty) {
        if (mounted) setState(() => _userName = (profile['fullName'] as String).split(' ').first);
        return;
      }
    } catch (_) {}
    if (user.email != null && user.email!.isNotEmpty) {
      final name = user.email!.split('@').first;
      if (mounted) setState(() => _userName = name[0].toUpperCase() + name.substring(1).toLowerCase());
    } else {
      if (mounted) setState(() => _userName = 'User');
    }
  }

  Future<void> _loadFindingsCounts() async {
    try {
      final totalSnapshot = await FirebaseFirestore.instance.collection('findings').get();
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final todaySnapshot = await FirebaseFirestore.instance
          .collection('findings')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();
      if (mounted) {
        setState(() {
          _totalFindings = totalSnapshot.docs.length;
          _todayFindings = todaySnapshot.docs.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading findings counts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER: greeting + actions
              Row(
                children: [
                  const LogoCard(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Hello, ${_userName.isEmpty ? "..." : _userName}',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _headerIcon(
                    Icons.notifications_outlined,
                    badge: _unreadNotifications,
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                      _loadUnreadNotifications();
                    },
                  ),
                  _headerIcon(Icons.qr_code_scanner, onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
                  }),
                ],
              ),

              const SizedBox(height: 20),

              // OFFLINE SYNC (compact)
              if (_offlineDataCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: _isSyncing ? null : _syncNow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC107).withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (_isSyncing)
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFFFC107))),
                            )
                          else
                            const Icon(Icons.cloud_upload_outlined, color: Color(0xFFFFC107), size: 18),
                          const SizedBox(width: 10),
                          Text(
                            '$_offlineDataCount pending',
                            style: const TextStyle(color: Color(0xFFFFC107), fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          if (!_isSyncing)
                            const Text('Sync', style: TextStyle(color: Color(0xFFFFC107), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),

              // STATS
              CombinedStatCard(totalFindings: '$_totalFindings', todayFindings: '$_todayFindings'),
              const SizedBox(height: 12),

              // SENSOR STATUS
              const ActiveDevicesCard(),
              const SizedBox(height: 20),

              // RECENT FINDINGS
              LastFindingsCard(findings: _lastFindings),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerIcon(IconData icon, {int badge = 0, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 36, height: 36,
        child: Stack(
          children: [
            Center(child: Icon(icon, color: Colors.white.withAlpha(200), size: 22)),
            if (badge > 0)
              Positioned(
                top: 2, right: 2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Color(0xFFFFC107), shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

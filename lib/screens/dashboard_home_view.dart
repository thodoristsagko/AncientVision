import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/dashboard_home_widgets.dart';
import '../services/auth_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../widgets/offline_indicator.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'qr_scanner_screen.dart';
import 'ai_recognition_screen.dart';
import 'photogrammetry_screen.dart';

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
    if (mounted) {
      setState(() => _unreadNotifications = count);
    }
  }

  Future<void> _checkOfflineData() async {
    final storage = LocalStorageService();
    await storage.initialize();
    if (mounted) {
      setState(() {
        _offlineDataCount = storage.offlineDataCount;
      });
    }
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
          content: Text(synced > 0
              ? '✓ Synced $synced finding${synced > 1 ? 's' : ''}'
              : 'Already up to date'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );

      // Reload findings
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
              'date': data['date'] ?? '',
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

    // First try Firebase Auth displayName
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      setState(() => _userName = user.displayName!.split(' ').first);
      return;
    }

    // Fallback: fetch from Firestore
    try {
      final profile = await AuthService.getUserProfile(user.uid);
      if (profile != null && profile['fullName'] != null && (profile['fullName'] as String).isNotEmpty) {
        final fullName = profile['fullName'] as String;
        if (mounted) {
          setState(() => _userName = fullName.split(' ').first);
        }
        return;
      }
    } catch (e) {
      // Continue to email fallback
    }

    // Final fallback: extract name from email
    if (user.email != null && user.email!.isNotEmpty) {
      final emailName = user.email!.split('@').first;
      // Capitalize first letter
      final name = emailName[0].toUpperCase() + emailName.substring(1).toLowerCase();
      if (mounted) setState(() => _userName = name);
    } else {
      if (mounted) setState(() => _userName = 'User');
    }
  }

  Future<void> _loadFindingsCounts() async {
    try {
      // Get total findings count
      final totalSnapshot = await FirebaseFirestore.instance
          .collection('findings')
          .get();

      // Get today's findings count
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
          colors: [
            Color(0xFF0D3A39),
            Color(0xFF1C2523),
          ],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, ${_userName.isEmpty ? "..." : _userName}!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) => GestureDetector(
                            onTap: () async {
                              await AuthService.signOut();
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  (route) => false,
                                );
                              }
                            },
                            child: Text(
                              'Sign Out',
                              style: TextStyle(
                                color: Colors.white.withAlpha(153),
                                fontSize: 14,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Notifications button
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                      _loadUnreadNotifications();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(51)),
                      ),
                      child: Stack(
                        children: [
                          const Center(
                            child: Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
                          ),
                          if (_unreadNotifications > 0)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFC107),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                child: Text(
                                  _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // QR Scanner button
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                      );
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Center(
                        child: Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Offline indicator chip
                  const OfflineChip(),
                  const LogoCard(),
                ],
              ),

              const SizedBox(height: 24),

              // OFFLINE SYNC INDICATOR
              if (_offlineDataCount > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107).withAlpha(51),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFC107), width: 1),
                  ),
                  child: Row(
                    children: [
                      if (_isSyncing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Color(0xFFFFC107)),
                          ),
                        )
                      else
                        const Icon(Icons.cloud_off, color: Color(0xFFFFC107), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isSyncing ? 'Syncing...' : 'Offline Data',
                              style: const TextStyle(
                                color: Color(0xFFFFC107),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_offlineDataCount finding${_offlineDataCount > 1 ? 's' : ''} pending upload',
                              style: TextStyle(
                                color: Colors.white.withAlpha(204),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isSyncing)
                        TextButton(
                          onPressed: _syncNow,
                          child: const Text(
                            'Sync Now',
                            style: TextStyle(
                              color: Color(0xFFFFC107),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // STATS ROW
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      title: 'Total Findings',
                      value: '$_totalFindings',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      title: 'New Today',
                      value: '$_todayFindings',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ACTIVE DEVICES full width - shows connected BLE devices
              const ActiveDevicesCard(),

              const SizedBox(height: 12),

              // QUICK ACTIONS: AI Recognition & Photogrammetry
              _buildQuickActionsRow(),

              const SizedBox(height: 16),

              // LAST FINDINGS
              LastFindingsCard(findings: _lastFindings),

              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Row(
      children: [
        Expanded(
          child: GlassActionButton(
            icon: Icons.monetization_on_rounded,
            title: 'Coin AI',
            subtitle: 'Gemini AI',
            onTap: () async {
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(builder: (_) => const AIRecognitionScreen()),
              );
              if (result != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Classified as: ${result['type'] ?? 'Unknown'}'),
                    backgroundColor: const Color(0xFF4CAF50),
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassActionButton(
            icon: Icons.camera_alt_outlined,
            title: 'Photogrammetry',
            subtitle: '3D Scanning',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PhotogrammetryScreen(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

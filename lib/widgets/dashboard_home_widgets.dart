import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LogoCard extends StatelessWidget {
  const LogoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      width: 56,
      height: 56,
      fit: BoxFit.contain,
    );
  }
}

/// Combined stat card showing Total Findings and New Today in a single row
class CombinedStatCard extends StatelessWidget {
  final String totalFindings;
  final String todayFindings;

  const CombinedStatCard({
    super.key,
    required this.totalFindings,
    required this.todayFindings,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(89)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Findings',
                        style: TextStyle(
                          color: Colors.white.withAlpha(217),
                          fontSize: 13,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      totalFindings,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withAlpha(51),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Today',
                          style: TextStyle(
                            color: Colors.white.withAlpha(217),
                            fontSize: 13,
                          )),
                      const SizedBox(height: 4),
                      Text(
                        todayFindings,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;

  const StatCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(89)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    color: Colors.white.withAlpha(217),
                    fontSize: 14,
                  )),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dynamic Active Devices card that shows connected BLE devices
class ActiveDevicesCard extends StatefulWidget {
  const ActiveDevicesCard({super.key});

  @override
  State<ActiveDevicesCard> createState() => ActiveDevicesCardState();
}

class ActiveDevicesCardState extends State<ActiveDevicesCard> {
  int _connectedCount = 0;
  String _deviceName = '';
  late StreamSubscription<List<BluetoothDevice>> _subscription;

  @override
  void initState() {
    super.initState();
    _checkConnectedDevices();
    // Listen for connection changes
    _subscription = Stream.periodic(const Duration(seconds: 2))
        .asyncMap((_) => FlutterBluePlus.connectedDevices)
        .listen((devices) {
      if (mounted) {
        setState(() {
          _connectedCount = devices.length;
          _deviceName = devices.isNotEmpty ? (devices.first.platformName.isNotEmpty ? devices.first.platformName : 'M5StickC') : '';
        });
      }
    });
  }

  Future<void> _checkConnectedDevices() async {
    try {
      final devices = FlutterBluePlus.connectedDevices;
      if (mounted) {
        setState(() {
          _connectedCount = devices.length;
          _deviceName = devices.isNotEmpty ? (devices.first.platformName.isNotEmpty ? devices.first.platformName : 'M5StickC') : '';
        });
      }
    } catch (e) {
      debugPrint('Error checking connected devices: $e');
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectedCount > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isConnected
                  ? [const Color(0xFF4CAF50).withAlpha(40), const Color(0xFF4CAF50).withAlpha(20)]
                  : [Colors.white.withAlpha(26), Colors.white.withAlpha(13)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isConnected ? const Color(0xFF4CAF50).withAlpha(150) : Colors.white.withAlpha(90),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text('Active Devices',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withAlpha(217),
                                fontSize: 14,
                              )),
                        ),
                        const SizedBox(width: 8),
                        if (isConnected)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withAlpha(80),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('LIVE', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '$_connectedCount',
                      style: TextStyle(
                        color: isConnected ? const Color(0xFF4CAF50) : Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_deviceName.isNotEmpty)
                      Text(
                        _deviceName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isConnected
                      ? const Color(0xFF4CAF50).withAlpha(50)
                      : Colors.white.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: isConnected ? const Color(0xFF4CAF50) : Colors.white.withAlpha(150),
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Quick actions row (AI + Photogrammetry) ----

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    // Photogrammetry feature hidden from UI but code preserved
    // To re-enable, uncomment the second Expanded widget below
    return Row(
      children: [
        Expanded(
          child: GlassActionButton(
            icon: Icons.monetization_on_rounded,
            title: 'Coin AI',
            subtitle: 'Gemini AI',
            onTap: () async {
              // Import statement needed in the file that uses this widget
              // final result = await Navigator.push<Map<String, dynamic>>(
              //   context,
              //   MaterialPageRoute(builder: (_) => const AIRecognitionScreen()),
              // );
              // if (result != null && context.mounted) {
              //   ScaffoldMessenger.of(context).showSnackBar(
              //     SnackBar(
              //       content: Text('Classified as: ${result['type'] ?? 'Unknown'}'),
              //       backgroundColor: const Color(0xFF4CAF50),
              //     ),
              //   );
              // }
              // Navigation handled by parent widget
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
              // Import statement needed in the file that uses this widget
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(
              //     builder: (_) => const PhotogrammetryScreen(),
              //   ),
              // );
              // Navigation handled by parent widget
            },
          ),
        ),
      ],
    );
  }
}

class GlassActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const GlassActionButton({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(26),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withAlpha(89),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withAlpha(89),
                          width: 1,
                        ),
                      ),
                      child: Icon(icon, size: 18, color: Colors.white),
                    ),
                    if (subtitle != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107).withAlpha(51),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFFC107).withAlpha(128)),
                        ),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Color(0xFFFFC107),
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------- LAST FINDINGS CARD --------

class LastFindingsCard extends StatelessWidget {
  final List<Map<String, dynamic>> findings;

  const LastFindingsCard({super.key, required this.findings});

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '--:--';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '--:--';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withAlpha(89),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Last Findings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (findings.isEmpty)
                Text(
                  'No findings yet',
                  style: TextStyle(
                    color: Colors.white.withAlpha(128),
                    fontSize: 13,
                  ),
                )
              else
                ...findings.take(3).map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: FindingRow(
                    time: _formatTime(f['createdAt']),
                    type: f['type'] ?? 'Unknown',
                    site: f['site'] ?? 'Unknown',
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class FindingRow extends StatelessWidget {
  final String time;
  final String type;
  final String site;

  const FindingRow({
    super.key,
    required this.time,
    required this.type,
    required this.site,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          time,
          style: TextStyle(
            color: Colors.white.withAlpha(179),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            type,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          site,
          style: TextStyle(
            color: Colors.white.withAlpha(179),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

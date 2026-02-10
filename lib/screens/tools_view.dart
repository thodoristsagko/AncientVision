import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/export_service.dart';
import 'field_journal_screen.dart';
import 'quick_capture_screen.dart';
import 'manual_entry_form_screen.dart';
import 'ai_recognition_screen.dart';
import 'analytics_screen.dart';
import 'settings_screen.dart';
import 'help_screen.dart';
import 'admin_panel_screen.dart';
import 'login_screen.dart';

class ToolsView extends StatelessWidget {
  const ToolsView({super.key});

  bool get _isGuest => AuthService.currentUser == null;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    const Text(
                      'Professional Tools',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isGuest
                          ? 'Sign in to unlock all features'
                          : 'Industry-leading archaeological field tools',
                      style: TextStyle(
                        color: Colors.white.withAlpha(179),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_isGuest) ...[
                      // GUEST VIEW with locked features
                      _buildLockedFeaturePreview(context),
                    ] else ...[
                      // === HERO FEATURE: 3D RECONSTRUCTION === (HIDDEN)
                      // _buildHeroFeature(context),
                      // const SizedBox(height: 20),

                      // === FIELD WORK ===
                      _buildCategoryHeader('Field Work'),
                      const SizedBox(height: 12),
                      // Field Journal - Big Button (Main feature of Field Work)
                      _buildBigToolButton(
                        context,
                        icon: Icons.book_rounded,
                        title: 'Field Journal',
                        description: 'Daily logs, observations, and site notes with voice support',
                        color: const Color(0xFF795548),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const FieldJournalScreen()),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // === CAPTURE TOOLS ===
                      _buildCategoryHeader('Capture & Documentation'),
                      const SizedBox(height: 12),
                      // Quick Capture - Big Button
                      _buildBigToolButton(
                        context,
                        icon: Icons.flash_on_rounded,
                        title: 'Quick Capture',
                        description: 'Fast documentation - snap photo, add note, save instantly',
                        color: const Color(0xFF2196F3),
                        onTap: () async {
                          final result = await Navigator.push<Map<String, dynamic>>(
                            context,
                            MaterialPageRoute(builder: (_) => const QuickCaptureScreen()),
                          );
                          if (result != null && context.mounted) {
                            _handleQuickCaptureResult(context, result);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Manual Entry & Coin Recognition - Grid
                      _buildToolGrid(context, [
                        ToolCard(
                          icon: Icons.edit_note_rounded,
                          title: 'Manual Entry',
                          description: 'Full archaeological form',
                          color: const Color(0xFFFFC107),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ManualEntryFormScreen()),
                          ),
                        ),
                        ToolCard(
                          icon: Icons.auto_awesome_rounded,
                          title: 'Coin AI',
                          description: 'Gemini AI identification',
                          color: const Color(0xFFFF9800),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AIRecognitionScreen()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // === DATA & REPORTS ===
                      _buildCategoryHeader('Data & Reports'),
                      const SizedBox(height: 12),
                      _buildToolGrid(context, [
                        ToolCard(
                          icon: Icons.insights_rounded,
                          title: 'Analytics',
                          description: 'Statistics & activity',
                          color: const Color(0xFF00BCD4),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
                          ),
                        ),
                        ToolCard(
                          icon: Icons.file_download_rounded,
                          title: 'Export Data',
                          description: 'CSV, JSON, GeoJSON',
                          color: const Color(0xFF607D8B),
                          onTap: () => _showExportDialog(context),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // === SETTINGS & HELP ===
                      _buildCategoryHeader('Settings & Help'),
                      const SizedBox(height: 12),
                      _buildToolGrid(context, [
                        ToolCard(
                          icon: Icons.settings_rounded,
                          title: 'Settings',
                          description: 'Theme & preferences',
                          color: const Color(0xFF455A64),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          ),
                        ),
                        ToolCard(
                          icon: Icons.help_outline_rounded,
                          title: 'Help & Guide',
                          description: 'Tutorials & FAQ',
                          color: const Color(0xFF3F51B5),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HelpScreen()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // === ADMIN SECTION (only visible to admins) ===
                      FutureBuilder<bool>(
                        future: AuthService.isCurrentUserAdmin(),
                        builder: (context, snapshot) {
                          if (snapshot.data != true) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCategoryHeader('Admin'),
                              const SizedBox(height: 12),
                              _buildToolGrid(context, [
                                ToolCard(
                                  icon: Icons.admin_panel_settings_rounded,
                                  title: 'User Management',
                                  description: 'Manage roles & users',
                                  badge: 'Admin',
                                  color: const Color(0xFFF44336),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                                    );
                                  },
                                ),
                              ]),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 120),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildToolGrid(BuildContext context, List<ToolCard> tools) {
    return Row(
      children: [
        for (int i = 0; i < tools.length; i++) ...[
          Expanded(child: tools[i]),
          if (i < tools.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildBigToolButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(26),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(51),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withAlpha(204),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedFeaturePreview(BuildContext context) {
    return Column(
      children: [
        _buildLockedCard('3D Reconstruction', Icons.view_in_ar_rounded),
        const SizedBox(height: 12),
        _buildLockedCard('Manual Entry', Icons.edit_note_rounded),
        const SizedBox(height: 12),
        _buildLockedCard('Coin Recognition', Icons.auto_awesome_rounded),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Sign In to Unlock Tools',
                style: TextStyle(
                  color: Color(0xFF0D3A39),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLockedCard(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(26)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withAlpha(102),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 20),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2523),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export Data',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an export format for your findings',
              style: TextStyle(color: Colors.white.withAlpha(179)),
            ),
            const SizedBox(height: 20),
            ExportOptionTile(
              icon: Icons.code,
              title: 'JSON',
              subtitle: 'Full data with all fields',
              color: const Color(0xFF4CAF50),
              onTap: () async {
                Navigator.pop(context);
                await _exportData(context, ExportFormat.json);
              },
            ),
            ExportOptionTile(
              icon: Icons.table_chart,
              title: 'CSV',
              subtitle: 'Spreadsheet compatible',
              color: const Color(0xFF2196F3),
              onTap: () async {
                Navigator.pop(context);
                await _exportData(context, ExportFormat.csv);
              },
            ),
            ExportOptionTile(
              icon: Icons.map,
              title: 'GeoJSON',
              subtitle: 'For GIS applications',
              color: const Color(0xFFFF9800),
              onTap: () async {
                Navigator.pop(context);
                await _exportData(context, ExportFormat.geojson);
              },
            ),
            ExportOptionTile(
              icon: Icons.place,
              title: 'KML',
              subtitle: 'Google Earth format',
              color: const Color(0xFF9C27B0),
              onTap: () async {
                Navigator.pop(context);
                await _exportData(context, ExportFormat.kml);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData(BuildContext context, ExportFormat format) async {
    try {
      // Get findings from Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .get();

      final findings = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (findings.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No findings to export')),
          );
        }
        return;
      }

      final exportService = ExportService();
      File? file;

      switch (format) {
        case ExportFormat.json:
          file = await exportService.exportFindingsToJson(findings);
          break;
        case ExportFormat.csv:
          file = await exportService.exportFindingsToCsv(findings);
          break;
        case ExportFormat.geojson:
          file = await exportService.exportFindingsToGeoJson(findings);
          break;
        case ExportFormat.kml:
          file = await exportService.exportFindingsToKml(findings);
          break;
      }

      if (file != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${findings.length} findings to ${file.path.split('/').last}'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Handle Quick Capture result
  Future<void> _handleQuickCaptureResult(BuildContext context, Map<String, dynamic> result) async {
    // This method is referenced but its implementation is in main.dart
    // For now, we'll show a simple success message
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quick capture saved!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    }
  }
}

class ExportOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const ExportOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withAlpha(51),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: Colors.white.withAlpha(128)),
      onTap: onTap,
    );
  }
}

class ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final Color color;
  final VoidCallback onTap;

  const ToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(26),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(51),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withAlpha(51),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withAlpha(204),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

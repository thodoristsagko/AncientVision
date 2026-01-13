import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';

/// Settings Screen with comprehensive app configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsService = SettingsService();
  final _backupService = BackupService();
  final _notificationService = NotificationService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settingsService.initialize();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(
                  'Appearance',
                  Icons.palette,
                  [
                    _buildThemeSelector(),
                    _buildColorSelector(),
                    _buildFontSizeSlider(),
                  ],
                ),
                const SizedBox(height: 24),

                _buildSection(
                  'Data & Storage',
                  Icons.storage,
                  [
                    _buildSwitchTile(
                      'Auto Sync',
                      'Automatically sync data when online',
                      _settingsService.settings.autoSync,
                      (value) => _updateSetting('autoSync', value),
                    ),
                    _buildSwitchTile(
                      'Compress Images',
                      'Reduce image size to save storage',
                      _settingsService.settings.compressImages,
                      (value) => _updateSetting('compressImages', value),
                    ),
                    _buildBackupTile(),
                  ],
                ),
                const SizedBox(height: 24),

                _buildSection(
                  'Notifications',
                  Icons.notifications,
                  [
                    _buildSwitchTile(
                      'Enable Notifications',
                      'Receive alerts for processing status',
                      _settingsService.settings.notificationsEnabled,
                      (value) async {
                        if (value) {
                          await _notificationService.requestPermissions();
                        }
                        await _updateSetting('notificationsEnabled', value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _buildSection(
                  '3D & Photogrammetry',
                  Icons.view_in_ar,
                  [
                    _buildSwitchTile(
                      'Use Cloud Processing',
                      'Better results but requires internet',
                      _settingsService.settings.useCloudProcessing,
                      (value) => _updateSetting('useCloudProcessing', value),
                    ),
                    _buildSwitchTile(
                      'High Quality Preview',
                      'Better 3D preview (uses more memory)',
                      _settingsService.settings.highQualityPreview,
                      (value) => _updateSetting('highQualityPreview', value),
                    ),
                    _buildSliderTile(
                      'Max Photos per Scan',
                      _settingsService.settings.maxPhotosPerScan.toDouble(),
                      16,
                      100,
                      (value) => _updateSetting('maxPhotosPerScan', value.toInt()),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _buildSection(
                  'Field Work',
                  Icons.landscape,
                  [
                    _buildSwitchTile(
                      'Auto Save',
                      'Automatically save form drafts',
                      _settingsService.settings.autoSaveEnabled,
                      (value) => _updateSetting('autoSaveEnabled', value),
                    ),
                    _buildSwitchTile(
                      'Show GPS Coordinates',
                      'Display coordinates on findings',
                      _settingsService.settings.showGpsCoordinates,
                      (value) => _updateSetting('showGpsCoordinates', value),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _buildSection(
                  'Units & Format',
                  Icons.straighten,
                  [
                    _buildMeasurementSelector(),
                    _buildDateFormatSelector(),
                  ],
                ),
                const SizedBox(height: 24),

                // Reset button
                _buildResetButton(),

                const SizedBox(height: 24),

                // App info
                _buildAppInfo(),
              ],
            ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF8B4513), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildThemeSelector() {
    return ListTile(
      title: const Text('Theme', style: TextStyle(color: Colors.white)),
      subtitle: Text(
        _settingsService.settings.themeMode.label,
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: SegmentedButton<AppThemeMode>(
        selected: {_settingsService.settings.themeMode},
        onSelectionChanged: (Set<AppThemeMode> selection) {
          _updateSetting('themeMode', selection.first);
        },
        segments: AppThemeMode.values.map((mode) => ButtonSegment(
          value: mode,
          icon: Icon(mode.icon, size: 18),
        )).toList(),
        style: ButtonStyle(
          iconColor: WidgetStateProperty.all(Colors.white),
        ),
      ),
    );
  }

  Widget _buildColorSelector() {
    return ListTile(
      title: const Text('Accent Color', style: TextStyle(color: Colors.white)),
      trailing: Wrap(
        spacing: 8,
        children: List.generate(
          AccentColorOption.options.length.clamp(0, 5),
          (index) {
            final option = AccentColorOption.options[index];
            final isSelected = _settingsService.settings.accentColorIndex == index;
            return GestureDetector(
              onTap: () => _updateSetting('accentColorIndex', index),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: option.color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFontSizeSlider() {
    return ListTile(
      title: const Text('Font Size', style: TextStyle(color: Colors.white)),
      subtitle: Slider(
        value: _settingsService.settings.fontSize,
        min: 0.8,
        max: 1.4,
        divisions: 6,
        label: '${(_settingsService.settings.fontSize * 100).toInt()}%',
        activeColor: const Color(0xFF8B4513),
        onChanged: (value) => _updateSetting('fontSize', value),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      value: value,
      activeColor: const Color(0xFF8B4513),
      onChanged: onChanged,
    );
  }

  Widget _buildSliderTile(
    String title,
    double value,
    double min,
    double max,
    Function(double) onChanged,
  ) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).toInt(),
              label: value.toInt().toString(),
              activeColor: const Color(0xFF8B4513),
              onChanged: onChanged,
            ),
          ),
          Text(
            '${value.toInt()}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupTile() {
    return ListTile(
      title: const Text('Backup & Restore', style: TextStyle(color: Colors.white)),
      subtitle: const Text('Create or restore data backups', style: TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: _showBackupDialog,
    );
  }

  Widget _buildMeasurementSelector() {
    return ListTile(
      title: const Text('Measurement System', style: TextStyle(color: Colors.white)),
      trailing: DropdownButton<MeasurementSystem>(
        value: _settingsService.settings.measurementSystem,
        dropdownColor: const Color(0xFF2a2a3e),
        style: const TextStyle(color: Colors.white),
        underline: const SizedBox(),
        items: MeasurementSystem.values.map((system) => DropdownMenuItem(
          value: system,
          child: Text('${system.label} (${system.examples})'),
        )).toList(),
        onChanged: (value) {
          if (value != null) _updateSetting('measurementSystem', value);
        },
      ),
    );
  }

  Widget _buildDateFormatSelector() {
    return ListTile(
      title: const Text('Date Format', style: TextStyle(color: Colors.white)),
      trailing: DropdownButton<DateFormatPreference>(
        value: _settingsService.settings.dateFormat,
        dropdownColor: const Color(0xFF2a2a3e),
        style: const TextStyle(color: Colors.white),
        underline: const SizedBox(),
        items: DateFormatPreference.values.map((format) => DropdownMenuItem(
          value: format,
          child: Text(format.example),
        )).toList(),
        onChanged: (value) {
          if (value != null) _updateSetting('dateFormat', value);
        },
      ),
    );
  }

  Widget _buildResetButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _showResetConfirmation,
        icon: const Icon(Icons.restore, color: Colors.red),
        label: const Text('Reset to Defaults', style: TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _buildAppInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.explore, color: Color(0xFF8B4513), size: 40),
          const SizedBox(height: 8),
          const Text(
            'AncientVision',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Version 1.0.0',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 8),
          Text(
            'Archaeological Field Documentation App',
            style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Made for FLL Competition',
            style: TextStyle(color: Colors.amber.withAlpha(179), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    await _settingsService.updateSetting(key, value);
    if (mounted) setState(() {});
  }

  void _showBackupDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2a2a3e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.backup, color: Colors.green),
              title: const Text('Create Backup', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Save all data to a file', style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                final backup = await _backupService.createBackup(data: {
                  'timestamp': DateTime.now().toIso8601String(),
                });
                if (backup != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Backup created: ${backup.filename}')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.blue),
              title: const Text('Restore Backup', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Load data from a backup file', style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                final backups = await _backupService.listBackups();
                if (backups.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No backups found')),
                    );
                  }
                } else {
                  _showBackupList(backups);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBackupList(List<BackupInfo> backups) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2a2a3e),
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
              'Select Backup',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...backups.take(5).map((backup) => ListTile(
              title: Text(backup.filename, style: const TextStyle(color: Colors.white)),
              subtitle: Text('${backup.dateString} - ${backup.sizeString}', style: const TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                final data = await _backupService.restoreBackup(backup.path);
                if (data != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Backup restored successfully')),
                  );
                }
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showResetConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a3e),
        title: const Text('Reset Settings?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will reset all settings to their default values. This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _settingsService.resetToDefaults();
              if (mounted) setState(() {});
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

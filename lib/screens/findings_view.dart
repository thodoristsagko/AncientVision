// ignore_for_file: use_build_context_synchronously
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../models/finding_model.dart';
import '../services/auth_service.dart';
import '../services/local_storage_service.dart';
import '../services/export_service.dart';
import 'finding_details_page.dart';
import 'findings_map_screen.dart';
import 'quick_capture_screen.dart';
import 'ai_recognition_screen.dart';
import 'manual_entry_form_screen.dart';
import 'photogrammetry_screen.dart';
import '../widgets/finding_detail_card.dart';
import '../main.dart' show imgbbApiKey;

class FindingsView extends StatefulWidget {
  const FindingsView({super.key});

  @override
  State<FindingsView> createState() => _FindingsViewState();
}

class _FindingsViewState extends State<FindingsView> {
  List<Finding> _findings = [];
  List<Finding> _filteredFindings = [];
  bool _isLoading = true;
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  FindingSource? _selectedSource; // null means "All"

  // Batch selection mode
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  // Filter chips visibility
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _loadFindings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterFindings(String query) {
    setState(() {
      // Start with all findings
      var filtered = _findings.toList();

      // Filter by source if selected
      if (_selectedSource != null) {
        filtered = filtered.where((f) => f.source == _selectedSource).toList();
      }

      // Filter by search query
      if (query.isNotEmpty) {
        final searchLower = query.toLowerCase();
        filtered = filtered.where((f) {
          return f.name.toLowerCase().contains(searchLower) ||
              f.type.toLowerCase().contains(searchLower) ||
              f.site.toLowerCase().contains(searchLower) ||
              f.id.toLowerCase().contains(searchLower);
        }).toList();
      }

      _filteredFindings = filtered;
      if (_filteredFindings.isNotEmpty && _selectedIndex >= _filteredFindings.length) {
        _selectedIndex = 0;
      }
    });
  }

  void _setSourceFilter(FindingSource? source) {
    setState(() {
      _selectedSource = source;
    });
    _filterFindings(_searchController.text);
  }

  // Batch selection methods
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_filteredFindings.map((f) => f.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  Future<void> _showBatchExportDialog() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No findings selected')),
      );
      return;
    }

    final selectedFindings = _filteredFindings
        .where((f) => _selectedIds.contains(f.id))
        .toList();

    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _BatchExportSheet(
        selectedCount: selectedFindings.length,
      ),
    );

    if (format == null || !mounted) return;


    try {
      // Convert findings to export format
      final findingsData = selectedFindings.map((f) => {
        'id': f.id,
        'type': f.type,
        'site': f.site,
        'name': f.name,
        'date': f.date,
        'latitude': f.latitude,
        'longitude': f.longitude,
        'source': f.source.name,
      }).toList();

      final exportService = ExportService();
      final file = await exportService.batchExportFindings(
        findings: findingsData,
        format: format,
        includePhotos: true,
        onProgress: (progress, status) {
          debugPrint('Export progress: ${(progress * 100).toStringAsFixed(0)}% - $status');
        },
      );

      if (file != null && mounted) {
        // Share the file
        await exportService.shareFile(file);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${selectedFindings.length} findings'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );

        // Exit selection mode
        _toggleSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
      }
    }
  }

  Widget _buildSourceChip(FindingSource? source, String label, IconData icon) {
    final isSelected = _selectedSource == source;
    final color = source?.color ?? const Color(0xFFFFC107);

    return GestureDetector(
      onTap: () => _setSourceFilter(source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white.withAlpha(26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white.withAlpha(51),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.white.withAlpha(179),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withAlpha(179),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C2523),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Add Finding',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Quick Capture option
            _buildAddOption(
              icon: Icons.flash_on_rounded,
              title: 'Quick Capture',
              subtitle: 'Snap a photo and save instantly',
              color: const Color(0xFF2196F3),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (_) => const QuickCaptureScreen()),
                );
                if (result != null && context.mounted) {
                  _handleQuickCaptureResult(context, result);
                }
              },
            ),
            const SizedBox(height: 10),
            // Manual Entry option
            _buildAddOption(
              icon: Icons.edit_note_rounded,
              title: 'Manual Entry',
              subtitle: 'Full archaeological recording form',
              color: const Color(0xFFFFC107),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManualEntryFormScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            // Coin Recognition option
            _buildAddOption(
              icon: Icons.auto_awesome_rounded,
              title: 'Coin Recognition',
              subtitle: 'AI-powered coin identification',
              color: const Color(0xFF7C4DFF),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AIRecognitionScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            // Photogrammetry option
            _buildAddOption(
              icon: Icons.view_in_ar_rounded,
              title: 'Photogrammetry',
              subtitle: '3D reconstruction from photos',
              color: const Color(0xFF00BFA5),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PhotogrammetryScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            SafeArea(child: Container()),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(38)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(51),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withAlpha(153),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withAlpha(102),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadFindings() async {
    debugPrint('=== _loadFindings called ===');
    try {
      // First try with ordering, then fallback without if no results
      var snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 10));

      // If no results with ordering, try without (for docs missing createdAt)
      if (snapshot.docs.isEmpty) {
        debugPrint('No documents with createdAt, trying without ordering...');
        snapshot = await FirebaseFirestore.instance
            .collection('findings')
            .limit(20)
            .get()
            .timeout(const Duration(seconds: 10));
      }
      debugPrint('Firestore returned ${snapshot.docs.length} documents');

      final findings = snapshot.docs.map((doc) {
        final data = doc.data();
        debugPrint('Loading finding ${doc.id}');
        // Parse photoGallery from Firestore
        List<String> gallery = [];
        if (data['photoGallery'] != null) {
          gallery = List<String>.from(data['photoGallery']);
        }
        return Finding(
          id: doc.id,
          name: data['name'] ?? '',
          type: data['type'] ?? '',
          site: data['site'] ?? '',
          date: data['date'] ?? '',
          description: data['description'] ?? '',
          latitude: (data['latitude'] ?? 0.0).toDouble(),
          longitude: (data['longitude'] ?? 0.0).toDouble(),
          imageUrl: data['imageUrl'],
          photoGallery: gallery,
          model3dUrl: data['model3dUrl'],
          source: FindingSource.fromString(data['source']),
          // Coin fields
          denomination: data['denomination'],
          mint: data['mint'],
          ruler: data['ruler'],
          obverseLegend: data['obverseLegend'],
          reverseLegend: data['reverseLegend'],
          dieAxis: data['dieAxis'],
          obverseDescription: data['obverseDescription'],
          reverseDescription: data['reverseDescription'],
          // Fragment fields
          vesselPart: data['vesselPart'],
          wareType: data['wareType'],
          decorationStyle: data['decorationStyle'],
          fabricColorInt: data['fabricColorInt'],
          fabricColorExt: data['fabricColorExt'],
          rimDiameter: data['rimDiameter']?.toDouble(),
          wallThickness: data['wallThickness']?.toDouble(),
          surfaceTreatment: data['surfaceTreatment'],
          // Context fields
          locusNumber: data['locusNumber'],
          soilType: data['soilType'],
          matrixDescription: data['matrixDescription'],
          harrisPosition: data['harrisPosition'],
          associatedFeatures: data['associatedFeatures'] != null
              ? List<String>.from(data['associatedFeatures'])
              : null,
        );
      }).toList();

      setState(() {
        _findings = findings;
        _filteredFindings = findings;
        _isLoading = false;
        if (_findings.isNotEmpty && _selectedIndex >= _findings.length) {
          _selectedIndex = 0;
        }
      });
    } catch (e) {
      debugPrint('Error loading findings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to load findings: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadFindings,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _filteredFindings.isNotEmpty ? _filteredFindings[_selectedIndex] : null;

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
        child: RefreshIndicator(
          onRefresh: _loadFindings,
          color: const Color(0xFFFFC107),
          backgroundColor: const Color(0xFF0D3A39),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Findings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),

                // SEARCH BAR
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withAlpha(51),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterFindings,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by name, type, site, or ID...',
                      hintStyle: TextStyle(
                        color: Colors.white.withAlpha(102),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.white.withAlpha(128),
                        size: 20,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                _filterFindings('');
                              },
                              child: Icon(
                                Icons.clear_rounded,
                                color: Colors.white.withAlpha(128),
                                size: 20,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Toolbar row: filter toggle + selection mode controls + add button
                Row(
                  children: [
                    // Filter toggle button
                    GestureDetector(
                      onTap: () => setState(() => _showFilters = !_showFilters),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _showFilters || _selectedSource != null
                              ? const Color(0xFFFFC107).withAlpha(51)
                              : Colors.white.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _selectedSource != null
                                ? const Color(0xFFFFC107).withAlpha(128)
                                : Colors.white.withAlpha(51),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.filter_list_rounded,
                              color: _selectedSource != null
                                  ? const Color(0xFFFFC107)
                                  : Colors.white.withAlpha(179),
                              size: 18,
                            ),
                            if (_selectedSource != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                _selectedSource!.label,
                                style: const TextStyle(
                                  color: Color(0xFFFFC107),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Selection mode controls
                    if (_isSelectionMode) ...[
                      GestureDetector(
                        onTap: _showBatchExportDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.file_download, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'Export (${_selectedIds.length})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _selectedIds.length == _filteredFindings.length
                            ? _clearSelection
                            : _selectAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            _selectedIds.length == _filteredFindings.length ? 'None' : 'All',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _toggleSelectionMode,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(204),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Add button (FAB-style) - opens bottom sheet with options
                    if (AuthService.currentUser != null && !_isSelectionMode)
                      GestureDetector(
                        onTap: () => _showAddOptions(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC107),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Color(0xFF3E2723),
                            size: 22,
                          ),
                        ),
                      )
                    else if (AuthService.currentUser == null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(38),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              color: Colors.white.withAlpha(102),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Sign in',
                              style: TextStyle(
                                color: Colors.white.withAlpha(102),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                // Collapsible source filter chips
                if (_showFilters) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSourceChip(null, 'All', Icons.list_alt),
                        const SizedBox(width: 8),
                        ...FindingSource.values.map((source) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildSourceChip(source, source.label, source.icon),
                        )),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),

              // Show loading or empty state
              if (_isLoading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withAlpha(89),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFFC107),
                        ),
                      ),
                    ),
                  ),
                )
              else if (_findings.isEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withAlpha(89),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Animated icon container
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107).withAlpha(38),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFFC107).withAlpha(77),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.explore_outlined,
                              color: Color(0xFFFFC107),
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Start Your Discovery',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No archaeological findings recorded yet.\nDocument your first discovery!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withAlpha(153),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (AuthService.currentUser != null)
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ManualEntryFormScreen()),
                                ).then((_) => _loadFindings());
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add First Finding'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFC107),
                                foregroundColor: const Color(0xFF3E2723),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(26),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    color: Colors.white.withAlpha(128),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Sign in to add findings',
                                    style: TextStyle(
                                      color: Colors.white.withAlpha(128),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                // RECENT FINDINGS TABLE WITH SWIPE TO DELETE
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withAlpha(89),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Findings list
                          ..._filteredFindings.asMap().entries.map((entry) {
                            final index = entry.key;
                            final f = entry.value;
                            final isSelected = index == _selectedIndex;
                            final typeColor = Finding.getTypeColor(f.type);

                            return GestureDetector(
                              key: Key(f.id),
                              onTap: () {
                                if (_isSelectionMode) {
                                  setState(() {
                                    if (_selectedIds.contains(f.id)) {
                                      _selectedIds.remove(f.id);
                                      if (_selectedIds.isEmpty) {
                                        _isSelectionMode = false;
                                      }
                                    } else {
                                      _selectedIds.add(f.id);
                                    }
                                  });
                                } else {
                                  setState(() => _selectedIndex = index);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedIds.add(f.id);
                                  });
                                }
                              },
                              child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFFFC107).withAlpha(51)
                                        : Colors.white.withAlpha(13),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFFFC107).withAlpha(128)
                                          : Colors.transparent,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Selection checkbox (shown in selection mode)
                                      if (_isSelectionMode) ...[
                                        Icon(
                                          _selectedIds.contains(f.id)
                                              ? Icons.check_circle_rounded
                                              : Icons.circle_outlined,
                                          color: _selectedIds.contains(f.id)
                                              ? const Color(0xFF4CAF50)
                                              : Colors.white.withAlpha(102),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      // Type color indicator
                                      Container(
                                        width: 4,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: typeColor,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Finding info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  f.id,
                                                  style: TextStyle(
                                                    color: Colors.white.withAlpha(128),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    f.name,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${f.type} • ${f.site} • ${f.date}',
                                              style: TextStyle(
                                                color: Colors.white.withAlpha(153),
                                                fontSize: 11,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // 3D model indicator
                                      if (f.model3dUrl != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF7C4DFF).withAlpha(77),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            '3D',
                                            style: TextStyle(
                                              color: Color(0xFF7C4DFF),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => FindingDetailsPage(finding: f),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFC107).withAlpha(51),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            color: Color(0xFFFFC107),
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // MAP (Smaller size with OpenStreetMap)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      height: 300,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withAlpha(89),
                          width: 1,
                        ),
                      ),
                      child: FindingsMap(findings: _filteredFindings, selectedIndex: _selectedIndex),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // LATEST FINDING DETAIL PANEL
                if (selected != null) FindingDetailCard(finding: selected),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// Handle Quick Capture result - save to Firestore with source 'quick'
Future<void> _handleQuickCaptureResult(BuildContext context, Map<String, dynamic> result) async {
  // Support both formats: 'photo' (single) from QuickCapture, 'photos' (list) from elsewhere
  final singlePhoto = result['photo'] as XFile?;
  final photosList = result['photos'] as List<dynamic>?;
  final photos = photosList ?? (singlePhoto != null ? [singlePhoto] : null);
  final type = result['type'];
  // Support both 'note' and 'description' field names
  final description = (result['description'] ?? result['note']) as String?;
  final location = result['location'] as Map<String, dynamic>?;
  final persistedPath = result['persistedPath'] as String?;

  if (photos == null || photos.isEmpty) {
    debugPrint('QuickCapture: No photos to save');
    return;
  }

  // Get type label
  String typeLabel = 'Unknown';
  if (type != null) {
    try {
      typeLabel = type.label ?? 'Unknown';
    } catch (_) {
      typeLabel = type.toString();
    }
  }

  // Generate a local ID
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final localId = 'QC-$timestamp';

  // Create finding data with local photo path
  final findingData = {
    'id': localId,
    'name': description?.isNotEmpty == true ? description : 'Quick Capture ${DateTime.now().toIso8601String().split('T')[0]}',
    'type': typeLabel,
    'site': 'Field Site',
    'date': DateTime.now().toIso8601String().split('T')[0],
    'description': description ?? '',
    'latitude': location?['latitude'] ?? 0.0,
    'longitude': location?['longitude'] ?? 0.0,
    'imageUrl': persistedPath, // Use local path
    'photoGallery': persistedPath != null ? [persistedPath] : <String>[],
    'createdAt': DateTime.now().toIso8601String(),
    'source': 'quick',
  };

  // Save to local storage first (offline-first)
  try {
    final localStorage = LocalStorageService();
    await localStorage.initialize();
    // Cache locally and queue for cloud sync
    await localStorage.cacheFinding(findingId: localId, data: findingData);
    await localStorage.queueForUpload(findingId: localId, data: findingData);
    debugPrint('QuickCapture: Saved locally as $localId');

    // Show success immediately
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quick capture saved locally ($typeLabel)'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    }

    // Try to sync to cloud in background (non-blocking)
    _syncQuickCaptureToCloud(findingData, photos);
  } catch (e) {
    debugPrint('QuickCapture: Local save error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Background sync to cloud (non-blocking)
Future<void> _syncQuickCaptureToCloud(Map<String, dynamic> findingData, List<dynamic> photos) async {
  try {
    // Try to upload photos to imgbb
    final List<String> photoUrls = [];
    for (final photo in photos) {
      try {
        final xfile = photo as XFile;
        final bytes = await xfile.readAsBytes();
        final base64Image = base64Encode(bytes);

        final response = await http.post(
          Uri.parse('https://api.imgbb.com/1/upload'),
          body: {
            'key': imgbbApiKey,
            'image': base64Image,
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            photoUrls.add(data['data']['url']);
          }
        }
      } catch (e) {
        debugPrint('QuickCapture: Photo upload failed: $e');
      }
    }

    // Create a copy for cloud upload to avoid mutating the original local data
    final cloudData = Map<String, dynamic>.from(findingData);

    // Update cloud data with cloud URLs if available
    if (photoUrls.isNotEmpty) {
      cloudData['imageUrl'] = photoUrls.first;
      cloudData['photoGallery'] = photoUrls;
    }
    cloudData['createdAt'] = FieldValue.serverTimestamp();

    // Try to save to Firestore
    await FirebaseFirestore.instance
        .collection('findings')
        .doc(cloudData['id'] as String)
        .set(cloudData)
        .timeout(const Duration(seconds: 10));

    debugPrint('QuickCapture: Synced to cloud');
  } catch (e) {
    debugPrint('QuickCapture: Cloud sync failed (will retry later): $e');
    // Data is already saved locally, will sync when online
  }
}

/// Batch export format selection sheet
class _BatchExportSheet extends StatelessWidget {
  final int selectedCount;

  const _BatchExportSheet({required this.selectedCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C2523),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Icon(Icons.file_download, color: Color(0xFFFFC107), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Batch Export',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$selectedCount findings selected',
                      style: TextStyle(
                        color: Colors.white.withAlpha(179),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Format options
          const Text(
            'Select export format:',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),

          _buildFormatOption(
            context,
            ExportFormat.json,
            Icons.code,
            'JSON',
            'Full data with all fields',
          ),
          const SizedBox(height: 8),

          _buildFormatOption(
            context,
            ExportFormat.csv,
            Icons.table_chart,
            'CSV',
            'Spreadsheet compatible',
          ),
          const SizedBox(height: 8),

          _buildFormatOption(
            context,
            ExportFormat.geojson,
            Icons.map,
            'GeoJSON',
            'For mapping applications',
          ),
          const SizedBox(height: 8),

          _buildFormatOption(
            context,
            ExportFormat.kml,
            Icons.public,
            'KML',
            'For Google Earth',
          ),

          const SizedBox(height: 16),
          SafeArea(
            child: Container(),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatOption(
    BuildContext context,
    ExportFormat format,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, format),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withAlpha(51),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFFFFC107), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withAlpha(153),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withAlpha(102),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

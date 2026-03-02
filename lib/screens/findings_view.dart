// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../models/finding_model.dart';
import '../services/local_storage_service.dart';
import 'finding_details_page.dart';
import 'findings_map_screen.dart';
import 'quick_capture_screen.dart';
import 'ai_recognition_screen.dart';
import 'manual_entry_form_screen.dart';
import '../widgets/finding_detail_card.dart';
import '../config/env_config.dart';

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
          isSignificant: data['isSignificant'] ?? false,
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
                    const Spacer(),
                    // Add button (FAB-style) - opens bottom sheet with options
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
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFC107)),
                  ),
                )
              else if (_findings.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.explore_outlined, color: const Color(0xFFFFC107).withAlpha(150), size: 48),
                      const SizedBox(height: 16),
                      const Text('No findings yet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Tap + to add your first discovery', style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13)),
                    ],
                  ),
                )
              else ...[
                // RECENT FINDINGS TABLE WITH SWIPE TO DELETE
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ..._filteredFindings.asMap().entries.map((entry) {
                            final index = entry.key;
                            final f = entry.value;
                            final isSelected = index == _selectedIndex;
                            final typeColor = Finding.getTypeColor(f.type);

                            return GestureDetector(
                              key: Key(f.id),
                              onTap: () {
                                setState(() => _selectedIndex = index);
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

                const SizedBox(height: 12),

                // MAP
                Container(
                  height: (MediaQuery.of(context).size.height * 0.25).clamp(200.0, 350.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FindingsMap(findings: _filteredFindings, selectedIndex: _selectedIndex),
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
    'isSignificant': result['isSignificant'] ?? false,
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
            'key': EnvConfig.imgbbApiKey,
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

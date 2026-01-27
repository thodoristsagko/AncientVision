import 'package:flutter/material.dart';
import 'dart:io';
import '../models/photo_register.dart';
import '../utils/app_styles.dart';

/// Professional Photo Register Screen
class PhotoRegisterScreen extends StatefulWidget {
  const PhotoRegisterScreen({super.key});

  @override
  State<PhotoRegisterScreen> createState() => _PhotoRegisterScreenState();
}

class _PhotoRegisterScreenState extends State<PhotoRegisterScreen> {
  final PhotoRegisterService _service = PhotoRegisterService();
  bool _isLoading = true;
  PhotoSubject? _filterSubject;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _service.initialize();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<PhotoEntry> get _filteredEntries {
    var entries = _service.entries.toList(); // Create mutable copy

    if (_filterSubject != null) {
      entries = entries.where((e) => e.subject == _filterSubject).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      entries = entries.where((e) =>
        e.photoNumber.toLowerCase().contains(query) ||
        (e.description?.toLowerCase().contains(query) ?? false) ||
        (e.contextId?.toLowerCase().contains(query) ?? false)
      ).toList();
    }

    entries.sort((a, b) => b.dateTaken.compareTo(a.dateTaken));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Photo Register', style: AppTextStyles.h3),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportToCsv,
            tooltip: 'Export to CSV',
          ),
        ],
      ),
      body: Container(
        decoration: AppDecorations.screenBackground,
        child: SafeArea(
          child: _isLoading
              ? AppWidgets.loading()
              : Column(
                  children: [
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: TextField(
                        onChanged: (value) => setState(() => _searchQuery = value),
                        style: AppTextStyles.body,
                        decoration: InputDecoration(
                          hintText: 'Search photos...',
                          hintStyle: AppTextStyles.subtitleSmall,
                          prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),

                    // Stats bar
                    _buildStatsBar(),

                    // Photo grid
                    Expanded(
                      child: _filteredEntries.isEmpty
                          ? _buildEmptyState()
                          : GridView.builder(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.85,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _filteredEntries.length,
                              itemBuilder: (context, index) {
                                return _buildPhotoCard(_filteredEntries[index]);
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPhoto,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.primary,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Add Photo'),
      ),
    );
  }

  Widget _buildStatsBar() {
    final stats = _service.getStatistics();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total', stats['total'] ?? 0, Icons.photo_library),
          _buildStatItem('Review', stats['needsReview'] ?? 0, Icons.rate_review, color: AppColors.warning),
          _buildStatItem('GPS', stats['withGps'] ?? 0, Icons.gps_fixed, color: AppColors.success),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? AppColors.textSecondary, size: 20),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: AppTextStyles.h3.copyWith(color: color ?? AppColors.textPrimary),
        ),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text('No photos registered yet', style: AppTextStyles.subtitle),
          const SizedBox(height: AppSpacing.sm),
          Text('Tap + to add your first photo', style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(PhotoEntry entry) {
    return GestureDetector(
      onTap: () => _showPhotoDetails(entry),
      child: Container(
        decoration: AppDecorations.card,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo thumbnail
            Expanded(
              child: Container(
                width: double.infinity,
                color: AppColors.cardBorder,
                child: entry.filePath.isNotEmpty && File(entry.filePath).existsSync()
                    ? Image.file(
                        File(entry.filePath),
                        fit: BoxFit.cover,
                      )
                    : Center(
                        child: Icon(
                          Icons.image,
                          size: 48,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
            // Photo info
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.photoNumber,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.subject.label,
                          style: AppTextStyles.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.linkSummary,
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: AppDecorations.bottomSheet,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter by Subject', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filterSubject == null,
                  selectedColor: AppColors.accent,
                  onSelected: (selected) {
                    setState(() => _filterSubject = null);
                    Navigator.pop(context);
                  },
                ),
                ...PhotoSubject.values.map((subject) => ChoiceChip(
                  label: Text(subject.label),
                  selected: _filterSubject == subject,
                  selectedColor: AppColors.accent,
                  onSelected: (selected) {
                    setState(() => _filterSubject = selected ? subject : null);
                    Navigator.pop(context);
                  },
                )),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  void _showPhotoDetails(PhotoEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: AppDecorations.bottomSheet,
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Photo number badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        entry.photoNumber,
                        style: AppTextStyles.h3.copyWith(color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cardBorder,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(entry.subject.label, style: AppTextStyles.caption),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // Details
                _buildDetailSection('Basic Information', [
                  _buildDetailRow('Date', entry.dateString),
                  _buildDetailRow('Subject', entry.subject.label),
                  if (entry.direction != null)
                    _buildDetailRow('Direction', entry.direction!.label),
                  if (entry.takenBy != null)
                    _buildDetailRow('Taken By', entry.takenBy!),
                ]),

                _buildDetailSection('Links', [
                  _buildDetailRow('Context', entry.contextId ?? 'Not linked'),
                  _buildDetailRow('Find', entry.findId ?? 'Not linked'),
                ]),

                if (entry.description != null)
                  _buildDetailSection('Description', [
                    Text(entry.description!, style: AppTextStyles.body),
                  ]),

                if (entry.latitude != null)
                  _buildDetailSection('Location', [
                    _buildDetailRow('Latitude', entry.latitude!.toStringAsFixed(6)),
                    _buildDetailRow('Longitude', entry.longitude?.toStringAsFixed(6) ?? 'N/A'),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.h4),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: AppDecorations.section,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AppTextStyles.subtitle),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body),
          ),
        ],
      ),
    );
  }

  void _addPhoto() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Photo capture coming soon - use Quick Capture for now'),
        backgroundColor: Color(0xFFFFC107),
      ),
    );
  }

  void _exportToCsv() {
    _service.exportToCsv();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${_service.entries.length} photos to CSV'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}

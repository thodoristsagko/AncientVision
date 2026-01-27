import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/finds_register.dart';
import '../utils/app_styles.dart';

/// Professional Finds Register Screen - Museum-standard artifact cataloging
class FindsRegisterScreen extends StatefulWidget {
  const FindsRegisterScreen({super.key});

  @override
  State<FindsRegisterScreen> createState() => _FindsRegisterScreenState();
}

class _FindsRegisterScreenState extends State<FindsRegisterScreen>
    with SingleTickerProviderStateMixin {
  final FindsRegisterService _service = FindsRegisterService();
  late TabController _tabController;

  String _searchQuery = '';
  bool _showOnlyFlagged = false;
  bool _showOnlyNeedsReview = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _service.initialize();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<FindsRegisterEntry> get _filteredEntries {
    var entries = _service.entries.toList(); // Create mutable copy

    // Filter by category (tab)
    if (_tabController.index > 0) {
      final category = FindCategory.values[_tabController.index - 1];
      entries = entries.where((e) => e.category == category).toList();
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      entries = entries.where((e) =>
        e.findNumber.toLowerCase().contains(query) ||
        (e.description?.toLowerCase().contains(query) ?? false) ||
        (e.contextNumber?.toLowerCase().contains(query) ?? false)
      ).toList();
    }

    // Filter by flags
    if (_showOnlyFlagged) {
      entries = entries.where((e) => e.isFlagged).toList();
    }
    if (_showOnlyNeedsReview) {
      entries = entries.where((e) => e.needsReview).toList();
    }

    // Sort by sequence number descending (newest first)
    entries.sort((a, b) => b.sequenceNumber.compareTo(a.sequenceNumber));

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Finds Register', style: AppTextStyles.h3),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showOnlyFlagged ? Icons.flag : Icons.flag_outlined),
            onPressed: () => setState(() => _showOnlyFlagged = !_showOnlyFlagged),
            tooltip: 'Show flagged only',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportToCsv,
            tooltip: 'Export to CSV',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'stats', child: Text('View Statistics')),
              const PopupMenuItem(value: 'review', child: Text('Show Needs Review')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          onTap: (_) => setState(() {}),
          tabs: [
            const Tab(text: 'All'),
            Tab(text: FindCategory.smallFind.label),
            Tab(text: FindCategory.bulkFind.label),
            Tab(text: FindCategory.sample.label),
            Tab(text: FindCategory.specialFind.label),
          ],
        ),
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
                          hintText: 'Search finds...',
                          hintStyle: AppTextStyles.subtitleSmall,
                          prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),

                    // Statistics bar
                    _buildStatisticsBar(),

                    // Entries list
                    Expanded(
                      child: _filteredEntries.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                              itemCount: _filteredEntries.length,
                              itemBuilder: (context, index) {
                                return _buildEntryCard(_filteredEntries[index]);
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEntryDialog,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('New Find'),
      ),
    );
  }

  Widget _buildStatisticsBar() {
    final stats = _service.getStatistics();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total', stats['total'] ?? 0, Icons.inventory_2),
          _buildStatItem('Review', stats['needsReview'] ?? 0, Icons.rate_review, color: AppColors.warning),
          _buildStatItem('Flagged', stats['flagged'] ?? 0, Icons.flag, color: AppColors.error),
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
          Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text('No finds registered yet', style: AppTextStyles.subtitle),
          const SizedBox(height: AppSpacing.sm),
          Text('Tap + to add your first find', style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _buildEntryCard(FindsRegisterEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: AppDecorations.card,
      child: InkWell(
        onTap: () => _showEntryDetails(entry),
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Find number badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(entry.category),
                      borderRadius: BorderRadius.circular(AppSizes.borderRadiusSmall),
                    ),
                    child: Text(
                      entry.findNumber,
                      style: AppTextStyles.buttonSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Context number
                  if (entry.contextNumber != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cardBorder,
                        borderRadius: BorderRadius.circular(AppSizes.borderRadiusSmall),
                      ),
                      child: Text(
                        'Ctx ${entry.contextNumber}',
                        style: AppTextStyles.caption,
                      ),
                    ),
                  const Spacer(),
                  // Flags
                  if (entry.isFlagged)
                    Icon(Icons.flag, color: AppColors.error, size: 18),
                  if (entry.needsReview)
                    Icon(Icons.rate_review, color: AppColors.warning, size: 18),
                  // Processing status
                  _buildStatusChip(entry.processingStatus),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Description
              if (entry.description != null && entry.description!.isNotEmpty)
                Text(
                  entry.description!,
                  style: AppTextStyles.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: AppSpacing.sm),
              // Bottom row with metadata
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(entry.dateFoundString, style: AppTextStyles.caption),
                  const SizedBox(width: AppSpacing.md),
                  if (entry.storageLocation != null) ...[
                    Icon(Icons.inventory, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(entry.storageLocation!, style: AppTextStyles.caption),
                  ],
                  const Spacer(),
                  Text(entry.dimensionsString, style: AppTextStyles.caption),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(ProcessingStatus status) {
    Color chipColor;
    switch (status) {
      case ProcessingStatus.inSitu:
        chipColor = Colors.grey;
        break;
      case ProcessingStatus.lifted:
      case ProcessingStatus.washed:
      case ProcessingStatus.marked:
        chipColor = Colors.blue;
        break;
      case ProcessingStatus.photographed:
      case ProcessingStatus.analyzed:
        chipColor = Colors.orange;
        break;
      case ProcessingStatus.stored:
      case ProcessingStatus.exported:
        chipColor = Colors.green;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: chipColor.withAlpha(80)),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: chipColor, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  Color _getCategoryColor(FindCategory category) {
    switch (category) {
      case FindCategory.smallFind:
        return const Color(0xFF2196F3);
      case FindCategory.bulkFind:
        return const Color(0xFF795548);
      case FindCategory.sample:
        return const Color(0xFF9C27B0);
      case FindCategory.specialFind:
        return const Color(0xFFFF9800);
    }
  }

  void _showAddEntryDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddFindSheet(
        onSave: (entry) async {
          await _service.addEntry(entry);
          setState(() {});
        },
        getNextNumber: _service.getNextFindNumber,
      ),
    );
  }

  void _showEntryDetails(FindsRegisterEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FindDetailsSheet(
        entry: entry,
        onUpdate: (updated) async {
          await _service.updateEntry(updated);
          setState(() {});
        },
        onDelete: () async {
          await _service.deleteEntry(entry.id);
          setState(() {});
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  void _exportToCsv() {
    // Generate CSV data
    _service.exportToCsv();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${_service.entries.length} finds to CSV'),
        backgroundColor: AppColors.success,
        action: SnackBarAction(
          label: 'Share',
          textColor: Colors.white,
          onPressed: () {
            // Would implement share functionality
          },
        ),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'stats':
        _showStatisticsDialog();
        break;
      case 'review':
        setState(() => _showOnlyNeedsReview = !_showOnlyNeedsReview);
        break;
    }
  }

  void _showStatisticsDialog() {
    final stats = _service.getStatistics();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Register Statistics', style: AppTextStyles.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Finds: ${stats['total']}', style: AppTextStyles.body),
            const SizedBox(height: AppSpacing.md),
            Text('By Category:', style: AppTextStyles.subtitle),
            ...(stats['byCategory'] as Map<String, int>).entries.map((e) =>
              Text('  ${e.key}: ${e.value}', style: AppTextStyles.caption),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Needs Review: ${stats['needsReview']}', style: AppTextStyles.body),
            Text('Flagged: ${stats['flagged']}', style: AppTextStyles.body),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: AppTextStyles.button.copyWith(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for adding new find
class _AddFindSheet extends StatefulWidget {
  final Future<void> Function(FindsRegisterEntry) onSave;
  final String Function(FindCategory) getNextNumber;

  const _AddFindSheet({
    required this.onSave,
    required this.getNextNumber,
  });

  @override
  State<_AddFindSheet> createState() => _AddFindSheetState();
}

class _AddFindSheetState extends State<_AddFindSheet> {
  FindCategory _selectedCategory = FindCategory.smallFind;
  final _descriptionController = TextEditingController();
  final _contextController = TextEditingController();
  final _storageController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  bool _isFlagged = false;
  bool _needsReview = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _contextController.dispose();
    _storageController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.bottomSheet,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
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

              // Title
              Text('Register New Find', style: AppTextStyles.h2),
              const SizedBox(height: AppSpacing.xxl),

              // Category selector
              Text('Category', style: AppTextStyles.subtitle),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: FindCategory.values.map((cat) => ChoiceChip(
                  label: Text(cat.label),
                  selected: _selectedCategory == cat,
                  selectedColor: AppColors.accent,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedCategory = cat);
                  },
                )).toList(),
              ),
              const SizedBox(height: AppSpacing.md),

              // Auto-generated number preview
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: AppDecorations.highlightCard,
                child: Row(
                  children: [
                    Icon(Icons.tag, color: AppColors.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Find Number: ', style: AppTextStyles.subtitle),
                    Text(
                      widget.getNextNumber(_selectedCategory),
                      style: AppTextStyles.h3.copyWith(color: AppColors.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Description
              _buildTextField(
                controller: _descriptionController,
                label: 'Description',
                hint: 'Brief description of the find',
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.md),

              // Context number
              _buildTextField(
                controller: _contextController,
                label: 'Context Number',
                hint: 'e.g., 045',
              ),
              const SizedBox(height: AppSpacing.md),

              // Storage location
              _buildTextField(
                controller: _storageController,
                label: 'Storage Location',
                hint: 'Box/bag number',
              ),
              const SizedBox(height: AppSpacing.xl),

              // Measurements
              Text('Measurements (optional)', style: AppTextStyles.subtitle),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _buildNumberField(_lengthController, 'L (mm)')),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _buildNumberField(_widthController, 'W (mm)')),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _buildNumberField(_heightController, 'H (mm)')),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _buildNumberField(_weightController, 'g')),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Flags
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      value: _isFlagged,
                      onChanged: (v) => setState(() => _isFlagged = v ?? false),
                      title: Text('Flag as important', style: AppTextStyles.bodySmall),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.accent,
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      value: _needsReview,
                      onChanged: (v) => setState(() => _needsReview = v ?? false),
                      title: Text('Needs review', style: AppTextStyles.bodySmall),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveEntry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                    ),
                  ),
                  child: Text('Register Find', style: AppTextStyles.button),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.subtitle),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          style: AppTextStyles.body,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.subtitleSmall,
            filled: true,
            fillColor: AppColors.cardBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.borderRadiusSmall),
              borderSide: BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.borderRadiusSmall),
              borderSide: BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.borderRadiusSmall),
              borderSide: BorderSide(color: AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: AppTextStyles.bodySmall,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.caption,
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.borderRadiusSmall),
          borderSide: BorderSide(color: AppColors.cardBorder),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }

  void _saveEntry() async {
    final findNumber = widget.getNextNumber(_selectedCategory);
    final sequenceNumber = int.parse(findNumber.substring(2));

    final entry = FindsRegisterEntry(
      id: const Uuid().v4(),
      findNumber: findNumber,
      category: _selectedCategory,
      sequenceNumber: sequenceNumber,
      description: _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
      contextNumber: _contextController.text.isNotEmpty ? _contextController.text : null,
      storageLocation: _storageController.text.isNotEmpty ? _storageController.text : null,
      lengthMm: double.tryParse(_lengthController.text),
      widthMm: double.tryParse(_widthController.text),
      heightMm: double.tryParse(_heightController.text),
      weightGrams: double.tryParse(_weightController.text),
      dateFound: DateTime.now(),
      recordedAt: DateTime.now(),
      isFlagged: _isFlagged,
      needsReview: _needsReview,
    );

    await widget.onSave(entry);
    if (mounted) Navigator.pop(context);
  }
}

/// Bottom sheet for viewing/editing find details
class _FindDetailsSheet extends StatelessWidget {
  final FindsRegisterEntry entry;
  final Future<void> Function(FindsRegisterEntry) onUpdate;
  final VoidCallback onDelete;

  const _FindDetailsSheet({
    required this.entry,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(entry.category),
                      borderRadius: BorderRadius.circular(AppSizes.borderRadiusSmall),
                    ),
                    child: Text(
                      entry.findNumber,
                      style: AppTextStyles.h3.copyWith(color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (entry.isFlagged)
                    IconButton(
                      icon: Icon(Icons.flag, color: AppColors.error),
                      onPressed: () {},
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () => _confirmDelete(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Details sections
              _buildSection('Basic Information', [
                _buildDetailRow('Category', entry.category.label),
                _buildDetailRow('Context', entry.contextNumber ?? 'Not assigned'),
                _buildDetailRow('Date Found', entry.dateFoundString),
                if (entry.foundBy != null) _buildDetailRow('Found By', entry.foundBy!),
              ]),

              _buildSection('Description', [
                Text(
                  entry.description ?? 'No description',
                  style: AppTextStyles.body,
                ),
              ]),

              _buildSection('Measurements', [
                _buildDetailRow('Dimensions', entry.dimensionsString),
                _buildDetailRow('Coordinates', entry.coordinatesString),
              ]),

              _buildSection('Storage & Conservation', [
                _buildDetailRow('Storage', entry.storageLocation ?? 'Not assigned'),
                _buildDetailRow('Conservation', entry.conservationStatus.label),
                _buildDetailRow('Processing', entry.processingStatus.label),
              ]),

              const SizedBox(height: AppSpacing.xxl),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _updateStatus(context, ProcessingStatus.lifted),
                      icon: const Icon(Icons.upload),
                      label: const Text('Mark Lifted'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _updateStatus(context, ProcessingStatus.stored),
                      icon: const Icon(Icons.inventory),
                      label: const Text('Mark Stored'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
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

  Color _getCategoryColor(FindCategory category) {
    switch (category) {
      case FindCategory.smallFind:
        return const Color(0xFF2196F3);
      case FindCategory.bulkFind:
        return const Color(0xFF795548);
      case FindCategory.sample:
        return const Color(0xFF9C27B0);
      case FindCategory.specialFind:
        return const Color(0xFFFF9800);
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Find?', style: AppTextStyles.h3),
        content: Text(
          'Are you sure you want to delete ${entry.findNumber}? This cannot be undone.',
          style: AppTextStyles.subtitle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTextStyles.button.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: Text('Delete', style: AppTextStyles.button.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _updateStatus(BuildContext context, ProcessingStatus newStatus) async {
    final updated = entry.copyWith(
      processingStatus: newStatus,
      lastModified: DateTime.now(),
    );
    await onUpdate(updated);
    if (context.mounted) Navigator.pop(context);
  }
}

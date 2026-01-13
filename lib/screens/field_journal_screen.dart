import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/field_journal.dart';

/// Field Journal Screen for daily documentation
class FieldJournalScreen extends StatefulWidget {
  const FieldJournalScreen({super.key});

  @override
  State<FieldJournalScreen> createState() => _FieldJournalScreenState();
}

class _FieldJournalScreenState extends State<FieldJournalScreen> {
  List<JournalEntry> _entries = [];
  bool _isLoading = true;
  JournalEntryType _selectedFilter = JournalEntryType.daily;
  bool _showAllTypes = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entriesJson = prefs.getStringList('journal_entries') ?? [];
      _entries = entriesJson
          .map((json) => JournalEntry.fromJson(jsonDecode(json)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      _entries = [];
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'journal_entries',
      _entries.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Field Journal'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState()
              : _buildJournalList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewEntryDialog(),
        backgroundColor: const Color(0xFF8B4513),
        icon: const Icon(Icons.add),
        label: const Text('New Entry'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 80,
            color: Colors.white.withAlpha(77),
          ),
          const SizedBox(height: 16),
          Text(
            'No journal entries yet',
            style: TextStyle(
              color: Colors.white.withAlpha(179),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start documenting your fieldwork',
            style: TextStyle(
              color: Colors.white.withAlpha(128),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJournalList() {
    final filteredEntries = _showAllTypes
        ? _entries
        : _entries.where((e) => e.type == _selectedFilter).toList();

    // Group entries by date
    final groupedEntries = <String, List<JournalEntry>>{};
    for (final entry in filteredEntries) {
      final dateKey = _formatDateKey(entry.createdAt);
      groupedEntries.putIfAbsent(dateKey, () => []).add(entry);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedEntries.length,
      itemBuilder: (context, index) {
        final dateKey = groupedEntries.keys.elementAt(index);
        final entries = groupedEntries[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                dateKey,
                style: TextStyle(
                  color: Colors.white.withAlpha(179),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...entries.map((entry) => _buildEntryCard(entry)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildEntryCard(JournalEntry entry) {
    return GestureDetector(
      onTap: () => _showEntryDetails(entry),
      onLongPress: () => _showEntryOptions(entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(26),
          borderRadius: BorderRadius.circular(12),
          border: entry.isPinned
              ? Border.all(color: Colors.amber, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: entry.type.color.withAlpha(51),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    entry.type.icon,
                    color: entry.type.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        entry.type.label,
                        style: TextStyle(
                          color: entry.type.color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.isPinned)
                  const Icon(Icons.push_pin, color: Colors.amber, size: 16),
                if (entry.hasVoiceNote)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.mic, color: Colors.red.withAlpha(179), size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              entry.content,
              style: TextStyle(
                color: Colors.white.withAlpha(204),
                fontSize: 14,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (entry.tags != null && entry.tags!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: entry.tags!.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '#$tag',
                    style: TextStyle(
                      color: Colors.white.withAlpha(179),
                      fontSize: 12,
                    ),
                  ),
                )).toList(),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(entry.createdAt),
                  style: TextStyle(
                    color: Colors.white.withAlpha(128),
                    fontSize: 12,
                  ),
                ),
                if (entry.workCondition != null)
                  Row(
                    children: [
                      Icon(
                        entry.workCondition!.icon,
                        color: entry.workCondition!.color,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.workCondition!.label,
                        style: TextStyle(
                          color: Colors.white.withAlpha(128),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
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
              'Filter by Type',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.all_inclusive, color: Colors.white),
              title: const Text('All Types', style: TextStyle(color: Colors.white)),
              trailing: _showAllTypes ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () {
                setState(() => _showAllTypes = true);
                Navigator.pop(context);
              },
            ),
            ...JournalEntryType.values.take(6).map((type) => ListTile(
              leading: Icon(type.icon, color: type.color),
              title: Text(type.label, style: const TextStyle(color: Colors.white)),
              trailing: !_showAllTypes && _selectedFilter == type
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _showAllTypes = false;
                  _selectedFilter = type;
                });
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showNewEntryDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    JournalEntryType selectedType = JournalEntryType.daily;
    WorkCondition? selectedCondition;
    List<String> tags = [];
    final tagController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2a2a3e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'New Journal Entry',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // Type selection
                const Text('Entry Type', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: JournalEntryType.values.take(6).map((type) {
                    final isSelected = selectedType == type;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedType = type),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? type.color : Colors.white.withAlpha(26),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(type.icon, size: 16, color: isSelected ? Colors.white : type.color),
                            const SizedBox(width: 4),
                            Text(
                              type.label,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Title
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withAlpha(26),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Content
                TextField(
                  controller: contentController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Content',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withAlpha(26),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Work condition
                const Text('Work Condition', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: WorkCondition.values.map((condition) {
                    final isSelected = selectedCondition == condition;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedCondition = condition),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? condition.color.withAlpha(51) : Colors.white.withAlpha(26),
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected ? Border.all(color: condition.color) : null,
                        ),
                        child: Icon(condition.icon, color: condition.color, size: 24),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Tags
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tagController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Add tag...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withAlpha(26),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white),
                      onPressed: () {
                        if (tagController.text.isNotEmpty) {
                          setModalState(() {
                            tags.add(tagController.text);
                            tagController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: tags.map((tag) => Chip(
                      label: Text('#$tag'),
                      onDeleted: () => setModalState(() => tags.remove(tag)),
                      backgroundColor: Colors.white.withAlpha(26),
                      labelStyle: const TextStyle(color: Colors.white),
                      deleteIconColor: Colors.white54,
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (titleController.text.isEmpty || contentController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please fill in title and content')),
                        );
                        return;
                      }

                      final entry = JournalEntry(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        type: selectedType,
                        title: titleController.text,
                        content: contentController.text,
                        workCondition: selectedCondition,
                        tags: tags.isEmpty ? null : tags,
                      );

                      setState(() {
                        _entries.insert(0, entry);
                      });
                      _saveEntries();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B4513),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save Entry', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEntryDetails(JournalEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2a2a3e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: entry.type.color.withAlpha(51),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(entry.type.icon, color: entry.type.color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${entry.type.label} - ${entry.dayOfWeek}',
                          style: TextStyle(color: entry.type.color),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                entry.content,
                style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
              ),
              if (entry.workCondition != null) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(entry.workCondition!.icon, color: entry.workCondition!.color),
                    const SizedBox(width: 8),
                    Text(
                      'Work Condition: ${entry.workCondition!.label}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ],
              if (entry.tags != null && entry.tags!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: entry.tags!.map((tag) => Chip(
                    label: Text('#$tag'),
                    backgroundColor: Colors.white.withAlpha(26),
                    labelStyle: const TextStyle(color: Colors.white),
                  )).toList(),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Created: ${_formatDateTime(entry.createdAt)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEntryOptions(JournalEntry entry) {
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
              leading: Icon(
                entry.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: Colors.amber,
              ),
              title: Text(
                entry.isPinned ? 'Unpin Entry' : 'Pin Entry',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                setState(() {
                  final index = _entries.indexOf(entry);
                  _entries[index] = entry.copyWith(isPinned: !entry.isPinned);
                });
                _saveEntries();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Entry', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() => _entries.remove(entry));
                _saveEntries();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entryDate = DateTime(date.year, date.month, date.day);

    if (entryDate == today) return 'Today';
    if (entryDate == today.subtract(const Duration(days: 1))) return 'Yesterday';

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime date) {
    return '${_formatDateKey(date)} at ${_formatTime(date)}';
  }
}

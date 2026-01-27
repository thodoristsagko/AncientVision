import 'package:flutter/material.dart';

/// Validation Service for archaeological data quality checks
/// Ensures data completeness and accuracy before saving
class ValidationService {
  static final ValidationService _instance = ValidationService._internal();
  factory ValidationService() => _instance;
  ValidationService._internal();

  /// Validate a finding entry
  ValidationResult validateFinding(Map<String, dynamic> data) {
    final errors = <ValidationError>[];
    final warnings = <ValidationWarning>[];

    // Required fields
    if (_isEmpty(data['name'])) {
      errors.add(ValidationError('name', 'Name is required'));
    }
    if (_isEmpty(data['type'])) {
      errors.add(ValidationError('type', 'Type is required'));
    }

    // Strongly recommended fields
    if (_isEmpty(data['contextNumber'])) {
      warnings.add(ValidationWarning('contextNumber', 'No context assigned - consider linking to a context'));
    }
    if (data['latitude'] == null || data['longitude'] == null) {
      warnings.add(ValidationWarning('coordinates', 'No GPS coordinates - location data improves documentation'));
    }
    if (_isEmpty(data['imageUrl']) && (data['photoIds'] as List?)?.isEmpty != false) {
      warnings.add(ValidationWarning('photo', 'No photo attached - photos are essential for archaeological records'));
    }

    // Optional but valuable
    if (_isEmpty(data['description'])) {
      warnings.add(ValidationWarning('description', 'Adding a description improves documentation quality'));
    }
    if (_isEmpty(data['material'])) {
      warnings.add(ValidationWarning('material', 'Material type not specified'));
    }
    if (_isEmpty(data['period'])) {
      warnings.add(ValidationWarning('period', 'Historical period not specified'));
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      completeness: _calculateCompleteness(data, _findingFields),
    );
  }

  /// Validate a context sheet entry
  ValidationResult validateContextSheet(Map<String, dynamic> data) {
    final errors = <ValidationError>[];
    final warnings = <ValidationWarning>[];

    // Required fields
    if (_isEmpty(data['contextNumber'])) {
      errors.add(ValidationError('contextNumber', 'Context number is required'));
    }
    if (_isEmpty(data['type'])) {
      errors.add(ValidationError('type', 'Context type is required'));
    }

    // Strongly recommended
    if (_isEmpty(data['interpretation'])) {
      warnings.add(ValidationWarning('interpretation', 'No interpretation provided'));
    }
    if (data['topElevation'] == null) {
      warnings.add(ValidationWarning('elevation', 'Top elevation not recorded'));
    }

    // Stratigraphic relationships
    final hasRelationships =
        (data['above'] as List?)?.isNotEmpty == true ||
        (data['below'] as List?)?.isNotEmpty == true ||
        (data['cuts'] as List?)?.isNotEmpty == true ||
        (data['cutBy'] as List?)?.isNotEmpty == true;

    if (!hasRelationships) {
      warnings.add(ValidationWarning('relationships', 'No stratigraphic relationships defined'));
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      completeness: _calculateCompleteness(data, _contextFields),
    );
  }

  /// Validate a finds register entry
  ValidationResult validateFindsRegister(Map<String, dynamic> data) {
    final errors = <ValidationError>[];
    final warnings = <ValidationWarning>[];

    // Required fields
    if (_isEmpty(data['findNumber'])) {
      errors.add(ValidationError('findNumber', 'Find number is required'));
    }
    if (_isEmpty(data['category'])) {
      errors.add(ValidationError('category', 'Category is required'));
    }

    // Strongly recommended
    if (_isEmpty(data['contextNumber'])) {
      warnings.add(ValidationWarning('contextNumber', 'No context linked - finds should be associated with contexts'));
    }
    if (_isEmpty(data['storageLocation'])) {
      warnings.add(ValidationWarning('storageLocation', 'Storage location not specified'));
    }
    if (data['dateFound'] == null) {
      warnings.add(ValidationWarning('dateFound', 'Date found not recorded'));
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      completeness: _calculateCompleteness(data, _findsRegisterFields),
    );
  }

  /// Validate a journal entry
  ValidationResult validateJournalEntry(Map<String, dynamic> data) {
    final errors = <ValidationError>[];
    final warnings = <ValidationWarning>[];

    // Required fields
    if (_isEmpty(data['title'])) {
      errors.add(ValidationError('title', 'Title is required'));
    }
    if (_isEmpty(data['content']) && _isEmpty(data['transcription'])) {
      errors.add(ValidationError('content', 'Content or voice note is required'));
    }

    // Recommended
    if (_isEmpty(data['weather'])) {
      warnings.add(ValidationWarning('weather', 'Weather conditions not recorded'));
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      completeness: _calculateCompleteness(data, _journalFields),
    );
  }

  /// Calculate data completeness percentage
  double _calculateCompleteness(Map<String, dynamic> data, List<String> fields) {
    if (fields.isEmpty) return 1.0;

    int filled = 0;
    for (final field in fields) {
      if (!_isEmpty(data[field])) {
        filled++;
      }
    }
    return filled / fields.length;
  }

  bool _isEmpty(dynamic value) {
    if (value == null) return true;
    if (value is String && value.trim().isEmpty) return true;
    if (value is List && value.isEmpty) return true;
    return false;
  }

  // Field lists for completeness calculation
  static const _findingFields = [
    'name', 'type', 'contextNumber', 'latitude', 'longitude',
    'description', 'material', 'period', 'condition', 'imageUrl'
  ];

  static const _contextFields = [
    'contextNumber', 'type', 'interpretation', 'description',
    'soilType', 'soilColor', 'topElevation', 'bottomElevation',
    'above', 'below'
  ];

  static const _findsRegisterFields = [
    'findNumber', 'category', 'contextNumber', 'description',
    'storageLocation', 'dateFound', 'foundBy', 'conservationStatus'
  ];

  static const _journalFields = [
    'title', 'content', 'type', 'weather', 'workCondition'
  ];
}

/// Result of validation
class ValidationResult {
  final bool isValid;
  final List<ValidationError> errors;
  final List<ValidationWarning> warnings;
  final double completeness; // 0.0 to 1.0

  ValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
    this.completeness = 0.0,
  });

  /// Get completeness as percentage string
  String get completenessPercent => '${(completeness * 100).round()}%';

  /// Get quality rating based on completeness
  DataQuality get quality {
    if (completeness >= 0.9) return DataQuality.excellent;
    if (completeness >= 0.7) return DataQuality.good;
    if (completeness >= 0.5) return DataQuality.fair;
    return DataQuality.incomplete;
  }

  /// Check if there are any issues
  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;

  /// Get total issue count
  int get issueCount => errors.length + warnings.length;
}

/// Validation error (blocks saving)
class ValidationError {
  final String field;
  final String message;

  ValidationError(this.field, this.message);
}

/// Validation warning (allows saving but shows alert)
class ValidationWarning {
  final String field;
  final String message;

  ValidationWarning(this.field, this.message);
}

/// Data quality rating
enum DataQuality {
  excellent('Excellent', Color(0xFF4CAF50), Icons.verified),
  good('Good', Color(0xFF8BC34A), Icons.thumb_up),
  fair('Fair', Color(0xFFFF9800), Icons.warning_amber),
  incomplete('Incomplete', Color(0xFFF44336), Icons.error_outline);

  final String label;
  final Color color;
  final IconData icon;

  const DataQuality(this.label, this.color, this.icon);
}

/// Extension to show validation feedback in UI
extension ValidationResultUI on ValidationResult {
  /// Show validation dialog
  Future<bool> showValidationDialog(BuildContext context) async {
    if (isValid && warnings.isEmpty) return true;

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isValid ? Icons.warning_amber : Icons.error,
              color: isValid ? const Color(0xFFFF9800) : const Color(0xFFF44336),
            ),
            const SizedBox(width: 8),
            Text(
              isValid ? 'Data Quality Notice' : 'Validation Failed',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Completeness indicator
              _buildCompletenessBar(),
              const SizedBox(height: 16),

              // Errors
              if (errors.isNotEmpty) ...[
                const Text(
                  'Errors (must fix):',
                  style: TextStyle(
                    color: Color(0xFFF44336),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...errors.map((e) => _buildIssueItem(e.message, true)),
                const SizedBox(height: 12),
              ],

              // Warnings
              if (warnings.isNotEmpty) ...[
                const Text(
                  'Recommendations:',
                  style: TextStyle(
                    color: Color(0xFFFF9800),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...warnings.map((w) => _buildIssueItem(w.message, false)),
              ],
            ],
          ),
        ),
        actions: [
          if (!isValid)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Fix Issues', style: TextStyle(color: Colors.white70)),
            ),
          if (isValid)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go Back', style: TextStyle(color: Colors.white70)),
            ),
          if (isValid)
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: const Color(0xFF0D3A39),
              ),
              child: const Text('Save Anyway'),
            ),
        ],
      ),
    ) ?? false;
  }

  Widget _buildCompletenessBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Data Completeness',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Row(
              children: [
                Icon(quality.icon, color: quality.color, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$completenessPercent - ${quality.label}',
                  style: TextStyle(color: quality.color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: completeness,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(quality.color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildIssueItem(String message, bool isError) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.close : Icons.info_outline,
            color: isError ? const Color(0xFFF44336) : const Color(0xFFFF9800),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withAlpha(200),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

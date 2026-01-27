/// Finds Register - Museum-standard archaeological artifact cataloging
/// Part of AncientVision professional field documentation system

/// Category of find for sequential numbering
enum FindCategory {
  smallFind('Small Find', 'SF'),
  bulkFind('Bulk Find', 'BF'),
  sample('Sample', 'SA'),
  specialFind('Special Find', 'SP');

  final String label;
  final String prefix;
  const FindCategory(this.label, this.prefix);

  static FindCategory fromPrefix(String prefix) {
    return FindCategory.values.firstWhere(
      (c) => c.prefix == prefix,
      orElse: () => FindCategory.smallFind,
    );
  }
}

/// Conservation status of the find
enum ConservationStatus {
  stable('Stable', 'No immediate treatment needed'),
  atRisk('At Risk', 'Requires monitoring or treatment'),
  treated('Treated', 'Conservation treatment completed'),
  fragile('Fragile', 'Handle with extreme care'),
  deteriorating('Deteriorating', 'Active decay - urgent');

  final String label;
  final String description;
  const ConservationStatus(this.label, this.description);
}

/// Processing status of the find
enum ProcessingStatus {
  inSitu('In Situ', 'Not yet lifted'),
  lifted('Lifted', 'Removed from context'),
  washed('Washed', 'Cleaned and dried'),
  marked('Marked', 'Catalog number applied'),
  photographed('Photographed', 'Photos taken'),
  analyzed('Analyzed', 'Specialist analysis complete'),
  stored('Stored', 'In permanent storage'),
  exported('Exported', 'Sent to museum/lab');

  final String label;
  final String description;
  const ProcessingStatus(this.label, this.description);
}

/// Main Finds Register entry - museum-standard cataloging
class FindsRegisterEntry {
  final String id;
  final String findNumber;          // e.g., "SF001", "BF042"
  final FindCategory category;
  final int sequenceNumber;         // Numeric part for ordering

  // Location & Context
  final String? siteId;
  final String? contextNumber;      // Link to ContextSheet
  final String? trenchId;
  final String? areaId;
  final double? x;                  // Coordinates within trench (meters)
  final double? y;
  final double? z;                  // Depth below datum (meters)
  final double? latitude;           // GPS latitude
  final double? longitude;          // GPS longitude

  // Classification (links to ArtifactClassification)
  final String? artifactTypeId;
  final String? materialId;
  final String? periodId;
  final String? conditionId;

  // Description
  final String? description;
  final String? preliminaryId;      // Initial field identification
  final List<String> photoIds;      // Links to Photo Register
  final String? model3dId;          // Link to 3D reconstruction

  // Measurements (quick entry)
  final double? lengthMm;
  final double? widthMm;
  final double? heightMm;
  final double? weightGrams;

  // Recovery & Storage
  final DateTime dateFound;
  final String? foundBy;
  final String? liftedBy;
  final DateTime? dateLlifted;
  final String? storageLocation;    // Box/bag number
  final String? storageNotes;

  // Conservation
  final ConservationStatus conservationStatus;
  final String? conservationNotes;
  final DateTime? conservationDate;
  final String? conservedBy;

  // Processing
  final ProcessingStatus processingStatus;
  final List<String> processingHistory;  // Log of status changes

  // Metadata
  final DateTime recordedAt;
  final String? recordedBy;
  final DateTime? lastModified;
  final String? modifiedBy;
  final bool isExported;
  final String? exportedTo;
  final DateTime? exportDate;

  // Notes & Tags
  final String? notes;
  final List<String> tags;
  final bool needsReview;
  final bool isFlagged;             // Important/special attention

  FindsRegisterEntry({
    required this.id,
    required this.findNumber,
    required this.category,
    required this.sequenceNumber,
    this.siteId,
    this.contextNumber,
    this.trenchId,
    this.areaId,
    this.x,
    this.y,
    this.z,
    this.latitude,
    this.longitude,
    this.artifactTypeId,
    this.materialId,
    this.periodId,
    this.conditionId,
    this.description,
    this.preliminaryId,
    this.photoIds = const [],
    this.model3dId,
    this.lengthMm,
    this.widthMm,
    this.heightMm,
    this.weightGrams,
    required this.dateFound,
    this.foundBy,
    this.liftedBy,
    this.dateLlifted,
    this.storageLocation,
    this.storageNotes,
    this.conservationStatus = ConservationStatus.stable,
    this.conservationNotes,
    this.conservationDate,
    this.conservedBy,
    this.processingStatus = ProcessingStatus.inSitu,
    this.processingHistory = const [],
    required this.recordedAt,
    this.recordedBy,
    this.lastModified,
    this.modifiedBy,
    this.isExported = false,
    this.exportedTo,
    this.exportDate,
    this.notes,
    this.tags = const [],
    this.needsReview = false,
    this.isFlagged = false,
  });

  /// Create from JSON
  factory FindsRegisterEntry.fromJson(Map<String, dynamic> json) {
    return FindsRegisterEntry(
      id: json['id'] ?? '',
      findNumber: json['findNumber'] ?? '',
      category: FindCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => FindCategory.smallFind,
      ),
      sequenceNumber: json['sequenceNumber'] ?? 0,
      siteId: json['siteId'],
      contextNumber: json['contextNumber'],
      trenchId: json['trenchId'],
      areaId: json['areaId'],
      x: json['x']?.toDouble(),
      y: json['y']?.toDouble(),
      z: json['z']?.toDouble(),
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      artifactTypeId: json['artifactTypeId'],
      materialId: json['materialId'],
      periodId: json['periodId'],
      conditionId: json['conditionId'],
      description: json['description'],
      preliminaryId: json['preliminaryId'],
      photoIds: List<String>.from(json['photoIds'] ?? []),
      model3dId: json['model3dId'],
      lengthMm: json['lengthMm']?.toDouble(),
      widthMm: json['widthMm']?.toDouble(),
      heightMm: json['heightMm']?.toDouble(),
      weightGrams: json['weightGrams']?.toDouble(),
      dateFound: json['dateFound'] != null
          ? DateTime.parse(json['dateFound'])
          : DateTime.now(),
      foundBy: json['foundBy'],
      liftedBy: json['liftedBy'],
      dateLlifted: json['dateLlifted'] != null
          ? DateTime.parse(json['dateLlifted'])
          : null,
      storageLocation: json['storageLocation'],
      storageNotes: json['storageNotes'],
      conservationStatus: ConservationStatus.values.firstWhere(
        (s) => s.name == json['conservationStatus'],
        orElse: () => ConservationStatus.stable,
      ),
      conservationNotes: json['conservationNotes'],
      conservationDate: json['conservationDate'] != null
          ? DateTime.parse(json['conservationDate'])
          : null,
      conservedBy: json['conservedBy'],
      processingStatus: ProcessingStatus.values.firstWhere(
        (s) => s.name == json['processingStatus'],
        orElse: () => ProcessingStatus.inSitu,
      ),
      processingHistory: List<String>.from(json['processingHistory'] ?? []),
      recordedAt: json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'])
          : DateTime.now(),
      recordedBy: json['recordedBy'],
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'])
          : null,
      modifiedBy: json['modifiedBy'],
      isExported: json['isExported'] ?? false,
      exportedTo: json['exportedTo'],
      exportDate: json['exportDate'] != null
          ? DateTime.parse(json['exportDate'])
          : null,
      notes: json['notes'],
      tags: List<String>.from(json['tags'] ?? []),
      needsReview: json['needsReview'] ?? false,
      isFlagged: json['isFlagged'] ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'findNumber': findNumber,
      'category': category.name,
      'sequenceNumber': sequenceNumber,
      'siteId': siteId,
      'contextNumber': contextNumber,
      'trenchId': trenchId,
      'areaId': areaId,
      'x': x,
      'y': y,
      'z': z,
      'latitude': latitude,
      'longitude': longitude,
      'artifactTypeId': artifactTypeId,
      'materialId': materialId,
      'periodId': periodId,
      'conditionId': conditionId,
      'description': description,
      'preliminaryId': preliminaryId,
      'photoIds': photoIds,
      'model3dId': model3dId,
      'lengthMm': lengthMm,
      'widthMm': widthMm,
      'heightMm': heightMm,
      'weightGrams': weightGrams,
      'dateFound': dateFound.toIso8601String(),
      'foundBy': foundBy,
      'liftedBy': liftedBy,
      'dateLlifted': dateLlifted?.toIso8601String(),
      'storageLocation': storageLocation,
      'storageNotes': storageNotes,
      'conservationStatus': conservationStatus.name,
      'conservationNotes': conservationNotes,
      'conservationDate': conservationDate?.toIso8601String(),
      'conservedBy': conservedBy,
      'processingStatus': processingStatus.name,
      'processingHistory': processingHistory,
      'recordedAt': recordedAt.toIso8601String(),
      'recordedBy': recordedBy,
      'lastModified': lastModified?.toIso8601String(),
      'modifiedBy': modifiedBy,
      'isExported': isExported,
      'exportedTo': exportedTo,
      'exportDate': exportDate?.toIso8601String(),
      'notes': notes,
      'tags': tags,
      'needsReview': needsReview,
      'isFlagged': isFlagged,
    };
  }

  /// Create a copy with updated fields
  FindsRegisterEntry copyWith({
    String? id,
    String? findNumber,
    FindCategory? category,
    int? sequenceNumber,
    String? siteId,
    String? contextNumber,
    String? trenchId,
    String? areaId,
    double? x,
    double? y,
    double? z,
    double? latitude,
    double? longitude,
    String? artifactTypeId,
    String? materialId,
    String? periodId,
    String? conditionId,
    String? description,
    String? preliminaryId,
    List<String>? photoIds,
    String? model3dId,
    double? lengthMm,
    double? widthMm,
    double? heightMm,
    double? weightGrams,
    DateTime? dateFound,
    String? foundBy,
    String? liftedBy,
    DateTime? dateLlifted,
    String? storageLocation,
    String? storageNotes,
    ConservationStatus? conservationStatus,
    String? conservationNotes,
    DateTime? conservationDate,
    String? conservedBy,
    ProcessingStatus? processingStatus,
    List<String>? processingHistory,
    DateTime? recordedAt,
    String? recordedBy,
    DateTime? lastModified,
    String? modifiedBy,
    bool? isExported,
    String? exportedTo,
    DateTime? exportDate,
    String? notes,
    List<String>? tags,
    bool? needsReview,
    bool? isFlagged,
  }) {
    return FindsRegisterEntry(
      id: id ?? this.id,
      findNumber: findNumber ?? this.findNumber,
      category: category ?? this.category,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      siteId: siteId ?? this.siteId,
      contextNumber: contextNumber ?? this.contextNumber,
      trenchId: trenchId ?? this.trenchId,
      areaId: areaId ?? this.areaId,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      artifactTypeId: artifactTypeId ?? this.artifactTypeId,
      materialId: materialId ?? this.materialId,
      periodId: periodId ?? this.periodId,
      conditionId: conditionId ?? this.conditionId,
      description: description ?? this.description,
      preliminaryId: preliminaryId ?? this.preliminaryId,
      photoIds: photoIds ?? this.photoIds,
      model3dId: model3dId ?? this.model3dId,
      lengthMm: lengthMm ?? this.lengthMm,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      weightGrams: weightGrams ?? this.weightGrams,
      dateFound: dateFound ?? this.dateFound,
      foundBy: foundBy ?? this.foundBy,
      liftedBy: liftedBy ?? this.liftedBy,
      dateLlifted: dateLlifted ?? this.dateLlifted,
      storageLocation: storageLocation ?? this.storageLocation,
      storageNotes: storageNotes ?? this.storageNotes,
      conservationStatus: conservationStatus ?? this.conservationStatus,
      conservationNotes: conservationNotes ?? this.conservationNotes,
      conservationDate: conservationDate ?? this.conservationDate,
      conservedBy: conservedBy ?? this.conservedBy,
      processingStatus: processingStatus ?? this.processingStatus,
      processingHistory: processingHistory ?? this.processingHistory,
      recordedAt: recordedAt ?? this.recordedAt,
      recordedBy: recordedBy ?? this.recordedBy,
      lastModified: lastModified ?? this.lastModified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      isExported: isExported ?? this.isExported,
      exportedTo: exportedTo ?? this.exportedTo,
      exportDate: exportDate ?? this.exportDate,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      needsReview: needsReview ?? this.needsReview,
      isFlagged: isFlagged ?? this.isFlagged,
    );
  }

  /// Get formatted dimensions string
  String get dimensionsString {
    final parts = <String>[];
    if (lengthMm != null) parts.add('L: ${lengthMm!.toStringAsFixed(1)}mm');
    if (widthMm != null) parts.add('W: ${widthMm!.toStringAsFixed(1)}mm');
    if (heightMm != null) parts.add('H: ${heightMm!.toStringAsFixed(1)}mm');
    if (weightGrams != null) parts.add('${weightGrams!.toStringAsFixed(1)}g');
    return parts.isEmpty ? 'No measurements' : parts.join(' × ');
  }

  /// Get formatted coordinates string
  String get coordinatesString {
    if (x == null && y == null && z == null) return 'No coordinates';
    final parts = <String>[];
    if (x != null) parts.add('X: ${x!.toStringAsFixed(2)}m');
    if (y != null) parts.add('Y: ${y!.toStringAsFixed(2)}m');
    if (z != null) parts.add('Z: ${z!.toStringAsFixed(2)}m');
    return parts.join(', ');
  }

  /// Get date found as formatted string
  String get dateFoundString {
    return '${dateFound.day}/${dateFound.month}/${dateFound.year}';
  }

  /// Export to CSV row
  List<String> toCsvRow() {
    return [
      findNumber,
      category.label,
      contextNumber ?? '',
      trenchId ?? '',
      description ?? '',
      artifactTypeId ?? '',
      materialId ?? '',
      periodId ?? '',
      x?.toString() ?? '',
      y?.toString() ?? '',
      z?.toString() ?? '',
      lengthMm?.toString() ?? '',
      widthMm?.toString() ?? '',
      heightMm?.toString() ?? '',
      weightGrams?.toString() ?? '',
      dateFoundString,
      foundBy ?? '',
      storageLocation ?? '',
      conservationStatus.label,
      processingStatus.label,
      notes ?? '',
    ];
  }

  /// CSV header row
  static List<String> get csvHeaders => [
    'Find Number',
    'Category',
    'Context',
    'Trench',
    'Description',
    'Type',
    'Material',
    'Period',
    'X (m)',
    'Y (m)',
    'Z (m)',
    'Length (mm)',
    'Width (mm)',
    'Height (mm)',
    'Weight (g)',
    'Date Found',
    'Found By',
    'Storage Location',
    'Conservation Status',
    'Processing Status',
    'Notes',
  ];
}

/// Service for managing finds register
class FindsRegisterService {
  static final FindsRegisterService _instance = FindsRegisterService._internal();
  factory FindsRegisterService() => _instance;
  FindsRegisterService._internal();

  final List<FindsRegisterEntry> _entries = [];
  final Map<FindCategory, int> _sequenceCounters = {
    for (var cat in FindCategory.values) cat: 0
  };

  /// Initialize service and load saved data
  Future<void> initialize() async {
    await _loadFromStorage();
  }

  /// Get all entries
  List<FindsRegisterEntry> get entries => List.unmodifiable(_entries);

  /// Get entries by category
  List<FindsRegisterEntry> getByCategory(FindCategory category) {
    return _entries.where((e) => e.category == category).toList();
  }

  /// Get entries by context
  List<FindsRegisterEntry> getByContext(String contextNumber) {
    return _entries.where((e) => e.contextNumber == contextNumber).toList();
  }

  /// Get next find number for category
  String getNextFindNumber(FindCategory category) {
    final nextSeq = (_sequenceCounters[category] ?? 0) + 1;
    return '${category.prefix}${nextSeq.toString().padLeft(3, '0')}';
  }

  /// Add new entry
  Future<FindsRegisterEntry> addEntry(FindsRegisterEntry entry) async {
    // Update sequence counter
    _sequenceCounters[entry.category] = entry.sequenceNumber;
    _entries.add(entry);
    await _saveToStorage();
    return entry;
  }

  /// Update existing entry
  Future<void> updateEntry(FindsRegisterEntry entry) async {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      _entries[index] = entry;
      await _saveToStorage();
    }
  }

  /// Delete entry
  Future<void> deleteEntry(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _saveToStorage();
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'total': _entries.length,
      'byCategory': {
        for (var cat in FindCategory.values)
          cat.label: _entries.where((e) => e.category == cat).length
      },
      'byStatus': {
        for (var status in ProcessingStatus.values)
          status.label: _entries.where((e) => e.processingStatus == status).length
      },
      'needsReview': _entries.where((e) => e.needsReview).length,
      'flagged': _entries.where((e) => e.isFlagged).length,
    };
  }

  /// Export all entries to CSV string
  String exportToCsv() {
    final buffer = StringBuffer();
    buffer.writeln(FindsRegisterEntry.csvHeaders.join(','));
    for (final entry in _entries) {
      buffer.writeln(entry.toCsvRow().map((cell) => '"$cell"').join(','));
    }
    return buffer.toString();
  }

  /// Save to local storage
  Future<void> _saveToStorage() async {
    // Implementation would save to SharedPreferences
    // final prefs = await SharedPreferences.getInstance();
    // final json = _entries.map((e) => e.toJson()).toList();
    // await prefs.setString('finds_register', jsonEncode(json));
  }

  /// Load from local storage
  Future<void> _loadFromStorage() async {
    // Implementation would load from SharedPreferences
    // final prefs = await SharedPreferences.getInstance();
    // final jsonStr = prefs.getString('finds_register');
    // if (jsonStr != null) {
    //   final json = jsonDecode(jsonStr) as List;
    //   _entries.addAll(json.map((j) => FindsRegisterEntry.fromJson(j)));
    // }
  }
}

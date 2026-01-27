/// Photo Register - Professional archaeological photo documentation
/// Part of AncientVision field documentation system

/// Photo subject type
enum PhotoSubject {
  context('Context', 'Stratigraphic layer or feature'),
  find('Find', 'Individual artifact'),
  section('Section', 'Vertical profile'),
  plan('Plan', 'Overhead/plan view'),
  workingShot('Working Shot', 'Work in progress'),
  overview('Overview', 'General site view'),
  detail('Detail', 'Close-up detail'),
  scale('With Scale', 'Photo with scale bar');

  final String label;
  final String description;
  const PhotoSubject(this.label, this.description);
}

/// Camera direction
enum PhotoDirection {
  n('N', 'North'),
  ne('NE', 'North-East'),
  e('E', 'East'),
  se('SE', 'South-East'),
  s('S', 'South'),
  sw('SW', 'South-West'),
  w('W', 'West'),
  nw('NW', 'North-West'),
  vertical('V', 'Vertical/Overhead'),
  oblique('OBL', 'Oblique angle');

  final String code;
  final String label;
  const PhotoDirection(this.code, this.label);
}

/// Photo Register Entry
class PhotoEntry {
  final String id;
  final String photoNumber;       // P001, P002, etc.
  final String filePath;
  final DateTime dateTaken;
  final String? takenBy;

  // Links
  final String? contextId;
  final String? findId;
  final String? siteId;
  final String? trenchId;

  // Classification
  final PhotoSubject subject;
  final PhotoDirection? direction;
  final String? description;
  final List<String> tags;

  // Technical
  final double? scaleMm;          // Scale bar measurement if present
  final double? latitude;
  final double? longitude;
  final String? cameraModel;

  // Metadata
  final DateTime recordedAt;
  final String? recordedBy;
  final bool isProcessed;         // Has been reviewed/processed
  final bool needsReview;
  final String? notes;

  PhotoEntry({
    required this.id,
    required this.photoNumber,
    required this.filePath,
    required this.dateTaken,
    this.takenBy,
    this.contextId,
    this.findId,
    this.siteId,
    this.trenchId,
    this.subject = PhotoSubject.workingShot,
    this.direction,
    this.description,
    this.tags = const [],
    this.scaleMm,
    this.latitude,
    this.longitude,
    this.cameraModel,
    DateTime? recordedAt,
    this.recordedBy,
    this.isProcessed = false,
    this.needsReview = true,
    this.notes,
  }) : recordedAt = recordedAt ?? DateTime.now();

  factory PhotoEntry.fromJson(Map<String, dynamic> json) {
    return PhotoEntry(
      id: json['id'] ?? '',
      photoNumber: json['photoNumber'] ?? '',
      filePath: json['filePath'] ?? '',
      dateTaken: json['dateTaken'] != null
          ? DateTime.parse(json['dateTaken'])
          : DateTime.now(),
      takenBy: json['takenBy'],
      contextId: json['contextId'],
      findId: json['findId'],
      siteId: json['siteId'],
      trenchId: json['trenchId'],
      subject: PhotoSubject.values.firstWhere(
        (s) => s.name == json['subject'],
        orElse: () => PhotoSubject.workingShot,
      ),
      direction: json['direction'] != null
          ? PhotoDirection.values.firstWhere(
              (d) => d.name == json['direction'],
              orElse: () => PhotoDirection.n,
            )
          : null,
      description: json['description'],
      tags: List<String>.from(json['tags'] ?? []),
      scaleMm: json['scaleMm']?.toDouble(),
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      cameraModel: json['cameraModel'],
      recordedAt: json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'])
          : null,
      recordedBy: json['recordedBy'],
      isProcessed: json['isProcessed'] ?? false,
      needsReview: json['needsReview'] ?? true,
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'photoNumber': photoNumber,
      'filePath': filePath,
      'dateTaken': dateTaken.toIso8601String(),
      'takenBy': takenBy,
      'contextId': contextId,
      'findId': findId,
      'siteId': siteId,
      'trenchId': trenchId,
      'subject': subject.name,
      'direction': direction?.name,
      'description': description,
      'tags': tags,
      'scaleMm': scaleMm,
      'latitude': latitude,
      'longitude': longitude,
      'cameraModel': cameraModel,
      'recordedAt': recordedAt.toIso8601String(),
      'recordedBy': recordedBy,
      'isProcessed': isProcessed,
      'needsReview': needsReview,
      'notes': notes,
    };
  }

  PhotoEntry copyWith({
    String? id,
    String? photoNumber,
    String? filePath,
    DateTime? dateTaken,
    String? takenBy,
    String? contextId,
    String? findId,
    String? siteId,
    String? trenchId,
    PhotoSubject? subject,
    PhotoDirection? direction,
    String? description,
    List<String>? tags,
    double? scaleMm,
    double? latitude,
    double? longitude,
    String? cameraModel,
    DateTime? recordedAt,
    String? recordedBy,
    bool? isProcessed,
    bool? needsReview,
    String? notes,
  }) {
    return PhotoEntry(
      id: id ?? this.id,
      photoNumber: photoNumber ?? this.photoNumber,
      filePath: filePath ?? this.filePath,
      dateTaken: dateTaken ?? this.dateTaken,
      takenBy: takenBy ?? this.takenBy,
      contextId: contextId ?? this.contextId,
      findId: findId ?? this.findId,
      siteId: siteId ?? this.siteId,
      trenchId: trenchId ?? this.trenchId,
      subject: subject ?? this.subject,
      direction: direction ?? this.direction,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      scaleMm: scaleMm ?? this.scaleMm,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      cameraModel: cameraModel ?? this.cameraModel,
      recordedAt: recordedAt ?? this.recordedAt,
      recordedBy: recordedBy ?? this.recordedBy,
      isProcessed: isProcessed ?? this.isProcessed,
      needsReview: needsReview ?? this.needsReview,
      notes: notes ?? this.notes,
    );
  }

  /// Get formatted date string
  String get dateString {
    return '${dateTaken.day}/${dateTaken.month}/${dateTaken.year}';
  }

  /// Get link summary
  String get linkSummary {
    final links = <String>[];
    if (contextId != null) links.add('Ctx $contextId');
    if (findId != null) links.add('Find $findId');
    return links.isEmpty ? 'No links' : links.join(', ');
  }

  /// Export to CSV row
  List<String> toCsvRow() {
    return [
      photoNumber,
      dateString,
      subject.label,
      direction?.code ?? '',
      contextId ?? '',
      findId ?? '',
      description ?? '',
      scaleMm?.toString() ?? '',
      latitude?.toString() ?? '',
      longitude?.toString() ?? '',
      takenBy ?? '',
      notes ?? '',
    ];
  }

  /// CSV header row
  static List<String> get csvHeaders => [
    'Photo Number',
    'Date',
    'Subject',
    'Direction',
    'Context',
    'Find',
    'Description',
    'Scale (mm)',
    'Latitude',
    'Longitude',
    'Taken By',
    'Notes',
  ];
}

/// Service for managing photo register
class PhotoRegisterService {
  static final PhotoRegisterService _instance = PhotoRegisterService._internal();
  factory PhotoRegisterService() => _instance;
  PhotoRegisterService._internal();

  final List<PhotoEntry> _entries = [];
  int _nextSequence = 1;

  /// Initialize service
  Future<void> initialize() async {
    await _loadFromStorage();
  }

  /// Get all entries
  List<PhotoEntry> get entries => List.unmodifiable(_entries);

  /// Get entries by context
  List<PhotoEntry> getByContext(String contextId) {
    return _entries.where((e) => e.contextId == contextId).toList();
  }

  /// Get entries by find
  List<PhotoEntry> getByFind(String findId) {
    return _entries.where((e) => e.findId == findId).toList();
  }

  /// Get entries by subject
  List<PhotoEntry> getBySubject(PhotoSubject subject) {
    return _entries.where((e) => e.subject == subject).toList();
  }

  /// Get entries by date
  List<PhotoEntry> getByDate(DateTime date) {
    return _entries.where((e) =>
      e.dateTaken.year == date.year &&
      e.dateTaken.month == date.month &&
      e.dateTaken.day == date.day
    ).toList();
  }

  /// Get next photo number
  String getNextPhotoNumber() {
    return 'P${_nextSequence.toString().padLeft(3, '0')}';
  }

  /// Add new entry
  Future<PhotoEntry> addEntry(PhotoEntry entry) async {
    _nextSequence++;
    _entries.add(entry);
    await _saveToStorage();
    return entry;
  }

  /// Update existing entry
  Future<void> updateEntry(PhotoEntry entry) async {
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
      'bySubject': {
        for (var subject in PhotoSubject.values)
          subject.label: _entries.where((e) => e.subject == subject).length
      },
      'needsReview': _entries.where((e) => e.needsReview).length,
      'withGps': _entries.where((e) => e.latitude != null).length,
      'withScale': _entries.where((e) => e.scaleMm != null).length,
    };
  }

  /// Export all entries to CSV string
  String exportToCsv() {
    final buffer = StringBuffer();
    buffer.writeln(PhotoEntry.csvHeaders.join(','));
    for (final entry in _entries) {
      buffer.writeln(entry.toCsvRow().map((cell) => '"$cell"').join(','));
    }
    return buffer.toString();
  }

  /// Save to local storage
  Future<void> _saveToStorage() async {
    // Implementation would save to SharedPreferences
  }

  /// Load from local storage
  Future<void> _loadFromStorage() async {
    // Implementation would load from SharedPreferences
  }
}

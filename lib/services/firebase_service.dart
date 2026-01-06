import 'package:cloud_firestore/cloud_firestore.dart';

class Finding {
  final String id;
  final String name;
  final String type;
  final String site;
  final String date;
  final String description;
  final double latitude;
  final double longitude;
  final String? imageUrl;

  Finding({
    required this.id,
    required this.name,
    required this.type,
    required this.site,
    required this.date,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
  });

  factory Finding.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'type': type,
      'site': site,
      'date': date,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference _findingsCollection =
      _firestore.collection('findings');

  // Get all findings
  static Stream<List<Finding>> getFindingsStream() {
    return _findingsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Finding.fromFirestore(doc)).toList());
  }

  // Get next ID
  static Future<String> getNextId() async {
    final snapshot = await _findingsCollection
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return 'A-001';
    }

    final lastId = snapshot.docs.first.id;
    // Parse the number from ID like "A-003"
    final match = RegExp(r'A-(\d+)').firstMatch(lastId);
    if (match != null) {
      final num = int.parse(match.group(1)!) + 1;
      return 'A-${num.toString().padLeft(3, '0')}';
    }
    return 'A-001';
  }

  // Add a new finding
  static Future<void> addFinding(Finding finding) async {
    await _findingsCollection.doc(finding.id).set(finding.toFirestore());
  }

  // Update a finding
  static Future<void> updateFinding(Finding finding) async {
    await _findingsCollection.doc(finding.id).update(finding.toFirestore());
  }

  // Delete a finding
  static Future<void> deleteFinding(String id) async {
    await _findingsCollection.doc(id).delete();
  }

  // Get findings count
  static Future<int> getFindingsCount() async {
    final snapshot = await _findingsCollection.count().get();
    return snapshot.count ?? 0;
  }

  // Get today's findings count
  static Future<int> getTodayFindingsCount() async {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final snapshot = await _findingsCollection
        .where('date', isEqualTo: today)
        .count()
        .get();
    return snapshot.count ?? 0;
  }
}

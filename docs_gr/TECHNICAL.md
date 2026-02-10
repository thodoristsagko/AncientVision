# Τεχνική Αρχιτεκτονική AncientVision

Αναλυτική παρουσίαση του σχεδιασμού συστήματος, αλγορίθμων και λεπτομερειών υλοποίησης.

---

## Πίνακας Περιεχομένων

1. [Αρχιτεκτονική Συστήματος](#αρχιτεκτονική-συστήματος)
2. [Αλγόριθμοι 3D Ανακατασκευής](#αλγόριθμοι-3d-ανακατασκευής)
3. [Επίπεδο Υπηρεσιών](#επίπεδο-υπηρεσιών)
4. [Μοντέλα Δεδομένων](#μοντέλα-δεδομένων)
5. [Ενσωμάτωση Firebase](#ενσωμάτωση-firebase)

---

## Αρχιτεκτονική Συστήματος

### Διάγραμμα Επιπέδων

```
┌─────────────────────────────────────────────────────────────┐
│                     ΕΠΙΠΕΔΟ ΠΑΡΟΥΣΙΑΣΗΣ                       │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │Dashboard│ │Ευρήματα │ │Εργαλεία │ │Ασφάλεια │           │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘           │
│       │           │           │           │                  │
│  ┌────┴───────────┴───────────┴───────────┴────┐           │
│  │              Βιβλιοθήκη Widgets               │           │
│  │  PointCloudPainter | Model3DViewer           │           │
│  └──────────────────────┬───────────────────────┘           │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                  ΕΠΙΠΕΔΟ ΕΠΙΧΕΙΡΗΣΙΑΚΗΣ ΛΟΓΙΚΗΣ              │
│  ┌──────────────────────┴───────────────────────┐           │
│  │                 Υπηρεσίες                      │           │
│  │  AuthService | FirebaseService | ImageService │           │
│  │  ReconstructionService | LocalStorageService  │           │
│  │  CloudPhotogrammetryService | RobustSfM       │           │
│  └──────────────────────┬───────────────────────┘           │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                     ΕΠΙΠΕΔΟ ΔΕΔΟΜΕΝΩΝ                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │ Firebase │  │  ImgBB   │  │  Τοπική  │                   │
│  │Firestore │  │   API    │  │Αποθήκευση│                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                  ΕΠΙΠΕΔΟ ΥΛΙΚΟΥ                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │  Κάμερα  │  │   BLE    │  │   GPS    │                   │
│  │          │  │ M5StickC │  │          │                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

### Δομή Αρχείων

```
lib/
├── main.dart                    # ~600 γραμμές - Κύρια εφαρμογή (από 13,472)
│   ├── MyApp                    # Root widget
│   ├── AuthScreen               # Σύνδεση/εγγραφή
│   ├── MainScreen               # Scaffold πλοήγησης
│   └── Οθόνες μεταφέρθηκαν σε ξεχωριστά αρχεία
│
├── screens/                     # ΝΕΟ v4.0 - Διαχωρισμός οθονών
│   ├── dashboard_screen.dart    # Στατιστικά & επισκόπηση
│   ├── findings_screen.dart     # Γκαλερί & χάρτης
│   ├── tools_screen.dart        # Κόμβος λειτουργιών
│   ├── safety_screen.dart       # Παρακολούθηση αισθητήρων
│   ├── manual_entry_screen.dart # Φόρμα τεκμηρίωσης
│   ├── photogrammetry_screen.dart # 3D λήψη
│   └── export_screens.dart      # Εξαγωγές PDF & δεδομένων
│
├── services/                    # 25+ υπηρεσίες (ήταν 7)
│   ├── auth_service.dart        # Firebase Auth wrapper + Ρόλοι
│   ├── firebase_service.dart    # Λειτουργίες Firestore
│   ├── reconstruction_service.dart  # 3D pipeline
│   ├── sfm_robust.dart          # Αλγόριθμοι SfM
│   ├── image_service.dart       # Συμπίεση & ανάλυση
│   ├── cloud_photogrammetry_service.dart # OpenScan Cloud
│   ├── local_storage_service.dart   # Υποστήριξη εκτός σύνδεσης
│   ├── vibration_anomaly_service.dart  # ΝΕΟ v4.0 - VAE ML μοντέλο
│   ├── wavelet_service.dart     # ΝΕΟ v4.0 - Haar DWT (23 tests)
│   ├── vibration_metrics_service.dart  # ΝΕΟ v4.0 - Arias/CAV (40 tests)
│   ├── exif_service.dart        # ΝΕΟ v4.0 - Μεταδεδομένα εικόνας (28 tests)
│   ├── reconstruction_quality_service.dart  # ΝΕΟ v4.0 - Βαθμολογία ποιότητας
│   ├── bundle_adjustment_service.dart  # ΝΕΟ v4.0 - Βελτιστοποίηση BA (15 tests)
│   └── metadata_export_service.dart  # ΝΕΟ v4.0 - Μορφές εξαγωγής (22 tests)
│
├── models/
│   ├── point_cloud.dart         # PointCloud, Point3D
│   ├── mesh_model.dart          # MeshModel, MeshVertex, MeshFace
│   └── reconstruction_result.dart   # Αποτελέσματα επεξεργασίας
│
├── widgets/
│   ├── point_cloud_painter.dart # 3D απόδοση
│   ├── model_3d_viewer.dart     # Διαδραστικός προβολέας
│   └── spectrogram_widget.dart  # ΝΕΟ v4.0 - Οπτικοποίηση συχνοτήτων (20 tests)
│
└── utils/
    ├── quality_analyzer.dart    # Μετρήσεις ποιότητας εικόνας
    └── validators.dart          # Επικύρωση δεδομένων
```

**Βελτιώσεις Αρχιτεκτονικής v4.0:**
- Main.dart μειώθηκε από 13,472 → ~600 γραμμές (μείωση 96%)
- 25+ αρθρωτές υπηρεσίες με σαφείς ευθύνες
- 181 unit tests (ήταν 31 σε v3.0) - αύξηση 484%
- Υπηρεσίες έτοιμες για μελλοντική ενσωμάτωση (wavelet, EXIF, bundle adjustment)

---

## Αλγόριθμοι 3D Ανακατασκευής

### Επισκόπηση Pipeline

```
Εικόνες → Εξαγωγή Χαρακτηριστικών → Αντιστοίχιση → Essential Matrix
    → RANSAC → Ανάκτηση Θέσης → Τριγωνοποίηση → Point Cloud
```

### Εξαγωγή Χαρακτηριστικών Harris Corner

Ο αλγόριθμος Harris corner ανιχνεύει γωνίες μετρώντας τη διακύμανση έντασης σε πολλαπλές κατευθύνσεις.

```dart
// Υπολογισμός πίνακα δομής Harris
Ix2 = (∂I/∂x)²
Iy2 = (∂I/∂y)²
IxIy = (∂I/∂x)(∂I/∂y)

// Απόκριση Harris
R = det(M) - k * trace(M)²
// όπου M = [[Ix2, IxIy], [IxIy, Iy2]]
```

### Αντιστοίχιση Χαρακτηριστικών

Αντιστοίχιση με βάση συσχέτιση πάνω σε παράθυρα patch.

| Παράμετρος | Τιμή | Σκοπός |
|------------|------|--------|
| Μέγεθος Patch | 16x16 | Περιοχή αντιστοίχισης |
| Κατώφλι Συσχέτισης | 0.75 | Ελάχιστη ομοιότητα |

### Αλγόριθμος 8 Σημείων - Essential Matrix

```dart
// Περιορισμός Epipolar
x₂ᵀ E x₁ = 0

// Κατασκευή πίνακα εξισώσεων A
A = [x₁'x₂', x₁'y₂', x₁', y₁'x₂', y₁'y₂', y₁', x₂', y₂', 1]

// Επίλυση για E χρησιμοποιώντας SVD
E = reshape(nullspace(A))
```

### RANSAC Outlier Rejection

```dart
for iteration in range(1000):
    // 1. Τυχαία επιλογή 8 αντιστοιχιών
    sample = random_sample(matches, 8)

    // 2. Εκτίμηση Essential Matrix
    E = compute_essential_matrix(sample)

    // 3. Μέτρηση inliers (σφάλμα < κατώφλι)
    inliers = count_inliers(E, all_matches, threshold=0.02)

    // 4. Ενημέρωση καλύτερου μοντέλου
    if inliers > best_inliers:
        best_E = E
        best_inliers = inliers
```

| Παράμετρος | Τιμή |
|------------|------|
| Επαναλήψεις | 1000 |
| Κατώφλι | 0.02 |
| Ελάχιστο Ποσοστό Inlier | 15% |

### Τριγωνοποίηση

```dart
// Δεδομένων πινάκων προβολής P1, P2 και σημείων x1, x2
// Επίλυση για 3D σημείο X

A = [
    x1 * P1[2] - P1[0],
    y1 * P1[2] - P1[1],
    x2 * P2[2] - P2[0],
    y2 * P2[2] - P2[1]
]

// SVD επίλυση
X = nullspace(A)
```

---

## Επίπεδο Υπηρεσιών

### AuthService

Διαχειρίζεται ταυτοποίηση χρηστών και ρόλους.

```dart
class AuthService {
  // Σταθερές ρόλων
  static const String roleAdmin = 'admin';
  static const String roleArcheologist = 'archeologist';
  static const String roleViewer = 'viewer';

  // Μέθοδοι ταυτοποίησης
  static Future<UserCredential> registerWithEmail(...);
  static Future<UserCredential?> loginWithEmail(...);
  static Future<UserCredential?> signInWithGoogle();

  // Διαχείριση ρόλων
  static Future<String> getCurrentUserRole();
  static Future<bool> isCurrentUserAdmin();
  static Future<bool> updateUserRole(String uid, String role);
}
```

### ReconstructionService

Ενορχηστρώνει το 3D pipeline.

```dart
class ReconstructionService {
  // Κύρια μέθοδος επεξεργασίας
  Future<ReconstructionResult> processImages(List<File> images);

  // Επιμέρους βήματα
  List<List<Point>> _extractFeatures(img.Image image);
  List<FeatureMatch> _matchFeatures(features1, features2);
  Matrix4? _estimateRelativePose(matches);
  List<Point3D> _triangulatePoints(matches, P1, P2);
}
```

### CloudPhotogrammetryService

Ενσωμάτωση με OpenScan Cloud API.

```dart
class CloudPhotogrammetryService {
  static const String _baseUrl = 'https://openscan.eu/public/api/photogrammetry';

  Future<String?> uploadAndProcess(List<File> images);
  Future<Map<String, dynamic>> checkServerStatus();
  Future<String?> downloadResult(String taskId);
}
```

---

## Μοντέλα Δεδομένων

### Finding (Εύρημα)

```dart
class _Finding {
  final String id;
  final String name;
  final String type;
  final String site;
  final String date;
  final String description;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final List<String> photoGallery;
  final String? model3dUrl;

  // Αρχαιολογικά πεδία
  final String? findNumber;
  final String? excavationUnit;
  final String? stratigraphicLayer;
  final double? depthBelowSurface;
  final double? lengthMm;
  final double? widthMm;
  final double? heightMm;
  final double? weightGrams;
  final String? material;
  final String? condition;
  final String? period;
}
```

### PointCloud

```dart
class PointCloud {
  final List<Point3D> points;
  final int? width;
  final int? height;

  String toPLY();  // Εξαγωγή
  factory PointCloud.fromPLY(String content);  // Εισαγωγή
}

class Point3D {
  final double x, y, z;
  final int r, g, b;
}
```

### ReconstructionResult

```dart
class ReconstructionResult {
  final PointCloud? pointCloud;
  final MeshModel? mesh;
  final int featureCount;
  final int matchCount;
  final double reprojectionError;
  final double coverage;
  final Duration processingTime;
  final String? errorMessage;

  bool get isSuccess;
  double get qualityScore;
}
```

---

## Ενσωμάτωση Firebase

### Firestore Schema

```
firestore/
├── users/
│   └── {uid}/
│       ├── email: string
│       ├── fullName: string
│       ├── role: "admin" | "archeologist" | "viewer"
│       ├── status: "active" | "suspended"
│       ├── createdAt: timestamp
│       └── lastActivity: timestamp
│
├── findings/
│   └── {findingId}/
│       ├── name: string
│       ├── type: string
│       ├── site: string
│       ├── date: string
│       ├── description: string
│       ├── latitude: number
│       ├── longitude: number
│       ├── imageUrl: string
│       ├── photoGallery: string[]
│       ├── model3dUrl: string
│       ├── createdAt: timestamp
│       └── userId: string
│
└── account_logs/
    └── {logId}/
        ├── action: string
        ├── userId: string
        ├── email: string
        ├── details: string
        └── timestamp: timestamp
```

### Κανόνες Ασφαλείας

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Χρήστες: ανάγνωση δικών τους, admins διαβάζουν όλα
    match /users/{userId} {
      allow read: if request.auth.uid == userId ||
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
      allow write: if request.auth.uid == userId ||
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }

    // Ευρήματα: ανάγνωση από όλους, εγγραφή από archeologist+
    match /findings/{findingId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role in ['admin', 'archeologist'];
    }
  }
}
```

---

## Εξαρτήσεις

### Κύρια Πακέτα Flutter

| Πακέτο | Έκδοση | Σκοπός |
|--------|--------|--------|
| firebase_core | ^2.32.0 | Firebase αρχικοποίηση |
| firebase_auth | ^4.16.0 | Ταυτοποίηση |
| cloud_firestore | ^4.17.5 | Βάση δεδομένων |
| firebase_storage | ^11.6.5 | Αποθήκευση αρχείων |
| google_sign_in | ^6.3.0 | OAuth |
| camera | ^0.10.6 | Πρόσβαση κάμερας |
| image | ^4.3.0 | Επεξεργασία εικόνας |
| flutter_map | ^6.2.1 | Χάρτες |
| geolocator | ^10.1.1 | GPS |
| flutter_blue_plus | ^1.36.8 | Bluetooth BLE |
| shared_preferences | ^2.5.3 | Τοπική αποθήκευση |
| http | ^1.1.0 | HTTP αιτήματα |

---

## Στατιστικά Έργου

| Μετρική | Τιμή |
|---------|------|
| Γραμμές Κώδικα | ~12,000 |
| Αρχεία Dart | 17 |
| Υπηρεσίες | 7 |
| Μοντέλα | 3 |
| Widgets | 2 |
| Υποστηριζόμενες Πλατφόρμες | Android |

---

*Τεκμηρίωση για FLL 2025-2026 Innovation Project*

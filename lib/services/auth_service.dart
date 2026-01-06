import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  static User? get currentUser => _auth.currentUser;

  // Auth state stream
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Log account activity to Firestore
  static Future<void> _logActivity({
    required String action,
    String? userId,
    String? email,
    String? details,
  }) async {
    try {
      await _firestore.collection('account_logs').add({
        'action': action,
        'userId': userId,
        'email': email,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('LOG SUCCESS: $action for $email');
    } catch (e) {
      print('LOG FAILED: $e');
    }
  }

  // Email/Password Registration
  static Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name
    await credential.user?.updateDisplayName(fullName);

    // Store user profile in Firestore
    await _createUserProfile(
      uid: credential.user!.uid,
      email: email,
      fullName: fullName,
    );

    // Log registration
    await _logActivity(
      action: 'register',
      userId: credential.user!.uid,
      email: email,
      details: 'New account registered: $fullName',
    );

    return credential;
  }

  // Email/Password Login
  static Future<UserCredential?> loginWithEmail({
    required String email,
    required String password,
  }) async {
    UserCredential? credential;

    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      // Check if user is actually logged in despite the error (known firebase_auth bug)
      if (_auth.currentUser != null) {
        print('Login succeeded despite error: $e');
      } else {
        rethrow; // Re-throw if login actually failed
      }
    }

    // If user is logged in, update activity and log
    final user = _auth.currentUser;
    if (user != null) {
      await _updateLastActivity(user.uid);
      await _logActivity(
        action: 'login',
        userId: user.uid,
        email: email,
        details: 'Email/password login',
      );
    }

    return credential;
  }

  // Google Sign-In
  static Future<UserCredential?> signInWithGoogle() async {
    // Trigger the authentication flow
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    if (googleUser == null) {
      return null; // User cancelled
    }

    // Obtain the auth details from the request
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    // Create a new credential
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // Sign in to Firebase
    final userCredential = await _auth.signInWithCredential(credential);

    // Check if this is a new user and create profile
    if (userCredential.additionalUserInfo?.isNewUser ?? false) {
      await _createUserProfile(
        uid: userCredential.user!.uid,
        email: userCredential.user!.email ?? '',
        fullName: userCredential.user!.displayName ?? '',
        photoUrl: userCredential.user!.photoURL,
        provider: 'google',
      );

      // Log new Google registration
      await _logActivity(
        action: 'register',
        userId: userCredential.user!.uid,
        email: userCredential.user!.email,
        details: 'New account via Google Sign-In',
      );
    } else {
      // Update last activity and login count for existing user
      await _updateLastActivity(userCredential.user!.uid);

      // Log Google login
      await _logActivity(
        action: 'login',
        userId: userCredential.user?.uid,
        email: userCredential.user?.email,
        details: 'Google Sign-In',
      );
    }

    return userCredential;
  }

  // Create user profile in Firestore
  static Future<void> _createUserProfile({
    required String uid,
    required String email,
    required String fullName,
    String? photoUrl,
    String provider = 'email',
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'fullName': fullName,
      'photoUrl': photoUrl,
      'provider': provider, // 'email' or 'google'
      'role': 'viewer', // Default role, admin can change later
      'status': 'active', // active, suspended, deleted
      'findingsCount': 0,
      'loginCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActivity': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  // Update last activity and ensure all profile fields exist
  static Future<void> _updateLastActivity(String uid) async {
    final user = _auth.currentUser;

    try {
      // First, check if document exists and has all fields
      final doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        // Build update map with activity fields
        Map<String, dynamic> updateData = {
          'lastActivity': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
          'loginCount': FieldValue.increment(1),
        };

        // Add missing fields for existing users (migration)
        if (!data.containsKey('uid')) {
          updateData['uid'] = uid;
        }
        if (!data.containsKey('email') && user?.email != null) {
          updateData['email'] = user!.email;
        }
        if (!data.containsKey('fullName') && user?.displayName != null) {
          updateData['fullName'] = user!.displayName;
        }
        if (!data.containsKey('photoUrl') && user?.photoURL != null) {
          updateData['photoUrl'] = user!.photoURL;
        }
        if (!data.containsKey('provider')) {
          // Determine provider from user's providerData
          final providers = user?.providerData.map((p) => p.providerId).toList() ?? [];
          if (providers.contains('google.com')) {
            updateData['provider'] = 'google';
          } else {
            updateData['provider'] = 'email';
          }
        }
        if (!data.containsKey('role')) {
          updateData['role'] = 'viewer';
        }
        if (!data.containsKey('status')) {
          updateData['status'] = 'active';
        }
        if (!data.containsKey('findingsCount')) {
          updateData['findingsCount'] = 0;
        }
        if (!data.containsKey('createdAt')) {
          updateData['createdAt'] = FieldValue.serverTimestamp();
        }

        await _firestore.collection('users').doc(uid).update(updateData);
      } else {
        // Document doesn't exist, create full profile
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'email': user?.email ?? '',
          'fullName': user?.displayName ?? '',
          'photoUrl': user?.photoURL,
          'provider': user?.providerData.any((p) => p.providerId == 'google.com') == true ? 'google' : 'email',
          'role': 'viewer',
          'status': 'active',
          'findingsCount': 0,
          'loginCount': 1,
          'createdAt': FieldValue.serverTimestamp(),
          'lastActivity': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Failed to update last activity: $e');
    }
  }

  // Get user profile from Firestore
  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  // Sign out
  static Future<void> signOut() async {
    final user = _auth.currentUser;

    // Log sign out before actually signing out
    if (user != null) {
      await _logActivity(
        action: 'logout',
        userId: user.uid,
        email: user.email,
        details: 'User signed out',
      );
    }

    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Password reset
  static Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);

    // Log password reset request
    await _logActivity(
      action: 'password_reset',
      email: email,
      details: 'Password reset email requested',
    );
  }

  // Get account logs stream (for admin viewing) - sorted by timestamp
  static Stream<QuerySnapshot> getAccountLogsStream() {
    return _firestore
        .collection('account_logs')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  // Get all users stream (for admin viewing) - sorted by lastActivity
  static Stream<QuerySnapshot> getUsersStream() {
    return _firestore
        .collection('users')
        .orderBy('lastActivity', descending: true)
        .snapshots();
  }
}

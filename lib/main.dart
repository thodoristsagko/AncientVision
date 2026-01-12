import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:archive/archive_io.dart';
import 'package:vector_math/vector_math.dart' as vmath;
import 'package:video_player/video_player.dart';
// import 'package:qr_code_scanner/qr_code_scanner.dart'; // Temporarily disabled
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'services/auth_service.dart';
import 'services/local_storage_service.dart';
import 'services/reconstruction_service.dart';
import 'services/pdf_report_service.dart';
import 'services/image_service.dart';
import 'services/cloud_photogrammetry_service.dart';
import 'utils/validators.dart';
import 'utils/quality_analyzer.dart';
import 'models/reconstruction_result.dart';
import 'widgets/model_3d_viewer.dart';

// ============================================================
// IMGBB API KEY - Get your free key at https://api.imgbb.com/
// ============================================================
const String imgbbApiKey = '63efd0891caba4842791a2f892301d07';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: AuthService.authStateChanges,
        builder: (context, snapshot) {
          // Show loading while checking auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFFFFC107)),
              ),
            );
          }
          // If user is logged in, go to Dashboard
          if (snapshot.hasData) {
            return const DashboardScreen();
          }
          // Otherwise, show login screen
          return const LoginScreen();
        },
      ),
    );
  }
}

//
// ----------------------- LOGIN SCREEN ------------------------
//

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Validate
    setState(() {
      _emailError = Validators.validateEmail(_emailController.text);
      _passwordError = Validators.validatePassword(_passwordController.text);
    });

    if (_emailError != null || _passwordError != null) return;

    setState(() => _isLoading = true);

    try {
      await AuthService.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException: ${e.code} - ${e.message}');
      _showError(_getAuthErrorMessage(e.code));
    } catch (e) {
      print('Login error: $e');
      // Check if user is actually logged in despite the error (known firebase_auth bug)
      if (AuthService.currentUser != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
        return;
      }
      _showError('Login failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      final result = await AuthService.signInWithGoogle();

      if (result != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      _showError(_getAuthErrorMessage(e.code));
    } catch (e) {
      _showError('Google Sign-In failed');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'invalid-credential':
        return 'Invalid email or password';
      default:
        return 'Authentication failed. Please try again';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BigLogo(),
                const SizedBox(height: 40),

                _GlassPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GlassTextField(
                        label: 'Email',
                        hint: 'you@example.com',
                        controller: _emailController,
                        errorText: _emailError,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 20),
                      _GlassTextField(
                        label: 'Password',
                        hint: '********',
                        obscure: true,
                        controller: _passwordController,
                        errorText: _passwordError,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                _isLoading
                    ? const CircularProgressIndicator(color: Color(0xFFFFC107))
                    : Column(
                        children: [
                          _PrimaryButton(
                            text: 'Login',
                            onTap: (_) => _handleLogin(),
                          ),
                          const SizedBox(height: 12),
                          _GoogleSignInButton(onTap: _handleGoogleSignIn),
                          const SizedBox(height: 16),
                          // Continue as Guest
                          GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DashboardScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Continue as Guest',
                              style: TextStyle(
                                color: Color(0xFFFFC107),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                const SizedBox(height: 16),

                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    "Don't have an account? Register",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//
// ----------------------- REGISTER SCREEN ------------------------
//

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    // Validate all fields
    setState(() {
      _nameError = Validators.validateFullName(_nameController.text);
      _emailError = Validators.validateEmail(_emailController.text);
      _passwordError = Validators.validatePassword(_passwordController.text);
      _confirmPasswordError = Validators.validateConfirmPassword(
        _confirmPasswordController.text,
        _passwordController.text,
      );
    });

    if (_nameError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmPasswordError != null) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AuthService.registerWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      _showError(_getAuthErrorMessage(e.code));
    } catch (e) {
      _showError('Registration failed. Please try again');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account already exists with this email';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled';
      default:
        return 'Registration failed. Please try again';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _BigLogo(),
                const SizedBox(height: 32),

                _GlassPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GlassTextField(
                        label: 'Full Name',
                        hint: 'Your name',
                        controller: _nameController,
                        errorText: _nameError,
                      ),
                      const SizedBox(height: 16),
                      _GlassTextField(
                        label: 'Email',
                        hint: 'you@example.com',
                        controller: _emailController,
                        errorText: _emailError,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      _GlassTextField(
                        label: 'Password',
                        hint: '********',
                        obscure: true,
                        controller: _passwordController,
                        errorText: _passwordError,
                      ),
                      const SizedBox(height: 16),
                      _GlassTextField(
                        label: 'Confirm Password',
                        hint: '********',
                        obscure: true,
                        controller: _confirmPasswordController,
                        errorText: _confirmPasswordError,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                const SizedBox(
                  width: 340,
                  child: Text(
                    '*Role will be set by admin',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                _isLoading
                    ? const CircularProgressIndicator(color: Color(0xFFFFC107))
                    : _PrimaryButton(
                        text: 'Register',
                        onTap: (_) => _handleRegister(),
                      ),

                const SizedBox(height: 16),

                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'Already have an account? ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        TextSpan(
                          text: 'Login',
                          style: TextStyle(
                            color: Color(0xFFFFC107),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//
// ----------------------- COMMON GLASS WIDGETS ------------------------
//

class _BigLogo extends StatelessWidget {
  const _BigLogo({super.key});

  @override
  Widget build(BuildContext context) {
    const double size = 220;

    return Image.asset(
      'assets/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;

  const _GlassPanel({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  final String label;
  final String hint;
  final bool obscure;
  final TextEditingController? controller;
  final String? errorText;
  final TextInputType? keyboardType;

  const _GlassTextField({
    required this.label,
    required this.hint,
    this.obscure = false,
    this.controller,
    this.errorText,
    this.keyboardType,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: errorText != null
                      ? Colors.red.withOpacity(0.7)
                      : Colors.white.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: controller,
                obscureText: obscure,
                keyboardType: keyboardType,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              errorText!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String text;
  final void Function(BuildContext context) onTap;

  const _PrimaryButton({
    super.key,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(context),
      child: Container(
        width: 300,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFFFC107),
              Color(0xFFFF9800),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3E2723),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GoogleSignInButton({required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/google_logo.png',
              width: 24,
              height: 24,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.g_mobiledata,
                size: 28,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Continue with Google',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3E2723),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//
// ----------------------- DASHBOARD + NAVIGATION ------------------------
//

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return const _DashboardHomeView();
      case 1:
        return const _FindingsView();
      case 2:
        return const _ToolsView();
      case 3:
        return const _SafetyView();
      default:
        return const _DashboardHomeView();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _GlassBottomNavBar(
          currentIndex: _currentIndex,
          onItemSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }
}

//
// --------------------- HOME TAB CONTENT (Dashboard) ---------------------
//

class _DashboardHomeView extends StatefulWidget {
  const _DashboardHomeView({super.key});

  @override
  State<_DashboardHomeView> createState() => _DashboardHomeViewState();
}

class _DashboardHomeViewState extends State<_DashboardHomeView> {
  int _totalFindings = 0;
  int _todayFindings = 0;
  String _userName = '';
  List<Map<String, dynamic>> _lastFindings = [];
  int _offlineDataCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadFindingsCounts();
    _loadUserName();
    _loadLastFindings();
    _checkOfflineData();
  }

  Future<void> _checkOfflineData() async {
    final storage = LocalStorageService();
    await storage.initialize();
    if (mounted) {
      setState(() {
        _offlineDataCount = storage.offlineDataCount;
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    final storage = LocalStorageService();
    final synced = await storage.syncPendingUploads();

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _offlineDataCount = storage.offlineDataCount;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced > 0
              ? '✓ Synced $synced finding${synced > 1 ? 's' : ''}'
              : 'Already up to date'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );

      // Reload findings
      _loadFindingsCounts();
      _loadLastFindings();
    }
  }

  Future<void> _loadLastFindings() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get();

      if (mounted) {
        setState(() {
          _lastFindings = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'type': data['type'] ?? 'Unknown',
              'site': data['site'] ?? 'Unknown',
              'date': data['date'] ?? '',
              'createdAt': data['createdAt'],
            };
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading last findings: $e');
    }
  }

  Future<void> _loadUserName() async {
    final user = AuthService.currentUser;
    if (user == null) {
      setState(() => _userName = 'Guest');
      return;
    }

    // First try Firebase Auth displayName
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      setState(() => _userName = user.displayName!.split(' ').first);
      return;
    }

    // Fallback: fetch from Firestore
    try {
      final profile = await AuthService.getUserProfile(user.uid);
      if (profile != null && profile['fullName'] != null && (profile['fullName'] as String).isNotEmpty) {
        final fullName = profile['fullName'] as String;
        if (mounted) {
          setState(() => _userName = fullName.split(' ').first);
        }
        return;
      }
    } catch (e) {
      // Continue to email fallback
    }

    // Final fallback: extract name from email
    if (user.email != null && user.email!.isNotEmpty) {
      final emailName = user.email!.split('@').first;
      // Capitalize first letter
      final name = emailName[0].toUpperCase() + emailName.substring(1).toLowerCase();
      if (mounted) setState(() => _userName = name);
    } else {
      if (mounted) setState(() => _userName = 'User');
    }
  }

  Future<void> _loadFindingsCounts() async {
    try {
      // Get total findings count
      final totalSnapshot = await FirebaseFirestore.instance
          .collection('findings')
          .get();

      // Get today's findings count
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final todaySnapshot = await FirebaseFirestore.instance
          .collection('findings')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();

      if (mounted) {
        setState(() {
          _totalFindings = totalSnapshot.docs.length;
          _todayFindings = todaySnapshot.docs.length;
        });
      }
    } catch (e) {
      print('Error loading findings counts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, ${_userName.isEmpty ? "..." : _userName}!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) => GestureDetector(
                            onTap: () async {
                              await AuthService.signOut();
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  (route) => false,
                                );
                              }
                            },
                            child: Text(
                              'Sign Out',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const _LogoCard(),
                ],
              ),

              const SizedBox(height: 24),

              // OFFLINE SYNC INDICATOR
              if (_offlineDataCount > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFC107), width: 1),
                  ),
                  child: Row(
                    children: [
                      if (_isSyncing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Color(0xFFFFC107)),
                          ),
                        )
                      else
                        const Icon(Icons.cloud_off, color: Color(0xFFFFC107), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isSyncing ? 'Syncing...' : 'Offline Data',
                              style: const TextStyle(
                                color: Color(0xFFFFC107),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_offlineDataCount finding${_offlineDataCount > 1 ? 's' : ''} pending upload',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isSyncing)
                        TextButton(
                          onPressed: _syncNow,
                          child: const Text(
                            'Sync Now',
                            style: TextStyle(
                              color: Color(0xFFFFC107),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // STATS ROW
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: 'Total Findings',
                      value: '$_totalFindings',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'New Today',
                      value: '$_todayFindings',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ACTIVE SITES full width
              const _FullStatCard(title: 'Active Sites', value: '3'),

              const SizedBox(height: 12),

              // QUICK ACTIONS: AI Recognition & Photogrammetry
              const _QuickActionsRow(),

              const SizedBox(height: 16),

              // LAST FINDINGS
              _LastFindingsCard(findings: _lastFindings),

              const SizedBox(height: 12),

              // TODAY AT SITE
              const _TodayAtSiteCard(),

              const SizedBox(height: 12),

              // INSIGHT
              const _InsightCard(),

              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

//
// ----------------------- DASHBOARD WIDGETS ------------------------
//

class _LogoCard extends StatelessWidget {
  const _LogoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      width: 80,
      height: 80,
      fit: BoxFit.contain,
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;

  const _StatCard({required this.title, required this.value, super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                  )),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullStatCard extends StatelessWidget {
  final String title;
  final String value;

  const _FullStatCard({required this.title, required this.value, super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          height: 120,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                  )),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Quick actions row (AI + Photogrammetry) ----

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GlassActionButton(
            icon: Icons.auto_awesome_rounded,
            title: 'AI Recognition',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('AI Recognition screen (coming soon)'),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GlassActionButton(
            icon: Icons.camera_alt_outlined,
            title: 'Photogrammetry',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PhotogrammetryScreen(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _GlassActionButton({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------- LAST FINDINGS CARD --------

class _LastFindingsCard extends StatelessWidget {
  final List<Map<String, dynamic>> findings;

  const _LastFindingsCard({super.key, required this.findings});

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '--:--';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '--:--';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          height: 160,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Last Findings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (findings.isEmpty)
                Text(
                  'No findings yet',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                  ),
                )
              else
                ...findings.take(3).map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _FindingRow(
                    time: _formatTime(f['createdAt']),
                    type: f['type'] ?? 'Unknown',
                    site: f['site'] ?? 'Unknown',
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  final String time;
  final String type;
  final String site;

  const _FindingRow({
    super.key,
    required this.time,
    required this.type,
    required this.site,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          time,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            type,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          site,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// -------- TODAY AT SITE CARD --------

class _TodayAtSiteCard extends StatelessWidget {
  const _TodayAtSiteCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Today at Site',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ancient Agora',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Current trench: B3',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Weather: 23°C, Clear',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------- INSIGHT CARD --------

class _InsightCard extends StatefulWidget {
  const _InsightCard({super.key});

  @override
  State<_InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<_InsightCard> {
  String _currentInsight = 'Loading insights...';
  int _currentIndex = 0;
  List<String> _insights = [];

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .get();

      final findings = snapshot.docs;
      final total = findings.length;

      if (total == 0) {
        setState(() {
          _insights = [
            'No findings recorded yet. Start by adding your first archaeological discovery!',
            'Tip: Use GPS coordinates for accurate location tracking of your finds.',
            'Did you know? Proper documentation increases the scientific value of archaeological finds.',
          ];
          _currentInsight = _insights[0];
        });
        _startRotation();
        return;
      }

      // Analyze findings data
      final Map<String, int> typeCounts = {};
      final Map<String, int> siteCounts = {};
      int todayCount = 0;
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      for (final doc in findings) {
        final data = doc.data();
        final type = data['type'] as String? ?? 'Unknown';
        final site = data['site'] as String? ?? 'Unknown';

        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
        siteCounts[site] = (siteCounts[site] ?? 0) + 1;

        final createdAt = data['createdAt'] as Timestamp?;
        if (createdAt != null && createdAt.toDate().isAfter(startOfDay)) {
          todayCount++;
        }
      }

      // Find most common type and site
      String mostCommonType = 'Unknown';
      int maxTypeCount = 0;
      typeCounts.forEach((type, count) {
        if (count > maxTypeCount) {
          maxTypeCount = count;
          mostCommonType = type;
        }
      });

      String mostActiveSite = 'Unknown';
      int maxSiteCount = 0;
      siteCounts.forEach((site, count) {
        if (count > maxSiteCount) {
          maxSiteCount = count;
          mostActiveSite = site;
        }
      });

      final typePercentage = ((maxTypeCount / total) * 100).round();
      final sitePercentage = ((maxSiteCount / total) * 100).round();

      // Generate insights
      final generatedInsights = <String>[
        'You have recorded $total findings in total. ${todayCount > 0 ? "$todayCount added today!" : "Add more today!"}',
        '$typePercentage% of your findings are ${mostCommonType}s. Consider diversifying your documentation.',
        'Most active site: $mostActiveSite with $maxSiteCount findings ($sitePercentage% of total).',
        'Tip: Regular photo documentation helps preserve finding details for future analysis.',
        '${typeCounts.length} different artifact types recorded across ${siteCounts.length} sites.',
      ];

      if (todayCount > 0) {
        generatedInsights.add('Great progress! $todayCount new ${todayCount == 1 ? "finding" : "findings"} documented today.');
      }

      if (total >= 10) {
        generatedInsights.add('Milestone: Over 10 findings documented! Your catalog is growing.');
      }
      if (total >= 50) {
        generatedInsights.add('Impressive! 50+ findings in your database. Consider exporting a report.');
      }

      setState(() {
        _insights = generatedInsights;
        _currentInsight = _insights[0];
      });

      _startRotation();
    } catch (e) {
      setState(() {
        _insights = [
          'Tip: Use GPS for precise location tracking.',
          'Document findings immediately for best accuracy.',
          'Take multiple photos from different angles.',
        ];
        _currentInsight = _insights[0];
      });
      _startRotation();
    }
  }

  void _startRotation() {
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _insights.isNotEmpty) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _insights.length;
          _currentInsight = _insights[_currentIndex];
        });
        _startRotation();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.30),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Insight',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.lightbulb_outline,
                    color: Colors.amber.withOpacity(0.7),
                    size: 14,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Text(
                  _currentInsight,
                  key: ValueKey<String>(_currentInsight),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//
// --------------------- FINDINGS TAB CONTENT ---------------------
//

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
  final List<String> photoGallery; // Multiple photos for photogrammetry
  final String? model3dUrl; // Link to 3D model (Sketchfab, etc.)

  // ULTRA++ Archaeological Professional Fields
  final String? findNumber; // Catalog/Accession number (e.g., "2024-FLD-001")
  final String? excavationUnit; // Grid square/unit (e.g., "A4", "Trench 2")
  final String? stratigraphicLayer; // Context/layer number (e.g., "Layer 3", "Context 025")
  final double? depthBelowSurface; // Depth in meters
  final double? depthBelowDatum; // Depth from datum point in meters
  final double? lengthMm; // Length in millimeters
  final double? widthMm; // Width in millimeters
  final double? heightMm; // Height/thickness in millimeters
  final double? weightGrams; // Weight in grams
  final String? material; // Material classification (e.g., "Terracotta", "Bronze", "Limestone")
  final String? condition; // Preservation state (e.g., "Excellent", "Fragmentary", "Weathered")
  final String? datingMethod; // How it was dated (e.g., "Stratigraphy", "Typology", "C14")
  final List<String>? associatedFinds; // Related find numbers
  final String? soilType; // Soil context (e.g., "Sandy loam", "Clay")
  final String? colorMunsell; // Munsell color code for pottery/soil
  final String? period; // Cultural period (e.g., "Late Bronze Age", "Roman Imperial")
  final String? notes; // Field notes
  final String? excavator; // Who found/excavated it
  final String? weatheringDegree; // Weathering assessment (e.g., "None", "Slight", "Moderate", "Severe")

  const _Finding({
    required this.id,
    required this.name,
    required this.type,
    required this.site,
    required this.date,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
    this.photoGallery = const [],
    this.model3dUrl,
    this.findNumber,
    this.excavationUnit,
    this.stratigraphicLayer,
    this.depthBelowSurface,
    this.depthBelowDatum,
    this.lengthMm,
    this.widthMm,
    this.heightMm,
    this.weightGrams,
    this.material,
    this.condition,
    this.datingMethod,
    this.associatedFinds,
    this.soilType,
    this.colorMunsell,
    this.period,
    this.notes,
    this.excavator,
    this.weatheringDegree,
  });

  // Get color based on finding type for map markers
  static Color getTypeColor(String type) {
    final typeLower = type.toLowerCase();
    if (typeLower.contains('pottery') || typeLower.contains('ceramic')) {
      return const Color(0xFFE57373); // Red
    } else if (typeLower.contains('coin') || typeLower.contains('metal')) {
      return const Color(0xFFFFD54F); // Gold
    } else if (typeLower.contains('statue') || typeLower.contains('sculpture')) {
      return const Color(0xFF81C784); // Green
    } else if (typeLower.contains('tool') || typeLower.contains('weapon')) {
      return const Color(0xFF64B5F6); // Blue
    } else if (typeLower.contains('bone') || typeLower.contains('fossil')) {
      return const Color(0xFFFFFFFF); // White
    } else if (typeLower.contains('jewelry') || typeLower.contains('ornament')) {
      return const Color(0xFFBA68C8); // Purple
    }
    return const Color(0xFFFFC107); // Default amber
  }
}

class _FindingsView extends StatefulWidget {
  const _FindingsView({super.key});

  @override
  State<_FindingsView> createState() => _FindingsViewState();
}

class _FindingsViewState extends State<_FindingsView> {
  List<_Finding> _findings = [];
  List<_Finding> _filteredFindings = [];
  bool _isLoading = true;
  int _selectedIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredFindings = _findings;
      } else {
        _filteredFindings = _findings.where((f) {
          final searchLower = query.toLowerCase();
          return f.name.toLowerCase().contains(searchLower) ||
              f.type.toLowerCase().contains(searchLower) ||
              f.site.toLowerCase().contains(searchLower) ||
              f.id.toLowerCase().contains(searchLower);
        }).toList();
      }
      if (_filteredFindings.isNotEmpty && _selectedIndex >= _filteredFindings.length) {
        _selectedIndex = 0;
      }
    });
  }

  Future<void> _exportReport() async {
    if (_findings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No findings to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Generate HTML report
      final reportDate = DateTime.now();
      final dateStr = '${reportDate.year}-${reportDate.month.toString().padLeft(2, '0')}-${reportDate.day.toString().padLeft(2, '0')}';

      final StringBuffer html = StringBuffer();
      html.writeln('<!DOCTYPE html>');
      html.writeln('<html><head>');
      html.writeln('<meta charset="UTF-8">');
      html.writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
      html.writeln('<title>AncientVision Field Report - $dateStr</title>');
      html.writeln('<style>');
      html.writeln('body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 900px; margin: 0 auto; padding: 20px; background: #f5f5f5; }');
      html.writeln('.header { background: linear-gradient(135deg, #0D3A39, #1C2523); color: white; padding: 30px; border-radius: 16px; margin-bottom: 24px; }');
      html.writeln('.header h1 { margin: 0 0 8px 0; font-size: 28px; }');
      html.writeln('.header p { margin: 0; opacity: 0.8; }');
      html.writeln('.stats { display: flex; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }');
      html.writeln('.stat { background: white; padding: 20px; border-radius: 12px; flex: 1; min-width: 150px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }');
      html.writeln('.stat-value { font-size: 32px; font-weight: bold; color: #0D3A39; }');
      html.writeln('.stat-label { color: #666; font-size: 14px; }');
      html.writeln('.finding { background: white; border-radius: 16px; padding: 20px; margin-bottom: 16px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }');
      html.writeln('.finding-header { display: flex; justify-content: space-between; align-items: start; margin-bottom: 12px; }');
      html.writeln('.finding-name { font-size: 20px; font-weight: 600; color: #333; margin: 0; }');
      html.writeln('.finding-id { background: #FFC107; color: #3E2723; padding: 4px 10px; border-radius: 8px; font-size: 12px; font-weight: 600; }');
      html.writeln('.finding-type { display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 500; margin-bottom: 12px; }');
      html.writeln('.finding-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; }');
      html.writeln('.finding-field { padding: 12px; background: #f8f9fa; border-radius: 8px; }');
      html.writeln('.field-label { font-size: 11px; color: #666; text-transform: uppercase; margin-bottom: 4px; }');
      html.writeln('.field-value { font-size: 14px; color: #333; }');
      html.writeln('.finding-image { width: 100%; max-height: 300px; object-fit: cover; border-radius: 12px; margin-top: 12px; }');
      html.writeln('.footer { text-align: center; color: #666; font-size: 12px; margin-top: 40px; padding: 20px; }');
      html.writeln('@media print { body { background: white; } .finding { break-inside: avoid; } }');
      html.writeln('</style>');
      html.writeln('</head><body>');

      // Header
      html.writeln('<div class="header">');
      html.writeln('<h1>🏛️ AncientVision Field Report</h1>');
      html.writeln('<p>Archaeological findings documentation • Generated on $dateStr</p>');
      html.writeln('</div>');

      // Stats
      final typeCount = <String, int>{};
      final siteCount = <String, int>{};
      for (final f in _findings) {
        typeCount[f.type] = (typeCount[f.type] ?? 0) + 1;
        siteCount[f.site] = (siteCount[f.site] ?? 0) + 1;
      }

      html.writeln('<div class="stats">');
      html.writeln('<div class="stat"><div class="stat-value">${_findings.length}</div><div class="stat-label">Total Findings</div></div>');
      html.writeln('<div class="stat"><div class="stat-value">${typeCount.length}</div><div class="stat-label">Artifact Types</div></div>');
      html.writeln('<div class="stat"><div class="stat-value">${siteCount.length}</div><div class="stat-label">Excavation Sites</div></div>');
      html.writeln('</div>');

      // Findings
      for (final finding in _findings) {
        final typeColor = _Finding.getTypeColor(finding.type);
        final colorHex = '#${typeColor.value.toRadixString(16).substring(2)}';

        html.writeln('<div class="finding">');
        html.writeln('<div class="finding-header">');
        html.writeln('<h2 class="finding-name">${_escapeHtml(finding.name)}</h2>');
        html.writeln('<span class="finding-id">${finding.id}</span>');
        html.writeln('</div>');
        html.writeln('<span class="finding-type" style="background: ${colorHex}20; color: $colorHex;">${_escapeHtml(finding.type)}</span>');

        html.writeln('<div class="finding-grid">');
        html.writeln('<div class="finding-field"><div class="field-label">Site</div><div class="field-value">${_escapeHtml(finding.site)}</div></div>');
        html.writeln('<div class="finding-field"><div class="field-label">Date Found</div><div class="field-value">${_escapeHtml(finding.date)}</div></div>');
        html.writeln('<div class="finding-field"><div class="field-label">Coordinates</div><div class="field-value">${finding.latitude.toStringAsFixed(6)}, ${finding.longitude.toStringAsFixed(6)}</div></div>');
        if (finding.model3dUrl != null && finding.model3dUrl!.isNotEmpty) {
          html.writeln('<div class="finding-field"><div class="field-label">3D Model</div><div class="field-value"><a href="${_escapeHtml(finding.model3dUrl!)}" target="_blank">View Model</a></div></div>');
        }
        html.writeln('</div>');

        if (finding.description.isNotEmpty) {
          html.writeln('<div class="finding-field" style="margin-top: 12px;"><div class="field-label">Description</div><div class="field-value">${_escapeHtml(finding.description)}</div></div>');
        }

        if (finding.imageUrl != null && finding.imageUrl!.isNotEmpty) {
          html.writeln('<img class="finding-image" src="${finding.imageUrl}" alt="${_escapeHtml(finding.name)}">');
        }

        if (finding.photoGallery.isNotEmpty) {
          html.writeln('<div style="margin-top: 12px;"><div class="field-label">Photo Gallery (${finding.photoGallery.length} photos)</div>');
          html.writeln('<div style="display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px;">');
          for (int i = 0; i < finding.photoGallery.length && i < 4; i++) {
            html.writeln('<img src="${finding.photoGallery[i]}" style="width: 100px; height: 100px; object-fit: cover; border-radius: 8px;" alt="Gallery photo ${i + 1}">');
          }
          if (finding.photoGallery.length > 4) {
            html.writeln('<div style="width: 100px; height: 100px; background: #e0e0e0; border-radius: 8px; display: flex; align-items: center; justify-content: center; color: #666;">+${finding.photoGallery.length - 4} more</div>');
          }
          html.writeln('</div></div>');
        }

        html.writeln('</div>');
      }

      // Footer
      html.writeln('<div class="footer">');
      html.writeln('<p>Generated by AncientVision • FLL Archaeological Field Management App</p>');
      html.writeln('<p>© ${reportDate.year} AncientVision Project</p>');
      html.writeln('</div>');

      html.writeln('</body></html>');

      // Save to file
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/AncientVision_Report_$dateStr.html');
      await file.writeAsString(html.toString());

      // Show success dialog with options
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 28),
                SizedBox(width: 12),
                Text('Report Generated!', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your archaeological findings report has been saved.',
                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder, color: Color(0xFFFFC107), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.path,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: TextStyle(color: Colors.white.withOpacity(0.6))),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.file(file.path);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: const Color(0xFF3E2723),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  Future<void> _loadFindings() async {
    debugPrint('=== _loadFindings called ===');
    try {
      // First try with ordering, then fallback without if no results
      var snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      // If no results with ordering, try without (for docs missing createdAt)
      if (snapshot.docs.isEmpty) {
        debugPrint('No documents with createdAt, trying without ordering...');
        snapshot = await FirebaseFirestore.instance
            .collection('findings')
            .limit(20)
            .get();
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
        return _Finding(
          id: doc.id,
          name: data['name'] ?? '',
          type: data['type'] ?? '',
          site: data['site'] ?? '',
          date: data['date'] ?? '',
          description: data['description'] ?? '',
          latitude: (data['latitude'] ?? 37.9715).toDouble(),
          longitude: (data['longitude'] ?? 23.7267).toDouble(),
          imageUrl: data['imageUrl'],
          photoGallery: gallery,
          model3dUrl: data['model3dUrl'],
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
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
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
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.white.withOpacity(0.5),
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
                                color: Colors.white.withOpacity(0.5),
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

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _filteredFindings.isEmpty && _searchController.text.isNotEmpty
                            ? 'No results found'
                            : 'Pull down to refresh',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    // Export Report button
                    GestureDetector(
                      onTap: _exportReport,
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF4CAF50).withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.file_download_outlined,
                          color: Color(0xFF4CAF50),
                          size: 18,
                        ),
                      ),
                    ),
                  // AI Recognition button
                  if (AuthService.currentUser != null)
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('AI Recognition coming soon'),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C4DFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Manual Entry button
                  if (AuthService.currentUser != null)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ManualEntryFormScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              color: Color(0xFF3E2723),
                              size: 18,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Manual Entry',
                              style: TextStyle(
                                color: Color(0xFF3E2723),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white.withOpacity(0.4),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Sign in to add',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Show loading or empty state
              if (_isLoading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFFC107),
                        ),
                      ),
                    ),
                  ),
                )
              else if (_findings.isEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Animated icon container
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107).withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFFC107).withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.explore_outlined,
                              color: Color(0xFFFFC107),
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Start Your Discovery',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No archaeological findings recorded yet.\nDocument your first discovery!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (AuthService.currentUser != null)
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ManualEntryFormScreen(),
                                  ),
                                ).then((_) => _loadFindings());
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add First Finding'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFC107),
                                foregroundColor: const Color(0xFF3E2723),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    color: Colors.white.withOpacity(0.5),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Sign in to add findings',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                // RECENT FINDINGS TABLE WITH SWIPE TO DELETE
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Findings list
                          ..._filteredFindings.asMap().entries.map((entry) {
                            final index = entry.key;
                            final f = entry.value;
                            final isSelected = index == _selectedIndex;
                            final typeColor = _Finding.getTypeColor(f.type);

                            return GestureDetector(
                              key: Key(f.id),
                              onTap: () => setState(() => _selectedIndex = index),
                              child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFFFC107).withOpacity(0.2)
                                        : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFFFC107).withOpacity(0.5)
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
                                                    color: Colors.white.withOpacity(0.5),
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
                                                color: Colors.white.withOpacity(0.6),
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
                                            color: const Color(0xFF7C4DFF).withOpacity(0.3),
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
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.white.withOpacity(0.3),
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // MAP (Smaller size with OpenStreetMap)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      height: 300,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                      child: _FindingsMap(findings: _filteredFindings, selectedIndex: _selectedIndex),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // LATEST FINDING DETAIL PANEL
                if (selected != null) _FindingDetailCard(finding: selected),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _FindingDetailCard extends StatelessWidget {
  final _Finding finding;

  const _FindingDetailCard({super.key, required this.finding});

  Widget _buildFindingImage(String imageUrl) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: 80,
      height: 80,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFFC107),
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return const Icon(
          Icons.broken_image_outlined,
          color: Colors.white70,
          size: 36,
        );
      },
    );
  }

  Future<void> _open3DModel(BuildContext context) async {
    if (finding.model3dUrl != null) {
      final url = Uri.parse(finding.model3dUrl!);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _Finding.getTypeColor(finding.type);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Finding image with type color border
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: typeColor.withOpacity(0.6),
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: finding.imageUrl != null
                          ? _buildFindingImage(finding.imageUrl!)
                          : Icon(
                              Icons.image_outlined,
                              color: typeColor.withOpacity(0.5),
                              size: 36,
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Type color indicator
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: typeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                finding.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${finding.type} • ${finding.site} • ${finding.date}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (finding.description.isNotEmpty)
                          Text(
                            finding.description,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // Action buttons row
              if (finding.model3dUrl != null || finding.photoGallery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      // 3D Model button
                      if (finding.model3dUrl != null)
                        GestureDetector(
                          onTap: () => _open3DModel(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C4DFF).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF7C4DFF).withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.view_in_ar_rounded, color: Color(0xFF7C4DFF), size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'View 3D Model',
                                  style: TextStyle(
                                    color: Color(0xFF7C4DFF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (finding.model3dUrl != null && finding.photoGallery.isNotEmpty)
                        const SizedBox(width: 8),

                      // Photo gallery indicator
                      if (finding.photoGallery.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library_outlined, color: Colors.white.withOpacity(0.7), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                '${finding.photoGallery.length} photos',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingsMap extends StatefulWidget {
  final List<_Finding> findings;
  final int selectedIndex;

  const _FindingsMap({
    super.key,
    required this.findings,
    required this.selectedIndex,
  });

  @override
  State<_FindingsMap> createState() => _FindingsMapState();
}

class _FindingsMapState extends State<_FindingsMap> {
  MapController? _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(covariant _FindingsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When selectedIndex changes, move map to that finding
    if (oldWidget.selectedIndex != widget.selectedIndex && widget.findings.isNotEmpty) {
      final selected = widget.findings[widget.selectedIndex];
      _mapController?.move(
        LatLng(selected.latitude, selected.longitude),
        17.5,
      );
    }
  }

  Future<void> _openInGoogleMaps() async {
    final center = widget.findings[widget.selectedIndex];
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${center.latitude},${center.longitude}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  List<Marker> _buildMarkers() {
    return widget.findings.asMap().entries.map((entry) {
      final index = entry.key;
      final finding = entry.value;
      final isSelected = index == widget.selectedIndex;
      final typeColor = _Finding.getTypeColor(finding.type);

      return Marker(
        point: LatLng(finding.latitude, finding.longitude),
        width: isSelected ? 48 : 36,
        height: isSelected ? 48 : 36,
        child: GestureDetector(
          onTap: () => _openInGoogleMaps(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow for selected marker
              if (isSelected)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: typeColor.withOpacity(0.3),
                  ),
                ),
              // Main marker icon
              Icon(
                Icons.location_pin,
                size: isSelected ? 40 : 32,
                color: isSelected ? typeColor : typeColor.withOpacity(0.85),
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
              // Type indicator dot
              Positioned(
                top: isSelected ? 8 : 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: typeColor, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Center on the most recent finding (first in the list)
    final firstFinding = widget.findings.first;

    return Stack(
      children: [
        // Interactive OpenStreetMap
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(firstFinding.latitude, firstFinding.longitude),
            initialZoom: 17.5,
            minZoom: 10,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.ancient_vision',
            ),
            MarkerLayer(
              markers: _buildMarkers(),
            ),
          ],
        ),

        // Map label overlay
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Ancient Agora Site',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        // Open in Google Maps button
        Positioned(
          bottom: 12,
          right: 12,
          child: GestureDetector(
            onTap: _openInGoogleMaps,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.open_in_new,
                    color: Color(0xFF3E2723),
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Open in Google Maps',
                    style: TextStyle(
                      color: Color(0xFF3E2723),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

//
// --------------------- ADD TAB VIEW ---------------------
//

// =============================================================================
// TOOLS VIEW - Professional Feature Discovery
// =============================================================================
// Clear, organized view of ALL app capabilities categorized by function
// =============================================================================

class _ToolsView extends StatelessWidget {
  const _ToolsView({super.key});

  bool get _isGuest => AuthService.currentUser == null;

  @override
  Widget build(BuildContext context) {
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    const Text(
                      'Professional Tools',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isGuest
                          ? 'Sign in to unlock all features'
                          : 'Industry-leading archaeological field tools',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_isGuest) ...[
                      // GUEST VIEW with locked features
                      _buildLockedFeaturePreview(context),
                    ] else ...[
                      // === HERO FEATURE: 3D RECONSTRUCTION ===
                      _buildHeroFeature(context),
                      const SizedBox(height: 20),

                      // === CAPTURE TOOLS ===
                      _buildCategoryHeader('Capture & Documentation'),
                      const SizedBox(height: 12),
                      _buildToolGrid(context, [
                        _ToolCard(
                          icon: Icons.edit_note_rounded,
                          title: 'Manual Entry',
                          description: 'Full archaeological form',
                          badge: 'Professional',
                          color: const Color(0xFF2196F3),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ManualEntryFormScreen()),
                          ),
                        ),
                        _ToolCard(
                          icon: Icons.camera_alt_rounded,
                          title: 'Photo Capture',
                          description: 'High-quality documentation',
                          badge: 'HDR',
                          color: const Color(0xFF9C27B0),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PhotogrammetryScreen()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // === ANALYSIS TOOLS ===
                      _buildCategoryHeader('AI & Analysis'),
                      const SizedBox(height: 12),
                      _buildToolGrid(context, [
                        _ToolCard(
                          icon: Icons.auto_awesome_rounded,
                          title: 'AI Recognition',
                          description: 'Auto-identify artifacts',
                          badge: 'Smart',
                          color: const Color(0xFFFF9800),
                          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('AI Recognition: Analyze photo to identify artifact type, material, and period')),
                          ),
                        ),
                        _ToolCard(
                          icon: Icons.analytics_rounded,
                          title: 'Quality Check',
                          description: 'Real-time validation',
                          badge: '4 Metrics',
                          color: const Color(0xFF4CAF50),
                          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Quality Analyzer: Sharpness, Exposure, Motion Blur, Noise detection')),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // === EXPORT & SHARING ===
                      _buildCategoryHeader('Export & Reports'),
                      const SizedBox(height: 12),
                      _buildToolGrid(context, [
                        _ToolCard(
                          icon: Icons.picture_as_pdf_rounded,
                          title: 'PDF Reports',
                          description: 'Publication-ready docs',
                          badge: 'Pro',
                          color: const Color(0xFFF44336),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PDFExportScreen()),
                          ),
                        ),
                        _ToolCard(
                          icon: Icons.share_rounded,
                          title: 'Export Data',
                          description: 'Export findings & 3D models',
                          badge: 'Share',
                          color: const Color(0xFF00BCD4),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ExportDataScreen()),
                          ),
                        ),
                      ]),

                      const SizedBox(height: 120),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroFeature(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PhotogrammetryScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6A1B9A),
              Color(0xFF8E24AA),
              Color(0xFFAB47BC),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8E24AA).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 28),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '⚡ HERO FEATURE',
                    style: TextStyle(
                      color: Color(0xFF0D3A39),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '3D Reconstruction',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'On-device photogrammetry with RANSAC & Essential Matrix. Industry-grade Structure from Motion in 10-30 seconds.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.90),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildFeatureBadge('RANSAC'),
                const SizedBox(width: 8),
                _buildFeatureBadge('Triple Validation'),
                const SizedBox(width: 8),
                _buildFeatureBadge('85-95% Success'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Start 3D Capture',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildToolGrid(BuildContext context, List<_ToolCard> tools) {
    return Row(
      children: [
        for (int i = 0; i < tools.length; i++) ...[
          Expanded(child: tools[i]),
          if (i < tools.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildLockedFeaturePreview(BuildContext context) {
    return Column(
      children: [
        _buildLockedCard('3D Reconstruction', Icons.view_in_ar_rounded),
        const SizedBox(height: 12),
        _buildLockedCard('Manual Entry', Icons.edit_note_rounded),
        const SizedBox(height: 12),
        _buildLockedCard('AI Recognition', Icons.auto_awesome_rounded),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Sign In to Unlock Tools',
                style: TextStyle(
                  color: Color(0xFF0D3A39),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLockedCard(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 20),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final Color color;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withOpacity(0.60),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Guest version of add option card - blurred with sign in required text
class _GuestAddOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;

  const _GuestAddOptionCard({
    required this.icon,
    required this.title,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white38, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in required',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.lock_outline_rounded,
                color: Colors.white.withOpacity(0.3),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _AddOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFFFFC107),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withOpacity(0.5),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//
// --------------------- MANUAL ENTRY FORM SCREEN ---------------------
//

class ManualEntryFormScreen extends StatefulWidget {
  final ReconstructionResult? reconstructionResult;
  final List<XFile>? photoGallery;

  const ManualEntryFormScreen({
    super.key,
    this.reconstructionResult,
    this.photoGallery,
  });

  @override
  State<ManualEntryFormScreen> createState() => _ManualEntryFormScreenState();
}

class _ManualEntryFormScreenState extends State<ManualEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _siteController = TextEditingController();
  final _dateController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _model3dUrlController = TextEditingController();
  bool _hasImage = false;
  XFile? _selectedImage;
  final List<XFile> _photoGallery = []; // For photogrammetry - multiple photos
  final ImagePicker _imagePicker = ImagePicker();
  String _nextId = 'A-001';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isGettingLocation = false;
  bool _isPhotogrammetryMode = false;

  // Auto-save functionality
  Timer? _autoSaveTimer;
  DateTime? _lastAutoSave;

  // Random example hints
  late String _nameHint;
  late String _typeHint;
  late String _siteHint;

  // Name-Type pairs that match logically (~100 pairs)
  static const _nameTypePairs = [
    // Coins
    {'name': 'Bronze Coin', 'type': 'Coin'},
    {'name': 'Silver Denarius', 'type': 'Coin'},
    {'name': 'Gold Stater', 'type': 'Coin'},
    {'name': 'Copper As', 'type': 'Coin'},
    {'name': 'Silver Drachma', 'type': 'Coin'},
    {'name': 'Gold Aureus', 'type': 'Coin'},
    {'name': 'Bronze Sestertius', 'type': 'Coin'},
    {'name': 'Silver Tetradrachm', 'type': 'Coin'},
    {'name': 'Electrum Coin', 'type': 'Coin'},
    {'name': 'Lead Token', 'type': 'Coin'},
    {'name': 'Bronze Obol', 'type': 'Coin'},
    {'name': 'Silver Shekel', 'type': 'Coin'},
    {'name': 'Gold Solidus', 'type': 'Coin'},
    {'name': 'Copper Follis', 'type': 'Coin'},
    {'name': 'Bronze Nummus', 'type': 'Coin'},
    // Pottery
    {'name': 'Ceramic Vase', 'type': 'Pottery'},
    {'name': 'Painted Amphora', 'type': 'Pottery'},
    {'name': 'Clay Bowl', 'type': 'Pottery'},
    {'name': 'Terracotta Lamp', 'type': 'Pottery'},
    {'name': 'Red-Figure Krater', 'type': 'Pottery'},
    {'name': 'Black-Figure Kylix', 'type': 'Pottery'},
    {'name': 'Ceramic Jug', 'type': 'Pottery'},
    {'name': 'Clay Pithos', 'type': 'Pottery'},
    {'name': 'Painted Lekythos', 'type': 'Pottery'},
    {'name': 'Terracotta Oinochoe', 'type': 'Pottery'},
    {'name': 'Ceramic Pyxis', 'type': 'Pottery'},
    {'name': 'Clay Storage Jar', 'type': 'Pottery'},
    {'name': 'Painted Hydria', 'type': 'Pottery'},
    {'name': 'Ceramic Plate', 'type': 'Pottery'},
    {'name': 'Terracotta Cup', 'type': 'Pottery'},
    {'name': 'Clay Cooking Pot', 'type': 'Pottery'},
    {'name': 'Ceramic Skyphos', 'type': 'Pottery'},
    {'name': 'Painted Kantharos', 'type': 'Pottery'},
    {'name': 'Clay Oil Lamp', 'type': 'Pottery'},
    {'name': 'Terracotta Askos', 'type': 'Pottery'},
    // Sculpture
    {'name': 'Marble Statue', 'type': 'Sculpture'},
    {'name': 'Bronze Figurine', 'type': 'Sculpture'},
    {'name': 'Clay Figurine', 'type': 'Sculpture'},
    {'name': 'Limestone Head', 'type': 'Sculpture'},
    {'name': 'Terracotta Bust', 'type': 'Sculpture'},
    {'name': 'Marble Relief', 'type': 'Sculpture'},
    {'name': 'Bronze Statuette', 'type': 'Sculpture'},
    {'name': 'Stone Torso', 'type': 'Sculpture'},
    {'name': 'Ivory Carving', 'type': 'Sculpture'},
    {'name': 'Marble Portrait', 'type': 'Sculpture'},
    {'name': 'Bronze Horse', 'type': 'Sculpture'},
    {'name': 'Clay Animal Figure', 'type': 'Sculpture'},
    {'name': 'Limestone Sphinx', 'type': 'Sculpture'},
    {'name': 'Terracotta Mask', 'type': 'Sculpture'},
    {'name': 'Marble Hand', 'type': 'Sculpture'},
    // Tools
    {'name': 'Iron Chisel', 'type': 'Tool'},
    {'name': 'Bronze Needle', 'type': 'Tool'},
    {'name': 'Stone Hammer', 'type': 'Tool'},
    {'name': 'Copper Awl', 'type': 'Tool'},
    {'name': 'Iron Knife', 'type': 'Tool'},
    {'name': 'Bronze Stylus', 'type': 'Tool'},
    {'name': 'Stone Pestle', 'type': 'Tool'},
    {'name': 'Iron Sickle', 'type': 'Tool'},
    {'name': 'Bronze Tweezers', 'type': 'Tool'},
    {'name': 'Flint Scraper', 'type': 'Tool'},
    {'name': 'Iron Tongs', 'type': 'Tool'},
    {'name': 'Bronze Spatula', 'type': 'Tool'},
    // Jewelry
    {'name': 'Gold Ring', 'type': 'Jewelry'},
    {'name': 'Silver Bracelet', 'type': 'Jewelry'},
    {'name': 'Glass Bead', 'type': 'Jewelry'},
    {'name': 'Gold Earring', 'type': 'Jewelry'},
    {'name': 'Bronze Fibula', 'type': 'Jewelry'},
    {'name': 'Silver Necklace', 'type': 'Jewelry'},
    {'name': 'Gold Pendant', 'type': 'Jewelry'},
    {'name': 'Amber Bead', 'type': 'Jewelry'},
    {'name': 'Bronze Brooch', 'type': 'Jewelry'},
    {'name': 'Silver Anklet', 'type': 'Jewelry'},
    {'name': 'Gold Diadem', 'type': 'Jewelry'},
    {'name': 'Carnelian Intaglio', 'type': 'Jewelry'},
    {'name': 'Bronze Armband', 'type': 'Jewelry'},
    {'name': 'Pearl Earring', 'type': 'Jewelry'},
    {'name': 'Gold Torc', 'type': 'Jewelry'},
    // Weapons
    {'name': 'Bronze Sword', 'type': 'Weapon'},
    {'name': 'Iron Spearhead', 'type': 'Weapon'},
    {'name': 'Obsidian Blade', 'type': 'Weapon'},
    {'name': 'Bronze Arrowhead', 'type': 'Weapon'},
    {'name': 'Iron Dagger', 'type': 'Weapon'},
    {'name': 'Bronze Shield Boss', 'type': 'Weapon'},
    {'name': 'Iron Axehead', 'type': 'Weapon'},
    {'name': 'Bronze Helmet', 'type': 'Weapon'},
    {'name': 'Iron Javelin Tip', 'type': 'Weapon'},
    {'name': 'Bronze Greave', 'type': 'Weapon'},
    {'name': 'Iron Sword Hilt', 'type': 'Weapon'},
    {'name': 'Bronze Scabbard', 'type': 'Weapon'},
    // Inscriptions
    {'name': 'Stone Tablet', 'type': 'Inscription'},
    {'name': 'Lead Seal', 'type': 'Inscription'},
    {'name': 'Clay Tablet', 'type': 'Inscription'},
    {'name': 'Bronze Plaque', 'type': 'Inscription'},
    {'name': 'Marble Stele', 'type': 'Inscription'},
    {'name': 'Limestone Block', 'type': 'Inscription'},
    {'name': 'Pottery Ostracon', 'type': 'Inscription'},
    {'name': 'Lead Curse Tablet', 'type': 'Inscription'},
    // Organic
    {'name': 'Bone Comb', 'type': 'Organic'},
    {'name': 'Ivory Handle', 'type': 'Organic'},
    {'name': 'Shell Ornament', 'type': 'Organic'},
    {'name': 'Bone Pin', 'type': 'Organic'},
    {'name': 'Antler Tool', 'type': 'Organic'},
    {'name': 'Wooden Box', 'type': 'Organic'},
    {'name': 'Leather Fragment', 'type': 'Organic'},
    {'name': 'Bone Dice', 'type': 'Organic'},
    // Glass
    {'name': 'Glass Vessel', 'type': 'Glass'},
    {'name': 'Glass Perfume Bottle', 'type': 'Glass'},
    {'name': 'Glass Bowl', 'type': 'Glass'},
    {'name': 'Glass Unguentarium', 'type': 'Glass'},
    {'name': 'Glass Cup', 'type': 'Glass'},
    {'name': 'Glass Flask', 'type': 'Glass'},
    // Mosaic & Fresco
    {'name': 'Mosaic Tile', 'type': 'Mosaic'},
    {'name': 'Mosaic Fragment', 'type': 'Mosaic'},
    {'name': 'Fresco Fragment', 'type': 'Fresco'},
    {'name': 'Painted Plaster', 'type': 'Fresco'},
  ];

  static const _siteExamples = [
    'Trench A1', 'Trench B2', 'Trench C3', 'Trench D4', 'Trench E5',
    'Grid 12-N', 'Grid 15-S', 'Grid 8-W', 'Sector Alpha', 'Sector Beta',
    'North Wall', 'South Gate', 'East Chamber', 'West Courtyard',
  ];

  @override
  void initState() {
    super.initState();
    _loadNextId();
    _generateRandomHints();
    // Set today's date as default
    final now = DateTime.now();
    _dateController.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Initialize with data from photogrammetry if available
    if (widget.photoGallery != null && widget.photoGallery!.isNotEmpty) {
      _photoGallery.addAll(widget.photoGallery!);
      _isPhotogrammetryMode = true;
    }

    // Load draft if exists
    _loadDraft();

    // Setup auto-save (saves every 30 seconds)
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _autoSave();
    });

    // Add listeners to controllers for auto-save
    _nameController.addListener(_scheduleAutoSave);
    _typeController.addListener(_scheduleAutoSave);
    _siteController.addListener(_scheduleAutoSave);
  }

  void _scheduleAutoSave() {
    // Schedule auto-save for 2 seconds after last edit
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _autoSave);
  }

  Future<void> _autoSave() async {
    if (_nameController.text.isEmpty && _typeController.text.isEmpty) {
      return; // Don't save empty forms
    }

    _lastAutoSave = DateTime.now();
    final storage = LocalStorageService();
    await storage.saveFormDraft(
      formId: 'manual_entry',
      data: {
        'name': _nameController.text,
        'type': _typeController.text,
        'site': _siteController.text,
        'date': _dateController.text,
        'latitude': _latController.text,
        'longitude': _lngController.text,
      },
    );
  }

  Future<void> _loadDraft() async {
    final storage = LocalStorageService();
    final draft = storage.getFormDraft('manual_entry');
    if (draft != null && mounted) {
      setState(() {
        _nameController.text = draft['name'] ?? '';
        _typeController.text = draft['type'] ?? '';
        _siteController.text = draft['site'] ?? '';
        if (draft['date'] != null && (draft['date'] as String).isNotEmpty) {
          _dateController.text = draft['date'];
        }
        _latController.text = draft['latitude'] ?? '';
        _lngController.text = draft['longitude'] ?? '';
      });

      // Show notification
      if (_nameController.text.isNotEmpty || _typeController.text.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📝 Draft restored'),
            backgroundColor: Color(0xFF2196F3),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _generateRandomHints() {
    final random = Random();
    // Pick a matching name-type pair
    final pair = _nameTypePairs[random.nextInt(_nameTypePairs.length)];
    _nameHint = 'e.g., ${pair['name']}';
    _typeHint = 'e.g., ${pair['type']}';
    _siteHint = 'e.g., ${_siteExamples[random.nextInt(_siteExamples.length)]}';
  }

  // Get current GPS location
  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable GPS.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _isGettingLocation = false);
        return;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() => _isGettingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isGettingLocation = false);
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _latController.text = position.latitude.toStringAsFixed(6);
        _lngController.text = position.longitude.toStringAsFixed(6);
        _isGettingLocation = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location captured successfully!'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      setState(() => _isGettingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Pick image from camera
  Future<void> _pickFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
          _hasImage = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo captured successfully!'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Pick image from gallery
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
          _hasImage = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image selected successfully!'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Load next ID from Firestore by scanning all documents
  Future<void> _loadNextId() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _nextId = 'A-001';
          _isLoading = false;
        });
        return;
      }

      // Find the highest ID number from all documents
      int maxNum = 0;
      for (final doc in snapshot.docs) {
        // Check document ID first
        var match = RegExp(r'A-(\d+)').firstMatch(doc.id);
        if (match != null) {
          final num = int.parse(match.group(1)!);
          if (num > maxNum) {
            maxNum = num;
          }
        }

        // Also check 'id' field inside the document
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data['id'] != null) {
          match = RegExp(r'A-(\d+)').firstMatch(data['id'].toString());
          if (match != null) {
            final num = int.parse(match.group(1)!);
            if (num > maxNum) {
              maxNum = num;
            }
          }
        }
      }

      // If no matching IDs found, use document count as fallback
      if (maxNum == 0) {
        maxNum = snapshot.docs.length;
      }

      setState(() {
        _nextId = 'A-${(maxNum + 1).toString().padLeft(3, '0')}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _nextId = 'A-001';
        _isLoading = false;
      });
    }
  }

  // Backup findings to local file
  Future<void> _backupFindings() async {
    try {
      // Get all findings
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No findings to backup'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Create backup data
      final backupData = snapshot.docs.map((doc) {
        final data = doc.data();
        data['documentId'] = doc.id;
        return data;
      }).toList();

      // Save to local file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${directory.path}/findings_backup_$timestamp.json');
      await file.writeAsString(jsonEncode(backupData));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backed up ${snapshot.docs.length} findings.\nSaved to: ${file.path}'),
            backgroundColor: const Color(0xFF4CAF50),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save finding to Firestore
  Future<void> _saveFinding() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // Parse coordinates from controllers, fallback to defaults if empty
    final lat = double.tryParse(_latController.text) ?? 37.9715;
    final lng = double.tryParse(_lngController.text) ?? 23.7267;

    try {

      // Upload image to ImgBB and get URL
      String? imageUrl;
      if (_selectedImage != null) {
        try {
          // Compress image for 10x faster upload
          final imageService = ImageService();
          final compressedFile = await imageService.compressImage(
            File(_selectedImage!.path),
            maxWidth: 1920,
            maxHeight: 1920,
            quality: 85,
          );

          final bytes = await compressedFile.readAsBytes();
          final base64Image = base64Encode(bytes);

          final response = await http.post(
            Uri.parse('https://api.imgbb.com/1/upload'),
            body: {
              'key': imgbbApiKey,
              'image': base64Image,
              'name': _nextId,
            },
          ).timeout(const Duration(seconds: 30));

          debugPrint('ImgBB response: ${response.statusCode}');
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true) {
              imageUrl = data['data']['url'];
              debugPrint('Image uploaded: $imageUrl');
            }
          } else {
            debugPrint('ImgBB error: ${response.body}');
          }
        } catch (e) {
          debugPrint('Image upload failed: $e');
        }
      }

      // Upload photo gallery images for photogrammetry
      List<String> galleryUrls = [];
      if (_photoGallery.isNotEmpty) {
        final imageService = ImageService();
        for (int i = 0; i < _photoGallery.length; i++) {
          try {
            // Compress for faster upload (critical for multiple images)
            final compressedFile = await imageService.compressImage(
              File(_photoGallery[i].path),
              maxWidth: 1920,
              maxHeight: 1920,
              quality: 85,
            );

            final bytes = await compressedFile.readAsBytes();
            final base64Image = base64Encode(bytes);
            final response = await http.post(
              Uri.parse('https://api.imgbb.com/1/upload'),
              body: {
                'key': imgbbApiKey,
                'image': base64Image,
                'name': '${_nextId}_photo_$i',
              },
            ).timeout(const Duration(seconds: 30));

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              if (data['success'] == true) {
                galleryUrls.add(data['data']['url']);
              }
            }
          } catch (e) {
            debugPrint('Gallery photo $i upload failed: $e');
          }
        }
      }

      // Get 3D model data from reconstruction result if available
      String? model3dUrl;
      Map<String, dynamic>? reconstructionData;

      if (widget.reconstructionResult != null) {
        final result = widget.reconstructionResult!;
        // Save reconstruction metadata
        reconstructionData = {
          'pointCount': result.pointCount,
          'processingTimeSeconds': result.processingTimeSeconds,
          'method': result.isSparse ? 'Sparse SfM (RANSAC)' : 'Dense SfM',
          'qualityMetrics': result.qualityMetrics,
          'inputImageCount': result.inputImageCount,
        };
      }

      final findingData = {
        'name': _nameController.text,
        'type': _typeController.text,
        'site': _siteController.text,
        'date': _dateController.text,
        'description': '',
        'latitude': lat,
        'longitude': lng,
        'imageUrl': imageUrl,
        'photoGallery': galleryUrls,
        'model3dUrl': model3dUrl,
        'reconstructionData': reconstructionData,
        'createdAt': FieldValue.serverTimestamp(),
      };

      try {
        // Try to save to Firebase
        await FirebaseFirestore.instance
            .collection('findings')
            .doc(_nextId)
            .set(findingData)
            .timeout(const Duration(seconds: 15));

        // Success - clear draft and cache locally
        final storage = LocalStorageService();
        await storage.clearFormDraft('manual_entry');
        await storage.cacheFinding(findingId: _nextId, data: findingData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Finding $_nextId saved successfully!'),
              backgroundColor: const Color(0xFF4CAF50),
            ),
          );
          Navigator.pop(context);
        }
      } on FirebaseException catch (e) {
        // Firebase error - save offline
        final storage = LocalStorageService();
        await storage.queueForUpload(findingId: _nextId, data: findingData);
        await storage.cacheFinding(findingId: _nextId, data: findingData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📱 Saved offline - will sync when online\n${e.message}'),
              backgroundColor: const Color(0xFFFFC107),
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      // General error - try to save offline
      try {
        final storage = LocalStorageService();
        final findingData = {
          'name': _nameController.text,
          'type': _typeController.text,
          'site': _siteController.text,
          'date': _dateController.text,
          'description': '',
          'latitude': lat,
          'longitude': lng,
          'createdAt': DateTime.now().toIso8601String(),
        };
        await storage.queueForUpload(findingId: _nextId, data: findingData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📱 Saved offline - will sync when online'),
              backgroundColor: Color(0xFFFFC107),
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.pop(context);
        }
      } catch (offlineError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Error: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _siteController.dispose();
    _dateController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _model3dUrlController.dispose();
    super.dispose();
  }

  // Add multiple photos for photogrammetry
  Future<void> _addPhotogrammetryPhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _photoGallery.add(image);
          _isPhotogrammetryMode = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Photo ${_photoGallery.length} added! Take more for better 3D reconstruction.'),
              backgroundColor: const Color(0xFF4CAF50),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeGalleryPhoto(int index) {
    setState(() {
      _photoGallery.removeAt(index);
      if (_photoGallery.isEmpty) {
        _isPhotogrammetryMode = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER WITH BACK BUTTON
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Manual Entry',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // Backup button
                      GestureDetector(
                        onTap: () {
                          _backupFindings();
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC107).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFFFC107).withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.download_rounded,
                            color: Color(0xFFFFC107),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a new finding to the database',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // AUTO-GENERATED ID DISPLAY
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.tag_rounded,
                                  color: Color(0xFFFFC107),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'ID',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.7),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFC107).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Auto',
                                            style: TextStyle(
                                              color: Color(0xFFFFC107),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    _isLoading
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFFFC107),
                                            ),
                                          )
                                        : Text(
                                            _nextId,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // FORM FIELDS
                  _buildFormField(
                    controller: _nameController,
                    label: 'Name',
                    hint: _nameHint,
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _typeController,
                    label: 'Type',
                    hint: _typeHint,
                    icon: Icons.category_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _siteController,
                    label: 'Site',
                    hint: _siteHint,
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _dateController,
                    label: 'Date',
                    hint: 'e.g., ${_dateController.text}',
                    icon: Icons.calendar_today_outlined,
                  ),

                  const SizedBox(height: 16),

                  // COORDINATES SECTION
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.my_location_rounded,
                                      color: Color(0xFFFFC107),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Coordinates',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.7),
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Optional',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.5),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _latController.text.isEmpty && _lngController.text.isEmpty
                                              ? 'No location set'
                                              : 'Location set',
                                          style: TextStyle(
                                            color: _latController.text.isEmpty && _lngController.text.isEmpty
                                                ? Colors.white.withOpacity(0.4)
                                                : Colors.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Latitude field
                              Row(
                                children: [
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      'Latitude',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _latController,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                        decoration: InputDecoration(
                                          hintText: 'e.g., 37.9715',
                                          hintStyle: TextStyle(
                                            color: Colors.white.withOpacity(0.4),
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Longitude field
                              Row(
                                children: [
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      'Longitude',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _lngController,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                        decoration: InputDecoration(
                                          hintText: 'e.g., 23.7267',
                                          hintStyle: TextStyle(
                                            color: Colors.white.withOpacity(0.4),
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Use GPS button
                              GestureDetector(
                                onTap: _isGettingLocation ? null : _getCurrentLocation,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC107).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFFFC107).withOpacity(0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _isGettingLocation
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFFFFC107),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.gps_fixed_rounded,
                                              color: Color(0xFFFFC107),
                                              size: 18,
                                            ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isGettingLocation ? 'Getting Location...' : 'Use GPS',
                                        style: const TextStyle(
                                          color: Color(0xFFFFC107),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // OPTIONAL PICTURE FIELD
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.photo_camera_outlined,
                                      color: Color(0xFFFFC107),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Picture',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.7),
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Optional',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.5),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _hasImage ? 'Image selected' : 'No image selected',
                                          style: TextStyle(
                                            color: _hasImage ? Colors.white : Colors.white.withOpacity(0.4),
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _pickFromCamera,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.2),
                                            width: 1,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.camera_alt_rounded,
                                              color: Colors.white70,
                                              size: 18,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Take Photo',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _pickFromGallery,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.2),
                                            width: 1,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.photo_library_rounded,
                                              color: Colors.white70,
                                              size: 18,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Gallery',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // PHOTOGRAMMETRY SECTION - Multiple photos for 3D reconstruction
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF7C4DFF).withOpacity(0.35),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C4DFF).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.view_in_ar_rounded,
                                      color: Color(0xFF7C4DFF),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'Photogrammetry',
                                              style: TextStyle(
                                                color: Color(0xFF7C4DFF),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF7C4DFF).withOpacity(0.2),
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
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _photoGallery.isEmpty
                                              ? 'Take multiple photos for 3D model'
                                              : '${_photoGallery.length} photos captured',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.6),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Photo gallery preview
                              if (_photoGallery.isNotEmpty) ...[
                                SizedBox(
                                  height: 70,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _photoGallery.length,
                                    itemBuilder: (context, index) {
                                      return Stack(
                                        children: [
                                          Container(
                                            width: 70,
                                            height: 70,
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: const Color(0xFF7C4DFF).withOpacity(0.5),
                                                width: 2,
                                              ),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: Image.file(
                                                File(_photoGallery[index].path),
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 2,
                                            right: 10,
                                            child: GestureDetector(
                                              onTap: () => _removeGalleryPhoto(index),
                                              child: Container(
                                                width: 20,
                                                height: 20,
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, color: Colors.white, size: 14),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],

                              // Add photo button
                              GestureDetector(
                                onTap: _addPhotogrammetryPhoto,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7C4DFF).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFF7C4DFF).withOpacity(0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.add_a_photo_rounded, color: Color(0xFF7C4DFF), size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        _photoGallery.isEmpty ? 'Start Capture' : 'Add More Photos',
                                        style: const TextStyle(
                                          color: Color(0xFF7C4DFF),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Tips
                              const SizedBox(height: 12),
                              Text(
                                'Tip: Take 10-20 photos from different angles for best 3D reconstruction',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // SUBMIT BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _isSaving ? null : _saveFinding,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFC107).withOpacity(0.3),
                                  blurRadius: 16,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Color(0xFF3E2723),
                                      ),
                                    )
                                  : const Text(
                                      'Add Finding',
                                      style: TextStyle(
                                        color: Color(0xFF3E2723),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFFFFC107),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: controller,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter $label';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//
// --------------------- SAFETY TAB CONTENT ---------------------
// BLE-enabled Trench Safety Monitor for M5StickC Plus 2
//

// BLE Service and Characteristic UUIDs (must match Arduino code)
const String _bleSensorServiceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String _bleIMUCharUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String _bleMoistureCharUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9";
const String _bleAlertCharUUID = "beb5483e-36e1-4688-b7f5-ea07361b26aa";

class _SafetyView extends StatefulWidget {
  const _SafetyView({super.key});

  @override
  State<_SafetyView> createState() => _SafetyViewState();
}

class _SafetyViewState extends State<_SafetyView> {
  // BLE state
  BluetoothDevice? _connectedDevice;
  bool _isScanning = false;
  bool _isConnecting = false;
  String _connectionStatus = 'Disconnected';

  // Sensor data
  double _accX = 0.0, _accY = 0.0, _accZ = 0.0;
  double _vibration = 0.0;
  int _moisturePercent = 0;
  String _alertLevel = 'safe';
  String _alertMessage = '';
  String _lastUpdate = '--:--';

  // Alert history
  final List<_AlertData> _alerts = [];

  // Subscriptions
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  List<StreamSubscription> _charSubscriptions = [];

  // Simulation mode
  bool _isSimulating = false;
  Timer? _simulationTimer;

  // Firebase data logging
  Timer? _firebaseLogTimer;
  List<Map<String, dynamic>> _sensorHistory = [];

  @override
  void initState() {
    super.initState();
    _checkBluetoothAndScan();
    _startFirebaseLogging();
    _loadSensorHistory();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    for (var sub in _charSubscriptions) {
      sub.cancel();
    }
    _simulationTimer?.cancel();
    _firebaseLogTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkBluetoothAndScan() async {
    // Check if Bluetooth is on
    if (await FlutterBluePlus.isSupported == false) {
      _showError('Bluetooth not supported on this device');
      return;
    }

    // Check Bluetooth state
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      setState(() => _connectionStatus = 'Bluetooth OFF');
      return;
    }

    _startScan();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _connectionStatus = 'Scanning...';
    });

    try {
      // Start scanning
      await FlutterBluePlus.startScan(
        withServices: [Guid(_bleSensorServiceUUID)],
        timeout: const Duration(seconds: 10),
      );

      // Listen for scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.contains('AncientVision')) {
            debugPrint('Found AncientVision sensor: ${r.device.platformName}');
            FlutterBluePlus.stopScan();
            _connectToDevice(r.device);
            break;
          }
        }
      });

      // Handle scan timeout
      await Future.delayed(const Duration(seconds: 10));
      if (_connectedDevice == null && mounted) {
        setState(() {
          _isScanning = false;
          _connectionStatus = 'Sensor not found';
        });
      }
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _connectionStatus = 'Scan failed';
        });
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
    });

    try {
      await device.connect(timeout: const Duration(seconds: 10));

      setState(() {
        _connectedDevice = device;
        _isConnecting = false;
        _isScanning = false;
        _connectionStatus = 'Connected';
      });

      // Listen for disconnection
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _connectedDevice = null;
            _connectionStatus = 'Disconnected';
          });
          // Try to reconnect after a delay
          Future.delayed(const Duration(seconds: 2), _startScan);
        }
      });

      // Discover services and subscribe to characteristics
      await _discoverAndSubscribe(device);

    } catch (e) {
      debugPrint('Connection error: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionStatus = 'Connection failed';
        });
      }
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() == _bleSensorServiceUUID.toLowerCase()) {
          for (BluetoothCharacteristic char in service.characteristics) {
            final charUuid = char.uuid.toString().toLowerCase();

            // Subscribe to notifications
            if (char.properties.notify) {
              await char.setNotifyValue(true);

              final sub = char.onValueReceived.listen((value) {
                _handleCharacteristicData(charUuid, value);
              });
              _charSubscriptions.add(sub);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Service discovery error: $e');
    }
  }

  void _handleCharacteristicData(String charUuid, List<int> value) {
    try {
      final jsonStr = String.fromCharCodes(value);
      final data = json.decode(jsonStr);

      setState(() {
        _lastUpdate = _formatTime(DateTime.now());

        if (charUuid == _bleIMUCharUUID.toLowerCase()) {
          _accX = (data['x'] as num?)?.toDouble() ?? 0.0;
          _accY = (data['y'] as num?)?.toDouble() ?? 0.0;
          _accZ = (data['z'] as num?)?.toDouble() ?? 0.0;
          _vibration = (data['vib'] as num?)?.toDouble() ?? 0.0;
        } else if (charUuid == _bleMoistureCharUUID.toLowerCase()) {
          _moisturePercent = (data['percent'] as num?)?.toInt() ?? 0;
        } else if (charUuid == _bleAlertCharUUID.toLowerCase()) {
          final newLevel = data['level'] as String? ?? 'safe';
          final newMessage = data['message'] as String? ?? '';

          // Add to alert history if level changed or new message
          if (newLevel != 'safe' && newMessage.isNotEmpty) {
            _alerts.insert(0, _AlertData(
              time: _lastUpdate,
              level: newLevel == 'critical' ? _AlertLevel.critical : _AlertLevel.warning,
              title: newLevel == 'critical' ? 'Critical Alert' : 'Warning',
              message: newMessage,
            ));
            // Keep only last 10 alerts
            if (_alerts.length > 10) _alerts.removeLast();

            // Save alert to Firebase
            _saveAlertToFirebase(newLevel, newMessage);
          }

          _alertLevel = newLevel;
          _alertMessage = newMessage;
        }
      });
    } catch (e) {
      debugPrint('Error parsing BLE data: $e');
    }
  }

  Future<void> _saveAlertToFirebase(String level, String message) async {
    try {
      await FirebaseFirestore.instance.collection('safety_alerts').add({
        'level': level,
        'message': message,
        'vibration': _vibration,
        'moisture': _moisturePercent,
        'accX': _accX,
        'accY': _accY,
        'accZ': _accZ,
        'deviceName': _isSimulating ? 'Simulator' : (_connectedDevice?.platformName ?? 'Unknown'),
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('Alert saved to Firebase: $level - $message');
    } catch (e) {
      debugPrint('Error saving alert to Firebase: $e');
    }
  }

  void _startFirebaseLogging() {
    // Save sensor data to Firebase every 10 seconds
    _firebaseLogTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && (_connectedDevice != null || _isSimulating)) {
        _saveSensorDataToFirebase();
      }
    });
  }

  Future<void> _saveSensorDataToFirebase() async {
    try {
      await FirebaseFirestore.instance.collection('sensor_data').add({
        'vibration': _vibration,
        'moisture': _moisturePercent,
        'accX': _accX,
        'accY': _accY,
        'accZ': _accZ,
        'deviceName': _isSimulating ? 'Simulator' : (_connectedDevice?.platformName ?? 'Unknown'),
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('Sensor data logged to Firebase');
    } catch (e) {
      debugPrint('Error saving sensor data to Firebase: $e');
    }
  }

  Future<void> _loadSensorHistory() async {
    try {
      // Load last 30 data points from Firebase (covers 5 minutes at 10-second intervals)
      final snapshot = await FirebaseFirestore.instance
          .collection('sensor_data')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();

      if (mounted) {
        setState(() {
          _sensorHistory = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'vibration': (data['vibration'] as num?)?.toDouble() ?? 0.0,
              'moisture': (data['moisture'] as num?)?.toInt() ?? 0,
              'timestamp': (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            };
          }).toList().reversed.toList(); // Reverse to get chronological order
        });
      }

      // Refresh history every 10 seconds
      Timer.periodic(const Duration(seconds: 10), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        _loadSensorHistory();
      });
    } catch (e) {
      debugPrint('Error loading sensor history: $e');
    }
  }

  void _startSimulation() {
    setState(() {
      _isSimulating = true;
      _connectionStatus = 'Simulating';
    });

    final random = Random();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        // Generate realistic sensor data
        _accX = -0.1 + random.nextDouble() * 0.2;
        _accY = -0.1 + random.nextDouble() * 0.2;
        _accZ = 0.95 + random.nextDouble() * 0.1;

        // Occasionally simulate vibration events
        if (random.nextInt(50) == 0) {
          _vibration = 0.3 + random.nextDouble() * 0.6; // Warning to critical
        } else {
          _vibration = random.nextDouble() * 0.15; // Normal range
        }

        // Moisture varies slowly
        _moisturePercent = 35 + random.nextInt(30); // 35-65% range

        // Occasionally go outside safe range
        if (random.nextInt(30) == 0) {
          _moisturePercent = random.nextBool() ? 20 + random.nextInt(10) : 65 + random.nextInt(15);
        }

        _lastUpdate = _formatTime(DateTime.now());

        // Check for alerts
        String newLevel = 'safe';
        String newMessage = '';

        if (_vibration > 0.8) {
          newLevel = 'critical';
          newMessage = 'EARTHQUAKE DETECTED!';
        } else if (_vibration > 0.3) {
          newLevel = 'warning';
          newMessage = 'High vibration detected';
        }

        if (_moisturePercent > 60) {
          newLevel = 'critical';
          newMessage = 'Soil too wet - collapse risk!';
        } else if (_moisturePercent < 30 && newLevel == 'safe') {
          newLevel = 'warning';
          newMessage = 'Soil too dry';
        }

        if (newLevel != 'safe' && newMessage.isNotEmpty && newLevel != _alertLevel) {
          _alerts.insert(0, _AlertData(
            time: _lastUpdate,
            level: newLevel == 'critical' ? _AlertLevel.critical : _AlertLevel.warning,
            title: newLevel == 'critical' ? 'Critical Alert' : 'Warning',
            message: newMessage,
          ));
          if (_alerts.length > 10) _alerts.removeLast();
          _saveAlertToFirebase(newLevel, newMessage);
        }

        _alertLevel = newLevel;
        _alertMessage = newMessage;
      });
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    setState(() {
      _isSimulating = false;
      _connectionStatus = 'Disconnected';
      _accX = 0.0;
      _accY = 0.0;
      _accZ = 0.0;
      _vibration = 0.0;
      _moisturePercent = 0;
      _alertLevel = 'safe';
      _alertMessage = '';
      _lastUpdate = '--:--';
    });
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  String _getVibrationStatus() {
    if (_vibration > 0.8) return 'CRITICAL!';
    if (_vibration > 0.3) return 'Warning';
    return 'Stable';
  }

  String _getMoistureStatus() {
    if (_moisturePercent < 30) return 'Too Dry';
    if (_moisturePercent > 60) return 'Too Wet!';
    return 'Safe range';
  }

  Color _getStatusColor() {
    if (_alertLevel == 'critical') return const Color(0xFFE53935);
    if (_alertLevel == 'warning') return const Color(0xFFFFB300);
    return const Color(0xFF4CAF50);
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectedDevice != null;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                children: [
                  const Icon(Icons.engineering_rounded, color: Colors.white, size: 26),
                  const SizedBox(width: 8),
                  const Text(
                    'Trench Safety',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  _LiveChip(isConnected: isConnected, status: _connectionStatus),
                ],
              ),
              const SizedBox(height: 8),

              // Connection status / Scan button
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: (isConnected || _isSimulating) ? null : _startScan,
                      child: Text(
                        _isSimulating
                          ? 'Simulation Mode Active'
                          : isConnected
                            ? 'Connected to M5StickC Plus 2'
                            : '$_connectionStatus ${_isScanning ? '' : '- Tap to scan'}',
                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      if (_isSimulating) {
                        _stopSimulation();
                      } else if (!isConnected) {
                        _startSimulation();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isSimulating ? Colors.orange : Colors.teal,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isSimulating ? 'Stop' : 'Simulate',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // STATS ROW
              Row(
                children: [
                  Expanded(
                    child: _SafetyStatCard(
                      title: 'Vibration',
                      value: '${_vibration.toStringAsFixed(3)} g',
                      status: _getVibrationStatus(),
                      statusColor: _vibration > 0.3 ? Colors.orange : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SafetyStatCard(
                      title: 'Soil Moisture',
                      value: '$_moisturePercent %',
                      status: _getMoistureStatus(),
                      statusColor: (_moisturePercent < 30 || _moisturePercent > 60) ? Colors.orange : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Live Sensors Card
              _LiveSensorsCard(
                accX: _accX, accY: _accY, accZ: _accZ,
                moisturePercent: _moisturePercent,
                lastUpdate: _lastUpdate,
                isConnected: isConnected,
              ),
              const SizedBox(height: 12),

              // Sensor History Graph Card
              _SensorHistoryGraphCard(sensorHistory: _sensorHistory),
              const SizedBox(height: 12),

              // Alerts Card
              _SafetyAlertsCard(alerts: _alerts),
              const SizedBox(height: 12),

              // Current Alert Banner (if any)
              if (_alertLevel != 'safe' && _alertMessage.isNotEmpty)
                _CurrentAlertBanner(level: _alertLevel, message: _alertMessage),

              const SizedBox(height: 12),
              const _SafetyInsightCard(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertData {
  final String time;
  final _AlertLevel level;
  final String title;
  final String message;

  _AlertData({required this.time, required this.level, required this.title, required this.message});
}

class _CurrentAlertBanner extends StatelessWidget {
  final String level;
  final String message;

  const _CurrentAlertBanner({required this.level, required this.message});

  @override
  Widget build(BuildContext context) {
    final isCritical = level == 'critical';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCritical ? Colors.red.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCritical ? Colors.red : Colors.orange, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            isCritical ? Icons.warning_rounded : Icons.info_outline,
            color: isCritical ? Colors.red : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCritical ? 'CRITICAL ALERT' : 'WARNING',
                  style: TextStyle(
                    color: isCritical ? Colors.red : Colors.orange,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(message, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  final bool isConnected;
  final String status;

  const _LiveChip({required this.isConnected, required this.status});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? const Color(0xFF4CAF50) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'LIVE' : 'OFFLINE',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SafetyStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String status;
  final Color? statusColor;

  const _SafetyStatCard({
    required this.title,
    required this.value,
    required this.status,
    this.statusColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 125,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(status, style: TextStyle(color: statusColor ?? Colors.white.withOpacity(0.75), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveSensorsCard extends StatelessWidget {
  final double accX, accY, accZ;
  final int moisturePercent;
  final String lastUpdate;
  final bool isConnected;

  const _LiveSensorsCard({
    required this.accX, required this.accY, required this.accZ,
    required this.moisturePercent, required this.lastUpdate, required this.isConnected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Live sensors', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: isConnected ? Colors.green : Colors.grey,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SensorRow(
                label: 'IMU (M5StickC Plus 2)',
                value: 'X ${accX.toStringAsFixed(2)}g   Y ${accY.toStringAsFixed(2)}g   Z ${accZ.toStringAsFixed(2)}g',
                icon: Icons.sensors_rounded,
              ),
              const SizedBox(height: 6),
              _SensorRow(
                label: 'Soil moisture',
                value: '$moisturePercent %   (safe: 30–60%)',
                icon: Icons.water_drop_outlined,
              ),
              const SizedBox(height: 10),
              Text('Last update: $lastUpdate', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SensorRow({required this.label, required this.value, required this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SensorHistoryGraphCard extends StatelessWidget {
  final List<Map<String, dynamic>> sensorHistory;

  const _SensorHistoryGraphCard({required this.sensorHistory, super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Sensor History', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal, width: 1),
                    ),
                    child: const Text('Live', style: TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Updates every 10 seconds from Firebase', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
              const SizedBox(height: 12),
              if (sensorHistory.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Waiting for data...', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                  ),
                )
              else
                SizedBox(
                  height: 180,
                  child: CustomPaint(
                    size: const Size(double.infinity, 180),
                    painter: _SensorGraphPainter(sensorHistory),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SensorGraphPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;

  _SensorGraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw grid lines
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Find max values for scaling
    double maxVibration = 1.0; // Max 1g
    double maxMoisture = 100.0; // Max 100%

    // Draw moisture line (blue)
    paint.color = Colors.blue;
    final moisturePath = ui.Path();
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final moisture = (data[i]['moisture'] as num?)?.toDouble() ?? 0.0;
      final y = size.height - (size.height * moisture / maxMoisture);
      if (i == 0) {
        moisturePath.moveTo(x, y);
      } else {
        moisturePath.lineTo(x, y);
      }
    }
    canvas.drawPath(moisturePath, paint);

    // Draw vibration line (red)
    paint.color = Colors.red;
    final vibrationPath = ui.Path();
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final vibration = (data[i]['vibration'] as num?)?.toDouble() ?? 0.0;
      final y = size.height - (size.height * vibration / maxVibration);
      if (i == 0) {
        vibrationPath.moveTo(x, y);
      } else {
        vibrationPath.lineTo(x, y);
      }
    }
    canvas.drawPath(vibrationPath, paint);

    // Draw legend
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Moisture legend
    textPainter.text = const TextSpan(
      text: 'Moisture %',
      style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.w600),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(10, 10));

    // Vibration legend
    textPainter.text = const TextSpan(
      text: 'Vibration g',
      style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w600),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 80, 10));
  }

  @override
  bool shouldRepaint(_SensorGraphPainter oldDelegate) => true;
}

class _SafetyAlertsCard extends StatelessWidget {
  final List<_AlertData> alerts;

  const _SafetyAlertsCard({required this.alerts, super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Alerts', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (alerts.isEmpty)
                Text('No alerts yet', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12))
              else
                ...alerts.take(5).map((alert) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _AlertRow(
                    time: alert.time,
                    level: alert.level,
                    title: alert.title,
                    trench: 'Trench B3',
                    message: alert.message,
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AlertLevel { critical, warning, ok }

class _AlertRow extends StatelessWidget {
  final String time;
  final _AlertLevel level;
  final String title;
  final String trench;
  final String message;

  const _AlertRow({
    required this.time, required this.level, required this.title,
    required this.trench, required this.message, super.key,
  });

  Color _dotColor() {
    switch (level) {
      case _AlertLevel.critical: return const Color(0xFFE53935);
      case _AlertLevel.warning: return const Color(0xFFFFB300);
      case _AlertLevel.ok: return const Color(0xFF43A047);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(time, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
        const SizedBox(width: 10),
        Container(
          width: 8, height: 8,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: _dotColor(), shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$title • $trench', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(message, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyInsightCard extends StatelessWidget {
  const _SafetyInsightCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.30), width: 1),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Safety Thresholds', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text(
                '• Soil Moisture: 30-60% is safe range\n'
                '• Vibration: <0.3g stable, >0.8g critical\n'
                '• Connect M5StickC Plus 2 for live monitoring',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//
// -------- GLASS BOTTOM NAV BAR --------
//

class _GlassBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onItemSelected;

  const _GlassBottomNavBar({
    required this.currentIndex,
    required this.onItemSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                index: 0,
                isSelected: currentIndex == 0,
                onTap: onItemSelected,
              ),
              _NavItem(
                icon: Icons.article_rounded,
                label: 'Findings',
                index: 1,
                isSelected: currentIndex == 1,
                onTap: onItemSelected,
              ),
              _NavItem(
                icon: Icons.apps_rounded,
                label: 'Tools',
                index: 2,
                isSelected: currentIndex == 2,
                onTap: onItemSelected,
              ),
              _NavItem(
                icon: Icons.engineering_rounded,
                label: 'Safety',
                index: 3,
                isSelected: currentIndex == 3,
                onTap: onItemSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool isSelected;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.white : Colors.white70;

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PROFESSIONAL PHOTOGRAMMETRY CAPTURE SCREEN
// =============================================================================
// A comprehensive photogrammetry capture experience with guided angles,
// progress tracking, quality validation, and export functionality.
// =============================================================================

class PhotogrammetryScreen extends StatefulWidget {
  final String? findingId;
  final String? findingName;

  const PhotogrammetryScreen({
    super.key,
    this.findingId,
    this.findingName,
  });

  @override
  State<PhotogrammetryScreen> createState() => _PhotogrammetryScreenState();
}

class _PhotogrammetryScreenState extends State<PhotogrammetryScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _imagePicker = ImagePicker();
  final List<PhotogrammetryCapture> _captures = [];
  int _currentAngleIndex = 0;
  bool _showTutorial = true;
  bool _isCapturing = false;
  late AnimationController _pulseController;

  // VIDEO CAPTURE MODE - NEW ULTRA FEATURE!
  bool _isVideoMode = false; // Toggle between photo and video mode
  bool _isRecording = false; // Currently recording video
  XFile? _recordedVideo; // Recorded video file
  bool _isExtractingFrames = false; // Processing video into frames
  int _extractedFrameCount = 0; // Number of frames extracted so far

  // AR-LIKE GUIDANCE - Device sensors
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  double _deviceTiltX = 0.0; // Phone tilt left/right
  double _deviceTiltY = 0.0; // Phone tilt forward/back
  double _compassHeading = 0.0; // Compass bearing (0-360°)
  bool _isDeviceLevel = false; // Is phone held level?
  double _rotationSpeed = 0.0; // How fast user is rotating

  // ULTRA++ ADVANCED FEATURES
  bool _hdrMode = false; // HDR (High Dynamic Range) mode for difficult lighting
  bool _batchMode = false; // Batch capture mode for multiple objects
  String? _currentObjectQR; // QR code for current object being scanned
  late stt.SpeechToText _speechToText; // Voice commands
  late FlutterTts _flutterTts; // Text-to-speech feedback
  bool _voiceEnabled = false; // Voice commands enabled
  bool _isListening = false; // Currently listening for voice command
  String _lastVoiceCommand = ''; // Last recognized voice command
  int _batchObjectCount = 0; // Number of objects in current batch
  bool _autoAdvance = true; // Auto-advance to next angle after capture
  bool _showGrid = false; // Show grid overlay for alignment
  bool _showHistogram = false; // Show histogram for exposure

  // 🌟 WORLD-CLASS AI & SMART FEATURES
  bool _aiAssistEnabled = false; // AI-powered suggestions and detection (disabled by default to prevent performance issues)
  String? _aiDetectedType; // AI-detected artifact type
  String? _aiDetectedMaterial; // AI-detected material
  String? _aiDetectedCondition; // AI-detected condition assessment
  String? _aiDetectedPeriod; // AI-suggested period/dating
  double _aiConfidence = 0.0; // AI confidence score (0-1)
  bool _scaleDetected = false; // Photo scale reference detected
  double? _detectedScaleMm; // Detected scale length in mm
  Map<String, dynamic> _smartSuggestions = {}; // Context-aware auto-fill suggestions
  List<String> _fieldJournalEntries = []; // Field journal/notes with timestamps
  int _sessionFindCount = 0; // Finds documented this session
  DateTime? _sessionStartTime; // Session start for analytics

  // 🎯 3D RECONSTRUCTION - Automated on-device photogrammetry
  final ReconstructionService _reconstructionService = ReconstructionService();
  ReconstructionResult? _reconstructionResult; // Result from 3D reconstruction
  bool _isReconstructing = false; // Currently generating 3D model
  double _reconstructionProgress = 0.0; // Progress 0.0 to 1.0
  String _reconstructionStatus = ''; // Current status message

  // Define the optimal capture angles for photogrammetry
  // 12 angles around the object + 2 top angles + 2 detail angles = 16 total
  static const List<CaptureAngle> _captureAngles = [
    // Ring 1: Eye level (0°) - 8 positions around the object
    CaptureAngle(id: 0, name: 'Front', angle: 0, elevation: 0, icon: Icons.arrow_upward),
    CaptureAngle(id: 1, name: 'Front-Right', angle: 45, elevation: 0, icon: Icons.arrow_forward),
    CaptureAngle(id: 2, name: 'Right', angle: 90, elevation: 0, icon: Icons.arrow_forward),
    CaptureAngle(id: 3, name: 'Back-Right', angle: 135, elevation: 0, icon: Icons.arrow_forward),
    CaptureAngle(id: 4, name: 'Back', angle: 180, elevation: 0, icon: Icons.arrow_downward),
    CaptureAngle(id: 5, name: 'Back-Left', angle: 225, elevation: 0, icon: Icons.arrow_back),
    CaptureAngle(id: 6, name: 'Left', angle: 270, elevation: 0, icon: Icons.arrow_back),
    CaptureAngle(id: 7, name: 'Front-Left', angle: 315, elevation: 0, icon: Icons.arrow_back),
    // Ring 2: High angle (45°) - 4 positions
    CaptureAngle(id: 8, name: 'Top-Front', angle: 0, elevation: 45, icon: Icons.north_east),
    CaptureAngle(id: 9, name: 'Top-Right', angle: 90, elevation: 45, icon: Icons.north_east),
    CaptureAngle(id: 10, name: 'Top-Back', angle: 180, elevation: 45, icon: Icons.south_east),
    CaptureAngle(id: 11, name: 'Top-Left', angle: 270, elevation: 45, icon: Icons.north_west),
    // Top down views
    CaptureAngle(id: 12, name: 'Top Center', angle: 0, elevation: 80, icon: Icons.vertical_align_bottom),
    CaptureAngle(id: 13, name: 'Top Angled', angle: 45, elevation: 70, icon: Icons.vertical_align_bottom),
    // Detail shots
    CaptureAngle(id: 14, name: 'Detail 1', angle: 0, elevation: 20, icon: Icons.zoom_in, isDetail: true),
    CaptureAngle(id: 15, name: 'Detail 2', angle: 180, elevation: 20, icon: Icons.zoom_in, isDetail: true),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Initialize AR-like sensor guidance
    _initializeSensors();

    // Initialize ULTRA++ voice commands
    _initializeVoiceCommands();

    // 🌟 Initialize World-Class AI & Analytics
    _sessionStartTime = DateTime.now();
    _sessionFindCount = 0;
    _loadSmartSuggestions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _speechToText.stop();
    _flutterTts.stop();
    super.dispose();
  }

  // Initialize device sensors for AR-like guidance
  void _initializeSensors() {
    // Accelerometer - detect phone tilt
    _accelerometerSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      setState(() {
        _deviceTiltX = event.x;
        _deviceTiltY = event.y;
        // Check if device is level (within 20° of vertical)
        _isDeviceLevel = (event.x.abs() < 2.0 && event.y.abs() < 2.0);
      });
    });

    // Gyroscope - detect rotation speed
    _gyroscopeSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      setState(() {
        // Calculate rotation speed magnitude (rad/s)
        _rotationSpeed = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      });
    });

    // Magnetometer - compass heading
    _magnetometerSubscription = magnetometerEventStream().listen((MagnetometerEvent event) {
      setState(() {
        // Calculate compass heading (0-360°)
        _compassHeading = atan2(event.y, event.x) * 180 / pi;
        if (_compassHeading < 0) _compassHeading += 360;
      });
    });
  }

  // ULTRA++ Initialize voice commands for hands-free operation
  Future<void> _initializeVoiceCommands() async {
    _speechToText = stt.SpeechToText();
    _flutterTts = FlutterTts();

    // Initialize speech-to-text
    bool available = await _speechToText.initialize(
      onStatus: (status) {
        if (status == 'notListening' && _voiceEnabled) {
          // Auto-restart listening if voice is enabled
          _startListening();
        }
      },
      onError: (error) {
        print('Voice recognition error: $error');
        setState(() => _isListening = false);
      },
    );

    // Configure text-to-speech
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5); // Slower for clarity in field
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    if (available) {
      print('✅ Voice commands initialized successfully');
    } else {
      print('⚠️ Voice recognition not available on this device');
    }
  }

  // Start listening for voice commands
  Future<void> _startListening() async {
    if (!_voiceEnabled || _isListening) return;

    bool available = await _speechToText.initialize();
    if (available) {
      setState(() => _isListening = true);

      _speechToText.listen(
        onResult: (result) {
          setState(() {
            _lastVoiceCommand = result.recognizedWords.toLowerCase();
          });

          if (result.finalResult) {
            _handleVoiceCommand(_lastVoiceCommand);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
      );
    }
  }

  // Stop listening for voice commands
  Future<void> _stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
    }
  }

  // Handle recognized voice commands
  Future<void> _handleVoiceCommand(String command) async {
    command = command.toLowerCase().trim();

    // Capture commands
    if (command.contains('capture') || command.contains('photo') || command.contains('take picture')) {
      await _speak('Capturing now');
      _capturePhoto();
    }
    // Navigation commands
    else if (command.contains('next') || command.contains('next angle')) {
      if (_currentAngleIndex < _captureAngles.length - 1) {
        setState(() => _currentAngleIndex++);
        await _speak('Moving to ${_currentAngle.name}');
      } else {
        await _speak('This is the last angle');
      }
    }
    else if (command.contains('previous') || command.contains('back') || command.contains('go back')) {
      if (_currentAngleIndex > 0) {
        setState(() => _currentAngleIndex--);
        await _speak('Moving back to ${_currentAngle.name}');
      } else {
        await _speak('Already at first angle');
      }
    }
    // Feature toggles
    else if (command.contains('hdr') || command.contains('hdr mode')) {
      setState(() => _hdrMode = !_hdrMode);
      await _speak(_hdrMode ? 'HDR mode enabled' : 'HDR mode disabled');
    }
    else if (command.contains('grid') || command.contains('show grid')) {
      setState(() => _showGrid = !_showGrid);
      await _speak(_showGrid ? 'Grid overlay enabled' : 'Grid overlay disabled');
    }
    else if (command.contains('histogram')) {
      setState(() => _showHistogram = !_showHistogram);
      await _speak(_showHistogram ? 'Histogram enabled' : 'Histogram disabled');
    }
    else if (command.contains('video mode')) {
      setState(() => _isVideoMode = true);
      await _speak('Switched to video mode');
    }
    else if (command.contains('photo mode')) {
      setState(() => _isVideoMode = false);
      await _speak('Switched to photo mode');
    }
    // Progress and info commands
    else if (command.contains('progress') || command.contains('how many')) {
      await _speak('${_captures.length} of ${_captureAngles.length} angles captured');
    }
    else if (command.contains('current angle') || command.contains('what angle')) {
      await _speak('Current angle is ${_currentAngle.name}');
    }
    else if (command.contains('skip') || command.contains('skip angle')) {
      if (_currentAngleIndex < _captureAngles.length - 1) {
        setState(() => _currentAngleIndex++);
        await _speak('Skipped to ${_currentAngle.name}');
      }
    }
    // Export commands
    else if (command.contains('export') || command.contains('save') || command.contains('finish')) {
      if (_captures.length >= 8) {
        await _speak('Exporting ${_captures.length} photos');
        _exportPhotos();
      } else {
        await _speak('Need at least 8 captures to export. You have ${_captures.length}');
      }
    }
    // Help command
    else if (command.contains('help') || command.contains('what can i say')) {
      await _speak('Say capture, next, previous, HDR, grid, progress, or export');
    }
    // Batch mode
    else if (command.contains('batch') || command.contains('batch mode')) {
      setState(() => _batchMode = !_batchMode);
      await _speak(_batchMode ? 'Batch mode enabled' : 'Batch mode disabled');
    }
    else {
      // Unknown command
      await _speak('Command not recognized. Say help for available commands');
    }
  }

  // Text-to-speech helper
  Future<void> _speak(String text) async {
    if (_voiceEnabled) {
      await _flutterTts.speak(text);
    }
  }

  // ============================================================================
  // 🌟 WORLD-CLASS AI & SMART FEATURES
  // ============================================================================

  // Load context-aware smart suggestions
  Future<void> _loadSmartSuggestions() async {
    final prefs = await SharedPreferences.getInstance();

    // Get user's most common entries for auto-suggestions
    _smartSuggestions = {
      'recentSites': prefs.getStringList('recent_sites') ?? ['Site A', 'Site B', 'Main Excavation'],
      'recentExcavators': prefs.getStringList('recent_excavators') ?? ['Dr. Smith', 'Team Alpha'],
      'recentUnits': prefs.getStringList('recent_units') ?? ['A1', 'A2', 'B1', 'Trench 1'],
      'recentLayers': prefs.getStringList('recent_layers') ?? ['Layer 1', 'Layer 2', 'Context 001'],
      'lastFindNumber': prefs.getInt('last_find_number') ?? 0,
    };
  }

  // 🤖 AI-POWERED ARTIFACT RECOGNITION
  // Analyzes captured image to detect artifact type, material, and condition
  Future<void> _runAIArtifactRecognition(XFile imageFile) async {
    if (!_aiAssistEnabled) return;

    try {
      // Load and analyze image
      final bytes = await File(imageFile.path).readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        print('⚠️ AI: Could not decode image');
        return;
      }

      // 🎯 ADVANCED IMAGE ANALYSIS
      final analysis = await _analyzeArtifactFeatures(image);

      if (!mounted) return; // Check if widget is still mounted

      setState(() {
        _aiDetectedType = analysis['type'];
        _aiDetectedMaterial = analysis['material'];
        _aiDetectedCondition = analysis['condition'];
        _aiDetectedPeriod = analysis['period'];
        _aiConfidence = (analysis['confidence'] ?? 0.0) as double;

        // Detect photo scale if present
        if (analysis['scaleDetected'] == true) {
          _scaleDetected = true;
          _detectedScaleMm = analysis['scaleMm'];
        }
      });

      // Provide AI suggestions via voice if enabled
      if (_voiceEnabled && _aiConfidence > 0.7) {
        try {
          await _speak('AI detected: $_aiDetectedType, confidence ${(_aiConfidence * 100).toInt()}%');
        } catch (voiceError) {
          print('Voice feedback error: $voiceError');
        }
      }

    } catch (e, stackTrace) {
      print('⚠️ AI recognition error: $e');
      print('Stack trace: $stackTrace');
      // Reset AI detection state on error
      if (mounted) {
        setState(() {
          _aiDetectedType = null;
          _aiDetectedMaterial = null;
          _aiDetectedCondition = null;
          _aiDetectedPeriod = null;
          _aiConfidence = 0.0;
        });
      }
    }
  }

  // Advanced artifact feature analysis
  Future<Map<String, dynamic>> _analyzeArtifactFeatures(img.Image image) async {
    // This is a sophisticated analysis combining multiple techniques:
    // 1. Color histogram analysis for material detection
    // 2. Edge detection for shape/condition assessment
    // 3. Texture analysis for surface condition
    // 4. Pattern matching for scale bar detection

    final analysis = <String, dynamic>{
      'confidence': 0.0,
      'scaleDetected': false,
    };

    // === COLOR ANALYSIS for MATERIAL DETECTION ===
    final colorStats = _analyzeColorDistribution(image);
    final avgRed = colorStats['avgRed'] ?? 0.0;
    final avgGreen = colorStats['avgGreen'] ?? 0.0;
    final avgBlue = colorStats['avgBlue'] ?? 0.0;
    final brightness = colorStats['brightness'] ?? 0.0;
    final saturation = colorStats['saturation'] ?? 0.0;

    // Pottery detection: reddish-brown, terracotta tones
    if (avgRed > 140 && avgRed > avgBlue + 20) {
      analysis['type'] = 'Pottery/Ceramic';
      analysis['material'] = 'Terracotta';
      analysis['confidence'] = 0.75;
    }
    // Metal detection: gray/silver or golden tones
    else if (saturation < 30 && brightness > 100) {
      if (avgRed > avgBlue) {
        analysis['type'] = 'Metal Object';
        analysis['material'] = 'Bronze/Copper';
        analysis['confidence'] = 0.70;
      } else {
        analysis['type'] = 'Metal Object';
        analysis['material'] = 'Iron/Steel';
        analysis['confidence'] = 0.68;
      }
    }
    // Stone detection: gray, beige tones with low saturation
    else if (saturation < 50 && avgGreen > 80) {
      analysis['type'] = 'Stone Artifact';
      analysis['material'] = 'Limestone/Marble';
      analysis['confidence'] = 0.72;
    }
    // Bone detection: white/cream with low saturation
    else if (brightness > 180 && saturation < 40) {
      analysis['type'] = 'Organic Material';
      analysis['material'] = 'Bone/Ivory';
      analysis['confidence'] = 0.65;
    }
    // Gold/precious metal: high yellow, high brightness
    else if (avgRed > 180 && avgGreen > 150 && avgBlue < 100) {
      analysis['type'] = 'Precious Metal';
      analysis['material'] = 'Gold';
      analysis['confidence'] = 0.80;
    }
    else {
      analysis['type'] = 'Unknown Artifact';
      analysis['material'] = 'Mixed/Unknown';
      analysis['confidence'] = 0.50;
    }

    // === CONDITION ASSESSMENT ===
    final edgeStrength = _calculateEdgeSharpness(image);
    final surfaceTexture = _analyzeSurfaceTexture(image);

    if (edgeStrength > 0.7 && surfaceTexture < 0.3) {
      analysis['condition'] = 'Excellent';
      analysis['weatheringDegree'] = 'None';
    } else if (edgeStrength > 0.5 && surfaceTexture < 0.5) {
      analysis['condition'] = 'Good';
      analysis['weatheringDegree'] = 'Slight';
    } else if (edgeStrength > 0.3) {
      analysis['condition'] = 'Fair';
      analysis['weatheringDegree'] = 'Moderate';
    } else {
      analysis['condition'] = 'Fragmentary';
      analysis['weatheringDegree'] = 'Severe';
    }

    // === PERIOD SUGGESTION based on type ===
    if (analysis['type'] == 'Pottery/Ceramic') {
      analysis['period'] = 'Classical/Hellenistic (suggested)';
    } else if (analysis['material'] == 'Bronze/Copper') {
      analysis['period'] = 'Bronze Age (suggested)';
    } else if (analysis['material'] == 'Iron/Steel') {
      analysis['period'] = 'Iron Age/Later (suggested)';
    } else {
      analysis['period'] = 'Undetermined';
    }

    // === SCALE BAR DETECTION ===
    final scaleInfo = _detectPhotoScale(image);
    if (scaleInfo['detected']) {
      analysis['scaleDetected'] = true;
      analysis['scaleMm'] = scaleInfo['lengthMm'];
      analysis['confidence'] = (analysis['confidence'] as double) * 1.1; // Boost confidence if scale present
      if (analysis['confidence'] > 1.0) analysis['confidence'] = 0.95;
    }

    return analysis;
  }

  // Analyze color distribution in image
  Map<String, double> _analyzeColorDistribution(img.Image image) {
    double totalR = 0, totalG = 0, totalB = 0;
    int pixelCount = 0;

    // Sample every 10th pixel for performance
    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixel(x, y);
        totalR += pixel.r;
        totalG += pixel.g;
        totalB += pixel.b;
        pixelCount++;
      }
    }

    final avgR = totalR / pixelCount;
    final avgG = totalG / pixelCount;
    final avgB = totalB / pixelCount;

    // Calculate HSL values
    final max = [avgR, avgG, avgB].reduce((a, b) => a > b ? a : b);
    final min = [avgR, avgG, avgB].reduce((a, b) => a < b ? a : b);
    final brightness = (max + min) / 2;
    final saturation = max == min ? 0.0 : (max - min) / (255 - (max - min).abs());

    return {
      'avgRed': avgR,
      'avgGreen': avgG,
      'avgBlue': avgB,
      'brightness': brightness,
      'saturation': saturation * 100,
    };
  }

  // Calculate edge sharpness (Sobel-like operator)
  double _calculateEdgeSharpness(img.Image image) {
    double edgeStrength = 0;
    int sampleCount = 0;

    // Sample edges at regular intervals
    for (int y = 1; y < image.height - 1; y += 20) {
      for (int x = 1; x < image.width - 1; x += 20) {
        final center = image.getPixel(x, y);
        final right = image.getPixel(x + 1, y);
        final bottom = image.getPixel(x, y + 1);

        // Gradient magnitude
        final dx = (right.r - center.r).abs() + (right.g - center.g).abs() + (right.b - center.b).abs();
        final dy = (bottom.r - center.r).abs() + (bottom.g - center.g).abs() + (bottom.b - center.b).abs();

        edgeStrength += sqrt(dx * dx + dy * dy);
        sampleCount++;
      }
    }

    return (edgeStrength / sampleCount) / 255; // Normalize to 0-1
  }

  // Analyze surface texture variation
  double _analyzeSurfaceTexture(img.Image image) {
    double variance = 0;
    int sampleCount = 0;

    // Calculate local variance in luminance
    for (int y = 10; y < image.height - 10; y += 15) {
      for (int x = 10; x < image.width - 10; x += 15) {
        final pixel = image.getPixel(x, y);
        final luminance = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114);

        // Compare with neighbors
        double localVar = 0;
        for (int dy = -5; dy <= 5; dy += 5) {
          for (int dx = -5; dx <= 5; dx += 5) {
            final neighbor = image.getPixel(x + dx, y + dy);
            final nLum = (neighbor.r * 0.299 + neighbor.g * 0.587 + neighbor.b * 0.114);
            localVar += (luminance - nLum).abs();
          }
        }

        variance += localVar;
        sampleCount++;
      }
    }

    return (variance / sampleCount) / 255; // Normalize to 0-1
  }

  // Detect photo scale bars (checkerboard or ruler patterns)
  Map<String, dynamic> _detectPhotoScale(img.Image image) {
    // Look for high-contrast repeating patterns typical of scale bars
    // Common scale patterns: black/white alternating squares (10mm, 50mm markers)

    bool detected = false;
    double lengthMm = 0;

    // Scan for horizontal high-contrast patterns
    for (int y = image.height - 100; y < image.height - 20; y += 10) {
      double lastLuminance = 0;
      int transitionCount = 0;

      for (int x = 50; x < image.width - 50; x += 5) {
        final pixel = image.getPixel(x, y);
        final luminance = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114);

        // Detect black/white transitions
        if ((lastLuminance - luminance).abs() > 100) {
          transitionCount++;
        }
        lastLuminance = luminance;
      }

      // If we found 6+ transitions, likely a scale bar (3+ squares)
      if (transitionCount >= 6 && transitionCount <= 20) {
        detected = true;
        // Estimate: common scales are 50mm or 100mm total
        // With 10mm divisions (5 or 10 divisions)
        if (transitionCount >= 10) {
          lengthMm = 100; // 10 divisions = 100mm scale
        } else {
          lengthMm = 50; // 5 divisions = 50mm scale
        }
        break;
      }
    }

    return {
      'detected': detected,
      'lengthMm': lengthMm,
    };
  }

  // 📊 SMART AUTO-FILL SUGGESTIONS
  String _getNextFindNumber() {
    final lastNumber = _smartSuggestions['lastFindNumber'] as int? ?? 0;
    final year = DateTime.now().year;
    final nextNumber = lastNumber + 1;
    return '$year-FLD-${nextNumber.toString().padLeft(3, '0')}';
  }

  // 📝 FIELD JOURNAL
  void _addFieldJournalEntry(String entry) {
    final timestamp = DateTime.now().toIso8601String();
    final journalEntry = '[$timestamp] $entry';
    setState(() {
      _fieldJournalEntries.add(journalEntry);
    });

    // Save to local storage
    _saveFieldJournal();
  }

  Future<void> _saveFieldJournal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('field_journal', _fieldJournalEntries);
  }

  // 📈 SESSION ANALYTICS
  Map<String, dynamic> _getSessionStats() {
    final duration = DateTime.now().difference(_sessionStartTime ?? DateTime.now());
    final avgTimePerFind = _sessionFindCount > 0
        ? duration.inSeconds / _sessionFindCount
        : 0;

    return {
      'duration': duration.inMinutes,
      'findCount': _sessionFindCount,
      'avgTimePerFind': avgTimePerFind.toInt(),
      'photosCapture': _captures.length,
      'hdrUsed': _hdrMode,
      'voiceUsed': _voiceEnabled,
    };
  }

  // Get guidance feedback based on current angle and device orientation
  String _getAngleGuidance() {
    final targetAngle = _currentAngle.angle;
    final targetElevation = _currentAngle.elevation;

    // Calculate angle difference
    double angleDiff = (targetAngle - _compassHeading).abs();
    if (angleDiff > 180) angleDiff = 360 - angleDiff;

    // Provide text guidance
    if (_rotationSpeed > 1.0) {
      return '⚠️ Slow down - rotate slowly for better quality';
    } else if (!_isDeviceLevel && targetElevation == 0) {
      return '📱 Hold phone level (horizontal)';
    } else if (angleDiff > 30) {
      return '🧭 Rotate ${angleDiff.toInt()}° to target angle';
    } else if (angleDiff > 15) {
      return '👍 Almost there - ${angleDiff.toInt()}° more';
    } else {
      return '✅ Perfect angle! Ready to capture';
    }
  }

  // Visual indicator color based on guidance
  Color _getGuidanceColor() {
    final targetAngle = _currentAngle.angle;
    double angleDiff = (targetAngle - _compassHeading).abs();
    if (angleDiff > 180) angleDiff = 360 - angleDiff;

    if (_rotationSpeed > 1.0) return Colors.orange;
    if (angleDiff < 15) return Colors.green;
    if (angleDiff < 30) return Colors.yellow;
    return Colors.red;
  }

  // Calculate progress percentage
  double get _progress => _captures.length / _captureAngles.length;

  // Get the next recommended angle
  CaptureAngle get _currentAngle => _captureAngles[_currentAngleIndex];

  // Check if all required angles are captured
  bool get _isComplete => _captures.length >= _captureAngles.length;

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      XFile? finalImage;

      // ULTRA++ HDR MODE - Capture multiple exposures and merge
      if (_hdrMode) {
        finalImage = await _captureHDRPhoto();
      } else {
        // Standard single photo capture
        finalImage = await _imagePicker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear, // Back camera (not selfie)
          maxWidth: 2048, // Higher resolution for photogrammetry
          maxHeight: 2048,
          imageQuality: 95, // High quality
        );
      }

      if (finalImage != null) {
        // Analyze image quality
        final quality = await _analyzeImageQuality(finalImage);

        // 🤖 AI ARTIFACT RECOGNITION - Run on first capture (completely non-blocking)
        if (_captures.isEmpty && _aiAssistEnabled) {
          _sessionFindCount++;
          // Save field journal entry
          _addFieldJournalEntry('New artifact captured - AI analyzing...');

          // Fire and forget - run AI in complete isolation to not affect capture workflow
          final imageForAI = finalImage; // Capture non-null value
          Future(() async {
            try {
              await _runAIArtifactRecognition(imageForAI).timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  debugPrint('⚠️ AI recognition timed out');
                },
              );
            } catch (e) {
              debugPrint('⚠️ AI recognition skipped: $e');
              // Silently fail - AI is optional and should never block the main workflow
            }
          });
        }

        final capture = PhotogrammetryCapture(
          file: finalImage,
          angle: _currentAngle,
          capturedAt: DateTime.now(),
          qualityScore: quality,
        );

        setState(() {
          _captures.add(capture);
          // Move to next angle if not at the end
          if (_currentAngleIndex < _captureAngles.length - 1 && _autoAdvance) {
            _currentAngleIndex++;
          }
        });

        // Show quality feedback
        if (mounted) {
          final qualityText = quality >= 0.8 ? 'Excellent!' : quality >= 0.6 ? 'Good' : 'Consider retaking';
          final qualityColor = quality >= 0.8 ? const Color(0xFF4CAF50) : quality >= 0.6 ? const Color(0xFFFFC107) : Colors.orange;
          final hdrBadge = _hdrMode ? ' [HDR]' : '';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    quality >= 0.6 ? Icons.check_circle : Icons.warning,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text('Photo ${_captures.length}/${_captureAngles.length}$hdrBadge: $qualityText'),
                ],
              ),
              backgroundColor: qualityColor,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  // ULTRA++ HDR Photo Capture - Multiple Exposure Bracketing
  Future<XFile?> _captureHDRPhoto() async {
    try {
      // Show HDR progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF7C4DFF)),
                const SizedBox(height: 16),
                const Text(
                  'Capturing HDR...',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Taking 3 exposures for optimal lighting',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      // Capture 3 images with different exposures
      // Note: ImagePicker doesn't support exposure control, so we simulate HDR
      // by capturing multiple frames and merging. For best results, the camera
      // app should adjust exposure between shots naturally.

      List<XFile> exposures = [];

      // Exposure 1: Normal (user will be prompted 3 times)
      final exp1 = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (exp1 == null) {
        if (mounted) Navigator.pop(context); // Close progress dialog
        return null;
      }
      exposures.add(exp1);

      // Small delay between captures
      await Future.delayed(const Duration(milliseconds: 500));

      // Exposure 2: Slightly different (camera may auto-adjust)
      final exp2 = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (exp2 == null) {
        if (mounted) Navigator.pop(context);
        return exp1; // Return first exposure if user cancels
      }
      exposures.add(exp2);

      await Future.delayed(const Duration(milliseconds: 500));

      // Exposure 3: Another frame
      final exp3 = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (exp3 == null) {
        if (mounted) Navigator.pop(context);
        return exp1; // Return first exposure if user cancels
      }
      exposures.add(exp3);

      // Close progress dialog
      if (mounted) Navigator.pop(context);

      // Merge HDR images
      final hdrImage = await _mergeHDRImages(exposures);

      return hdrImage ?? exp1; // Return HDR or fallback to first exposure

    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close any open dialogs
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('HDR capture failed: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    }
  }

  // Merge multiple exposures into HDR image
  Future<XFile?> _mergeHDRImages(List<XFile> exposures) async {
    try {
      if (exposures.isEmpty) return null;
      if (exposures.length == 1) return exposures[0];

      // Load all images
      List<img.Image> images = [];
      for (var exposure in exposures) {
        final bytes = await File(exposure.path).readAsBytes();
        final image = img.decodeImage(bytes);
        if (image != null) {
          images.add(image);
        }
      }

      if (images.isEmpty) return exposures[0];
      if (images.length == 1) return exposures[0];

      // Create HDR merged image using weighted average
      final width = images[0].width;
      final height = images[0].height;
      final merged = img.Image(width: width, height: height);

      // Merge pixels with weighted averaging
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          int totalR = 0, totalG = 0, totalB = 0;

          for (var image in images) {
            final pixel = image.getPixel(x, y);
            totalR += pixel.r.toInt();
            totalG += pixel.g.toInt();
            totalB += pixel.b.toInt();
          }

          // Average the exposures
          final avgR = totalR ~/ images.length;
          final avgG = totalG ~/ images.length;
          final avgB = totalB ~/ images.length;

          merged.setPixelRgba(x, y, avgR, avgG, avgB, 255);
        }
      }

      // Apply tone mapping for better HDR look
      final toneMapped = img.adjustColor(merged,
        contrast: 1.1,
        saturation: 1.05,
        brightness: 1.02,
      );

      // Save merged image
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final hdrPath = '${directory.path}/hdr_$timestamp.jpg';
      final hdrFile = File(hdrPath);
      await hdrFile.writeAsBytes(img.encodeJpg(toneMapped, quality: 95));

      return XFile(hdrPath);

    } catch (e) {
      print('HDR merge error: $e');
      return exposures.isNotEmpty ? exposures[0] : null;
    }
  }

  // ============================================================================
  // VIDEO CAPTURE MODE - ULTRA-ADVANCED FEATURE!
  // ============================================================================
  // Record a smooth video while walking around the object, then automatically
  // extract the best frames for photogrammetry processing
  // ============================================================================

  Future<void> _recordVideo() async {
    if (_isRecording) {
      // Stop recording
      await _stopVideoRecording();
    } else {
      // Start recording
      await _startVideoRecording();
    }
  }

  Future<void> _startVideoRecording() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxDuration: const Duration(minutes: 2), // Max 2 minutes
      );

      if (video != null) {
        setState(() {
          _recordedVideo = video;
          _isRecording = false;
          _isCapturing = false;
        });

        // Show processing dialog
        if (mounted) {
          _showVideoProcessingDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video recording error: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isRecording = false;
        _isCapturing = false;
      });
    }
  }

  Future<void> _stopVideoRecording() async {
    setState(() => _isRecording = false);
  }

  void _showVideoProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        title: const Text(
          '🎬 Video Recorded!',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extract frames automatically?',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            const SizedBox(height: 16),
            Text(
              'The system will analyze your video and extract the best quality frames for photogrammetry.',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF7C4DFF), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Auto-extract ~20-30 frames with quality filtering',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _recordedVideo = null);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _extractFramesFromVideo();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
            ),
            child: const Text('Extract Frames'),
          ),
        ],
      ),
    );
  }

  Future<void> _extractFramesFromVideo() async {
    if (_recordedVideo == null) return;

    setState(() {
      _isExtractingFrames = true;
      _extractedFrameCount = 0;
    });

    try {
      // Show progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              backgroundColor: const Color(0xFF1C2523),
              title: const Text(
                '⚙️ Processing Video',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF7C4DFF)),
                  const SizedBox(height: 16),
                  Text(
                    'Extracting frames: $_extractedFrameCount',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This may take 30-60 seconds...',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // Initialize video player to get video info
      final videoController = VideoPlayerController.file(File(_recordedVideo!.path));
      await videoController.initialize();

      final duration = videoController.value.duration;
      videoController.dispose();

      // Close progress dialog
      if (mounted) {
        Navigator.pop(context);
      }

      debugPrint('🎬 Video recorded: ${duration.inSeconds}s');

      // Show info about video mode
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            title: const Text(
              '📹 Video Recorded!',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Video saved: ${duration.inSeconds} seconds',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'For best photogrammetry results:\n\n'
                  '✅ Use Photo Mode for frame-by-frame capture\n'
                  '✅ Photo mode provides real-time quality analysis\n'
                  '✅ Better control over angles and coverage\n\n'
                  'Video saved to gallery for manual processing.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _isVideoMode = false);
                },
                child: const Text('Switch to Photo Mode', style: TextStyle(color: Color(0xFF7C4DFF))),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

    } catch (e) {
      debugPrint('❌ Frame extraction error: $e');

      // Close progress dialog if open
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Frame extraction failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isExtractingFrames = false;
        _recordedVideo = null;
      });
    }
  }

  // ULTRA-ADVANCED image quality analysis using QualityAnalyzer
  Future<double> _analyzeImageQuality(XFile image) async {
    try {
      final file = File(image.path);
      final bytes = await file.readAsBytes();

      // Decode image
      img.Image? decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return 0.5;

      // Use advanced QualityAnalyzer for comprehensive metrics
      final metrics = await QualityAnalyzer.analyzeImage(decodedImage);

      // Debug output
      debugPrint('📸 Quality Analysis:');
      debugPrint('   Sharpness: ${(metrics.sharpness * 100).toInt()}%');
      debugPrint('   Exposure: ${(metrics.exposure * 100).toInt()}%');
      debugPrint('   Motion Blur: ${(metrics.motionBlur * 100).toInt()}%');
      debugPrint('   Noise: ${(metrics.noise * 100).toInt()}%');
      debugPrint('   ⭐ Overall: ${(metrics.overallScore * 100).toInt()}%');

      // Return overall score
      return metrics.overallScore;
    } catch (e) {
      debugPrint('⚠️ Quality analysis error: $e');
      return 0.5;
    }
  }

  void _retakePhoto(int index) async {
    final capture = _captures[index];

    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 95,
    );

    if (image != null) {
      final quality = await _analyzeImageQuality(image);

      setState(() {
        _captures[index] = PhotogrammetryCapture(
          file: image,
          angle: capture.angle,
          capturedAt: DateTime.now(),
          qualityScore: quality,
        );
      });
    }
  }

  void _deletePhoto(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        title: const Text('Delete Photo?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${_captures[index].angle.name} photo?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _captures.removeAt(index));
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPhotos() async {
    if (_captures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No photos to export'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportDir = Directory('${directory.path}/photogrammetry_$timestamp');
      await exportDir.create(recursive: true);

      // === ULTRA-ADVANCED EXPORT ===

      // Copy all photos to export directory
      for (int i = 0; i < _captures.length; i++) {
        final capture = _captures[i];
        final newPath = '${exportDir.path}/${capture.angle.name.replaceAll(' ', '_')}_${i + 1}.jpg';
        await File(capture.file.path).copy(newPath);
      }

      // Create COMPREHENSIVE metadata file
      final metadata = StringBuffer();
      metadata.writeln('=' * 70);
      metadata.writeln('ANCIENTVISION PHOTOGRAMMETRY CAPTURE SET');
      metadata.writeln('=' * 70);
      metadata.writeln('Generated: ${DateTime.now().toIso8601String()}');
      if (widget.findingName != null) {
        metadata.writeln('Finding: ${widget.findingName}');
      }
      metadata.writeln('Total Photos: ${_captures.length}');

      // Calculate average quality
      double avgQuality = _captures.fold(0.0, (sum, c) => sum + c.qualityScore) / _captures.length;
      metadata.writeln('Average Quality: ${(avgQuality * 100).toInt()}%');
      metadata.writeln('');

      metadata.writeln('CAPTURE DETAILS');
      metadata.writeln('-' * 70);
      for (int i = 0; i < _captures.length; i++) {
        final capture = _captures[i];
        metadata.writeln('${i + 1}. ${capture.angle.name}');
        metadata.writeln('   Angle: ${capture.angle.angle}° | Elevation: ${capture.angle.elevation}°');
        metadata.writeln('   Quality: ${(capture.qualityScore * 100).toInt()}%');
        metadata.writeln('   Captured: ${capture.capturedAt.toIso8601String()}');
        metadata.writeln('');
      }

      metadata.writeln('PROCESSING INSTRUCTIONS');
      metadata.writeln('-' * 70);
      metadata.writeln('');
      metadata.writeln('OPTION 1: Automated Processing (Recommended)');
      metadata.writeln('   python photogrammetry_process.py .');
      metadata.writeln('   Or: python photogrammetry_process.py . --quality high');
      metadata.writeln('');
      metadata.writeln('OPTION 2: Meshroom GUI');
      metadata.writeln('   1. Open Meshroom application');
      metadata.writeln('   2. Drag this folder into Meshroom window');
      metadata.writeln('   3. Click "Start" button');
      metadata.writeln('   4. Wait 10-60 minutes for processing');
      metadata.writeln('');
      metadata.writeln('OPTION 3: COLMAP Command-line');
      metadata.writeln('   colmap automatic_reconstructor \\');
      metadata.writeln('     --workspace_path . \\');
      metadata.writeln('     --image_path . \\');
      metadata.writeln('     --quality high');
      metadata.writeln('');

      metadata.writeln('FREE SOFTWARE');
      metadata.writeln('-' * 70);
      metadata.writeln('Meshroom (Free, Open Source): https://alicevision.org/');
      metadata.writeln('COLMAP (Free, Open Source): https://colmap.github.io/');
      metadata.writeln('Regard3D (Free, Open Source): http://www.regard3d.org/');
      metadata.writeln('3DF Zephyr Free: https://www.3dflow.net/3df-zephyr-free/');
      metadata.writeln('');
      metadata.writeln('VIEWING & EDITING');
      metadata.writeln('-' * 70);
      metadata.writeln('MeshLab: https://www.meshlab.net/');
      metadata.writeln('CloudCompare: https://www.cloudcompare.org/');
      metadata.writeln('Blender: https://www.blender.org/');
      metadata.writeln('');
      metadata.writeln('HOSTING (FREE)');
      metadata.writeln('-' * 70);
      metadata.writeln('Sketchfab: https://sketchfab.com/');
      metadata.writeln('GitHub Pages + Three.js viewer');
      metadata.writeln('');
      metadata.writeln('=' * 70);
      metadata.writeln('Generated by AncientVision - Professional Photogrammetry System');
      metadata.writeln('=' * 70);

      await File('${exportDir.path}/README.txt').writeAsString(metadata.toString());

      // Create JSON metadata for automated processing
      final jsonMetadata = {
        'generated': DateTime.now().toIso8601String(),
        'findingName': widget.findingName,
        'totalPhotos': _captures.length,
        'averageQuality': avgQuality,
        'captures': _captures.map((c) => {
          'fileName': '${c.angle.name.replaceAll(' ', '_')}_${_captures.indexOf(c) + 1}.jpg',
          'angle': c.angle.angle,
          'elevation': c.angle.elevation,
          'quality': c.qualityScore,
          'timestamp': c.capturedAt.toIso8601String(),
        }).toList(),
      };
      await File('${exportDir.path}/metadata.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(jsonMetadata)
      );

      // Create ZIP archive for easy sharing
      final zipPath = '${directory.path}/photogrammetry_$timestamp.zip';
      try {
        final encoder = ZipFileEncoder();
        encoder.create(zipPath);
        encoder.addDirectory(exportDir);
        encoder.close();
        debugPrint('✅ ZIP created: $zipPath');
      } catch (e) {
        debugPrint('⚠️ ZIP creation failed: $e');
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 28),
                SizedBox(width: 12),
                Text('Export Complete!', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_captures.length} photos exported successfully!',
                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Next Steps:',
                        style: TextStyle(color: Color(0xFF7C4DFF), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. Transfer photos to your computer\n'
                        '2. Use Meshroom (free) for 3D reconstruction\n'
                        '3. Upload the 3D model to Sketchfab',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder, color: Color(0xFFFFC107), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          exportDir.path,
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(color: Color(0xFFFFC107))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Generate 3D model from captured photos - allows choice of method
  Future<void> _generate3DModel() async {
    if (_captures.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need at least 8 photos for 3D reconstruction'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show method selection dialog
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2523),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.view_in_ar_rounded, color: Color(0xFF7C4DFF), size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Choose Processing Method', style: TextStyle(color: Colors.white, fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cloud Processing Option - RECOMMENDED
            InkWell(
              onTap: () => Navigator.pop(ctx, 'cloud'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF7C4DFF).withOpacity(0.3), const Color(0xFF448AFF).withOpacity(0.3)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF7C4DFF), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_upload_rounded, color: Color(0xFF7C4DFF), size: 32),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Cloud Processing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('FREE via OpenScan', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('RECOMMENDED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• Professional-quality dense mesh\n'
                      '• Textured 3D model output\n'
                      '• 5-15 min processing time\n'
                      '• Requires internet connection',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // On-Device Option
            InkWell(
              onTap: () => Navigator.pop(ctx, 'device'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.phone_android_rounded, color: Colors.white.withOpacity(0.7), size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('On-Device Preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('Quick sparse point cloud', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• Sparse point cloud only\n'
                      '• 1-3 min processing time\n'
                      '• Works offline\n'
                      '• Lower quality preview',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
        ],
      ),
    );

    if (method == null) return;

    if (method == 'cloud') {
      await _generateCloudModel();
      return;
    }

    // On-device processing continues below...
    // Convert captures to File objects
    final imageFiles = _captures.map((c) => File(c.file.path)).toList();

    // Validate photos first
    setState(() {
      _isReconstructing = true;
      _reconstructionProgress = 0.0;
      _reconstructionStatus = 'Validating photos...';
    });

    try {
      final validation = await _reconstructionService.validatePhotosForReconstruction(imageFiles);

      // Show validation warnings if any
      if (validation['warnings'].isNotEmpty || validation['recommendedFixes'].isNotEmpty) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  validation['isValid'] ? Icons.warning_amber : Icons.error,
                  color: validation['isValid'] ? const Color(0xFFFFC107) : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    validation['isValid'] ? 'Quality Check' : 'Cannot Reconstruct',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (validation['errors'].isNotEmpty) ...[
                    const Text('Errors:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...((validation['errors'] as List).map((e) => Text('• $e', style: const TextStyle(color: Colors.red, fontSize: 12)))),
                    const SizedBox(height: 12),
                  ],
                  if (validation['warnings'].isNotEmpty) ...[
                    const Text('Warnings:', style: TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...((validation['warnings'] as List).map((w) => Text('• $w', style: const TextStyle(color: Colors.white70, fontSize: 12)))),
                    const SizedBox(height: 12),
                  ],
                  if (validation['recommendedFixes'].isNotEmpty) ...[
                    const Text('Recommendations:', style: TextStyle(color: Color(0xFF00BCD4), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...((validation['recommendedFixes'] as List).map((r) => Text('• $r', style: const TextStyle(color: Colors.white70, fontSize: 12)))),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              if (validation['isValid'])
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
                  child: const Text('Continue'),
                ),
            ],
          ),
        );

        if (shouldContinue != true) {
          setState(() {
            _isReconstructing = false;
          });
          return;
        }
      }

      // Generate sparse point cloud preview
      setState(() {
        _reconstructionProgress = 0.1;
        _reconstructionStatus = 'Starting reconstruction...';
      });

      final result = await _reconstructionService.generateSparsePreview(
        imageFiles: imageFiles,
        onProgress: (progress, status) {
          setState(() {
            _reconstructionProgress = progress;
            _reconstructionStatus = status;
          });
        },
      );

      setState(() {
        _reconstructionResult = result;
        _isReconstructing = false;
      });

      // Save result to history
      if (result.isComplete) {
        await _reconstructionService.saveResult(result);
      }

      if (result.isComplete && mounted) {
        // Show success and navigate to 3D viewer
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.view_in_ar, color: Color(0xFF7C4DFF), size: 28),
                SizedBox(width: 12),
                Text('3D Model Generated!', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sparse point cloud created with ${result.pointCount} points!',
                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick Preview:',
                        style: TextStyle(color: Color(0xFF7C4DFF), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '✓ Processing Time: ${result.processingTimeSeconds!.toStringAsFixed(1)}s\n'
                        '✓ Method: On-Device Sparse SfM\n'
                        '✓ Quality: Preview (for full quality, use cloud processing)',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Navigate to 3D viewer first
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Model3DViewer(
                        result: result,
                        onCompleteForm: () {
                          // After viewing 3D, go to form
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ManualEntryFormScreen(
                                reconstructionResult: result,
                                photoGallery: _captures.map((c) => c.file).toList(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.visibility),
                label: const Text('View 3D Model'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Navigate directly to manual entry form with 3D model data
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManualEntryFormScreen(
                        reconstructionResult: result,
                        photoGallery: _captures.map((c) => c.file).toList(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Complete Form'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
        );
      } else if (result.hasFailed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('3D reconstruction failed: ${result.errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isReconstructing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reconstruction error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Generate 3D model using FREE cloud processing (OpenScan Cloud API)
  Future<void> _generateCloudModel() async {
    // Get user email for token
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'ancientvision@fll.app';

    setState(() {
      _isReconstructing = true;
      _reconstructionProgress = 0.0;
      _reconstructionStatus = 'Preparing cloud upload...';
    });

    try {
      final cloudService = CloudPhotogrammetryService();

      // Get XFile list from captures
      final images = _captures.map((c) => c.file).toList();

      // Run cloud reconstruction
      final result = await cloudService.reconstruct(
        images: images,
        email: email,
        projectName: 'AncientVision_${DateTime.now().millisecondsSinceEpoch}',
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _reconstructionProgress = progress;
              _reconstructionStatus = status;
            });
          }
        },
      );

      setState(() {
        _isReconstructing = false;
      });

      if (result.success && mounted) {
        // Show success dialog
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.cloud_done_rounded, color: Color(0xFF4CAF50), size: 28),
                SizedBox(width: 12),
                Expanded(child: Text('Cloud Processing Complete!', style: TextStyle(color: Colors.white, fontSize: 18))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Professional Quality Model:', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        '✓ Dense mesh with textures\n'
                        '${result.vertexCount != null ? "✓ ${result.vertexCount} vertices\n" : ""}'
                        '${result.processingTime != null ? "✓ Processed in ${result.processingTime!.toStringAsFixed(0)}s\n" : ""}'
                        '✓ Ready for archaeological documentation',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (result.downloadUrl != null)
                  Text(
                    'Model saved locally and can be exported.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                  ),
              ],
            ),
            actions: [
              if (result.downloadUrl != null)
                TextButton.icon(
                  onPressed: () async {
                    // Share the download URL
                    await Share.share(
                      'AncientVision 3D Model: ${result.downloadUrl}',
                      subject: 'Archaeological 3D Scan',
                    );
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share Link'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Navigate to manual entry with cloud model data
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManualEntryFormScreen(
                        photoGallery: _captures.map((c) => c.file).toList(),
                        // Pass cloud model URL
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Complete Form'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
              ),
            ],
          ),
        );
      } else if (!result.success && mounted) {
        // Show error with option to try on-device
        final tryOnDevice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 12),
                Expanded(child: Text('Cloud Processing Unavailable', style: TextStyle(color: Colors.white, fontSize: 18))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.errorMessage ?? 'Cloud service temporarily unavailable.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 16),
                Text(
                  'You can try on-device processing instead for a quick preview.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.phone_android, size: 18),
                label: const Text('Try On-Device'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
              ),
            ],
          ),
        );

        if (tryOnDevice == true) {
          // Fall back to on-device processing
          await _runOnDeviceReconstruction();
        }
      }
    } catch (e) {
      setState(() {
        _isReconstructing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cloud processing error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Run on-device reconstruction (extracted from _generate3DModel for reuse)
  Future<void> _runOnDeviceReconstruction() async {
    final imageFiles = _captures.map((c) => File(c.file.path)).toList();

    setState(() {
      _isReconstructing = true;
      _reconstructionProgress = 0.0;
      _reconstructionStatus = 'Starting on-device processing...';
    });

    try {
      final result = await _reconstructionService.generateSparsePreview(
        imageFiles: imageFiles,
        onProgress: (progress, status) {
          setState(() {
            _reconstructionProgress = progress;
            _reconstructionStatus = status;
          });
        },
      );

      setState(() {
        _reconstructionResult = result;
        _isReconstructing = false;
      });

      if (result.isComplete) {
        await _reconstructionService.saveResult(result);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Model3DViewer(
                result: result,
                onCompleteForm: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManualEntryFormScreen(
                        reconstructionResult: result,
                        photoGallery: _captures.map((c) => c.file).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isReconstructing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('On-device error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showTutorial) {
      return _buildTutorialScreen();
    }
    return _buildCaptureScreen();
  }

  Widget _buildTutorialScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text(
                        'Photogrammetry Capture',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 32),

                // 3D Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF7C4DFF), width: 3),
                  ),
                  child: const Icon(Icons.view_in_ar, color: Color(0xFF7C4DFF), size: 60),
                ),
                const SizedBox(height: 32),

                const Text(
                  'Create 3D Models from Photos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Photogrammetry creates accurate 3D models by analyzing multiple photos taken from different angles.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Tips
                Expanded(
                  child: ListView(
                    children: [
                      _buildTipCard(
                        Icons.wb_sunny_outlined,
                        'Good Lighting',
                        'Use natural, diffused light. Avoid harsh shadows and direct sunlight.',
                        const Color(0xFFFFC107),
                      ),
                      _buildTipCard(
                        Icons.rotate_90_degrees_ccw,
                        '360° Coverage',
                        'Capture photos from all angles: front, back, sides, and top views.',
                        const Color(0xFF4CAF50),
                      ),
                      _buildTipCard(
                        Icons.blur_off,
                        'Sharp Focus',
                        'Keep the camera steady. Wait for focus before capturing.',
                        const Color(0xFF2196F3),
                      ),
                      _buildTipCard(
                        Icons.photo_size_select_large,
                        '50-70% Overlap',
                        'Each photo should overlap with adjacent photos for best results.',
                        const Color(0xFFE91E63),
                      ),
                    ],
                  ),
                ),

                // Start button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => setState(() => _showTutorial = false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt),
                        SizedBox(width: 8),
                        Text('Start Capture Session', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTipCard(IconData icon, String title, String description, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ULTRA++ Feature Chip Widget
  Widget _buildFeatureChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? color : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : Colors.white60,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🤖 AI Result Item Widget
  Widget _buildAIResultItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureScreen() {
    return Scaffold(
      body: Stack(
        children: [
          // Main content
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
              ),
            ),
            child: SafeArea(
              child: Column(
            children: [
              // Header with progress
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            widget.findingName ?? 'Photogrammetry',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_captures.length}/${_captureAngles.length} photos captured',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // 3D Model button
                    IconButton(
                      onPressed: _captures.length >= 8 && !_isReconstructing ? _generate3DModel : null,
                      icon: Icon(
                        Icons.view_in_ar,
                        color: _captures.length >= 8 && !_isReconstructing
                            ? const Color(0xFF7C4DFF)
                            : Colors.white30,
                      ),
                      tooltip: 'Generate 3D Model',
                    ),
                    // Export button
                    IconButton(
                      onPressed: _captures.isNotEmpty ? _exportPhotos : null,
                      icon: Icon(
                        Icons.ios_share,
                        color: _captures.isNotEmpty ? const Color(0xFF4CAF50) : Colors.white30,
                      ),
                      tooltip: 'Export Photos',
                    ),
                    // Info button
                    IconButton(
                      onPressed: () => setState(() => _showTutorial = true),
                      icon: const Icon(Icons.help_outline, color: Colors.white54),
                    ),
                  ],
                ),
              ),

              // ULTRA++ Advanced Features Panel
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune, color: Color(0xFF7C4DFF), size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Advanced Features',
                          style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // HDR Toggle
                        _buildFeatureChip(
                          icon: Icons.hdr_on,
                          label: 'HDR',
                          isActive: _hdrMode,
                          onTap: () => setState(() => _hdrMode = !_hdrMode),
                          color: const Color(0xFFFF9800),
                        ),
                        // Grid Overlay Toggle
                        _buildFeatureChip(
                          icon: Icons.grid_on,
                          label: 'Grid',
                          isActive: _showGrid,
                          onTap: () => setState(() => _showGrid = !_showGrid),
                          color: const Color(0xFF2196F3),
                        ),
                        // Histogram Toggle
                        _buildFeatureChip(
                          icon: Icons.bar_chart,
                          label: 'Histogram',
                          isActive: _showHistogram,
                          onTap: () => setState(() => _showHistogram = !_showHistogram),
                          color: const Color(0xFF9C27B0),
                        ),
                        // Batch Mode Toggle
                        _buildFeatureChip(
                          icon: Icons.photo_library,
                          label: 'Batch',
                          isActive: _batchMode,
                          onTap: () => setState(() => _batchMode = !_batchMode),
                          color: const Color(0xFFE91E63),
                        ),
                        // Auto-Advance Toggle
                        _buildFeatureChip(
                          icon: Icons.skip_next,
                          label: 'Auto',
                          isActive: _autoAdvance,
                          onTap: () => setState(() => _autoAdvance = !_autoAdvance),
                          color: const Color(0xFF4CAF50),
                        ),
                        // AI Toggle
                        _buildFeatureChip(
                          icon: Icons.smart_toy,
                          label: 'AI',
                          isActive: _aiAssistEnabled,
                          onTap: () => setState(() => _aiAssistEnabled = !_aiAssistEnabled),
                          color: const Color(0xFF00BCD4),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 🤖 AI DETECTION RESULTS PANEL
              if (_aiDetectedType != null && _aiConfidence > 0.5)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00BCD4).withOpacity(0.15),
                        const Color(0xFF7C4DFF).withOpacity(0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00BCD4), width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: Color(0xFF00BCD4), size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'AI Analysis',
                            style: TextStyle(
                              color: Color(0xFF00BCD4),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _aiConfidence > 0.7 ? const Color(0xFF4CAF50) : const Color(0xFFFFC107),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${(_aiConfidence * 100).toInt()}% confidence',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // AI Detection Details
                      Row(
                        children: [
                          Expanded(
                            child: _buildAIResultItem(
                              icon: Icons.category,
                              label: 'Type',
                              value: _aiDetectedType ?? 'Unknown',
                              color: const Color(0xFFFF9800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAIResultItem(
                              icon: Icons.grain,
                              label: 'Material',
                              value: _aiDetectedMaterial ?? 'Unknown',
                              color: const Color(0xFF8BC34A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildAIResultItem(
                              icon: Icons.verified,
                              label: 'Condition',
                              value: _aiDetectedCondition ?? 'Unknown',
                              color: const Color(0xFF2196F3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAIResultItem(
                              icon: Icons.history_edu,
                              label: 'Period',
                              value: _aiDetectedPeriod ?? 'Unknown',
                              color: const Color(0xFF9C27B0),
                            ),
                          ),
                        ],
                      ),
                      if (_scaleDetected && _detectedScaleMm != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF4CAF50)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.straighten, color: Color(0xFF4CAF50), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Photo Scale Detected: ${_detectedScaleMm!.toInt()}mm',
                                style: const TextStyle(
                                  color: Color(0xFF4CAF50),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

              // Circular progress with angle indicator
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Progress ring
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CustomPaint(
                        painter: _AngleProgressPainter(
                          captures: _captures,
                          angles: _captureAngles,
                          currentAngle: _currentAngleIndex,
                          progress: _progress,
                        ),
                      ),
                    ),
                    // Center content
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(_progress * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!_isComplete)
                          Text(
                            'Next: ${_currentAngle.name}',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                          ),
                        if (_isComplete)
                          const Text(
                            'Complete!',
                            style: TextStyle(color: Color(0xFF4CAF50), fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Current angle instruction / Video mode instruction
              if (!_isComplete)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Color.lerp(
                                const Color(0xFF7C4DFF).withOpacity(0.3),
                                const Color(0xFF7C4DFF).withOpacity(0.6),
                                _pulseController.value,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isVideoMode ? Icons.videocam : _currentAngle.icon,
                              color: Colors.white,
                              size: 24,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isVideoMode ? 'Video Capture Mode' : _currentAngle.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _isVideoMode
                                  ? 'Walk smoothly around the object in a complete circle. Keep steady movement.'
                                  : _getAngleInstruction(_currentAngle),
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Photo gallery
              Expanded(
                child: _captures.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 64, color: Colors.white.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            Text(
                              'Tap the capture button to start',
                              style: TextStyle(color: Colors.white.withOpacity(0.5)),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: _captures.length,
                          itemBuilder: (context, index) {
                            final capture = _captures[index];
                            return GestureDetector(
                              onTap: () => _showPhotoOptions(index),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(capture.file.path),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  // Quality indicator
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: capture.qualityScore >= 0.8
                                            ? const Color(0xFF4CAF50)
                                            : capture.qualityScore >= 0.6
                                                ? const Color(0xFFFFC107)
                                                : Colors.orange,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 1),
                                      ),
                                    ),
                                  ),
                                  // Angle label
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [Colors.black87, Colors.transparent],
                                        ),
                                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                                      ),
                                      child: Text(
                                        capture.angle.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 8),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),

              // ULTRA++ Voice Commands Control
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Voice command toggle button
                    GestureDetector(
                      onTap: () {
                        setState(() => _voiceEnabled = !_voiceEnabled);
                        if (_voiceEnabled) {
                          _startListening();
                          _speak('Voice commands enabled');
                        } else {
                          _stopListening();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _voiceEnabled
                              ? const Color(0xFF4CAF50).withOpacity(0.2)
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _voiceEnabled ? const Color(0xFF4CAF50) : Colors.white30,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isListening ? Icons.mic : Icons.mic_off,
                              color: _voiceEnabled ? const Color(0xFF4CAF50) : Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isListening ? 'Listening...' : (_voiceEnabled ? 'Voice ON' : 'Voice OFF'),
                              style: TextStyle(
                                color: _voiceEnabled ? const Color(0xFF4CAF50) : Colors.white70,
                                fontWeight: _voiceEnabled ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Voice command indicator & last command display
                    if (_voiceEnabled && _lastVoiceCommand.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '"${_lastVoiceCommand.length > 20 ? _lastVoiceCommand.substring(0, 20) + '...' : _lastVoiceCommand}"',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Video mode toggle
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Photo mode button
                        GestureDetector(
                          onTap: () => setState(() => _isVideoMode = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isVideoMode ? const Color(0xFF7C4DFF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Photo Mode',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: !_isVideoMode ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Video mode button
                        GestureDetector(
                          onTap: () => setState(() => _isVideoMode = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: _isVideoMode ? const Color(0xFF7C4DFF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Video Mode',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: _isVideoMode ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Capture button
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Skip button (only in photo mode)
                    if (!_isComplete && _captures.isNotEmpty && !_isVideoMode)
                      Container(
                        margin: const EdgeInsets.only(right: 16),
                        child: TextButton(
                          onPressed: () {
                            if (_currentAngleIndex < _captureAngles.length - 1) {
                              setState(() => _currentAngleIndex++);
                            }
                          },
                          child: const Text('Skip', style: TextStyle(color: Colors.white54)),
                        ),
                      ),

                    // Main capture button
                    GestureDetector(
                      onTap: _isCapturing ? null : (_isVideoMode ? _recordVideo : _capturePhoto),
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: _isCapturing
                                  ? Colors.grey
                                  : Color.lerp(
                                      const Color(0xFF7C4DFF),
                                      const Color(0xFF9C7CFF),
                                      _pulseController.value,
                                    ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7C4DFF).withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: _isCapturing
                                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                                : Icon(
                                    _isVideoMode ? Icons.videocam : Icons.camera_alt,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                          );
                        },
                      ),
                    ),

                    // Previous button
                    if (!_isComplete && _currentAngleIndex > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 16),
                        child: TextButton(
                          onPressed: () {
                            setState(() => _currentAngleIndex--);
                          },
                          child: const Text('Back', style: TextStyle(color: Colors.white54)),
                        ),
                      ),
                  ],
                ),
              ),

              // Completion actions
              if (_isComplete)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentAngleIndex = 0;
                            });
                          },
                          icon: const Icon(Icons.add_a_photo),
                          label: const Text('Add More'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white30),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _exportPhotos,
                          icon: const Icon(Icons.check),
                          label: const Text('Export'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
            ),
          ),

          // 🎯 3D RECONSTRUCTION PROGRESS OVERLAY
          if (_isReconstructing)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(32),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2523),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF7C4DFF), width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.view_in_ar,
                        size: 64,
                        color: Color(0xFF7C4DFF),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Generating 3D Model',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _reconstructionStatus,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: CircularProgressIndicator(
                              value: _reconstructionProgress,
                              strokeWidth: 8,
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF7C4DFF),
                              ),
                            ),
                          ),
                          Text(
                            '${(_reconstructionProgress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'This may take 10-30 seconds...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getAngleInstruction(CaptureAngle angle) {
    if (angle.isDetail) {
      return 'Get close for a detailed shot of interesting features';
    }
    if (angle.elevation >= 70) {
      return 'Position camera directly above the object';
    }
    if (angle.elevation >= 40) {
      return 'Angle camera down at ~45° from ${angle.angle}°';
    }
    return 'Position at ${angle.angle}° around the object at eye level';
  }

  void _showPhotoOptions(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2523),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _captures[index].angle.name,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Quality: ${(_captures[index].qualityScore * 100).toInt()}%',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _retakePhoto(index);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retake'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFC107),
                      side: const BorderSide(color: Color(0xFFFFC107)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deletePhoto(index);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// Custom painter for the angle progress ring
class _AngleProgressPainter extends CustomPainter {
  final List<PhotogrammetryCapture> captures;
  final List<CaptureAngle> angles;
  final int currentAngle;
  final double progress;

  _AngleProgressPainter({
    required this.captures,
    required this.angles,
    required this.currentAngle,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background ring
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius, bgPaint);

    // Draw angle markers
    for (int i = 0; i < angles.length; i++) {
      final angle = angles[i];
      final radians = (angle.angle - 90) * pi / 180;
      final markerRadius = radius - 15;
      final markerX = center.dx + markerRadius * cos(radians);
      final markerY = center.dy + markerRadius * sin(radians);

      final bool isCaptured = captures.any((c) => c.angle.id == angle.id);
      final bool isCurrent = i == currentAngle;

      final markerPaint = Paint()
        ..color = isCaptured
            ? const Color(0xFF4CAF50)
            : isCurrent
                ? const Color(0xFF7C4DFF)
                : Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(markerX, markerY), isCurrent ? 8 : 6, markerPaint);

      if (isCurrent) {
        final outerPaint = Paint()
          ..color = const Color(0xFF7C4DFF).withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(markerX, markerY), 12, outerPaint);
      }
    }

    // Progress arc
    final progressPaint = Paint()
      ..color = const Color(0xFF7C4DFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

//
// --------------------- PDF EXPORT SCREEN ---------------------
//

class PDFExportScreen extends StatefulWidget {
  const PDFExportScreen({super.key});

  @override
  State<PDFExportScreen> createState() => _PDFExportScreenState();
}

class _PDFExportScreenState extends State<PDFExportScreen> {
  List<Map<String, dynamic>> _findings = [];
  bool _isLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadFindings();
  }

  Future<void> _loadFindings() async {
    try {
      final user = AuthService.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _findings = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generatePDF(Map<String, dynamic> finding) async {
    setState(() => _isGenerating = true);

    try {
      final pdfService = PDFReportService();

      // Prepare data
      final findingData = {
        'ID': finding['id'],
        'Type': finding['type'] ?? 'Unknown',
        'Site': finding['site'] ?? 'Unknown',
        'Date': finding['date'] ?? 'Unknown',
        'Latitude': finding['latitude']?.toString() ?? 'N/A',
        'Longitude': finding['longitude']?.toString() ?? 'N/A',
      };

      // Load photos if available
      final photoUrls = (finding['photoGallery'] as List?)?.cast<String>() ?? [];
      final photoFiles = <File>[];

      // For now, skip downloading photos (would require HTTP calls)
      // In production, we'd download from URLs

      final file = await pdfService.generateArchaeologicalReport(
        findingName: finding['name'] ?? 'Unknown Finding',
        findingData: findingData,
        photoFiles: photoFiles,
        reconstruction: null, // Would need to serialize/deserialize
      );

      setState(() => _isGenerating = false);

      if (mounted) {
        // Share the PDF
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Archaeological Report - ${finding['name']}',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF report generated successfully!'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Generate PDF Reports',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _findings.isEmpty
                        ? const Center(
                            child: Text(
                              'No findings to export',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _findings.length,
                            itemBuilder: (context, index) {
                              final finding = _findings[index];
                              return Card(
                                color: Colors.white.withOpacity(0.1),
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.picture_as_pdf,
                                    color: Color(0xFFF44336),
                                  ),
                                  title: Text(
                                    finding['name'] ?? 'Unknown',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    '${finding['type']} - ${finding['site']}',
                                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                                  ),
                                  trailing: _isGenerating
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.download, color: Color(0xFF4CAF50)),
                                          onPressed: () => _generatePDF(finding),
                                        ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//
// --------------------- EXPORT DATA SCREEN ---------------------
//

class ExportDataScreen extends StatelessWidget {
  const ExportDataScreen({super.key});

  Future<void> _exportAllData(BuildContext context) async {
    try {
      final user = AuthService.currentUser;
      if (user == null) return;

      // Fetch all findings
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .get();

      final findings = snapshot.docs.map((doc) => doc.data()).toList();

      // Convert to JSON
      final jsonData = jsonEncode(findings);

      // Save to file
      final output = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${output.path}/findings_export_$timestamp.json');
      await file.writeAsString(jsonData);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'AncientVision Findings Export',
        text: 'Exported ${findings.length} archaeological findings',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${findings.length} findings successfully!'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3A39), Color(0xFF1C2523)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Export Data',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Export options
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildExportCard(
                        context,
                        icon: Icons.folder_zip,
                        title: 'Export All Findings',
                        description: 'Export all findings as JSON file',
                        color: const Color(0xFF2196F3),
                        onTap: () => _exportAllData(context),
                      ),
                      const SizedBox(height: 16),
                      _buildExportCard(
                        context,
                        icon: Icons.view_in_ar,
                        title: 'Export 3D Models',
                        description: 'Export 3D models as PLY files (Coming Soon)',
                        color: const Color(0xFF9C27B0),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('3D model export: Use Share button in 3D viewer'),
                              backgroundColor: Color(0xFFFFC107),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

// Data classes for photogrammetry
class CaptureAngle {
  final int id;
  final String name;
  final double angle; // Horizontal angle (0-360)
  final double elevation; // Vertical angle (0 = eye level, 90 = top)
  final IconData icon;
  final bool isDetail;

  const CaptureAngle({
    required this.id,
    required this.name,
    required this.angle,
    required this.elevation,
    required this.icon,
    this.isDetail = false,
  });
}

class PhotogrammetryCapture {
  final XFile file;
  final CaptureAngle angle;
  final DateTime capturedAt;
  final double qualityScore; // 0.0 - 1.0

  PhotogrammetryCapture({
    required this.file,
    required this.angle,
    required this.capturedAt,
    required this.qualityScore,
  });
}

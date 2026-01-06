import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'services/auth_service.dart';
import 'utils/validators.dart';

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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
        return const _AddView();
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

  @override
  void initState() {
    super.initState();
    _loadFindingsCounts();
    _loadUserName();
    _loadLastFindings();
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Photogrammetry screen (coming soon)'),
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
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                ...findings.map((f) => Padding(
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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

  const _Finding({
    required this.id,
    required this.name,
    required this.type,
    required this.site,
    required this.date,
    required this.description,
    required this.latitude,
    required this.longitude,
  });
}

class _FindingsView extends StatefulWidget {
  const _FindingsView({super.key});

  @override
  State<_FindingsView> createState() => _FindingsViewState();
}

class _FindingsViewState extends State<_FindingsView> {
  List<_Finding> _findings = [];
  bool _isLoading = true;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadFindings();
  }

  Future<void> _loadFindings() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .get();

      final findings = snapshot.docs.map((doc) {
        final data = doc.data();
        return _Finding(
          id: doc.id,
          name: data['name'] ?? '',
          type: data['type'] ?? '',
          site: data['site'] ?? '',
          date: data['date'] ?? '',
          description: data['description'] ?? '',
          latitude: (data['latitude'] ?? 37.9715).toDouble(),
          longitude: (data['longitude'] ?? 23.7267).toDouble(),
        );
      }).toList();

      setState(() {
        _findings = findings;
        _isLoading = false;
        if (_findings.isNotEmpty && _selectedIndex >= _findings.length) {
          _selectedIndex = 0;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _findings.isNotEmpty ? _findings[_selectedIndex] : null;

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
              const Text(
                'Findings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Tap on a finding in the table to see details.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // Reload button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isLoading = true;
                      });
                      _loadFindings();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 18,
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
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.white.withOpacity(0.5),
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No findings yet',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add your first finding using the Manual Entry button above',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                // RECENT FINDINGS TABLE
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          showCheckboxColumn: false,
                          headingTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          dataTextStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          columnSpacing: 12,
                          columns: const [
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Type')),
                            DataColumn(label: Text('Site')),
                            DataColumn(label: Text('Date')),
                          ],
                          rows: List.generate(_findings.length, (index) {
                            final f = _findings[index];
                            final isSelected = index == _selectedIndex;
                            return DataRow(
                              selected: isSelected,
                              color: WidgetStateProperty.resolveWith<Color?>(
                                (Set<WidgetState> states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return const Color(0xFFFFC107).withOpacity(0.3);
                                  }
                                  return null;
                                },
                              ),
                              onSelectChanged: (_) {
                                setState(() {
                                  _selectedIndex = index;
                                });
                              },
                              cells: [
                                DataCell(Text(f.id)),
                                DataCell(Text(f.name)),
                                DataCell(Text(f.type)),
                                DataCell(Text(f.site)),
                                DataCell(Text(f.date)),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // MAP (Smaller size with OpenStreetMap)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                      child: _FindingsMap(findings: _findings, selectedIndex: _selectedIndex),
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
    );
  }
}

class _FindingDetailCard extends StatelessWidget {
  final _Finding finding;

  const _FindingDetailCard({super.key, required this.finding});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // placeholder image
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: Colors.white70,
                  size: 36,
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      finding.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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
                    Text(
                      finding.description,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
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

      return Marker(
        point: LatLng(finding.latitude, finding.longitude),
        width: isSelected ? 40 : 32,
        height: isSelected ? 40 : 32,
        child: GestureDetector(
          onTap: () => _openInGoogleMaps(),
          child: Icon(
            Icons.location_pin,
            size: isSelected ? 40 : 32,
            color: isSelected ? const Color(0xFFFFC107) : Colors.red,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate center position (average of all findings)
    final centerLat = widget.findings.map((f) => f.latitude).reduce((a, b) => a + b) / widget.findings.length;
    final centerLng = widget.findings.map((f) => f.longitude).reduce((a, b) => a + b) / widget.findings.length;

    return Stack(
      children: [
        // Interactive OpenStreetMap
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(centerLat, centerLng),
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

class _AddView extends StatelessWidget {
  const _AddView({super.key});

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
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add New',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isGuest
                          ? 'Sign in to add new findings'
                          : 'Choose how you want to add a new finding',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 32),

                    if (_isGuest) ...[
                      // GUEST VIEW - Blurred options with sign in required
                      _GuestAddOptionCard(
                        icon: Icons.edit_note_rounded,
                        title: 'Manual Entry',
                      ),
                      const SizedBox(height: 16),
                      _GuestAddOptionCard(
                        icon: Icons.auto_awesome_rounded,
                        title: 'AI Recognition',
                      ),
                      const SizedBox(height: 16),
                      _GuestAddOptionCard(
                        icon: Icons.camera_alt_outlined,
                        title: 'Photogrammetry',
                      ),
                      const SizedBox(height: 24),
                      // Sign in button
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (route) => false,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Sign In to Add Findings',
                              style: TextStyle(
                                color: Color(0xFF0D3A39),
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // LOGGED IN VIEW - Normal options
                      _AddOptionCard(
                        icon: Icons.edit_note_rounded,
                        title: 'Manual Entry',
                        description: 'Enter finding details manually with ID, name, type, site, and date.',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ManualEntryFormScreen()),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      _AddOptionCard(
                        icon: Icons.auto_awesome_rounded,
                        title: 'AI Recognition',
                        description: 'Take a photo and let AI identify and catalog the finding automatically.',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('AI Recognition coming soon'),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      _AddOptionCard(
                        icon: Icons.camera_alt_outlined,
                        title: 'Photogrammetry',
                        description: 'Create a 3D model of the finding using multiple photos.',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Photogrammetry coming soon'),
                            ),
                          );
                        },
                      ),
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
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
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
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
  const ManualEntryFormScreen({super.key});

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
  bool _hasImage = false;
  XFile? _selectedImage;
  final ImagePicker _imagePicker = ImagePicker();
  String _nextId = 'A-001';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isGettingLocation = false;

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

    try {
      // Parse coordinates from controllers, fallback to defaults if empty
      final lat = double.tryParse(_latController.text) ?? 37.9715;
      final lng = double.tryParse(_lngController.text) ?? 23.7267;

      await FirebaseFirestore.instance.collection('findings').doc(_nextId).set({
        'name': _nameController.text,
        'type': _typeController.text,
        'site': _siteController.text,
        'date': _dateController.text,
        'description': '',
        'latitude': lat,
        'longitude': lng,
        'imageUrl': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Finding $_nextId added successfully!'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving finding: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
    super.dispose();
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
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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

                  const SizedBox(height: 32),

                  // SUBMIT BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _isSaving ? null : _saveFinding,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
//

class _SafetyView extends StatelessWidget {
  const _SafetyView({super.key});

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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.engineering_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Trench Safety',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _LiveChip(),
                ],
              ),

              const SizedBox(height: 8),
              Text(
                'Monitoring trench B3 – North wall',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 16),

              // STATS ROW: Vibration / Moisture
              Row(
                children: const [
                  Expanded(
                    child: _SafetyStatCard(
                      title: 'Vibration',
                      value: '0.12 g',
                      status: 'Stable',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _SafetyStatCard(
                      title: 'Soil Moisture',
                      value: '41 %',
                      status: 'Safe range',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              const _LiveSensorsCard(),

              const SizedBox(height: 12),

              const _SafetyAlertsCard(),

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

class _LiveChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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

  const _SafetyStatCard({
    required this.title,
    required this.value,
    required this.status,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 125,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveSensorsCard extends StatelessWidget {
  const _LiveSensorsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
              const Text(
                'Live sensors',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const _SensorRow(
                label: 'IMU (M5StickPlus2)',
                value: 'X 0.01g   Y -0.02g   Z 0.98g',
                icon: Icons.sensors_rounded,
              ),
              const SizedBox(height: 6),
              const _SensorRow(
                label: 'Soil moisture',
                value: '41 %   (safe: 30–60%)',
                icon: Icons.water_drop_outlined,
              ),
              const SizedBox(height: 10),
              Text(
                'Last update: 14:32',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
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

  const _SensorRow({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyAlertsCard extends StatelessWidget {
  const _SafetyAlertsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
            children: const [
              Text(
                'Alerts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10),
              _AlertRow(
                time: '14:31',
                level: _AlertLevel.critical,
                title: 'High vibration',
                trench: 'Trench B3',
                message: 'Possible soil movement detected.',
              ),
              SizedBox(height: 6),
              _AlertRow(
                time: '13:05',
                level: _AlertLevel.warning,
                title: 'Wet soil',
                trench: 'Trench A1',
                message: 'Moisture above safe range.',
              ),
              SizedBox(height: 6),
              _AlertRow(
                time: '12:10',
                level: _AlertLevel.ok,
                title: 'Back to safe',
                trench: 'Trench B3',
                message: 'Vibration normalised.',
              ),
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
    required this.time,
    required this.level,
    required this.title,
    required this.trench,
    required this.message,
    super.key,
  });

  Color _dotColor() {
    switch (level) {
      case _AlertLevel.critical:
        return const Color(0xFFE53935);
      case _AlertLevel.warning:
        return const Color(0xFFFFB300);
      case _AlertLevel.ok:
        return const Color(0xFF43A047);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: _dotColor(),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title • $trench',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
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
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Safety Insight',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Today 80% of alerts were caused by high moisture. '
                'Check drainage near trench B3 and limit heavy equipment nearby.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                icon: Icons.add_circle_outline_rounded,
                label: 'Add',
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

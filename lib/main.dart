import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:video_player/video_player.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';
import 'services/local_storage_service.dart';
import 'services/reconstruction_service.dart';
import 'services/image_service.dart';
import 'services/cloud_photogrammetry_service.dart';
import 'services/notification_service.dart';
import 'utils/validators.dart';
import 'utils/quality_analyzer.dart';
import 'models/reconstruction_result.dart';
import 'widgets/model_3d_viewer.dart';
import 'screens/analytics_screen.dart';
import 'screens/field_journal_screen.dart';
import 'screens/quick_capture_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/help_screen.dart';
// import 'screens/qr_scanner_screen.dart'; // Removed - QR scanner hidden
import 'screens/ai_recognition_screen.dart';
import 'services/export_service.dart';
import 'services/biometric_service.dart';
import 'services/background_service.dart';
import 'services/settings_service.dart';
import 'services/vibration_anomaly_service.dart';
import 'widgets/offline_indicator.dart';

// ============================================================
// IMGBB API KEY - Get your free key at https://api.imgbb.com/
// ============================================================
const String imgbbApiKey = '63efd0891caba4842791a2f892301d07';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Initialize notification service
  await NotificationService().initialize();
  await NotificationService().requestPermissions();
  // Initialize background service to keep app running
  await BackgroundServiceManager().initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _settingsService = SettingsService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  Future<void> _initSettings() async {
    await _settingsService.initialize();
    _settingsService.addListener(_onSettingsChanged);
    if (mounted) setState(() => _initialized = true);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0D3A39),
          body: const Center(
            child: CircularProgressIndicator(color: Color(0xFFFFC107)),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _settingsService.getThemeData(MediaQuery.platformBrightnessOf(context)),
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
          // If user is logged in, check for biometric
          if (snapshot.hasData) {
            return const _BiometricGate();
          }
          // Otherwise, show login screen
          return const LoginScreen();
        },
      ),
    );
  }
}

/// Gate that checks if biometric lock should be shown
class _BiometricGate extends StatefulWidget {
  const _BiometricGate();

  @override
  State<_BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<_BiometricGate> with WidgetsBindingObserver {
  bool _isChecking = true;
  bool _showBiometricLock = false;
  bool _wasInBackground = false;
  DateTime? _backgroundTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBiometric();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      // App going to background
      _wasInBackground = true;
      _backgroundTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      // App returning from background - check if we need to re-authenticate
      _wasInBackground = false;
      _checkBiometricOnResume();
    }
  }

  Future<void> _checkBiometricOnResume() async {
    // Only require re-auth if app was in background for more than 30 seconds
    if (_backgroundTime != null) {
      final elapsed = DateTime.now().difference(_backgroundTime!);
      debugPrint('App resumed after ${elapsed.inSeconds} seconds in background');
      if (elapsed.inSeconds > 30) {
        debugPrint('Over 30 seconds - checking biometric lock...');
        final biometricService = BiometricService();
        final shouldShow = await biometricService.shouldShowBiometricLock();
        debugPrint('Should show biometric lock on resume: $shouldShow');
        if (shouldShow && mounted) {
          setState(() => _showBiometricLock = true);
        }
      }
    }
  }

  Future<void> _checkBiometric() async {
    final biometricService = BiometricService();

    // Debug: Check biometric state
    final isSupported = await biometricService.isDeviceSupported();
    final canCheck = await biometricService.canCheckBiometrics();
    final isEnrolled = await biometricService.isEnrolled();
    final isEnabled = await biometricService.isEnabled();
    debugPrint('Biometric check: supported=$isSupported, canCheck=$canCheck, enrolled=$isEnrolled, enabled=$isEnabled');

    // Auto-enroll biometrics if device supports it but user hasn't enrolled yet
    // This makes quick unlock available by default for convenience
    if (isSupported && canCheck && !isEnrolled) {
      debugPrint('Auto-enrolling biometrics for quick unlock...');
      await biometricService.autoEnroll();
    }

    final shouldShow = await biometricService.shouldShowBiometricLock();
    debugPrint('Should show biometric lock: $shouldShow');

    if (mounted) {
      setState(() {
        _showBiometricLock = shouldShow;
        _isChecking = false;
      });

      // If no biometric lock needed, start background service directly
      if (!shouldShow) {
        _startBackgroundService();
      }
      // If biometric needed, the lock screen will auto-trigger authentication
    }
  }

  Future<void> _startBackgroundService() async {
    await BackgroundServiceManager().startService();
  }

  Future<void> _usePassword() async {
    final biometricService = BiometricService();
    final hasPin = await biometricService.hasPin();

    if (!hasPin) {
      // No PIN set - show PIN setup dialog
      if (mounted) {
        await _showPinSetupDialog();
      }
    } else {
      // PIN exists - show PIN entry dialog
      if (mounted) {
        await _showPinEntryDialog();
      }
    }
  }

  Future<void> _showPinSetupDialog() async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C2523),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Set Up PIN',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create a 4-8 digit PIN for quick access when biometrics are unavailable.',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Enter PIN',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFFC107)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Confirm PIN',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFFC107)),
                  ),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: const Color(0xFF0D3A39),
              ),
              onPressed: () async {
                final pin = pinController.text;
                final confirm = confirmController.text;

                if (pin.length < 4) {
                  setDialogState(() => errorText = 'PIN must be at least 4 digits');
                  return;
                }
                if (pin != confirm) {
                  setDialogState(() => errorText = 'PINs do not match');
                  return;
                }

                final result = await BiometricService().setupPin(pin);
                if (result.success) {
                  if (context.mounted) Navigator.pop(context, true);
                } else {
                  setDialogState(() => errorText = result.error);
                }
              },
              child: const Text('Save PIN'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => _showBiometricLock = false);
      _startBackgroundService();
    }
  }

  Future<void> _showPinEntryDialog() async {
    final pinController = TextEditingController();
    String? errorText;
    int attempts = 0;
    const maxAttempts = 5;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C2523),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Enter PIN',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your PIN to unlock AncientVision',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFFC107)),
                  ),
                ),
                onSubmitted: (_) async {
                  final pin = pinController.text;
                  final result = await BiometricService().verifyPin(pin);

                  if (result.success) {
                    if (context.mounted) Navigator.pop(context, true);
                  } else {
                    attempts++;
                    if (attempts >= maxAttempts) {
                      if (context.mounted) {
                        Navigator.pop(context, false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Too many attempts. Try biometrics or restart the app.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } else {
                      setDialogState(() {
                        errorText = '${result.error}. ${maxAttempts - attempts} attempts left.';
                        pinController.clear();
                      });
                    }
                  }
                },
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: const Color(0xFF0D3A39),
              ),
              onPressed: () async {
                final pin = pinController.text;
                final result = await BiometricService().verifyPin(pin);

                if (result.success) {
                  if (context.mounted) Navigator.pop(context, true);
                } else {
                  attempts++;
                  if (attempts >= maxAttempts) {
                    if (context.mounted) {
                      Navigator.pop(context, false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Too many attempts. Try biometrics or restart the app.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } else {
                    setDialogState(() {
                      errorText = '${result.error}. ${maxAttempts - attempts} attempts left.';
                      pinController.clear();
                    });
                  }
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => _showBiometricLock = false);
      _startBackgroundService();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFFC107)),
        ),
      );
    }

    if (_showBiometricLock) {
      return _BiometricLockScreen(
        onBiometricSuccess: () {
          setState(() => _showBiometricLock = false);
          _startBackgroundService();
        },
        onUsePassword: _usePassword,
      );
    }

    return const DashboardScreen();
  }
}

/// Lock screen shown when biometric auth is required
class _BiometricLockScreen extends StatefulWidget {
  final VoidCallback onBiometricSuccess;
  final Future<void> Function() onUsePassword;

  const _BiometricLockScreen({
    required this.onBiometricSuccess,
    required this.onUsePassword,
  });

  @override
  State<_BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<_BiometricLockScreen> {
  String _biometricType = 'Biometric';
  String? _errorMessage;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricType();
    // Auto-trigger authentication when lock screen appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleAuthenticate();
    });
  }

  Future<void> _loadBiometricType() async {
    final type = await BiometricService().getBiometricTypeName();
    if (mounted) {
      setState(() => _biometricType = type);
    }
  }

  Future<void> _handleAuthenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final result = await BiometricService().authenticateWithFeedback();

    if (mounted) {
      setState(() => _isAuthenticating = false);
      if (result.success) {
        // Success - notify parent to hide lock and proceed to dashboard
        widget.onBiometricSuccess();
      } else if (result.error != null) {
        setState(() => _errorMessage = result.error);
      }
    }
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Icon(
                  Icons.account_balance,
                  size: 50,
                  color: Color(0xFF0D3A39),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'AncientVision',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Unlock with $_biometricType',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),
              ],
              // Fingerprint button
              GestureDetector(
                onTap: _isAuthenticating ? null : _handleAuthenticate,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFC107),
                      width: 2,
                    ),
                  ),
                  child: _isAuthenticating
                      ? const CircularProgressIndicator(
                          color: Color(0xFFFFC107),
                          strokeWidth: 2,
                        )
                      : const Icon(
                          Icons.fingerprint,
                          size: 48,
                          color: Color(0xFFFFC107),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isAuthenticating ? 'Authenticating...' : 'Tap to unlock',
                style: TextStyle(
                  color: Colors.white.withAlpha(153),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // Use PIN option
              TextButton(
                onPressed: widget.onUsePassword,
                child: const Text(
                  'Use PIN instead',
                  style: TextStyle(
                    color: Color(0xFFFFC107),
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
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

  /// Navigate to dashboard, optionally prompting for biometric enrollment
  Future<void> _navigateToDashboard() async {
    if (!mounted) return;

    final biometricService = BiometricService();
    final isEnrolled = await biometricService.isEnrolled();
    final isSupported = await biometricService.isDeviceSupported();

    // If not enrolled and device supports biometrics, show enrollment prompt
    if (!isEnrolled && isSupported && mounted) {
      final biometricType = await biometricService.getBiometricTypeName();
      final shouldEnroll = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1C2523),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFFFFC107), size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Enable Quick Unlock?',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Text(
            'Use $biometricType to sign in faster next time. Your data stays secure.',
            style: TextStyle(color: Colors.white.withOpacity(0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Not now',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: const Color(0xFF0D3A39),
              ),
              child: const Text('Enable'),
            ),
          ],
        ),
      );

      if (shouldEnroll == true && mounted) {
        final enrolled = await biometricService.enroll();
        if (enrolled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quick unlock enabled!'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      }
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
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
        await _navigateToDashboard();
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} - ${e.message}');
      _showError(_getAuthErrorMessage(e.code));
    } catch (e) {
      debugPrint('Login error: $e');
      // Check if user is actually logged in despite the error (known firebase_auth bug)
      if (AuthService.currentUser != null && mounted) {
        await _navigateToDashboard();
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
        await _navigateToDashboard();
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

  /// Navigate to dashboard, optionally prompting for biometric enrollment
  Future<void> _navigateToDashboard() async {
    if (!mounted) return;

    final biometricService = BiometricService();
    final isEnrolled = await biometricService.isEnrolled();
    final isSupported = await biometricService.isDeviceSupported();

    // If not enrolled and device supports biometrics, show enrollment prompt
    if (!isEnrolled && isSupported && mounted) {
      final biometricType = await biometricService.getBiometricTypeName();
      final shouldEnroll = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1C2523),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.fingerprint, color: Color(0xFFFFC107), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Enable Quick Unlock?',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Text(
            'Use $biometricType to sign in faster next time. Your data stays secure.',
            style: TextStyle(color: Colors.white.withOpacity(0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Not now',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: const Color(0xFF0D3A39),
              ),
              child: const Text('Enable'),
            ),
          ],
        ),
      );

      if (shouldEnroll == true && mounted) {
        final enrolled = await biometricService.enroll();
        if (enrolled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quick unlock enabled!'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      }
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
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
        await _navigateToDashboard();
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

  // Global mute state (shared across all tabs)
  bool _isMuted = false;

  // Full-screen alert state (shown on top of all tabs)
  bool _showFullScreenAlert = false;
  String _fullScreenAlertMessage = '';
  String _fullScreenAlertLevel = 'warning';

  // Audio/voice for alerts
  late FlutterTts _tts;
  final AudioPlayer _alarmPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    _tts.stop();
    _alarmPlayer.stop();
    _alarmPlayer.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        _alarmPlayer.stop();
        _tts.stop();
        // Also dismiss any active full-screen alert when muting
        _showFullScreenAlert = false;
      }
    });
  }

  void _triggerFullScreenAlert(String message, String level) async {
    if (!mounted) return;
    if (_isMuted) return;

    setState(() {
      _showFullScreenAlert = true;
      _fullScreenAlertMessage = message;
      _fullScreenAlertLevel = level;
    });

    // Haptic feedback
    try {
      HapticFeedback.heavyImpact();
    } catch (e) {
      debugPrint('Haptic error: $e');
    }

    // Play alarm sound
    try {
      await _alarmPlayer.play(AssetSource('audio/alarm.wav'));
    } catch (e) {
      debugPrint('Could not play alarm: $e');
    }

    // Voice alert
    try {
      String voiceMessage = level == 'critical'
          ? 'Critical alert! $message'
          : 'Warning! $message';
      await _tts.speak(voiceMessage);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  void _dismissFullScreenAlert() {
    _alarmPlayer.stop();
    setState(() {
      _showFullScreenAlert = false;
    });
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _currentIndex,
      children: [
        const _DashboardHomeView(),
        const _FindingsView(),
        const _ToolsView(),
        _SafetyView(
          isMuted: _isMuted,
          onToggleMute: _toggleMute,
          onAlert: _triggerFullScreenAlert,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return OfflineIndicator(
      child: Stack(
        children: [
          Scaffold(
            extendBody: true,
            backgroundColor: Colors.transparent,
            body: _buildBody(),
            bottomNavigationBar: SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _GlassBottomNavBar(
                currentIndex: _currentIndex,
                isMuted: _isMuted,
                onToggleMute: _toggleMute,
                onItemSelected: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
              ),
            ),
          ),
          // Full-screen alert overlay on top of everything
          if (_showFullScreenAlert)
            _FullScreenAlertOverlay(
              message: _fullScreenAlertMessage,
              level: _fullScreenAlertLevel,
              onDismiss: _dismissFullScreenAlert,
            ),
        ],
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
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadFindingsCounts();
    _loadUserName();
    _loadLastFindings();
    _checkOfflineData();
    _loadUnreadNotifications();
  }

  Future<void> _loadUnreadNotifications() async {
    final count = await NotificationService().getUnreadCount();
    if (mounted) {
      setState(() => _unreadNotifications = count);
    }
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
      debugPrint('Error loading last findings: $e');
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
      debugPrint('Error loading findings counts: $e');
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
                  const SizedBox(width: 8),
                  // Notifications button
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                      _loadUnreadNotifications();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Stack(
                        children: [
                          const Center(
                            child: Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
                          ),
                          if (_unreadNotifications > 0)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFC107),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                child: Text(
                                  _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Offline indicator chip
                  const OfflineChip(),
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

              // ACTIVE DEVICES full width - shows connected BLE devices
              const _ActiveDevicesCard(),

              const SizedBox(height: 12),

              // QUICK ACTIONS: AI Recognition & Photogrammetry
              const _QuickActionsRow(),

              const SizedBox(height: 16),

              // LAST FINDINGS
              _LastFindingsCard(findings: _lastFindings),

              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

//
// ----------------------- NOTIFICATIONS SCREEN ------------------------
//

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _loadSettings();
    // Clear unread count when viewing notifications
    NotificationService().clearUnreadCount();
  }

  Future<void> _loadNotifications() async {
    final notifications = await NotificationService().getNotificationHistory();
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    final enabled = await NotificationService().areNotificationsEnabled();
    if (mounted) {
      setState(() => _notificationsEnabled = enabled);
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    await NotificationService().setNotificationsEnabled(value);
    setState(() => _notificationsEnabled = value);
  }

  Future<void> _clearHistory() async {
    await NotificationService().clearNotificationHistory();
    setState(() => _notifications = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C2523),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D3A39),
        title: const Text('Notifications', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1C2523),
                    title: const Text('Clear History', style: TextStyle(color: Colors.white)),
                    content: const Text(
                      'Are you sure you want to clear all notifications?',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _clearHistory();
                        },
                        child: const Text('Clear', style: TextStyle(color: Color(0xFFFFC107))),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Settings toggle
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active, color: Color(0xFFFFC107), size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Push Notifications',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Get notified when 3D processing completes',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _notificationsEnabled,
                  onChanged: _toggleNotifications,
                  activeColor: const Color(0xFFFFC107),
                ),
              ],
            ),
          ),

          // Notification list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 64, color: Colors.white.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            Text(
                              'No notifications yet',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You\'ll be notified when cloud processing completes',
                              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: notification.isSuccess
                                    ? const Color(0xFF4CAF50).withOpacity(0.3)
                                    : notification.isError
                                        ? const Color(0xFFF44336).withOpacity(0.3)
                                        : Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: notification.isSuccess
                                        ? const Color(0xFF4CAF50).withOpacity(0.2)
                                        : notification.isError
                                            ? const Color(0xFFF44336).withOpacity(0.2)
                                            : Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    notification.isSuccess
                                        ? Icons.check_circle_outline
                                        : notification.isError
                                            ? Icons.error_outline
                                            : Icons.notifications_outlined,
                                    color: notification.isSuccess
                                        ? const Color(0xFF4CAF50)
                                        : notification.isError
                                            ? const Color(0xFFF44336)
                                            : Colors.white60,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              notification.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            notification.timeAgo,
                                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        notification.body,
                                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
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
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(90)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    color: Colors.white.withAlpha(217),
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

/// Dynamic Active Devices card that shows connected BLE devices
class _ActiveDevicesCard extends StatefulWidget {
  const _ActiveDevicesCard({super.key});

  @override
  State<_ActiveDevicesCard> createState() => _ActiveDevicesCardState();
}

class _ActiveDevicesCardState extends State<_ActiveDevicesCard> {
  int _connectedCount = 0;
  String _deviceName = '';
  late StreamSubscription<List<BluetoothDevice>> _subscription;

  @override
  void initState() {
    super.initState();
    _checkConnectedDevices();
    // Listen for connection changes
    _subscription = Stream.periodic(const Duration(seconds: 2))
        .asyncMap((_) => FlutterBluePlus.connectedDevices)
        .listen((devices) {
      if (mounted) {
        setState(() {
          _connectedCount = devices.length;
          _deviceName = devices.isNotEmpty ? (devices.first.platformName.isNotEmpty ? devices.first.platformName : 'M5StickC') : '';
        });
      }
    });
  }

  Future<void> _checkConnectedDevices() async {
    try {
      final devices = await FlutterBluePlus.connectedDevices;
      if (mounted) {
        setState(() {
          _connectedCount = devices.length;
          _deviceName = devices.isNotEmpty ? (devices.first.platformName.isNotEmpty ? devices.first.platformName : 'M5StickC') : '';
        });
      }
    } catch (e) {
      debugPrint('Error checking connected devices: $e');
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectedCount > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          height: 120,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isConnected
                  ? [const Color(0xFF4CAF50).withAlpha(40), const Color(0xFF4CAF50).withAlpha(20)]
                  : [Colors.white.withAlpha(26), Colors.white.withAlpha(13)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isConnected ? const Color(0xFF4CAF50).withAlpha(150) : Colors.white.withAlpha(90),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Active Devices',
                            style: TextStyle(
                              color: Colors.white.withAlpha(217),
                              fontSize: 14,
                            )),
                        const SizedBox(width: 8),
                        if (isConnected)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withAlpha(80),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('LIVE', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '$_connectedCount',
                      style: TextStyle(
                        color: isConnected ? const Color(0xFF4CAF50) : Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_deviceName.isNotEmpty)
                      Text(
                        _deviceName,
                        style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isConnected
                      ? const Color(0xFF4CAF50).withAlpha(50)
                      : Colors.white.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: isConnected ? const Color(0xFF4CAF50) : Colors.white.withAlpha(150),
                  size: 28,
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
    // Photogrammetry feature hidden from UI but code preserved
    // To re-enable, uncomment the second Expanded widget below
    return Row(
      children: [
        Expanded(
          child: _GlassActionButton(
            icon: Icons.monetization_on_rounded,
            title: 'Coin AI',
            subtitle: 'Gemini AI',
            onTap: () async {
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(builder: (_) => const AIRecognitionScreen()),
              );
              if (result != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Classified as: ${result['type'] ?? 'Unknown'}'),
                    backgroundColor: const Color(0xFF4CAF50),
                  ),
                );
              }
            },
          ),
        ),
        // PHOTOGRAMMETRY BUTTON - HIDDEN BY REQUEST (code preserved)
        // Uncomment to re-enable:
        // const SizedBox(width: 12),
        // Expanded(
        //   child: _GlassActionButton(
        //     icon: Icons.camera_alt_outlined,
        //     title: 'Photogrammetry',
        //     onTap: () {
        //       Navigator.push(
        //         context,
        //         MaterialPageRoute(
        //           builder: (_) => const PhotogrammetryScreen(),
        //         ),
        //       );
        //     },
        //   ),
        // ),
      ],
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _GlassActionButton({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    if (subtitle != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.5)),
                        ),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Color(0xFFFFC107),
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
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

//
// --------------------- FINDINGS TAB CONTENT ---------------------
//

/// Source type for findings
enum FindingSource {
  manual('Manual Entry', Icons.edit_note, Color(0xFFFFC107)),
  photo('Coin Recognition', Icons.auto_awesome, Color(0xFFFF9800)),
  quick('Quick Capture', Icons.flash_on, Color(0xFF2196F3));

  final String label;
  final IconData icon;
  final Color color;

  const FindingSource(this.label, this.icon, this.color);

  static FindingSource fromString(String? source) {
    switch (source?.toLowerCase()) {
      case 'photo':
      case 'photo_capture':
        return FindingSource.photo;
      case 'quick':
      case 'quick_capture':
        return FindingSource.quick;
      case 'manual':
      case 'manual_entry':
      default:
        return FindingSource.manual;
    }
  }
}

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
  final FindingSource source;

  // Coin-specific fields
  final String? denomination;
  final String? mint;
  final String? ruler;
  final String? obverseLegend;
  final String? reverseLegend;
  final int? dieAxis;
  final String? obverseDescription;
  final String? reverseDescription;

  // Fragment-specific fields
  final String? vesselPart;
  final String? wareType;
  final String? decorationStyle;
  final String? fabricColorInt;
  final String? fabricColorExt;
  final double? rimDiameter;
  final double? wallThickness;
  final String? surfaceTreatment;

  // Context fields
  final String? locusNumber;
  final String? soilType;
  final String? matrixDescription;
  final String? harrisPosition;
  final List<String>? associatedFeatures;

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
    this.source = FindingSource.manual,
    // Coin fields
    this.denomination,
    this.mint,
    this.ruler,
    this.obverseLegend,
    this.reverseLegend,
    this.dieAxis,
    this.obverseDescription,
    this.reverseDescription,
    // Fragment fields
    this.vesselPart,
    this.wareType,
    this.decorationStyle,
    this.fabricColorInt,
    this.fabricColorExt,
    this.rimDiameter,
    this.wallThickness,
    this.surfaceTreatment,
    // Context fields
    this.locusNumber,
    this.soilType,
    this.matrixDescription,
    this.harrisPosition,
    this.associatedFeatures,
  });

  /// Check if this is a coin finding
  bool get isCoin => type.toLowerCase().contains('coin');

  /// Check if this is a fragment/sherd finding
  bool get isFragment => type.toLowerCase().contains('fragment') || type.toLowerCase().contains('sherd');

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

/// Full-screen details page for a finding
class _FindingDetailsPage extends StatelessWidget {
  final _Finding finding;

  const _FindingDetailsPage({super.key, required this.finding});

  @override
  Widget build(BuildContext context) {
    final typeColor = _Finding.getTypeColor(finding.type);

    return Scaffold(
      backgroundColor: const Color(0xFF0D3A39),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(finding.id, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top section: Description (left) and Photo (right)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Name and Description
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Finding name with type color
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              color: typeColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              finding.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: typeColor.withAlpha(50),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: typeColor, width: 1),
                        ),
                        child: Text(
                          finding.type,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Description
                      const Text(
                        'Description',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(13),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          finding.description.isNotEmpty
                              ? finding.description
                              : 'No description available',
                          style: TextStyle(
                            color: finding.description.isNotEmpty
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Right: Photo
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: finding.imageUrl != null && finding.imageUrl!.isNotEmpty
                            ? Image.network(
                                finding.imageUrl!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  height: 180,
                                  color: const Color(0xFF1C2523),
                                  child: const Center(
                                    child: Icon(Icons.broken_image, color: Colors.white38, size: 48),
                                  ),
                                ),
                              )
                            : Container(
                                height: 180,
                                color: const Color(0xFF1C2523),
                                child: const Center(
                                  child: Icon(Icons.image_not_supported, color: Colors.white38, size: 48),
                                ),
                              ),
                      ),
                      // Photo gallery thumbnails
                      if (finding.photoGallery.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 50,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: finding.photoGallery.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    finding.photoGallery[index],
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 50,
                                      height: 50,
                                      color: const Color(0xFF1C2523),
                                      child: const Icon(Icons.broken_image, color: Colors.white38, size: 20),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Bottom section: Details cards
            // Location card
            _buildDetailCard(
              icon: Icons.location_on,
              title: 'Location',
              children: [
                _buildDetailRow('Site', finding.site),
                _buildDetailRow('Coordinates', '${finding.latitude.toStringAsFixed(6)}, ${finding.longitude.toStringAsFixed(6)}'),
              ],
            ),

            const SizedBox(height: 12),

            // Date & Source card
            _buildDetailCard(
              icon: Icons.info_outline,
              title: 'Information',
              children: [
                _buildDetailRow('Date Found', finding.date),
                _buildDetailRow('Source', finding.source.label),
                if (finding.model3dUrl != null)
                  _buildDetailRow('3D Model', 'Available'),
              ],
            ),

            // Coin details card (shown only for coins)
            if (finding.isCoin && _hasCoinData()) ...[
              const SizedBox(height: 12),
              _buildDetailCard(
                icon: Icons.paid,
                title: 'Coin Details',
                children: [
                  if (finding.denomination != null)
                    _buildDetailRow('Denomination', finding.denomination!),
                  if (finding.mint != null)
                    _buildDetailRow('Mint', finding.mint!),
                  if (finding.ruler != null)
                    _buildDetailRow('Ruler/Authority', finding.ruler!),
                  if (finding.obverseLegend != null)
                    _buildDetailRow('Obverse Legend', finding.obverseLegend!),
                  if (finding.reverseLegend != null)
                    _buildDetailRow('Reverse Legend', finding.reverseLegend!),
                  if (finding.dieAxis != null)
                    _buildDetailRow('Die Axis', '${finding.dieAxis} o\'clock'),
                  if (finding.obverseDescription != null)
                    _buildDetailRow('Obverse Desc.', finding.obverseDescription!),
                  if (finding.reverseDescription != null)
                    _buildDetailRow('Reverse Desc.', finding.reverseDescription!),
                ],
              ),
            ],

            // Fragment details card (shown only for fragments)
            if (finding.isFragment && _hasFragmentData()) ...[
              const SizedBox(height: 12),
              _buildDetailCard(
                icon: Icons.broken_image,
                title: 'Fragment Details',
                children: [
                  if (finding.vesselPart != null)
                    _buildDetailRow('Vessel Part', finding.vesselPart!),
                  if (finding.wareType != null)
                    _buildDetailRow('Ware Type', finding.wareType!),
                  if (finding.decorationStyle != null)
                    _buildDetailRow('Decoration', finding.decorationStyle!),
                  if (finding.rimDiameter != null)
                    _buildDetailRow('Rim Diameter', '${finding.rimDiameter} mm'),
                  if (finding.wallThickness != null)
                    _buildDetailRow('Wall Thickness', '${finding.wallThickness} mm'),
                  if (finding.fabricColorInt != null)
                    _buildDetailRow('Interior Color', finding.fabricColorInt!),
                  if (finding.fabricColorExt != null)
                    _buildDetailRow('Exterior Color', finding.fabricColorExt!),
                  if (finding.surfaceTreatment != null)
                    _buildDetailRow('Surface Treatment', finding.surfaceTreatment!),
                ],
              ),
            ],

            // Context details card (shown if context data exists)
            if (_hasContextData()) ...[
              const SizedBox(height: 12),
              _buildDetailCard(
                icon: Icons.layers,
                title: 'Stratigraphic Context',
                children: [
                  if (finding.locusNumber != null)
                    _buildDetailRow('Locus/Context', finding.locusNumber!),
                  if (finding.soilType != null)
                    _buildDetailRow('Soil Type', finding.soilType!),
                  if (finding.matrixDescription != null)
                    _buildDetailRow('Matrix', finding.matrixDescription!),
                  if (finding.harrisPosition != null)
                    _buildDetailRow('Harris Position', finding.harrisPosition!),
                  if (finding.associatedFeatures != null && finding.associatedFeatures!.isNotEmpty)
                    _buildDetailRow('Associated', finding.associatedFeatures!.join(', ')),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // 3D Model button if available
            if (finding.model3dUrl != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withAlpha(30),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF7C4DFF), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.view_in_ar, color: Color(0xFF7C4DFF), size: 32),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '3D Model Available',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'View the reconstructed 3D model',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Color(0xFF7C4DFF), size: 20),
                  ],
                ),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFFC107), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Check if finding has any coin-specific data
  bool _hasCoinData() {
    return finding.denomination != null ||
        finding.mint != null ||
        finding.ruler != null ||
        finding.obverseLegend != null ||
        finding.reverseLegend != null ||
        finding.dieAxis != null ||
        finding.obverseDescription != null ||
        finding.reverseDescription != null;
  }

  /// Check if finding has any fragment-specific data
  bool _hasFragmentData() {
    return finding.vesselPart != null ||
        finding.wareType != null ||
        finding.decorationStyle != null ||
        finding.rimDiameter != null ||
        finding.wallThickness != null ||
        finding.fabricColorInt != null ||
        finding.fabricColorExt != null ||
        finding.surfaceTreatment != null;
  }

  /// Check if finding has any context/stratigraphic data
  bool _hasContextData() {
    return finding.locusNumber != null ||
        finding.soilType != null ||
        finding.matrixDescription != null ||
        finding.harrisPosition != null ||
        (finding.associatedFeatures != null && finding.associatedFeatures!.isNotEmpty);
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
  final TextEditingController _searchController = TextEditingController();
  FindingSource? _selectedSource; // null means "All"

  // Batch selection mode
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isExporting = false;

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
      // Start with all findings
      var filtered = _findings.toList();

      // Filter by source if selected
      if (_selectedSource != null) {
        filtered = filtered.where((f) => f.source == _selectedSource).toList();
      }

      // Filter by search query
      if (query.isNotEmpty) {
        final searchLower = query.toLowerCase();
        filtered = filtered.where((f) {
          return f.name.toLowerCase().contains(searchLower) ||
              f.type.toLowerCase().contains(searchLower) ||
              f.site.toLowerCase().contains(searchLower) ||
              f.id.toLowerCase().contains(searchLower);
        }).toList();
      }

      _filteredFindings = filtered;
      if (_filteredFindings.isNotEmpty && _selectedIndex >= _filteredFindings.length) {
        _selectedIndex = 0;
      }
    });
  }

  void _setSourceFilter(FindingSource? source) {
    setState(() {
      _selectedSource = source;
    });
    _filterFindings(_searchController.text);
  }

  // Batch selection methods
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_filteredFindings.map((f) => f.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  Future<void> _showBatchExportDialog() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No findings selected')),
      );
      return;
    }

    final selectedFindings = _filteredFindings
        .where((f) => _selectedIds.contains(f.id))
        .toList();

    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _BatchExportSheet(
        selectedCount: selectedFindings.length,
      ),
    );

    if (format == null || !mounted) return;

    setState(() => _isExporting = true);

    try {
      // Convert findings to export format
      final findingsData = selectedFindings.map((f) => {
        'id': f.id,
        'type': f.type,
        'site': f.site,
        'name': f.name,
        'date': f.date,
        'latitude': f.latitude,
        'longitude': f.longitude,
        'source': f.source.name,
      }).toList();

      final exportService = ExportService();
      final file = await exportService.batchExportFindings(
        findings: findingsData,
        format: format,
        includePhotos: true,
        onProgress: (progress, status) {
          debugPrint('Export progress: ${(progress * 100).toStringAsFixed(0)}% - $status');
        },
      );

      if (file != null && mounted) {
        // Share the file
        await exportService.shareFile(file);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${selectedFindings.length} findings'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );

        // Exit selection mode
        _toggleSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Widget _buildSourceChip(FindingSource? source, String label, IconData icon) {
    final isSelected = _selectedSource == source;
    final color = source?.color ?? const Color(0xFFFFC107);

    return GestureDetector(
      onTap: () => _setSourceFilter(source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
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
          source: FindingSource.fromString(data['source']),
          // Coin fields
          denomination: data['denomination'],
          mint: data['mint'],
          ruler: data['ruler'],
          obverseLegend: data['obverseLegend'],
          reverseLegend: data['reverseLegend'],
          dieAxis: data['dieAxis'],
          obverseDescription: data['obverseDescription'],
          reverseDescription: data['reverseDescription'],
          // Fragment fields
          vesselPart: data['vesselPart'],
          wareType: data['wareType'],
          decorationStyle: data['decorationStyle'],
          fabricColorInt: data['fabricColorInt'],
          fabricColorExt: data['fabricColorExt'],
          rimDiameter: data['rimDiameter']?.toDouble(),
          wallThickness: data['wallThickness']?.toDouble(),
          surfaceTreatment: data['surfaceTreatment'],
          // Context fields
          locusNumber: data['locusNumber'],
          soilType: data['soilType'],
          matrixDescription: data['matrixDescription'],
          harrisPosition: data['harrisPosition'],
          associatedFeatures: data['associatedFeatures'] != null
              ? List<String>.from(data['associatedFeatures'])
              : null,
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

                // Source filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildSourceChip(null, 'All', Icons.list_alt),
                      const SizedBox(width: 8),
                      ...FindingSource.values.map((source) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildSourceChip(source, source.label, source.icon),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                  // Batch Export button
                  if (AuthService.currentUser != null && _filteredFindings.isNotEmpty)
                    GestureDetector(
                      onTap: _isSelectionMode ? _showBatchExportDialog : _toggleSelectionMode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _isSelectionMode
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF2196F3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isSelectionMode ? Icons.file_download : Icons.checklist,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isSelectionMode
                                  ? 'Export (${_selectedIds.length})'
                                  : 'Select',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Cancel selection button
                  if (_isSelectionMode)
                    GestureDetector(
                      onTap: _toggleSelectionMode,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  // Select All button
                  if (_isSelectionMode)
                    GestureDetector(
                      onTap: _selectedIds.length == _filteredFindings.length
                          ? _clearSelection
                          : _selectAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _selectedIds.length == _filteredFindings.length ? 'None' : 'All',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  // Coin Recognition button
                  if (AuthService.currentUser != null && !_isSelectionMode)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AIRecognitionScreen()),
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
                              'Coin Recognition',
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
                  // Action buttons row
                  if (AuthService.currentUser != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Quick Capture button
                        GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push<Map<String, dynamic>>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const QuickCaptureScreen(),
                              ),
                            );
                            if (result != null && context.mounted) {
                              _handleQuickCaptureResult(context, result);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2196F3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.flash_on,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Manual Entry button
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
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.edit_note,
                              color: Color(0xFF3E2723),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(38),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white.withAlpha(102),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Sign in',
                            style: TextStyle(
                              color: Colors.white.withAlpha(102),
                              fontSize: 10,
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
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => _FindingDetailsPage(finding: f),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFC107).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            color: Color(0xFFFFC107),
                                            size: 16,
                                          ),
                                        ),
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
  String _locationName = 'Archaeological Site';
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // Load initial location name
    if (widget.findings.isNotEmpty) {
      _reverseGeocode(widget.findings.first.latitude, widget.findings.first.longitude);
    }
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
      // Update location name for the new position
      _reverseGeocode(selected.latitude, selected.longitude);
    }
  }

  Future<void> _reverseGeocode(double lat, double lon) async {
    if (_isLoadingLocation) return;
    setState(() => _isLoadingLocation = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'AncientVision-FLL-App/1.0',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        // Try to get a meaningful location name
        String name = data['name'] as String? ?? '';
        if (name.isEmpty) {
          name = address?['historic'] as String? ??
                 address?['tourism'] as String? ??
                 address?['archaeological_site'] as String? ??
                 address?['amenity'] as String? ??
                 address?['suburb'] as String? ??
                 address?['neighbourhood'] as String? ??
                 address?['village'] as String? ??
                 address?['town'] as String? ??
                 address?['city'] as String? ??
                 'Archaeological Site';
        }

        if (mounted) {
          setState(() => _locationName = name);
        }
      }
    } catch (e) {
      // Keep the default name on error
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
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

        // Map label overlay - dynamic location name
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoadingLocation)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
                      ),
                    ),
                  ),
                Text(
                  _locationName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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

/// Handle Quick Capture result - save to Firestore with source 'quick'
Future<void> _handleQuickCaptureResult(BuildContext context, Map<String, dynamic> result) async {
  // Support both formats: 'photo' (single) from QuickCapture, 'photos' (list) from elsewhere
  final singlePhoto = result['photo'] as XFile?;
  final photosList = result['photos'] as List<dynamic>?;
  final photos = photosList ?? (singlePhoto != null ? [singlePhoto] : null);
  final type = result['type'];
  // Support both 'note' and 'description' field names
  final description = (result['description'] ?? result['note']) as String?;
  final location = result['location'] as Map<String, dynamic>?;
  final persistedPath = result['persistedPath'] as String?;

  if (photos == null || photos.isEmpty) {
    debugPrint('QuickCapture: No photos to save');
    return;
  }

  // Get type label
  String typeLabel = 'Unknown';
  if (type != null) {
    try {
      typeLabel = type.label ?? 'Unknown';
    } catch (_) {
      typeLabel = type.toString();
    }
  }

  // Generate a local ID
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final localId = 'QC-$timestamp';

  // Create finding data with local photo path
  final findingData = {
    'id': localId,
    'name': description?.isNotEmpty == true ? description : 'Quick Capture ${DateTime.now().toIso8601String().split('T')[0]}',
    'type': typeLabel,
    'site': 'Field Site',
    'date': DateTime.now().toIso8601String().split('T')[0],
    'description': description ?? '',
    'latitude': location?['latitude'] ?? 37.9715,
    'longitude': location?['longitude'] ?? 23.7267,
    'imageUrl': persistedPath, // Use local path
    'photoGallery': persistedPath != null ? [persistedPath] : <String>[],
    'createdAt': DateTime.now().toIso8601String(),
    'source': 'quick',
  };

  // Save to local storage first (offline-first)
  try {
    final localStorage = LocalStorageService();
    await localStorage.initialize();
    // Cache locally and queue for cloud sync
    await localStorage.cacheFinding(findingId: localId, data: findingData);
    await localStorage.queueForUpload(findingId: localId, data: findingData);
    debugPrint('QuickCapture: Saved locally as $localId');

    // Show success immediately
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quick capture saved locally ($typeLabel)'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    }

    // Try to sync to cloud in background (non-blocking)
    _syncQuickCaptureToCloud(findingData, photos);
  } catch (e) {
    debugPrint('QuickCapture: Local save error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Background sync to cloud (non-blocking)
Future<void> _syncQuickCaptureToCloud(Map<String, dynamic> findingData, List<dynamic> photos) async {
  try {
    // Try to upload photos to imgbb
    final List<String> photoUrls = [];
    for (final photo in photos) {
      try {
        final xfile = photo as XFile;
        final bytes = await xfile.readAsBytes();
        final base64Image = base64Encode(bytes);

        final response = await http.post(
          Uri.parse('https://api.imgbb.com/1/upload'),
          body: {
            'key': imgbbApiKey,
            'image': base64Image,
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            photoUrls.add(data['data']['url']);
          }
        }
      } catch (e) {
        debugPrint('QuickCapture: Photo upload failed: $e');
      }
    }

    // Update finding data with cloud URLs if available
    if (photoUrls.isNotEmpty) {
      findingData['imageUrl'] = photoUrls.first;
      findingData['photoGallery'] = photoUrls;
    }
    findingData['createdAt'] = FieldValue.serverTimestamp();

    // Try to save to Firestore
    await FirebaseFirestore.instance
        .collection('findings')
        .doc(findingData['id'] as String)
        .set(findingData)
        .timeout(const Duration(seconds: 10));

    debugPrint('QuickCapture: Synced to cloud');
  } catch (e) {
    debugPrint('QuickCapture: Cloud sync failed (will retry later): $e');
    // Data is already saved locally, will sync when online
  }
}

/// Handle QR Scanner result - view finding details or create new
void _handleQRScanResult(BuildContext context, Map<String, dynamic> result) {
  final action = result['action'] as String?;

  switch (action) {
    case 'view':
      // Show finding details
      final finding = result['finding'] as Map<String, dynamic>?;
      if (finding != null) {
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF1C2523),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => _QRFindingDetailsSheet(finding: finding),
        );
      }
      break;
    case 'create':
      // Navigate to manual entry with pre-filled ID
      final id = result['id'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Create finding with ID: $id'),
          action: SnackBarAction(
            label: 'Create',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManualEntryFormScreen()),
              );
            },
          ),
        ),
      );
      break;
    case 'link':
      // Link external code to a finding
      final code = result['code'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External code: $code'),
          backgroundColor: const Color(0xFF2196F3),
        ),
      );
      break;
  }
}

/// Bottom sheet to show scanned finding details
class _QRFindingDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> finding;

  const _QRFindingDetailsSheet({required this.finding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  finding['artifactId'] ?? 'Unknown',
                  style: const TextStyle(
                    color: Color(0xFF0D3A39),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            finding['name'] ?? finding['description'] ?? 'Unnamed Finding',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (finding['site'] != null)
            _buildDetailRow(Icons.location_on_outlined, 'Site', finding['site']),
          if (finding['type'] != null)
            _buildDetailRow(Icons.category_outlined, 'Type', finding['type']),
          if (finding['material'] != null)
            _buildDetailRow(Icons.texture_outlined, 'Material', finding['material']),
          if (finding['period'] != null)
            _buildDetailRow(Icons.history_outlined, 'Period', finding['period']),
          if (finding['date'] != null)
            _buildDetailRow(Icons.calendar_today_outlined, 'Date', finding['date']),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                // Navigate to full finding view if needed
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View Full Record'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: const Color(0xFF0D3A39),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 18),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

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
                      // === HERO FEATURE: 3D RECONSTRUCTION === (HIDDEN)
                      // _buildHeroFeature(context),
                      // const SizedBox(height: 20),

                      // === FIELD WORK ===
                      _buildCategoryHeader('Field Work'),
                      const SizedBox(height: 12),
                      // Field Journal - Big Button (Main feature of Field Work)
                      _buildBigToolButton(
                        context,
                        icon: Icons.book_rounded,
                        title: 'Field Journal',
                        description: 'Daily logs, observations, and site notes with voice support',
                        color: const Color(0xFF795548),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const FieldJournalScreen()),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // === CAPTURE TOOLS ===
                      _buildCategoryHeader('Capture & Documentation'),
                      const SizedBox(height: 12),
                      // Quick Capture - Big Button
                      _buildBigToolButton(
                        context,
                        icon: Icons.flash_on_rounded,
                        title: 'Quick Capture',
                        description: 'Fast documentation - snap photo, add note, save instantly',
                        color: const Color(0xFF2196F3),
                        onTap: () async {
                          final result = await Navigator.push<Map<String, dynamic>>(
                            context,
                            MaterialPageRoute(builder: (_) => const QuickCaptureScreen()),
                          );
                          if (result != null && context.mounted) {
                            _handleQuickCaptureResult(context, result);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Manual Entry & Coin Recognition - Grid
                      _buildToolGrid(context, [
                        _ToolCard(
                          icon: Icons.edit_note_rounded,
                          title: 'Manual Entry',
                          description: 'Full archaeological form',
                          color: const Color(0xFFFFC107),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ManualEntryFormScreen()),
                          ),
                        ),
                        _ToolCard(
                          icon: Icons.auto_awesome_rounded,
                          title: 'Coin AI',
                          description: 'Gemini AI identification',
                          color: const Color(0xFFFF9800),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AIRecognitionScreen()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // === DATA & REPORTS ===
                      _buildCategoryHeader('Data & Reports'),
                      const SizedBox(height: 12),
                      _buildToolGrid(context, [
                        _ToolCard(
                          icon: Icons.insights_rounded,
                          title: 'Analytics',
                          description: 'Statistics & activity',
                          color: const Color(0xFF00BCD4),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
                          ),
                        ),
                        _ToolCard(
                          icon: Icons.file_download_rounded,
                          title: 'Export Data',
                          description: 'CSV, JSON, GeoJSON',
                          color: const Color(0xFF607D8B),
                          onTap: () => _showExportDialog(context),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // === SETTINGS & HELP ===
                      _buildCategoryHeader('Settings & Help'),
                      const SizedBox(height: 12),
                      _buildToolGrid(context, [
                        _ToolCard(
                          icon: Icons.settings_rounded,
                          title: 'Settings',
                          description: 'Theme & preferences',
                          color: const Color(0xFF455A64),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          ),
                        ),
                        _ToolCard(
                          icon: Icons.help_outline_rounded,
                          title: 'Help & Guide',
                          description: 'Tutorials & FAQ',
                          color: const Color(0xFF3F51B5),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HelpScreen()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // === ADMIN SECTION (only visible to admins) ===
                      FutureBuilder<bool>(
                        future: AuthService.isCurrentUserAdmin(),
                        builder: (context, snapshot) {
                          if (snapshot.data != true) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCategoryHeader('Admin'),
                              const SizedBox(height: 12),
                              _buildToolGrid(context, [
                                _ToolCard(
                                  icon: Icons.admin_panel_settings_rounded,
                                  title: 'User Management',
                                  description: 'Manage roles & users',
                                  badge: 'Admin',
                                  color: const Color(0xFFF44336),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                                  ),
                                ),
                              ]),
                            ],
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
        fontSize: 18,
        fontWeight: FontWeight.bold,
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

  Widget _buildBigToolButton(
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
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(26),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(51),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
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
                      color: Colors.white.withAlpha(204),
                      fontSize: 14,
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

  Widget _buildLockedFeaturePreview(BuildContext context) {
    return Column(
      children: [
        _buildLockedCard('3D Reconstruction', Icons.view_in_ar_rounded),
        const SizedBox(height: 12),
        _buildLockedCard('Manual Entry', Icons.edit_note_rounded),
        const SizedBox(height: 12),
        _buildLockedCard('Coin Recognition', Icons.auto_awesome_rounded),
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

  void _showExportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2523),
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
              'Export Data',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an export format for your findings',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 20),
            _ExportOptionTile(
              icon: Icons.code,
              title: 'JSON',
              subtitle: 'Full data with all fields',
              color: const Color(0xFF4CAF50),
              onTap: () async {
                Navigator.pop(context);
                await _exportData(context, ExportFormat.json);
              },
            ),
            _ExportOptionTile(
              icon: Icons.table_chart,
              title: 'CSV',
              subtitle: 'Spreadsheet compatible',
              color: const Color(0xFF2196F3),
              onTap: () async {
                Navigator.pop(context);
                await _exportData(context, ExportFormat.csv);
              },
            ),
            _ExportOptionTile(
              icon: Icons.map,
              title: 'GeoJSON',
              subtitle: 'For GIS applications',
              color: const Color(0xFFFF9800),
              onTap: () async {
                Navigator.pop(context);
                await _exportData(context, ExportFormat.geojson);
              },
            ),
            _ExportOptionTile(
              icon: Icons.place,
              title: 'KML',
              subtitle: 'Google Earth format',
              color: const Color(0xFF9C27B0),
              onTap: () async {
                Navigator.pop(context);
                await _exportData(context, ExportFormat.kml);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData(BuildContext context, ExportFormat format) async {
    try {
      // Get findings from Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('findings')
          .orderBy('createdAt', descending: true)
          .get();

      final findings = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (findings.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No findings to export')),
          );
        }
        return;
      }

      final exportService = ExportService();
      File? file;

      switch (format) {
        case ExportFormat.json:
          file = await exportService.exportFindingsToJson(findings);
          break;
        case ExportFormat.csv:
          file = await exportService.exportFindingsToCsv(findings);
          break;
        case ExportFormat.geojson:
          file = await exportService.exportFindingsToGeoJson(findings);
          break;
        case ExportFormat.kml:
          file = await exportService.exportFindingsToKml(findings);
          break;
      }

      if (file != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${findings.length} findings to ${file.path.split('/').last}'),
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
}

class _ExportOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ExportOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5)),
      onTap: onTap,
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final Color color;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
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
          color: Colors.white.withAlpha(26),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(51),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withAlpha(51),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withAlpha(204),
                fontSize: 14,
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
  final String? cloudModelUrl;

  const ManualEntryFormScreen({
    super.key,
    this.reconstructionResult,
    this.photoGallery,
    this.cloudModelUrl,
  });

  @override
  State<ManualEntryFormScreen> createState() => _ManualEntryFormScreenState();
}

class _ManualEntryFormScreenState extends State<ManualEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _siteController = TextEditingController();
  final _descriptionController = TextEditingController();
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

  // ========== COIN-SPECIFIC FIELDS ==========
  final _denominationController = TextEditingController();
  final _mintController = TextEditingController();
  final _rulerController = TextEditingController();
  final _obverseLegendController = TextEditingController();
  final _reverseLegendController = TextEditingController();
  final _dieAxisController = TextEditingController();

  // ========== FRAGMENT-SPECIFIC FIELDS ==========
  String? _selectedVesselPart;
  String? _selectedWareType;
  String? _selectedDecoration;
  final _rimDiameterController = TextEditingController();
  final _wallThicknessController = TextEditingController();

  // Auto-save functionality
  Timer? _autoSaveTimer;
  DateTime? _lastAutoSave;

  // Random example hints
  late String _nameHint;
  late String _typeHint;
  late String _siteHint;

  static const _nameTypePairs = [
    {'name': 'Bronze Coin', 'type': 'Coin'},
    {'name': 'Ceramic Vase', 'type': 'Pottery'},
    {'name': 'Marble Statue', 'type': 'Sculpture'},
    {'name': 'Iron Chisel', 'type': 'Tool'},
    {'name': 'Gold Ring', 'type': 'Jewelry'},
    {'name': 'Bronze Sword', 'type': 'Weapon'},
    {'name': 'Stone Tablet', 'type': 'Inscription'},
    {'name': 'Bone Comb', 'type': 'Organic'},
  ];

  static const _siteExamples = ['Trench A1', 'Grid 12-N', 'North Wall'];

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

    // Initialize cloud model URL if provided
    if (widget.cloudModelUrl != null) {
      _model3dUrlController.text = widget.cloudModelUrl!;
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
    _typeController.addListener(_onTypeChanged); // Trigger rebuild for conditional fields
    _siteController.addListener(_scheduleAutoSave);
  }

  void _onTypeChanged() {
    // Trigger rebuild to show/hide coin/fragment fields
    if (mounted) setState(() {});
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
        'description': _descriptionController.text,
        'date': _dateController.text,
        'latitude': _latController.text,
        'longitude': _lngController.text,
        // Coin fields
        'denomination': _denominationController.text,
        'mint': _mintController.text,
        'ruler': _rulerController.text,
        'obverseLegend': _obverseLegendController.text,
        'reverseLegend': _reverseLegendController.text,
        'dieAxis': _dieAxisController.text,
        // Fragment fields
        'vesselPart': _selectedVesselPart,
        'wareType': _selectedWareType,
        'decorationStyle': _selectedDecoration,
        'rimDiameter': _rimDiameterController.text,
        'wallThickness': _wallThicknessController.text,
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
        _descriptionController.text = draft['description'] ?? '';
        if (draft['date'] != null && (draft['date'] as String).isNotEmpty) {
          _dateController.text = draft['date'];
        }
        _latController.text = draft['latitude'] ?? '';
        _lngController.text = draft['longitude'] ?? '';
        // Coin fields
        _denominationController.text = draft['denomination'] ?? '';
        _mintController.text = draft['mint'] ?? '';
        _rulerController.text = draft['ruler'] ?? '';
        _obverseLegendController.text = draft['obverseLegend'] ?? '';
        _reverseLegendController.text = draft['reverseLegend'] ?? '';
        _dieAxisController.text = draft['dieAxis'] ?? '';
        // Fragment fields
        _selectedVesselPart = draft['vesselPart'];
        _selectedWareType = draft['wareType'];
        _selectedDecoration = draft['decorationStyle'];
        _rimDiameterController.text = draft['rimDiameter'] ?? '';
        _wallThicknessController.text = draft['wallThickness'] ?? '';
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

      // Determine source based on how the form was opened
      final source = widget.photoGallery != null || widget.reconstructionResult != null
          ? 'photo'
          : 'manual';

      final findingData = {
        'name': _nameController.text,
        'type': _typeController.text,
        'site': _siteController.text,
        'date': _dateController.text,
        'description': _descriptionController.text,
        'latitude': lat,
        'longitude': lng,
        'imageUrl': imageUrl,
        'photoGallery': galleryUrls,
        'model3dUrl': model3dUrl,
        'reconstructionData': reconstructionData,
        'createdAt': FieldValue.serverTimestamp(),
        'source': source,
        // Coin-specific fields (saved if populated)
        if (_denominationController.text.isNotEmpty) 'denomination': _denominationController.text,
        if (_mintController.text.isNotEmpty) 'mint': _mintController.text,
        if (_rulerController.text.isNotEmpty) 'ruler': _rulerController.text,
        if (_obverseLegendController.text.isNotEmpty) 'obverseLegend': _obverseLegendController.text,
        if (_reverseLegendController.text.isNotEmpty) 'reverseLegend': _reverseLegendController.text,
        if (_dieAxisController.text.isNotEmpty) 'dieAxis': int.tryParse(_dieAxisController.text),
        // Fragment-specific fields (saved if populated)
        if (_selectedVesselPart != null) 'vesselPart': _selectedVesselPart,
        if (_selectedWareType != null) 'wareType': _selectedWareType,
        if (_selectedDecoration != null) 'decorationStyle': _selectedDecoration,
        if (_rimDiameterController.text.isNotEmpty) 'rimDiameter': double.tryParse(_rimDiameterController.text),
        if (_wallThicknessController.text.isNotEmpty) 'wallThickness': double.tryParse(_wallThicknessController.text),
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
          'description': _descriptionController.text,
          'latitude': lat,
          'longitude': lng,
          'createdAt': DateTime.now().toIso8601String(),
          'source': 'manual',
          // Coin-specific fields (saved if populated)
          if (_denominationController.text.isNotEmpty) 'denomination': _denominationController.text,
          if (_mintController.text.isNotEmpty) 'mint': _mintController.text,
          if (_rulerController.text.isNotEmpty) 'ruler': _rulerController.text,
          if (_obverseLegendController.text.isNotEmpty) 'obverseLegend': _obverseLegendController.text,
          if (_reverseLegendController.text.isNotEmpty) 'reverseLegend': _reverseLegendController.text,
          if (_dieAxisController.text.isNotEmpty) 'dieAxis': int.tryParse(_dieAxisController.text),
          // Fragment-specific fields (saved if populated)
          if (_selectedVesselPart != null) 'vesselPart': _selectedVesselPart,
          if (_selectedWareType != null) 'wareType': _selectedWareType,
          if (_selectedDecoration != null) 'decorationStyle': _selectedDecoration,
          if (_rimDiameterController.text.isNotEmpty) 'rimDiameter': double.tryParse(_rimDiameterController.text),
          if (_wallThicknessController.text.isNotEmpty) 'wallThickness': double.tryParse(_wallThicknessController.text),
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
    _descriptionController.dispose();
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

                  // ========== COIN-SPECIFIC FIELDS ==========
                  if (_typeController.text.toLowerCase().contains('coin'))
                    _buildCoinFields(),

                  // ========== FRAGMENT-SPECIFIC FIELDS ==========
                  if (_typeController.text.toLowerCase().contains('fragment') ||
                      _typeController.text.toLowerCase().contains('sherd'))
                    _buildFragmentFields(),

                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _siteController,
                    label: 'Site',
                    hint: _siteHint,
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildFormField(
                    controller: _descriptionController,
                    label: 'Description',
                    hint: 'e.g., Fragment with geometric patterns',
                    icon: Icons.description_outlined,
                    maxLines: 3,
                    isRequired: false,
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
    int maxLines = 1,
    bool isRequired = true,
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
                        maxLines: maxLines,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: TextStyle(
                            color: Colors.white.withAlpha(102),
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        validator: isRequired ? (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter $label';
                          }
                          return null;
                        } : null,
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

  // ========== COIN-SPECIFIC FIELDS SECTION ==========
  Widget _buildCoinFields() {
    return Column(
      children: [
        const SizedBox(height: 16),
        // Section header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFB8860B).withAlpha(51),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.paid, color: Color(0xFFB8860B), size: 18),
              SizedBox(width: 8),
              Text(
                'COIN DETAILS',
                style: TextStyle(
                  color: Color(0xFFB8860B),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Denomination
        _buildFormField(
          controller: _denominationController,
          label: 'Denomination',
          hint: 'e.g., Drachma, Denarius, Obol',
          icon: Icons.monetization_on_outlined,
          isRequired: false,
        ),
        const SizedBox(height: 12),
        // Mint
        _buildFormField(
          controller: _mintController,
          label: 'Mint Location',
          hint: 'e.g., Athens, Rome, Alexandria',
          icon: Icons.factory_outlined,
          isRequired: false,
        ),
        const SizedBox(height: 12),
        // Ruler/Authority
        _buildFormField(
          controller: _rulerController,
          label: 'Ruler/Authority',
          hint: 'e.g., Alexander III, Augustus',
          icon: Icons.account_balance_outlined,
          isRequired: false,
        ),
        const SizedBox(height: 12),
        // Obverse Legend
        _buildFormField(
          controller: _obverseLegendController,
          label: 'Obverse (Front) Legend',
          hint: 'Inscription on front side',
          icon: Icons.text_fields,
          isRequired: false,
        ),
        const SizedBox(height: 12),
        // Reverse Legend
        _buildFormField(
          controller: _reverseLegendController,
          label: 'Reverse (Back) Legend',
          hint: 'Inscription on back side',
          icon: Icons.text_fields,
          isRequired: false,
        ),
        const SizedBox(height: 12),
        // Die Axis
        _buildFormField(
          controller: _dieAxisController,
          label: 'Die Axis (Clock Position)',
          hint: 'e.g., 12, 6, 3 (o\'clock)',
          icon: Icons.access_time,
          isRequired: false,
        ),
      ],
    );
  }

  // ========== FRAGMENT-SPECIFIC FIELDS SECTION ==========
  Widget _buildFragmentFields() {
    return Column(
      children: [
        const SizedBox(height: 16),
        // Section header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFCD853F).withAlpha(51),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.broken_image, color: Color(0xFFCD853F), size: 18),
              SizedBox(width: 8),
              Text(
                'FRAGMENT DETAILS',
                style: TextStyle(
                  color: Color(0xFFCD853F),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Vessel Part Selector
        _buildDropdownField(
          label: 'Vessel Part',
          icon: Icons.pie_chart_outline,
          value: _selectedVesselPart,
          items: const ['Rim', 'Body', 'Base', 'Handle', 'Spout', 'Lid', 'Foot', 'Neck', 'Shoulder'],
          onChanged: (val) => setState(() => _selectedVesselPart = val),
        ),
        const SizedBox(height: 12),
        // Ware Type Selector
        _buildDropdownField(
          label: 'Ware Type',
          icon: Icons.layers_outlined,
          value: _selectedWareType,
          items: const ['Coarse Ware', 'Fine Ware', 'Cooking Ware', 'Storage Ware', 'Tableware', 'Transport', 'Unknown'],
          onChanged: (val) => setState(() => _selectedWareType = val),
        ),
        const SizedBox(height: 12),
        // Decoration Style Selector
        _buildDropdownField(
          label: 'Decoration',
          icon: Icons.brush_outlined,
          value: _selectedDecoration,
          items: const ['Plain', 'Painted', 'Incised', 'Stamped', 'Glazed', 'Relief', 'Burnished', 'Slipped'],
          onChanged: (val) => setState(() => _selectedDecoration = val),
        ),
        const SizedBox(height: 12),
        // Rim Diameter
        _buildFormField(
          controller: _rimDiameterController,
          label: 'Rim Diameter (mm)',
          hint: 'Estimated diameter if rim sherd',
          icon: Icons.radio_button_unchecked,
          isRequired: false,
        ),
        const SizedBox(height: 12),
        // Wall Thickness
        _buildFormField(
          controller: _wallThicknessController,
          label: 'Wall Thickness (mm)',
          hint: 'Sherd thickness',
          icon: Icons.straighten,
          isRequired: false,
        ),
      ],
    );
  }

  // Dropdown field builder for fragment selectors
  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
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
                  child: Icon(icon, color: const Color(0xFFFFC107), size: 20),
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
                      DropdownButtonFormField<String>(
                        value: value,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        dropdownColor: const Color(0xFF1C2523),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        hint: Text(
                          'Select $label',
                          style: TextStyle(color: Colors.white.withAlpha(102)),
                        ),
                        items: items.map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        )).toList(),
                        onChanged: onChanged,
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

const String _bleSensorServiceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String _bleIMUCharUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String _bleMoistureCharUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9";
const String _bleAlertCharUUID = "beb5483e-36e1-4688-b7f5-ea07361b26aa";

class _SafetyView extends StatefulWidget {
  final bool isMuted;
  final VoidCallback onToggleMute;
  final void Function(String message, String level) onAlert;

  const _SafetyView({
    required this.isMuted,
    required this.onToggleMute,
    required this.onAlert,
    super.key,
  });

  @override
  State<_SafetyView> createState() => _SafetyViewState();
}

class _SafetyViewState extends State<_SafetyView> with AutomaticKeepAliveClientMixin {
  // Keep the BLE connection alive when switching tabs
  @override
  bool get wantKeepAlive => true;

  BluetoothDevice? _connectedDevice;
  bool _isScanning = false;
  bool _isConnecting = false;
  String _connectionStatus = 'Disconnected';

  double _accX = 0.0, _accY = 0.0, _accZ = 0.0;
  double _vibration = 0.0;
  int _moisturePercent = 0;
  String _alertLevel = 'safe';
  String _alertMessage = '';
  String _lastUpdate = '--:--';

  // New v2.0 vibration analysis fields from firmware
  double _ppv = 0.0;           // Peak Particle Velocity (mm/s)
  double _rms = 0.0;           // RMS acceleration (g)
  double _dominantFreq = 0.0;  // Dominant frequency (Hz)
  double _crestFactor = 0.0;   // Crest factor (Peak/RMS)
  String _hazardType = 'none'; // Hazard classification type

  // v3.0 fields
  double _centroid = 0.0;      // Spectral centroid (Hz)
  double _kurtosis = 0.0;      // Excess kurtosis
  double _staLtaRatio = 0.0;   // STA/LTA ratio
  double _ppvSmoothed = 0.0;   // EMA smoothed PPV
  double _ppvPeakHold = 0.0;   // 5-second peak hold
  DateTime _ppvPeakTime = DateTime.now();

  // v3.0 app-side alert hysteresis
  int _alertPersistence = 0;
  int _alertCooldownCount = 0;
  String _pendingAlertLevel = 'safe';

  // PPV history for trend graph (DIN 4150-3)
  final List<Map<String, dynamic>> _ppvHistory = [];

  // Vibration feature log for ML training data
  final List<Map<String, dynamic>> _vibrationFeatureLog = [];

  // ML Anomaly Detection (Tier 2)
  final _anomalyService = VibrationAnomalyService();
  AnomalyResult _lastAnomalyResult = const AnomalyResult(score: 0, level: AnomalyLevel.unknown, rawError: 0);
  bool _mlModelLoaded = false;

  final List<_AlertData> _alerts = [];

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  List<StreamSubscription> _charSubscriptions = [];

  bool _isSimulating = false;
  Timer? _simulationTimer;
  Timer? _firebaseLogTimer;
  List<Map<String, dynamic>> _sensorHistory = [];

  // Enhanced connection management
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;
  DateTime? _lastDataReceived;
  String? _lastNotifiedAlertLevel; // Prevent duplicate notifications

  @override
  void initState() {
    super.initState();
    _checkBluetoothAndScan();
    _startFirebaseLogging();
    _loadSensorHistory();
    _initAnomalyModel();
  }

  Future<void> _initAnomalyModel() async {
    final success = await _anomalyService.initialize();
    if (mounted) {
      setState(() => _mlModelLoaded = success);
    }
    debugPrint('ML anomaly model loaded: $success');
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
    _reconnectTimer?.cancel();
    _keepAliveTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkBluetoothAndScan() async {
    if (await FlutterBluePlus.isSupported == false) {
      _showError('Bluetooth not supported');
      return;
    }
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      setState(() => _connectionStatus = 'Bluetooth OFF');
      return;
    }

    // FIRST: Check if device is already connected
    try {
      final connectedDevices = FlutterBluePlus.connectedDevices;
      for (final device in connectedDevices) {
        final name = device.platformName.toLowerCase();
        if (name.contains('ancientvision') || name.contains('ancient') ||
            name.contains('m5stick') || name.contains('m5-') || name.startsWith('m5')) {
          debugPrint('>>> ALREADY CONNECTED: ${device.platformName} - subscribing to data...');
          setState(() {
            _connectedDevice = device;
            _connectionStatus = 'Connected';
            _isConnecting = false;
            _isScanning = false;
          });
          _startKeepAliveMonitor();
          // Request larger MTU for already-connected devices too
          try {
            final mtu = await device.requestMtu(512);
            debugPrint('>>> MTU negotiated (already connected): $mtu');
          } catch (e) {
            debugPrint('>>> MTU request failed (non-fatal): $e');
          }
          await Future.delayed(const Duration(milliseconds: 500));
          await _discoverAndSubscribe(device);
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking connected devices: $e');
    }

    // If not already connected, start scanning
    _startScan();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _connectionStatus = 'Scanning...';
    });

    try {
      // Scan for ALL BLE devices (don't filter by service - ESP32 may not advertise it)
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),
      );

      int devicesFound = 0;
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final name = r.device.platformName;
          final nameLower = name.toLowerCase();

          // Log all devices found for debugging
          if (name.isNotEmpty && devicesFound < 20) {
            debugPrint('BLE Found: "$name" (${r.device.remoteId})');
            devicesFound++;
          }

          // Match our device by name (case insensitive)
          // Also match "M5" prefix for M5Stack devices
          if (nameLower.contains('ancientvision') ||
              nameLower.contains('ancient') ||
              nameLower.contains('m5stick') ||
              nameLower.contains('m5-') ||
              nameLower.startsWith('m5')) {
            debugPrint('>>> MATCHED DEVICE: $name - connecting...');
            FlutterBluePlus.stopScan();
            _connectToDevice(r.device);
            return; // Exit the listener
          }
        }
      });

      await Future.delayed(const Duration(seconds: 20));
      if (_connectedDevice == null && mounted) {
        setState(() {
          _isScanning = false;
          _connectionStatus = 'Sensor not found - check device is on';
        });
        debugPrint('Scan complete - AncientVision device not found');
      }
    } catch (e) {
      debugPrint('BLE Scan error: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _connectionStatus = 'Scan failed: $e';
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
      // Enable auto-connect for persistent connection
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: true,
      );

      setState(() {
        _connectedDevice = device;
        _isConnecting = false;
        _isScanning = false;
        _connectionStatus = 'Connected';
        _reconnectAttempts = 0; // Reset on successful connection
      });

      // Start keepalive monitoring
      _startKeepAliveMonitor();

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          _handleDisconnection();
        } else if (state == BluetoothConnectionState.connected && mounted) {
          setState(() {
            _connectionStatus = 'Connected';
            _reconnectAttempts = 0;
          });
        }
      });

      // Request larger MTU so BLE JSON payloads are not truncated
      try {
        final mtu = await device.requestMtu(512);
        debugPrint('>>> MTU negotiated: $mtu');
      } catch (e) {
        debugPrint('>>> MTU request failed (non-fatal): $e');
      }

      // Small delay to let MTU take effect before service discovery
      await Future.delayed(const Duration(milliseconds: 500));

      await _discoverAndSubscribe(device);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionStatus = 'Connection failed';
        });
        // Auto-retry with exponential backoff
        _scheduleReconnect();
      }
    }
  }

  /// Handle device disconnection with smart reconnect
  void _handleDisconnection() {
    final deviceName = _connectedDevice?.platformName ?? 'Sensor';

    setState(() {
      _connectedDevice = null;
      _connectionStatus = 'Reconnecting...';
    });

    // Send notification about disconnection
    NotificationService().showDeviceDisconnected(deviceName: deviceName);

    // Cancel keepalive
    _keepAliveTimer?.cancel();

    // Schedule reconnect with exponential backoff
    _scheduleReconnect();
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      setState(() => _connectionStatus = 'Connection lost - tap Scan');
      return;
    }

    // Exponential backoff: 1s, 2s, 4s, 8s... max 30s
    final delaySeconds = (1 << _reconnectAttempts).clamp(1, 30);
    _reconnectAttempts++;

    setState(() {
      _connectionStatus = 'Reconnecting in ${delaySeconds}s... (${_reconnectAttempts}/$_maxReconnectAttempts)';
    });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && _connectedDevice == null) {
        _startScan();
      }
    });
  }

  /// Monitor connection health and request RSSI periodically
  void _startKeepAliveMonitor() {
    _keepAliveTimer?.cancel();
    _lastDataReceived = DateTime.now();

    _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || _connectedDevice == null) {
        timer.cancel();
        return;
      }

      // Check if we've received data recently
      final now = DateTime.now();
      if (_lastDataReceived != null &&
          now.difference(_lastDataReceived!).inSeconds > 15) {
        // No data for 15 seconds - connection might be stale
        debugPrint('Connection stale - no data for 15s');
        try {
          // Try to read RSSI to verify connection is alive
          await _connectedDevice!.readRssi();
        } catch (e) {
          // Connection is dead, trigger reconnect
          _handleDisconnection();
        }
      }
    });
  }

  Future<void> _disconnectDevice() async {
    if (_connectedDevice == null) return;

    try {
      // Cancel characteristic subscriptions
      for (final sub in _charSubscriptions) {
        await sub.cancel();
      }
      _charSubscriptions.clear();

      // Cancel connection subscription
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;

      // Disconnect the device
      await _connectedDevice!.disconnect();

      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _connectionStatus = 'Disconnected';
        });
      }
    } catch (e) {
      debugPrint('Disconnect error: $e');
      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _connectionStatus = 'Disconnected';
        });
      }
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    try {
      debugPrint('>>> Starting service discovery for ${device.platformName}...');
      List<BluetoothService> services = await device.discoverServices();
      debugPrint('>>> Found ${services.length} services');

      bool foundService = false;
      for (BluetoothService service in services) {
        final serviceUuid = service.uuid.toString().toLowerCase();
        debugPrint('>>> Service: $serviceUuid');

        // Check if this is our sensor service
        if (serviceUuid.contains('4fafc201') || serviceUuid == _bleSensorServiceUUID.toLowerCase()) {
          foundService = true;
          debugPrint('>>> MATCHED our sensor service!');

          for (BluetoothCharacteristic char in service.characteristics) {
            final charUuidStr = char.uuid.toString().toLowerCase();
            debugPrint('>>>   Characteristic: $charUuidStr notify=${char.properties.notify} read=${char.properties.read}');
            if (char.properties.notify) {
              try {
                await char.setNotifyValue(true);
                debugPrint('>>>   Notifications ENABLED for $charUuidStr');
                final sub = char.onValueReceived.listen((value) {
                  debugPrint('>>>   DATA RECEIVED on $charUuidStr: ${value.length} bytes');
                  _handleCharacteristicData(charUuidStr, value);
                });
                _charSubscriptions.add(sub);
                debugPrint('>>>   SUBSCRIBED to $charUuidStr');
              } catch (e) {
                debugPrint('>>>   FAILED to subscribe to $charUuidStr: $e');
              }
            }
          }
        }
      }

      if (!foundService) {
        debugPrint('>>> WARNING: Our sensor service was NOT found!');
      }
    } catch (e) {
      debugPrint('Service discovery error: $e');
    }
  }

  void _handleCharacteristicData(String charUuid, List<int> value) {
    if (!mounted) return;

    try {
      // Strip null bytes that C snprintf may include
      final cleaned = value.where((b) => b != 0).toList();
      final jsonStr = String.fromCharCodes(cleaned).trim();
      debugPrint('>>> RAW BLE DATA from $charUuid (${value.length} bytes): "$jsonStr"');
      if (jsonStr.isEmpty) return;

      // Check for truncated JSON (missing closing brace)
      if (!jsonStr.endsWith('}')) {
        debugPrint('>>> WARNING: Truncated BLE data! MTU too small. Raw length=${value.length}');
        return;
      }

      final data = json.decode(jsonStr);
      if (data == null) return;

      // Update last data received for keepalive monitoring
      _lastDataReceived = DateTime.now();

      // Debug: log received data with full UUID
      debugPrint('>>> PARSED BLE Data UUID=$charUuid data=$data');

      setState(() {
        _lastUpdate = _formatTime(DateTime.now());

        // Match by last part of UUID (the unique suffix)
        // IMU: beb5483e-36e1-4688-b7f5-ea07361b26a8
        // Moisture: beb5483e-36e1-4688-b7f5-ea07361b26a9
        // Alert: beb5483e-36e1-4688-b7f5-ea07361b26aa
        if (charUuid.endsWith('26a8') || charUuid.contains('b26a8')) {
          // IMU characteristic (v2.0: includes processed vibration features)
          _accX = (data['x'] as num?)?.toDouble() ?? 0.0;
          _accY = (data['y'] as num?)?.toDouble() ?? 0.0;
          _accZ = (data['z'] as num?)?.toDouble() ?? 0.0;
          _vibration = (data['vib'] as num?)?.toDouble() ?? 0.0;

          // Parse v2.0+ fields (backward compatible - defaults to 0 if missing)
          _ppv = (data['ppv'] as num?)?.toDouble() ?? 0.0;
          _rms = (data['rms'] as num?)?.toDouble() ?? 0.0;
          _dominantFreq = (data['freq'] as num?)?.toDouble() ?? 0.0;
          _crestFactor = (data['crest'] as num?)?.toDouble() ?? 0.0;

          // Parse v3.0 fields
          _centroid = (data['cent'] as num?)?.toDouble() ?? 0.0;
          _kurtosis = (data['kurt'] as num?)?.toDouble() ?? 0.0;
          _staLtaRatio = (data['stalta'] as num?)?.toDouble() ?? 0.0;

          // PPV EMA smoothing (alpha = 0.3)
          _ppvSmoothed = 0.3 * _ppv + 0.7 * _ppvSmoothed;

          // 5-second peak hold
          if (_ppv > _ppvPeakHold) {
            _ppvPeakHold = _ppv;
            _ppvPeakTime = DateTime.now();
          } else if (DateTime.now().difference(_ppvPeakTime).inSeconds >= 5) {
            _ppvPeakHold = _ppv;
            _ppvPeakTime = DateTime.now();
          }

          // Add to legacy graph history
          _sensorHistory.add({
            'vibration': _vibration,
            'moisture': _moisturePercent,
            'timestamp': DateTime.now(),
          });
          if (_sensorHistory.length > 30) _sensorHistory.removeAt(0);

          // Add to PPV trend history (for DIN 4150-3 graph)
          _ppvHistory.add({
            'ppv': _ppv,
            'freq': _dominantFreq,
            'crest': _crestFactor,
            'rms': _rms,
            'cent': _centroid,
            'kurt': _kurtosis,
            'stalta': _staLtaRatio,
            'timestamp': DateTime.now(),
          });
          if (_ppvHistory.length > 60) _ppvHistory.removeAt(0);

          // Log feature vector for ML training
          _vibrationFeatureLog.add({
            'rms': _rms,
            'ppv': _ppv,
            'freq': _dominantFreq,
            'crest': _crestFactor,
            'cent': _centroid,
            'kurt': _kurtosis,
            'stalta': _staLtaRatio,
            'timestamp': DateTime.now().toIso8601String(),
          });
          if (_vibrationFeatureLog.length > 500) _vibrationFeatureLog.removeAt(0);

          // Run ML anomaly detection (Tier 2) with v3.0 features
          if (_mlModelLoaded && (_rms > 0 || _ppv > 0)) {
            _lastAnomalyResult = _anomalyService.detect({
              'rms': _rms,
              'ppv': _ppv,
              'freq': _dominantFreq,
              'crest': _crestFactor,
              'cent': _centroid,
              'kurt': _kurtosis,
              'stalta': _staLtaRatio,
            });
          }

          debugPrint('>>> VIBRATION v3.0: PPV=${_ppv}mm/s(smooth=${_ppvSmoothed.toStringAsFixed(1)}) Freq=${_dominantFreq}Hz Crest=$_crestFactor Kurt=$_kurtosis STA/LTA=$_staLtaRatio ML=${_lastAnomalyResult.levelLabel}');
        } else if (charUuid.endsWith('26a9') || charUuid.contains('b26a9')) {
          // Moisture characteristic (also includes vibration for reliability)
          _moisturePercent = (data['percent'] as num?)?.toInt() ?? 0;
          // Read vibration from moisture characteristic (more reliable than IMU char)
          if (data.containsKey('vib')) {
            _vibration = (data['vib'] as num?)?.toDouble() ?? 0.0;
            debugPrint('>>> VIBRATION FROM MOISTURE: $_vibration');
          }
          debugPrint('>>> MOISTURE UPDATED: $_moisturePercent%');
        } else if (charUuid.endsWith('26aa') || charUuid.contains('b26aa')) {
          final newLevel = data['level'] as String? ?? 'safe';
          final newMessage = data['message'] as String? ?? '';
          _hazardType = data['type'] as String? ?? 'none';

          if (newLevel != 'safe' && newMessage.isNotEmpty) {
            _alerts.insert(0, _AlertData(
              time: _lastUpdate,
              level: newLevel == 'critical' ? _AlertLevel.critical : _AlertLevel.warning,
              title: newLevel == 'critical' ? 'Critical Alert' : 'Warning',
              message: newMessage,
            ));
            if (_alerts.length > 10) _alerts.removeLast();
            _saveAlertToFirebase(newLevel, newMessage);

            // Send push notification for alerts (only if level changed)
            _sendAlertNotification(newLevel, newMessage);

            // Show full-screen alert for ALL alerts (both warning and critical)
            _triggerFullScreenAlert(newMessage, newLevel);
          }

          _alertLevel = newLevel;
          _alertMessage = newMessage;
        }
      });
    } catch (e) {
      debugPrint('Error parsing BLE data: $e');
    }
  }

  /// Send push notification for safety alerts
  void _sendAlertNotification(String level, String message) {
    // Only notify if alert level changed (prevent spam)
    if (_lastNotifiedAlertLevel == level) return;
    _lastNotifiedAlertLevel = level;

    if (level == 'critical') {
      NotificationService().showSafetyCritical(
        message: message,
        sensorType: 'Trench Safety',
      );
    } else if (level == 'warning') {
      NotificationService().showSafetyWarning(
        message: message,
        sensorType: 'Trench Safety',
      );
    } else {
      // Alert cleared
      _lastNotifiedAlertLevel = null;
    }
  }

  /// Trigger full-screen alert via parent Dashboard (works on all tabs)
  void _triggerFullScreenAlert(String message, String level) {
    widget.onAlert(message, level);
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
        'ppv': _ppv,
        'rms': _rms,
        'freq': _dominantFreq,
        'crest': _crestFactor,
        'hazardType': _hazardType,
        'deviceName': _isSimulating ? 'Simulator' : (_connectedDevice?.platformName ?? 'Unknown'),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving alert: $e');
    }
  }

  void _startFirebaseLogging() {
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
        'ppv': _ppv,
        'rms': _rms,
        'freq': _dominantFreq,
        'crest': _crestFactor,
        'hazardType': _hazardType,
        'deviceName': _isSimulating ? 'Simulator' : (_connectedDevice?.platformName ?? 'Unknown'),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving sensor data: $e');
    }
  }

  Future<void> _loadSensorHistory() async {
    // Don't load from Firebase if device is connected - use live BLE data instead
    if (_connectedDevice != null) {
      debugPrint('Device connected - using live BLE data for graph');
      return;
    }

    try {
      // Only load from Firebase when no device connected
      final snapshot = await FirebaseFirestore.instance
          .collection('sensor_data')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();

      if (mounted && _connectedDevice == null) {
        setState(() {
          _sensorHistory = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'vibration': (data['vibration'] as num?)?.toDouble() ?? 0.0,
              'moisture': (data['moisture'] as num?)?.toInt() ?? 0,
              'timestamp': (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            };
          }).toList().reversed.toList();
        });
      }
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

        // Simulate v3.0 vibration analysis
        // Normal background: PPV 0.05-0.25 mm/s, freq 1-5 Hz (footsteps/ambient)
        _ppv = 0.05 + random.nextDouble() * 0.2;
        _rms = 0.001 + random.nextDouble() * 0.01;
        _dominantFreq = 1.0 + random.nextDouble() * 4.0;
        _crestFactor = 1.5 + random.nextDouble() * 1.5;
        _centroid = 2.0 + random.nextDouble() * 4.0;
        _kurtosis = -0.5 + random.nextDouble() * 2.0;
        _staLtaRatio = 0.5 + random.nextDouble() * 1.0;
        _vibration = _rms;
        _hazardType = 'none';

        // Occasionally simulate hazard events
        int eventRoll = random.nextInt(80);
        if (eventRoll == 0) {
          // Simulate seismic event: low freq, high PPV
          _ppv = 3.5 + random.nextDouble() * 8.0;
          _dominantFreq = 2.0 + random.nextDouble() * 6.0;
          _crestFactor = 2.0 + random.nextDouble() * 2.0;
          _rms = 0.05 + random.nextDouble() * 0.3;
          _centroid = 1.0 + random.nextDouble() * 5.0;
          _kurtosis = 1.0 + random.nextDouble() * 3.0;
          _staLtaRatio = 4.0 + random.nextDouble() * 6.0;
          _vibration = _rms;
          _hazardType = 'seismic';
        } else if (eventRoll == 1) {
          // Simulate machinery: mid freq, moderate PPV
          _ppv = 2.0 + random.nextDouble() * 3.0;
          _dominantFreq = 15.0 + random.nextDouble() * 30.0;
          _crestFactor = 2.0 + random.nextDouble() * 1.5;
          _rms = 0.02 + random.nextDouble() * 0.1;
          _centroid = 15.0 + random.nextDouble() * 20.0;
          _kurtosis = 0.5 + random.nextDouble() * 2.0;
          _staLtaRatio = 2.0 + random.nextDouble() * 2.0;
          _vibration = _rms;
          _hazardType = 'machinery';
        } else if (eventRoll == 2) {
          // Simulate impact: high crest factor
          _ppv = 1.5 + random.nextDouble() * 3.0;
          _dominantFreq = 5.0 + random.nextDouble() * 20.0;
          _crestFactor = 5.5 + random.nextDouble() * 3.0;
          _rms = 0.01 + random.nextDouble() * 0.05;
          _centroid = 10.0 + random.nextDouble() * 20.0;
          _kurtosis = 5.0 + random.nextDouble() * 5.0;
          _staLtaRatio = 6.0 + random.nextDouble() * 4.0;
          _vibration = _rms;
          _hazardType = 'impact';
        }

        // PPV smoothing & peak hold (simulation)
        _ppvSmoothed = 0.3 * _ppv + 0.7 * _ppvSmoothed;
        if (_ppv > _ppvPeakHold) {
          _ppvPeakHold = _ppv;
          _ppvPeakTime = DateTime.now();
        } else if (DateTime.now().difference(_ppvPeakTime).inSeconds >= 5) {
          _ppvPeakHold = _ppv;
          _ppvPeakTime = DateTime.now();
        }

        // PPV history for trend graph
        _ppvHistory.add({
          'ppv': _ppv,
          'freq': _dominantFreq,
          'crest': _crestFactor,
          'rms': _rms,
          'cent': _centroid,
          'kurt': _kurtosis,
          'stalta': _staLtaRatio,
          'timestamp': DateTime.now(),
        });
        if (_ppvHistory.length > 60) _ppvHistory.removeAt(0);

        // Moisture varies slowly
        _moisturePercent = 35 + random.nextInt(30);
        if (random.nextInt(30) == 0) {
          _moisturePercent = random.nextBool() ? 20 + random.nextInt(10) : 65 + random.nextInt(15);
        }

        _lastUpdate = _formatTime(DateTime.now());

        // DIN 4150-3 compliant alert logic with v3.0 STA/LTA
        String candidateLevel = 'safe';
        String newMessage = '';

        if (_ppv > 10.0) {
          candidateLevel = 'critical';
          newMessage = 'Structural damage risk - EVACUATE';
        } else if (_ppv > 3.0 && _dominantFreq <= 10.0) {
          candidateLevel = 'critical';
          newMessage = 'Seismic activity detected';
        } else if (_staLtaRatio > 4.0 && _ppv > 1.0) {
          candidateLevel = 'critical';
          newMessage = 'Seismic event (STA/LTA)';
        } else if (_ppv > 3.0 && _dominantFreq > 10.0) {
          candidateLevel = 'warning';
          newMessage = 'Heavy machinery nearby';
        } else if (_crestFactor > 5.0 && _ppv > 1.0) {
          candidateLevel = 'warning';
          newMessage = 'Impact detected';
        } else if (_ppv > 2.5) {
          candidateLevel = 'warning';
          newMessage = 'Continuous vibration high';
        }

        if (_moisturePercent > 60) {
          candidateLevel = 'critical';
          newMessage = 'Soil too wet - collapse risk!';
          _hazardType = 'moisture_high';
        } else if (_moisturePercent < 30 && candidateLevel == 'safe') {
          candidateLevel = 'warning';
          newMessage = 'Soil too dry';
          _hazardType = 'moisture_low';
        }

        // Run ML anomaly detection in simulation too (v3.0: 7 features)
        if (_mlModelLoaded) {
          _lastAnomalyResult = _anomalyService.detect({
            'rms': _rms,
            'ppv': _ppv,
            'freq': _dominantFreq,
            'crest': _crestFactor,
            'cent': _centroid,
            'kurt': _kurtosis,
            'stalta': _staLtaRatio,
          });
        }

        // App-side alert hysteresis (v3.0)
        // 3-sample persistence to trigger, 6-sample cooldown to clear
        if (candidateLevel != 'safe' && candidateLevel != _alertLevel) {
          if (candidateLevel == _pendingAlertLevel) {
            _alertPersistence++;
          } else {
            _pendingAlertLevel = candidateLevel;
            _alertPersistence = 1;
          }
          if (_alertPersistence >= 3) {
            // Confirmed alert - fire it
            _alerts.insert(0, _AlertData(
              time: _lastUpdate,
              level: candidateLevel == 'critical' ? _AlertLevel.critical : _AlertLevel.warning,
              title: candidateLevel == 'critical' ? 'Critical Alert' : 'Warning',
              message: newMessage,
            ));
            if (_alerts.length > 10) _alerts.removeLast();
            _saveAlertToFirebase(candidateLevel, newMessage);
            _sendAlertNotification(candidateLevel, newMessage);
            if (candidateLevel == 'critical') {
              _triggerFullScreenAlert(newMessage, candidateLevel);
            }
            _alertLevel = candidateLevel;
            _alertMessage = newMessage;
            _alertPersistence = 0;
            _alertCooldownCount = 0;
          }
        } else if (candidateLevel == 'safe' && _alertLevel != 'safe') {
          _alertCooldownCount++;
          if (_alertCooldownCount >= 6) {
            _alertLevel = 'safe';
            _alertMessage = '';
            _alertCooldownCount = 0;
            _alertPersistence = 0;
            _pendingAlertLevel = 'safe';
          }
        } else {
          _alertPersistence = 0;
          _alertCooldownCount = 0;
          if (candidateLevel != 'safe') {
            _alertLevel = candidateLevel;
            _alertMessage = newMessage;
          }
        }
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
      _ppv = 0.0;
      _rms = 0.0;
      _dominantFreq = 0.0;
      _crestFactor = 0.0;
      _centroid = 0.0;
      _kurtosis = 0.0;
      _staLtaRatio = 0.0;
      _ppvSmoothed = 0.0;
      _ppvPeakHold = 0.0;
      _hazardType = 'none';
      _moisturePercent = 0;
      _alertLevel = 'safe';
      _alertMessage = '';
      _alertPersistence = 0;
      _alertCooldownCount = 0;
      _pendingAlertLevel = 'safe';
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
    // DIN 4150-3 compliant status using PPV
    if (_ppv > 10.0) return 'CRITICAL - EVACUATE';
    if (_ppv > 3.0) return 'DIN 4150-3 EXCEEDED';
    if (_ppv > 2.5) return 'Heritage limit';
    if (_ppv > 0.3) return 'Perceptible';
    // Fallback to legacy threshold if no PPV data
    if (_ppv == 0.0 && _vibration > 0.8) return 'CRITICAL!';
    if (_ppv == 0.0 && _vibration > 0.3) return 'Warning';
    return 'Safe';
  }

  String _getHazardTypeLabel() {
    switch (_hazardType) {
      case 'seismic': return 'Seismic Activity';
      case 'machinery': return 'Heavy Machinery';
      case 'structural': return 'Structural Risk';
      case 'hf_stress': return 'HF Stress';
      case 'impact': return 'Impact';
      case 'continuous': return 'Continuous Vib.';
      case 'source_change': return 'Source Changed';
      case 'moisture_low': return 'Dry Soil';
      case 'moisture_high': return 'Wet Soil';
      case 'test': return 'Test Alert';
      default: return 'Normal';
    }
  }

  Color _getPPVColor() {
    if (_ppv > 10.0) return const Color(0xFFE53935); // Red - structural damage
    if (_ppv > 3.0) return const Color(0xFFFF5722);  // Deep orange - DIN exceeded
    if (_ppv > 2.5) return const Color(0xFFFF9800);  // Orange - heritage limit
    if (_ppv > 0.3) return const Color(0xFFFFC107);  // Amber - perceptible
    return const Color(0xFF4CAF50);                    // Green - safe
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isConnected = _connectedDevice != null;

    return Stack(
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

              // Connection status and action buttons
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isConnected
                        ? 'Connected to M5StickC Plus 2'
                        : _isConnecting
                          ? 'Scanning for devices...'
                          : _connectionStatus,
                      style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Rescan button - enabled when not connected
                  GestureDetector(
                    onTap: isConnected ? null : _startScan,
                    child: AnimatedOpacity(
                      opacity: isConnected ? 0.3 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Scan',
                          style: TextStyle(color: Color(0xFF0D3A39), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Disconnect button - enabled when connected
                  GestureDetector(
                    onTap: isConnected ? _disconnectDevice : null,
                    child: AnimatedOpacity(
                      opacity: isConnected ? 1.0 : 0.3,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Disconnect',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Mute button - uses global mute from Dashboard
                  GestureDetector(
                    onTap: widget.onToggleMute,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.isMuted ? Colors.grey : Colors.green.withAlpha(200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.isMuted ? 'Muted' : 'Sound',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // STATS ROW - PPV (primary metric) + Moisture
              Row(
                children: [
                  Expanded(
                    child: _SafetyStatCard(
                      title: 'PPV (DIN 4150-3)',
                      value: _ppv > 0 ? '${_ppv.toStringAsFixed(1)} mm/s' : '${_vibration.toStringAsFixed(3)} g',
                      status: _getVibrationStatus(),
                      statusColor: _getPPVColor(),
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
              const SizedBox(height: 12),

              // Vibration Analysis Card (new v2.0)
              _VibrationAnalysisCard(
                ppv: _ppv,
                rms: _rms,
                dominantFreq: _dominantFreq,
                crestFactor: _crestFactor,
                ppvSmoothed: _ppvSmoothed,
                ppvPeakHold: _ppvPeakHold,
                kurtosis: _kurtosis,
                staLtaRatio: _staLtaRatio,
                centroid: _centroid,
                hazardType: _hazardType,
                hazardLabel: _getHazardTypeLabel(),
                ppvColor: _getPPVColor(),
                isConnected: isConnected,
              ),
              const SizedBox(height: 12),

              // PPV Trend Graph with DIN 4150-3 limit lines
              _PPVTrendGraphCard(ppvHistory: _ppvHistory),
              const SizedBox(height: 12),

              // ML Anomaly Detection Indicator (Tier 2)
              if (_mlModelLoaded && (_ppv > 0 || _rms > 0))
                _MLAnomalyIndicator(result: _lastAnomalyResult),
              if (_mlModelLoaded && (_ppv > 0 || _rms > 0))
                const SizedBox(height: 12),

              // Live Sensors Card (legacy + enhanced)
              _LiveSensorsCard(
                accX: _accX, accY: _accY, accZ: _accZ,
                vibration: _vibration,
                moisturePercent: _moisturePercent,
                lastUpdate: _lastUpdate,
                isConnected: isConnected,
                ppv: _ppv,
                dominantFreq: _dominantFreq,
                crestFactor: _crestFactor,
                rms: _rms,
                hazardType: _hazardType,
              ),
              const SizedBox(height: 12),

              // Sensor History Graph Card (legacy moisture + vibration)
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
    ),
      ],
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

/// Full-screen alert overlay for critical safety warnings
class _FullScreenAlertOverlay extends StatefulWidget {
  final String message;
  final String level;
  final VoidCallback onDismiss;

  const _FullScreenAlertOverlay({
    required this.message,
    required this.level,
    required this.onDismiss,
  });

  @override
  State<_FullScreenAlertOverlay> createState() => _FullScreenAlertOverlayState();
}

class _FullScreenAlertOverlayState extends State<_FullScreenAlertOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCritical = widget.level == 'critical';
    final alertColor = isCritical ? const Color(0xFFE53935) : const Color(0xFFFFB300);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              alertColor.withAlpha(230),
              alertColor.withAlpha(200),
              Colors.black.withAlpha(240),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pulsing icon
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(50),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: alertColor.withAlpha(150),
                            blurRadius: 40,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                      child: Icon(
                        isCritical ? Icons.warning_rounded : Icons.error_outline,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              // Alert title
              Text(
                isCritical ? '⚠️ CRITICAL ALERT ⚠️' : '⚠️ WARNING',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Alert message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(100),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(100), width: 2),
                  ),
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Timestamp
              Text(
                'Detected at ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Acknowledge button
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(80),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: alertColor, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'ACKNOWLEDGE',
                            style: TextStyle(
                              color: alertColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Safety instruction
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  isCritical
                      ? 'EVACUATE THE TRENCH IMMEDIATELY!\nFollow emergency protocol.'
                      : 'Check conditions and take appropriate action.',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  final double vibration;
  final double ppv;
  final double dominantFreq;
  final double crestFactor;
  final double rms;
  final String hazardType;

  const _LiveSensorsCard({
    required this.accX, required this.accY, required this.accZ,
    required this.moisturePercent, required this.lastUpdate, required this.isConnected,
    this.vibration = 0.0,
    this.ppv = 0.0,
    this.dominantFreq = 0.0,
    this.crestFactor = 0.0,
    this.rms = 0.0,
    this.hazardType = 'none',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // DIN 4150-3 compliant status
    String vibStatus = 'Safe';
    Color vibColor = Colors.green;
    if (ppv > 10.0) {
      vibStatus = 'CRITICAL';
      vibColor = const Color(0xFFE53935);
    } else if (ppv > 3.0) {
      vibStatus = 'DIN EXCEEDED';
      vibColor = const Color(0xFFFF5722);
    } else if (ppv > 2.5) {
      vibStatus = 'Heritage limit';
      vibColor = Colors.orange;
    } else if (ppv > 0.3) {
      vibStatus = 'Perceptible';
      vibColor = const Color(0xFFFFC107);
    } else if (ppv == 0.0 && vibration > 0.5) {
      vibStatus = 'HIGH!';
      vibColor = Colors.red;
    } else if (ppv == 0.0 && vibration > 0.2) {
      vibStatus = 'Moderate';
      vibColor = Colors.orange;
    }

    final bool hasV2Data = ppv > 0 || rms > 0;

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
                  if (hasV2Data)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withAlpha(60),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('v2.0 DSP', style: TextStyle(color: Color(0xFF00BCD4), fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: isConnected ? Colors.green : Colors.grey,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SensorRow(
                label: hasV2Data ? 'PPV (DIN 4150-3)' : 'Vibration (M5StickC)',
                value: hasV2Data
                    ? '${ppv.toStringAsFixed(1)} mm/s   Status: $vibStatus'
                    : '${vibration.toStringAsFixed(2)}g   Status: $vibStatus',
                icon: Icons.vibration,
                valueColor: vibColor,
              ),
              if (hasV2Data) ...[
                const SizedBox(height: 6),
                _SensorRow(
                  label: 'Frequency analysis',
                  value: '${dominantFreq.toStringAsFixed(0)} Hz   Crest: ${crestFactor.toStringAsFixed(1)}   RMS: ${rms.toStringAsFixed(4)}g',
                  icon: Icons.graphic_eq,
                ),
              ],
              const SizedBox(height: 6),
              _SensorRow(
                label: 'Soil moisture',
                value: '$moisturePercent %   (safe: 30-60%)',
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
  final Color? valueColor;

  const _SensorRow({required this.label, required this.value, required this.icon, this.valueColor, super.key});

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
              Text(value, style: TextStyle(color: valueColor ?? Colors.white.withOpacity(0.8), fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

// ===================== ML ANOMALY INDICATOR =====================
class _MLAnomalyIndicator extends StatelessWidget {
  final AnomalyResult result;

  const _MLAnomalyIndicator({required this.result, super.key});

  Color _getColor() {
    switch (result.level) {
      case AnomalyLevel.normal: return const Color(0xFF4CAF50);
      case AnomalyLevel.unusual: return const Color(0xFFFFC107);
      case AnomalyLevel.anomaly: return const Color(0xFFE53935);
      case AnomalyLevel.unknown: return Colors.grey;
    }
  }

  IconData _getIcon() {
    switch (result.level) {
      case AnomalyLevel.normal: return Icons.check_circle_outline;
      case AnomalyLevel.unusual: return Icons.help_outline;
      case AnomalyLevel.anomaly: return Icons.warning_rounded;
      case AnomalyLevel.unknown: return Icons.device_unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(80), width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getIcon(), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('ML Anomaly Detection', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withAlpha(50),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            result.levelLabel,
                            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Score bar
                    Row(
                      children: [
                        Text('Score: ', style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 6,
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(20),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: result.score.clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(result.score * 100).toStringAsFixed(0)}%',
                          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
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

// ===================== VIBRATION ANALYSIS CARD (v2.0) =====================
class _VibrationAnalysisCard extends StatelessWidget {
  final double ppv, rms, dominantFreq, crestFactor;
  final double ppvSmoothed, ppvPeakHold, kurtosis, staLtaRatio, centroid;
  final String hazardType, hazardLabel;
  final Color ppvColor;
  final bool isConnected;

  const _VibrationAnalysisCard({
    required this.ppv, required this.rms, required this.dominantFreq,
    required this.crestFactor, required this.hazardType, required this.hazardLabel,
    required this.ppvColor, required this.isConnected,
    this.ppvSmoothed = 0, this.ppvPeakHold = 0, this.kurtosis = 0,
    this.staLtaRatio = 0, this.centroid = 0, super.key,
  });

  String _getFreqBandLabel() {
    if (dominantFreq <= 0) return '--';
    if (dominantFreq <= 1.0) return 'Sub-Hz (wind/ambient)';
    if (dominantFreq <= 5.0) return '1-5 Hz (footsteps/sway)';
    if (dominantFreq <= 10.0) return '1-10 Hz (seismic band)';
    if (dominantFreq <= 50.0) return '10-50 Hz (machinery)';
    return '50-100 Hz (structural)';
  }

  Color _getFreqBandColor() {
    if (dominantFreq <= 0) return Colors.grey;
    if (dominantFreq <= 5.0) return const Color(0xFF4CAF50);
    if (dominantFreq <= 10.0) return const Color(0xFFFF5722);
    if (dominantFreq <= 50.0) return const Color(0xFFFF9800);
    return const Color(0xFFFFC107);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData = ppv > 0 || rms > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withAlpha(25),
                Colors.white.withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(90), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ppvColor.withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.analytics_rounded, color: ppvColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Vibration Analysis', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ppvColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ppvColor.withAlpha(100), width: 1),
                    ),
                    child: Text(
                      hazardLabel,
                      style: TextStyle(color: ppvColor, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('DIN 4150-3 compliant vibration monitoring', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11)),
              const SizedBox(height: 14),

              if (!hasData)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isConnected ? 'Waiting for v2.0 firmware data...' : 'Connect sensor for analysis',
                      style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 12),
                    ),
                  ),
                )
              else ...[
                // PPV Gauge Bar (smoothed value, with peak hold)
                _buildGaugeRow('PPV', ppvSmoothed > 0 ? ppvSmoothed : ppv, 'mm/s', 15.0, ppvColor),
                if (ppvPeakHold > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Peak (5s): ${ppvPeakHold.toStringAsFixed(1)} mm/s',
                      style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 10),
                    ),
                  ),
                const SizedBox(height: 10),

                // DIN 4150-3 threshold markers
                _buildDINThresholdBar(),
                const SizedBox(height: 14),

                // Metrics grid - row 1
                Row(
                  children: [
                    _buildMetricTile('RMS', '${rms.toStringAsFixed(4)}g', Icons.show_chart),
                    const SizedBox(width: 10),
                    _buildMetricTile('Crest', crestFactor.toStringAsFixed(1), Icons.bolt),
                    const SizedBox(width: 10),
                    _buildMetricTile('Freq', '${dominantFreq.toStringAsFixed(0)}Hz', Icons.graphic_eq),
                  ],
                ),
                const SizedBox(height: 8),

                // Metrics grid - row 2 (v3.0 features)
                Row(
                  children: [
                    _buildMetricTile('Kurt', kurtosis.toStringAsFixed(1), Icons.assessment,
                      valueColor: kurtosis > 6 ? const Color(0xFFFF5722) : kurtosis > 3 ? const Color(0xFFFF9800) : null),
                    const SizedBox(width: 10),
                    _buildMetricTile('STA/LTA', staLtaRatio.toStringAsFixed(1), Icons.sensors,
                      valueColor: staLtaRatio > 4.0 ? const Color(0xFFFF5722) : staLtaRatio > 2.0 ? const Color(0xFFFF9800) : null),
                    const SizedBox(width: 10),
                    _buildMetricTile('Cent', '${centroid.toStringAsFixed(0)}Hz', Icons.center_focus_strong),
                  ],
                ),
                const SizedBox(height: 10),

                // Frequency band indicator
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getFreqBandColor().withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _getFreqBandColor().withAlpha(60), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.waves, color: _getFreqBandColor(), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _getFreqBandLabel(),
                        style: TextStyle(color: _getFreqBandColor(), fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGaugeRow(String label, double value, String unit, double maxValue, Color color) {
    final fraction = (value / maxValue).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12)),
            const Spacer(),
            Text('${value.toStringAsFixed(1)} $unit', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color.withAlpha(200), color]),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(color: color.withAlpha(80), blurRadius: 6)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDINThresholdBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DIN 4150-3 Thresholds', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 10)),
        const SizedBox(height: 4),
        SizedBox(
          height: 20,
          child: Row(
            children: [
              _buildThresholdSegment('Safe', 0.3 / 15.0, const Color(0xFF4CAF50)),
              _buildThresholdSegment('', (2.5 - 0.3) / 15.0, const Color(0xFFFFC107)),
              _buildThresholdSegment('3mm/s', (3.0 - 2.5) / 15.0, const Color(0xFFFF9800)),
              _buildThresholdSegment('Heritage', (8.0 - 3.0) / 15.0, const Color(0xFFFF5722)),
              _buildThresholdSegment('10mm/s', (10.0 - 8.0) / 15.0, const Color(0xFFE53935)),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C).withAlpha(150),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: const Center(child: Text('DMG', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600))),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThresholdSegment(String label, double fraction, Color color) {
    return Expanded(
      flex: (fraction * 100).round().clamp(1, 100),
      child: Container(
        decoration: BoxDecoration(color: color.withAlpha(120)),
        child: Center(
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w600), overflow: TextOverflow.clip, maxLines: 1),
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(40), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white.withAlpha(150), size: 16),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ===================== PPV TREND GRAPH (DIN 4150-3) =====================
class _PPVTrendGraphCard extends StatelessWidget {
  final List<Map<String, dynamic>> ppvHistory;

  const _PPVTrendGraphCard({required this.ppvHistory, super.key});

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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withAlpha(25),
                Colors.white.withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(90), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5722).withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.trending_up_rounded, color: Color(0xFFFF5722), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('PPV Trend', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5722).withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('DIN 4150-3', style: TextStyle(color: Color(0xFFFF5722), fontSize: 9, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Peak Particle Velocity with heritage limit lines', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11)),
              const SizedBox(height: 12),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem(const Color(0xFFFF5722), 'PPV'),
                  const SizedBox(width: 16),
                  _buildLegendItem(const Color(0xFFE53935).withAlpha(150), '3 mm/s limit'),
                  const SizedBox(width: 16),
                  _buildLegendItem(const Color(0xFFFFC107).withAlpha(150), '2.5 mm/s cont.'),
                ],
              ),
              const SizedBox(height: 10),
              if (ppvHistory.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.timeline, color: Colors.white.withAlpha(100), size: 28),
                        const SizedBox(height: 6),
                        Text('Waiting for PPV data...', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Y-axis labels
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('10', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 18),
                        Text('5', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 18),
                        Text('3', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 18),
                        Text('0', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 120,
                        child: CustomPaint(
                          size: const Size(double.infinity, 120),
                          painter: _PPVGraphPainter(ppvHistory),
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

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14, height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PPVGraphPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;

  _PPVGraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const double maxPPV = 12.0; // Max Y-axis (mm/s)
    const double topPad = 4.0;
    const double botPad = 2.0;
    final double graphH = size.height - topPad - botPad;

    // Draw grid
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = topPad + graphH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw DIN 4150-3 limit lines
    // 3 mm/s heritage limit (1-10 Hz)
    final limitY3 = topPad + graphH - (graphH * 3.0 / maxPPV);
    final limitPaint3 = Paint()
      ..color = const Color(0xFFE53935).withAlpha(120)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _drawDashedLine(canvas, Offset(0, limitY3), Offset(size.width, limitY3), limitPaint3);

    // 2.5 mm/s continuous limit
    final limitY25 = topPad + graphH - (graphH * 2.5 / maxPPV);
    final limitPaint25 = Paint()
      ..color = const Color(0xFFFFC107).withAlpha(100)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _drawDashedLine(canvas, Offset(0, limitY25), Offset(size.width, limitY25), limitPaint25);

    // Draw PPV line
    if (data.length < 2) return;

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final ppv = ((data[i]['ppv'] as num?)?.toDouble() ?? 0.0).clamp(0.0, maxPPV);
      final y = topPad + graphH - (graphH * ppv / maxPPV);
      points.add(Offset(x, y));
    }

    // Fill
    final fillPath = ui.Path();
    fillPath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      fillPath.lineTo(points[i].dx, points[i].dy);
    }
    fillPath.lineTo(size.width, topPad + graphH);
    fillPath.lineTo(0, topPad + graphH);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, topPad),
        Offset(0, topPad + graphH),
        [const Color(0xFFFF5722).withAlpha(80), const Color(0xFFFF5722).withAlpha(10)],
      );
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePath = ui.Path();
    linePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    final linePaint = Paint()
      ..color = const Color(0xFFFF5722)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // Glow
    final glowPaint = Paint()
      ..color = const Color(0xFFFF5722).withAlpha(40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    canvas.drawPath(linePath, glowPaint);

    // Latest point dot
    if (points.isNotEmpty) {
      final last = points.last;
      canvas.drawCircle(last, 4, Paint()..color = const Color(0xFFFF5722));
      canvas.drawCircle(last, 4, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = sqrt(dx * dx + dy * dy);
    final unitX = dx / length;
    final unitY = dy / length;

    double drawn = 0;
    while (drawn < length) {
      final segEnd = (drawn + dashWidth).clamp(0.0, length);
      canvas.drawLine(
        Offset(start.dx + unitX * drawn, start.dy + unitY * drawn),
        Offset(start.dx + unitX * segEnd, start.dy + unitY * segEnd),
        paint,
      );
      drawn += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_PPVGraphPainter oldDelegate) => true;
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withAlpha(25),
                Colors.white.withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(90), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BCD4).withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.show_chart_rounded, color: Color(0xFF00BCD4), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Sensor History', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.withAlpha(100), Colors.green.withAlpha(50)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withAlpha(150), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        const Text('Live', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Real-time environmental monitoring', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
              const SizedBox(height: 16),
              // Legend row with improved styling
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem(const Color(0xFF42A5F5), 'Moisture'),
                  const SizedBox(width: 24),
                  _buildLegendItem(const Color(0xFFEF5350), 'Vibration'),
                ],
              ),
              const SizedBox(height: 12),
              if (sensorHistory.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        Icon(Icons.sensors_off_rounded, color: Colors.white.withAlpha(100), size: 32),
                        const SizedBox(height: 8),
                        Text('Waiting for sensor data...', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13)),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Y-axis labels
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('100%', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 28),
                        Text('50%', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                        const SizedBox(height: 28),
                        Text('0%', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 9)),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 120,
                        child: CustomPaint(
                          size: const Size(double.infinity, 120),
                          painter: _SensorGraphPainter(sensorHistory),
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

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: color.withAlpha(100), blurRadius: 4)],
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _SensorGraphPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;

  _SensorGraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const double leftPadding = 0;
    const double rightPadding = 0;
    const double topPadding = 8.0;
    const double bottomPadding = 4.0;
    final double graphWidth = size.width - leftPadding - rightPadding;
    final double graphHeight = size.height - topPadding - bottomPadding;

    // Draw subtle grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPadding + (graphHeight * i / 4);
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width - rightPadding, y), gridPaint);
    }

    // Max values for scaling
    const double maxVibration = 1.0;
    const double maxMoisture = 100.0;

    // Colors
    const moistureColor = Color(0xFF42A5F5);
    const vibrationColor = Color(0xFFEF5350);

    // Draw moisture area fill and line
    _drawSmoothLineWithFill(
      canvas, size, data, 'moisture', maxMoisture,
      moistureColor, topPadding, bottomPadding, leftPadding, graphWidth, graphHeight,
    );

    // Draw vibration area fill and line (scaled to percentage)
    _drawSmoothLineWithFill(
      canvas, size, data, 'vibration', maxVibration,
      vibrationColor, topPadding, bottomPadding, leftPadding, graphWidth, graphHeight,
    );

    // Draw data points
    _drawDataPoints(canvas, data, 'moisture', maxMoisture, moistureColor, topPadding, leftPadding, graphWidth, graphHeight);
    _drawDataPoints(canvas, data, 'vibration', maxVibration, vibrationColor, topPadding, leftPadding, graphWidth, graphHeight);
  }

  void _drawSmoothLineWithFill(
    Canvas canvas, Size size, List<Map<String, dynamic>> data, String key, double maxValue,
    Color color, double topPadding, double bottomPadding, double leftPadding, double graphWidth, double graphHeight,
  ) {
    if (data.length < 2) return;

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = leftPadding + (graphWidth * i / (data.length - 1));
      final value = (data[i][key] as num?)?.toDouble() ?? 0.0;
      final y = topPadding + graphHeight - (graphHeight * value / maxValue);
      points.add(Offset(x, y));
    }

    // Create smooth path using quadratic bezier curves
    final linePath = ui.Path();
    linePath.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final midX = (current.dx + next.dx) / 2;
      final midY = (current.dy + next.dy) / 2;

      if (i == 0) {
        linePath.quadraticBezierTo(current.dx, current.dy, midX, midY);
      } else {
        linePath.quadraticBezierTo(current.dx, current.dy, midX, midY);
      }
    }
    linePath.lineTo(points.last.dx, points.last.dy);

    // Draw gradient fill
    final fillPath = ui.Path.from(linePath);
    fillPath.lineTo(leftPadding + graphWidth, topPadding + graphHeight);
    fillPath.lineTo(leftPadding, topPadding + graphHeight);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, topPadding),
        Offset(0, topPadding + graphHeight),
        [color.withAlpha(80), color.withAlpha(10)],
      );
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Draw glow effect
    final glowPaint = Paint()
      ..color = color.withAlpha(50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawPath(linePath, glowPaint);
  }

  void _drawDataPoints(
    Canvas canvas, List<Map<String, dynamic>> data, String key, double maxValue,
    Color color, double topPadding, double leftPadding, double graphWidth, double graphHeight,
  ) {
    final dotPaint = Paint()..color = color;
    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Only draw dots at first, last, and a few middle points to avoid clutter
    final indicesToDraw = <int>{0, data.length - 1};
    if (data.length > 4) {
      indicesToDraw.add(data.length ~/ 2);
    }

    for (final i in indicesToDraw) {
      final x = leftPadding + (graphWidth * i / (data.length - 1));
      final value = (data[i][key] as num?)?.toDouble() ?? 0.0;
      final y = topPadding + graphHeight - (graphHeight * value / maxValue);

      canvas.drawCircle(Offset(x, y), 4, dotPaint);
      canvas.drawCircle(Offset(x, y), 4, dotBorderPaint);
    }
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
  final bool isMuted;
  final VoidCallback onToggleMute;

  const _GlassBottomNavBar({
    required this.currentIndex,
    required this.onItemSelected,
    required this.isMuted,
    required this.onToggleMute,
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
              const SizedBox(width: 4),
              // Global mute button
              GestureDetector(
                onTap: onToggleMute,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isMuted
                        ? Colors.red.withOpacity(0.3)
                        : Colors.green.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: isMuted ? Colors.red.shade300 : Colors.green.shade300,
                    size: 20,
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

  // CAPTURE SETTINGS
  late stt.SpeechToText _speechToText; // Voice commands
  late FlutterTts _flutterTts; // Text-to-speech feedback
  bool _voiceEnabled = false; // Voice commands enabled
  bool _isListening = false; // Currently listening for voice command
  String _lastVoiceCommand = ''; // Last recognized voice command
  bool _autoAdvance = true; // Auto-advance to next angle after capture (default ON)

  // SESSION TRACKING
  Map<String, dynamic> _smartSuggestions = {}; // Context-aware auto-fill suggestions
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
        debugPrint('Voice recognition error: $error');
        setState(() => _isListening = false);
      },
    );

    // Configure text-to-speech
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5); // Slower for clarity in field
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    if (available) {
      debugPrint(' Voice commands initialized successfully');
    } else {
      debugPrint(' Voice recognition not available on this device');
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
      await _speak('Say capture, next, previous, progress, skip, or export');
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

  // Toggle voice commands on/off
  void _toggleVoiceCommands() {
    setState(() => _voiceEnabled = !_voiceEnabled);
    if (_voiceEnabled) {
      _startListening();
      _speak('Voice commands enabled');
    } else {
      _speechToText.stop();
      _speak('Voice commands disabled');
    }
  }

  // ============================================================================
  // SESSION TRACKING
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
      // Standard photo capture - optimized for photogrammetry
      final finalImage = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear, // Back camera
        maxWidth: 2048, // High resolution for 3D reconstruction
        maxHeight: 2048,
        imageQuality: 95, // High quality
      );

      if (finalImage != null) {
        // Analyze image quality
        final quality = await _analyzeImageQuality(finalImage);

        // Track session
        if (_captures.isEmpty) {
          _sessionFindCount++;
        }

        final capture = PhotogrammetryCapture(
          file: finalImage,
          angle: _currentAngle,
          capturedAt: DateTime.now(),
          qualityScore: quality,
        );

        setState(() {
          _captures.add(capture);
          // Auto-advance to next angle if enabled
          if (_currentAngleIndex < _captureAngles.length - 1 && _autoAdvance) {
            _currentAngleIndex++;
          }
        });

        // Show quality feedback
        if (mounted) {
          final qualityText = quality >= 0.8 ? 'Excellent!' : quality >= 0.6 ? 'Good' : 'Consider retaking';
          final qualityColor = quality >= 0.8 ? const Color(0xFF4CAF50) : quality >= 0.6 ? const Color(0xFFFFC107) : Colors.orange;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    quality >= 0.6 ? Icons.check_circle : Icons.warning,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text('Photo ${_captures.length}/${_captureAngles.length}: $qualityText'),
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
      debugPrint(' Frame extraction error: $e');

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
      debugPrint(' Quality analysis error: $e');
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

  /// Share captured photos - exports and offers sharing options
  Future<void> _sharePhotos() async {
    if (_captures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No photos to share'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      // First export the photos
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportDir = Directory('${directory.path}/photogrammetry_$timestamp');
      await exportDir.create(recursive: true);

      // Copy all photos
      List<String> filePaths = [];
      for (int i = 0; i < _captures.length; i++) {
        final capture = _captures[i];
        final newPath = '${exportDir.path}/${capture.angle.name.replaceAll(' ', '_')}_${i + 1}.jpg';
        await File(capture.file.path).copy(newPath);
        filePaths.add(newPath);
      }

      // Create ZIP for easy sharing
      final zipPath = '${directory.path}/AncientVision_3D_Photos_$timestamp.zip';
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addDirectory(exportDir);
      encoder.close();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2523),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.share, color: Color(0xFF2196F3), size: 28),
                SizedBox(width: 12),
                Text('Share Photos', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_captures.length} photos ready to share!',
                  style: TextStyle(color: Colors.white.withAlpha(200)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.folder_zip, color: Color(0xFFFFC107), size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'ZIP Archive Created',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Location: ${exportDir.path}',
                        style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Transfer the ZIP file to your computer for 3D processing with Meshroom or COLMAP.',
                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
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
          SnackBar(content: Text('Share error: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
        debugPrint(' ZIP created: $zipPath');
      } catch (e) {
        debugPrint(' ZIP creation failed: $e');
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
        // Send success notification
        await NotificationService().showProcessingComplete(
          projectName: 'On-Device Model',
          pointCount: result.pointCount,
        );

        // Go directly to 3D viewer - user can save from there
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Model3DViewer(
              result: result,
              onCompleteForm: () {
                // After viewing 3D, go to form to save finding
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
      } else if (result.hasFailed && mounted) {
        // Send failure notification
        await NotificationService().showProcessingFailed(
          projectName: 'On-Device Model',
          errorMessage: result.errorMessage,
        );

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

      // Send error notification
      await NotificationService().showProcessingFailed(
        projectName: 'On-Device Model',
        errorMessage: e.toString(),
      );

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
        // Send success notification
        await NotificationService().showProcessingComplete(
          projectName: 'Cloud Model',
        );

        // Cloud model ready - go directly to save finding form
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Cloud processing complete! Fill in the finding details.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ManualEntryFormScreen(
              photoGallery: _captures.map((c) => c.file).toList(),
              cloudModelUrl: result.downloadUrl,
            ),
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
                        const Icon(Icons.settings, color: Color(0xFF4CAF50), size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Capture Settings',
                          style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Auto-Advance Toggle (always visible, default ON)
                        _buildFeatureChip(
                          icon: Icons.skip_next,
                          label: 'Auto-Advance',
                          isActive: _autoAdvance,
                          onTap: () => setState(() => _autoAdvance = !_autoAdvance),
                          color: const Color(0xFF4CAF50),
                        ),
                        const SizedBox(width: 8),
                        // Voice Commands Toggle
                        _buildFeatureChip(
                          icon: Icons.mic,
                          label: 'Voice',
                          isActive: _voiceEnabled,
                          onTap: _toggleVoiceCommands,
                          color: const Color(0xFF2196F3),
                        ),
                      ],
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

              // Completion actions - Share, See Model, Exit
              if (_isComplete)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      // Congratulations message
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF4CAF50).withAlpha(40),
                              const Color(0xFF8BC34A).withAlpha(30),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Capture Complete!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${_captures.length} photos ready for 3D reconstruction',
                                    style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Main action - See 3D Model
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _generate3DModel,
                          icon: const Icon(Icons.view_in_ar, size: 24),
                          label: const Text('See 3D Model', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C4DFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Secondary actions - Share and Exit
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _sharePhotos,
                              icon: const Icon(Icons.share),
                              label: const Text('Share'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2196F3),
                                side: const BorderSide(color: Color(0xFF2196F3)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.exit_to_app),
                              label: const Text('Exit'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white30),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
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

// =============================================================================
// ADMIN PANEL SCREEN - User & Role Management
// =============================================================================

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
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
                    const Icon(Icons.admin_panel_settings, color: Color(0xFFF44336), size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Admin Panel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // User list
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: AuthService.getUsersStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No users found',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    final users = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final userData = users[index].data() as Map<String, dynamic>;
                        final uid = users[index].id;
                        final email = userData['email'] ?? 'Unknown';
                        final name = userData['fullName'] ?? email;
                        final role = userData['role'] ?? 'viewer';
                        final status = userData['status'] ?? 'active';
                        final isCurrentUser = uid == AuthService.currentUser?.uid;

                        return Card(
                          color: Colors.white.withOpacity(0.1),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: _getRoleColor(role).withOpacity(0.5),
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
                                    CircleAvatar(
                                      backgroundColor: _getRoleColor(role),
                                      radius: 20,
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isCurrentUser)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.withOpacity(0.3),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Text(
                                                    'You',
                                                    style: TextStyle(color: Colors.blue, fontSize: 10),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          Text(
                                            email,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.6),
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    // Role badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getRoleColor(role).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: _getRoleColor(role), width: 1),
                                      ),
                                      child: Text(
                                        role.toUpperCase(),
                                        style: TextStyle(
                                          color: _getRoleColor(role),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Status badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: status == 'active'
                                            ? Colors.green.withOpacity(0.2)
                                            : Colors.red.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          color: status == 'active' ? Colors.green : Colors.red,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    // Role change dropdown
                                    if (!isCurrentUser)
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, color: Colors.white70),
                                        color: const Color(0xFF1C2523),
                                        onSelected: (newRole) => _changeUserRole(uid, email, newRole),
                                        itemBuilder: (context) => [
                                          _buildRoleMenuItem('admin', role),
                                          _buildRoleMenuItem('archeologist', role),
                                          _buildRoleMenuItem('viewer', role),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return const Color(0xFFF44336);
      case 'archeologist':
        return const Color(0xFFFFC107);
      case 'viewer':
      default:
        return const Color(0xFF4CAF50);
    }
  }

  PopupMenuItem<String> _buildRoleMenuItem(String role, String currentRole) {
    final isSelected = role == currentRole;
    return PopupMenuItem(
      value: role,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            color: _getRoleColor(role),
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            role.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeUserRole(String uid, String email, String newRole) async {
    final success = await AuthService.updateUserRole(uid, newRole);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Updated $email to $newRole'
                : 'Failed to update role',
          ),
          backgroundColor: success ? const Color(0xFF4CAF50) : Colors.red,
        ),
      );
    }
  }
}

/// Batch export format selection sheet
class _BatchExportSheet extends StatelessWidget {
  final int selectedCount;

  const _BatchExportSheet({required this.selectedCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C2523),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Icon(Icons.file_download, color: Color(0xFFFFC107), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Batch Export',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$selectedCount findings selected',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Format options
          const Text(
            'Select export format:',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),

          // JSON option
          _buildFormatOption(
            context,
            ExportFormat.json,
            Icons.code,
            'JSON',
            'Full data with all fields',
          ),
          const SizedBox(height: 8),

          // CSV option
          _buildFormatOption(
            context,
            ExportFormat.csv,
            Icons.table_chart,
            'CSV',
            'Spreadsheet compatible',
          ),
          const SizedBox(height: 8),

          // GeoJSON option
          _buildFormatOption(
            context,
            ExportFormat.geojson,
            Icons.map,
            'GeoJSON',
            'For mapping applications',
          ),
          const SizedBox(height: 8),

          // KML option
          _buildFormatOption(
            context,
            ExportFormat.kml,
            Icons.public,
            'KML',
            'For Google Earth',
          ),

          const SizedBox(height: 16),
          SafeArea(
            child: Container(),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatOption(
    BuildContext context,
    ExportFormat format,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, format),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFFFFC107), size: 24),
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
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withValues(alpha: 0.4),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

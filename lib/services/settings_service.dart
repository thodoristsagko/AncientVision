import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App theme mode
enum AppThemeMode {
  light('Light', Icons.light_mode),
  dark('Dark', Icons.dark_mode),
  system('System', Icons.settings_brightness);

  final String label;
  final IconData icon;

  const AppThemeMode(this.label, this.icon);
}

/// Measurement unit preference
enum MeasurementSystem {
  metric('Metric', 'cm, m, kg'),
  imperial('Imperial', 'in, ft, lb');

  final String label;
  final String examples;

  const MeasurementSystem(this.label, this.examples);
}

/// Date format preference
enum DateFormatPreference {
  dmy('DD/MM/YYYY', '31/12/2024'),
  mdy('MM/DD/YYYY', '12/31/2024'),
  ymd('YYYY-MM-DD', '2024-12-31');

  final String label;
  final String example;

  const DateFormatPreference(this.label, this.example);
}

/// App accent color options
class AccentColorOption {
  final String name;
  final Color color;

  const AccentColorOption(this.name, this.color);

  static const List<AccentColorOption> options = [
    AccentColorOption('Amber', Color(0xFFFFB300)),
    AccentColorOption('Brown', Color(0xFF8B4513)),
    AccentColorOption('Blue', Color(0xFF1976D2)),
    AccentColorOption('Teal', Color(0xFF00897B)),
    AccentColorOption('Green', Color(0xFF388E3C)),
    AccentColorOption('Purple', Color(0xFF7B1FA2)),
    AccentColorOption('Red', Color(0xFFC62828)),
    AccentColorOption('Orange', Color(0xFFE65100)),
    AccentColorOption('Indigo', Color(0xFF303F9F)),
    AccentColorOption('Pink', Color(0xFFC2185B)),
  ];
}

/// Complete app settings
class AppSettings {
  // Appearance
  final AppThemeMode themeMode;
  final int accentColorIndex;
  final double fontSize;
  final bool compactMode;

  // Regional
  final MeasurementSystem measurementSystem;
  final DateFormatPreference dateFormat;
  final String languageCode;

  // Data & Sync
  final bool autoSync;
  final bool offlineMode;
  final bool compressImages;
  final int imageQuality; // 1-100

  // Notifications
  final bool notificationsEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;

  // Privacy & Security
  final bool requireAuth;
  final bool analyticsEnabled;

  // Field Work
  final bool autoSaveEnabled;
  final int autoSaveInterval; // seconds
  final bool showGpsCoordinates;
  final bool recordWeatherAuto;

  // 3D & Photogrammetry
  final bool useCloudProcessing;
  final bool highQualityPreview;
  final int maxPhotosPerScan;

  AppSettings({
    this.themeMode = AppThemeMode.system,
    this.accentColorIndex = 1, // Brown by default
    this.fontSize = 1.0,
    this.compactMode = false,
    this.measurementSystem = MeasurementSystem.metric,
    this.dateFormat = DateFormatPreference.dmy,
    this.languageCode = 'en',
    this.autoSync = true,
    this.offlineMode = false,
    this.compressImages = true,
    this.imageQuality = 85,
    this.notificationsEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.requireAuth = false,
    this.analyticsEnabled = false,
    this.autoSaveEnabled = true,
    this.autoSaveInterval = 30,
    this.showGpsCoordinates = true,
    this.recordWeatherAuto = false,
    this.useCloudProcessing = true,
    this.highQualityPreview = false,
    this.maxPhotosPerScan = 50,
  });

  Color get accentColor {
    if (accentColorIndex >= 0 && accentColorIndex < AccentColorOption.options.length) {
      return AccentColorOption.options[accentColorIndex].color;
    }
    return AccentColorOption.options[1].color; // Default brown
  }

  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? accentColorIndex,
    double? fontSize,
    bool? compactMode,
    MeasurementSystem? measurementSystem,
    DateFormatPreference? dateFormat,
    String? languageCode,
    bool? autoSync,
    bool? offlineMode,
    bool? compressImages,
    int? imageQuality,
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? requireAuth,
    bool? analyticsEnabled,
    bool? autoSaveEnabled,
    int? autoSaveInterval,
    bool? showGpsCoordinates,
    bool? recordWeatherAuto,
    bool? useCloudProcessing,
    bool? highQualityPreview,
    int? maxPhotosPerScan,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        accentColorIndex: accentColorIndex ?? this.accentColorIndex,
        fontSize: fontSize ?? this.fontSize,
        compactMode: compactMode ?? this.compactMode,
        measurementSystem: measurementSystem ?? this.measurementSystem,
        dateFormat: dateFormat ?? this.dateFormat,
        languageCode: languageCode ?? this.languageCode,
        autoSync: autoSync ?? this.autoSync,
        offlineMode: offlineMode ?? this.offlineMode,
        compressImages: compressImages ?? this.compressImages,
        imageQuality: imageQuality ?? this.imageQuality,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        requireAuth: requireAuth ?? this.requireAuth,
        analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
        autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
        autoSaveInterval: autoSaveInterval ?? this.autoSaveInterval,
        showGpsCoordinates: showGpsCoordinates ?? this.showGpsCoordinates,
        recordWeatherAuto: recordWeatherAuto ?? this.recordWeatherAuto,
        useCloudProcessing: useCloudProcessing ?? this.useCloudProcessing,
        highQualityPreview: highQualityPreview ?? this.highQualityPreview,
        maxPhotosPerScan: maxPhotosPerScan ?? this.maxPhotosPerScan,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'accentColorIndex': accentColorIndex,
        'fontSize': fontSize,
        'compactMode': compactMode,
        'measurementSystem': measurementSystem.name,
        'dateFormat': dateFormat.name,
        'languageCode': languageCode,
        'autoSync': autoSync,
        'offlineMode': offlineMode,
        'compressImages': compressImages,
        'imageQuality': imageQuality,
        'notificationsEnabled': notificationsEnabled,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
        'requireAuth': requireAuth,
        'analyticsEnabled': analyticsEnabled,
        'autoSaveEnabled': autoSaveEnabled,
        'autoSaveInterval': autoSaveInterval,
        'showGpsCoordinates': showGpsCoordinates,
        'recordWeatherAuto': recordWeatherAuto,
        'useCloudProcessing': useCloudProcessing,
        'highQualityPreview': highQualityPreview,
        'maxPhotosPerScan': maxPhotosPerScan,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (m) => m.name == json['themeMode'],
          orElse: () => AppThemeMode.system,
        ),
        accentColorIndex: json['accentColorIndex'] ?? 1,
        fontSize: json['fontSize']?.toDouble() ?? 1.0,
        compactMode: json['compactMode'] ?? false,
        measurementSystem: MeasurementSystem.values.firstWhere(
          (m) => m.name == json['measurementSystem'],
          orElse: () => MeasurementSystem.metric,
        ),
        dateFormat: DateFormatPreference.values.firstWhere(
          (d) => d.name == json['dateFormat'],
          orElse: () => DateFormatPreference.dmy,
        ),
        languageCode: json['languageCode'] ?? 'en',
        autoSync: json['autoSync'] ?? true,
        offlineMode: json['offlineMode'] ?? false,
        compressImages: json['compressImages'] ?? true,
        imageQuality: json['imageQuality'] ?? 85,
        notificationsEnabled: json['notificationsEnabled'] ?? true,
        soundEnabled: json['soundEnabled'] ?? true,
        vibrationEnabled: json['vibrationEnabled'] ?? true,
        requireAuth: json['requireAuth'] ?? false,
        analyticsEnabled: json['analyticsEnabled'] ?? false,
        autoSaveEnabled: json['autoSaveEnabled'] ?? true,
        autoSaveInterval: json['autoSaveInterval'] ?? 30,
        showGpsCoordinates: json['showGpsCoordinates'] ?? true,
        recordWeatherAuto: json['recordWeatherAuto'] ?? false,
        useCloudProcessing: json['useCloudProcessing'] ?? true,
        highQualityPreview: json['highQualityPreview'] ?? false,
        maxPhotosPerScan: json['maxPhotosPerScan'] ?? 50,
      );
}

/// Service for managing app settings
class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _settingsKey = 'app_settings';

  AppSettings _settings = AppSettings();
  bool _isInitialized = false;

  AppSettings get settings => _settings;
  bool get isDarkMode => _settings.themeMode == AppThemeMode.dark;
  Color get accentColor => _settings.accentColor;

  /// Initialize settings from storage
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_settingsKey);

      if (json != null) {
        _settings = AppSettings.fromJson(
          Map<String, dynamic>.from(
            Uri.splitQueryString(json).map((k, v) => MapEntry(k, _parseValue(v))),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      _settings = AppSettings();
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Update settings
  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await _saveSettings();
    notifyListeners();
  }

  /// Update a single setting
  Future<void> updateSetting<T>(String key, T value) async {
    switch (key) {
      case 'themeMode':
        _settings = _settings.copyWith(themeMode: value as AppThemeMode);
        break;
      case 'accentColorIndex':
        _settings = _settings.copyWith(accentColorIndex: value as int);
        break;
      case 'fontSize':
        _settings = _settings.copyWith(fontSize: value as double);
        break;
      case 'compactMode':
        _settings = _settings.copyWith(compactMode: value as bool);
        break;
      case 'measurementSystem':
        _settings = _settings.copyWith(measurementSystem: value as MeasurementSystem);
        break;
      case 'dateFormat':
        _settings = _settings.copyWith(dateFormat: value as DateFormatPreference);
        break;
      case 'autoSync':
        _settings = _settings.copyWith(autoSync: value as bool);
        break;
      case 'offlineMode':
        _settings = _settings.copyWith(offlineMode: value as bool);
        break;
      case 'compressImages':
        _settings = _settings.copyWith(compressImages: value as bool);
        break;
      case 'imageQuality':
        _settings = _settings.copyWith(imageQuality: value as int);
        break;
      case 'notificationsEnabled':
        _settings = _settings.copyWith(notificationsEnabled: value as bool);
        break;
      case 'autoSaveEnabled':
        _settings = _settings.copyWith(autoSaveEnabled: value as bool);
        break;
      case 'showGpsCoordinates':
        _settings = _settings.copyWith(showGpsCoordinates: value as bool);
        break;
      case 'useCloudProcessing':
        _settings = _settings.copyWith(useCloudProcessing: value as bool);
        break;
      case 'highQualityPreview':
        _settings = _settings.copyWith(highQualityPreview: value as bool);
        break;
      case 'maxPhotosPerScan':
        _settings = _settings.copyWith(maxPhotosPerScan: value as int);
        break;
    }

    await _saveSettings();
    notifyListeners();
  }

  /// Toggle dark mode
  Future<void> toggleDarkMode() async {
    final newMode = _settings.themeMode == AppThemeMode.dark
        ? AppThemeMode.light
        : AppThemeMode.dark;
    await updateSetting('themeMode', newMode);
  }

  /// Get theme data based on current settings
  ThemeData getThemeData(Brightness platformBrightness) {
    final isDark = _settings.themeMode == AppThemeMode.dark ||
        (_settings.themeMode == AppThemeMode.system &&
            platformBrightness == Brightness.dark);

    final accentColor = _settings.accentColor;

    if (isDark) {
      return ThemeData(
        brightness: Brightness.dark,
        primaryColor: accentColor,
        colorScheme: ColorScheme.dark(
          primary: accentColor,
          secondary: accentColor,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(fontSize: 16 * _settings.fontSize),
          bodyMedium: TextStyle(fontSize: 14 * _settings.fontSize),
          bodySmall: TextStyle(fontSize: 12 * _settings.fontSize),
        ),
      );
    } else {
      return ThemeData(
        brightness: Brightness.light,
        primaryColor: accentColor,
        colorScheme: ColorScheme.light(
          primary: accentColor,
          secondary: accentColor,
        ),
        scaffoldBackgroundColor: Colors.grey[50],
        cardColor: Colors.white,
        appBarTheme: AppBarTheme(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(fontSize: 16 * _settings.fontSize),
          bodyMedium: TextStyle(fontSize: 14 * _settings.fontSize),
          bodySmall: TextStyle(fontSize: 12 * _settings.fontSize),
        ),
      );
    }
  }

  /// Reset settings to defaults
  Future<void> resetToDefaults() async {
    _settings = AppSettings();
    await _saveSettings();
    notifyListeners();
  }

  /// Save settings to storage
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = _settings.toJson();
      await prefs.setString(
        _settingsKey,
        json.entries.map((e) => '${e.key}=${e.value}').join('&'),
      );
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  dynamic _parseValue(String value) {
    if (value == 'true') return true;
    if (value == 'false') return false;
    final intVal = int.tryParse(value);
    if (intVal != null) return intVal;
    final doubleVal = double.tryParse(value);
    if (doubleVal != null) return doubleVal;
    return value;
  }
}

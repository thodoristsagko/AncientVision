import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Coin identification service using Numista API and local period database
/// Provides accurate coin classification by period, region, and type
class CoinIdentificationService {
  static final CoinIdentificationService _instance = CoinIdentificationService._internal();
  factory CoinIdentificationService() => _instance;
  CoinIdentificationService._internal();

  // Numista API configuration
  // Users can get a free API key at https://en.numista.com/api/
  static const String _baseUrl = 'https://api.numista.com/v3';
  String? _apiKey;

  // Set API key (user should provide their own)
  void setApiKey(String key) {
    _apiKey = key;
  }

  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  /// Comprehensive coin period database
  static const Map<String, CoinPeriodInfo> periodDatabase = {
    // Greek Periods
    'archaic_greek': CoinPeriodInfo(
      period: 'Archaic Greek',
      dateRange: '700-480 BCE',
      characteristics: ['Thick flan', 'Incuse reverse', 'Simple designs', 'Electrum or silver'],
      regions: ['Lydia', 'Ionia', 'Aegina', 'Athens'],
    ),
    'classical_greek': CoinPeriodInfo(
      period: 'Classical Greek',
      dateRange: '480-323 BCE',
      characteristics: ['High relief', 'Artistic excellence', 'City emblems', 'Owl of Athens'],
      regions: ['Athens', 'Corinth', 'Syracuse', 'Macedonia'],
    ),
    'hellenistic': CoinPeriodInfo(
      period: 'Hellenistic',
      dateRange: '323-31 BCE',
      characteristics: ['Royal portraits', 'Larger flans', 'Detailed imagery', 'Alexander types'],
      regions: ['Ptolemaic Egypt', 'Seleucid', 'Macedon', 'Bactria'],
    ),

    // Roman Periods
    'roman_republic': CoinPeriodInfo(
      period: 'Roman Republic',
      dateRange: '280-27 BCE',
      characteristics: ['Denarius silver', 'Roma head', 'Dioscuri', 'Family types'],
      regions: ['Rome', 'Italy'],
    ),
    'roman_imperial': CoinPeriodInfo(
      period: 'Roman Imperial',
      dateRange: '27 BCE - 284 CE',
      characteristics: ['Emperor portraits', 'Legends', 'Sestertius bronze', 'Aureus gold'],
      regions: ['Roman Empire'],
    ),
    'late_roman': CoinPeriodInfo(
      period: 'Late Roman',
      dateRange: '284-476 CE',
      characteristics: ['Smaller modules', 'Christian symbols', 'Multiple emperors', 'Follis bronze'],
      regions: ['Roman Empire', 'Constantinople'],
    ),

    // Byzantine
    'early_byzantine': CoinPeriodInfo(
      period: 'Early Byzantine',
      dateRange: '491-717 CE',
      characteristics: ['Facing busts', 'Cross motifs', 'Greek legends', 'Solidus gold'],
      regions: ['Constantinople', 'Ravenna', 'Carthage'],
    ),
    'middle_byzantine': CoinPeriodInfo(
      period: 'Middle Byzantine',
      dateRange: '717-1204 CE',
      characteristics: ['Christ imagery', 'Cup-shaped', 'Religious themes'],
      regions: ['Constantinople'],
    ),
    'late_byzantine': CoinPeriodInfo(
      period: 'Late Byzantine',
      dateRange: '1204-1453 CE',
      characteristics: ['Debased metal', 'Small module', 'Regional mints'],
      regions: ['Nicaea', 'Thessalonica', 'Constantinople'],
    ),

    // Celtic
    'celtic': CoinPeriodInfo(
      period: 'Celtic',
      dateRange: '300 BCE - 100 CE',
      characteristics: ['Abstract designs', 'Horse motifs', 'Geometric patterns', 'Gold staters'],
      regions: ['Gaul', 'Britain', 'Danubian'],
    ),

    // Medieval
    'early_medieval': CoinPeriodInfo(
      period: 'Early Medieval',
      dateRange: '500-1000 CE',
      characteristics: ['Crude designs', 'Deniers', 'Pennies', 'Cross patterns'],
      regions: ['Frankish', 'Anglo-Saxon', 'Viking'],
    ),
    'high_medieval': CoinPeriodInfo(
      period: 'High Medieval',
      dateRange: '1000-1300 CE',
      characteristics: ['Long cross', 'Short cross', 'Crusader types', 'Grosso silver'],
      regions: ['England', 'France', 'Holy Roman Empire', 'Italian states'],
    ),

    // Islamic
    'umayyad': CoinPeriodInfo(
      period: 'Umayyad Caliphate',
      dateRange: '661-750 CE',
      characteristics: ['Arabic script only', 'No images', 'Dinar gold', 'Dirham silver'],
      regions: ['Damascus', 'North Africa', 'Spain'],
    ),
    'abbasid': CoinPeriodInfo(
      period: 'Abbasid Caliphate',
      dateRange: '750-1258 CE',
      characteristics: ['Kufic script', 'Caliphal names', 'Mint names'],
      regions: ['Baghdad', 'Persia', 'Central Asia'],
    ),

    // Ancient Near East
    'persian': CoinPeriodInfo(
      period: 'Persian Empire',
      dateRange: '550-330 BCE',
      characteristics: ['Daric gold', 'Siglos silver', 'Archer king', 'Incuse reverse'],
      regions: ['Persia', 'Asia Minor'],
    ),
    'parthian': CoinPeriodInfo(
      period: 'Parthian Empire',
      dateRange: '247 BCE - 224 CE',
      characteristics: ['Archer reverse', 'Drachm silver', 'Royal portraits'],
      regions: ['Persia', 'Mesopotamia'],
    ),
    'sasanian': CoinPeriodInfo(
      period: 'Sasanian Empire',
      dateRange: '224-651 CE',
      characteristics: ['Fire altar reverse', 'Drachm silver', 'Distinctive crowns'],
      regions: ['Persia'],
    ),

    // Jewish
    'hasmonean': CoinPeriodInfo(
      period: 'Hasmonean',
      dateRange: '140-37 BCE',
      characteristics: ['Hebrew script', 'No portraits', 'Cornucopia', 'Bronze prutah'],
      regions: ['Judea'],
    ),
    'herodian': CoinPeriodInfo(
      period: 'Herodian',
      dateRange: '37 BCE - 92 CE',
      characteristics: ['Greek legends', 'No portraits (mostly)', 'Symbolic designs'],
      regions: ['Judea'],
    ),
    'jewish_revolt': CoinPeriodInfo(
      period: 'Jewish Revolt',
      dateRange: '66-135 CE',
      characteristics: ['Hebrew/Paleo-Hebrew', 'Temple imagery', 'Year dates', 'Silver shekels'],
      regions: ['Judea'],
    ),
  };

  /// Identify coin period based on visual characteristics
  CoinAnalysisResult analyzeByCharacteristics({
    required String material,
    String? shape,
    String? scriptType,
    String? imageType,
    List<String>? keywords,
  }) {
    final matches = <String, double>{};
    final materialLower = material.toLowerCase();

    for (final entry in periodDatabase.entries) {
      double score = 0;
      final info = entry.value;

      // Check material match
      for (final char in info.characteristics) {
        final charLower = char.toLowerCase();
        if (charLower.contains(materialLower) ||
            (materialLower == 'gold' && charLower.contains('gold')) ||
            (materialLower == 'silver' && charLower.contains('silver')) ||
            (materialLower == 'bronze' && (charLower.contains('bronze') || charLower.contains('copper')))) {
          score += 0.3;
        }
      }

      // Check keyword matches
      if (keywords != null) {
        for (final keyword in keywords) {
          final keywordLower = keyword.toLowerCase();
          for (final char in info.characteristics) {
            if (char.toLowerCase().contains(keywordLower)) {
              score += 0.2;
            }
          }
          for (final region in info.regions) {
            if (region.toLowerCase().contains(keywordLower)) {
              score += 0.2;
            }
          }
        }
      }

      // Check script type
      if (scriptType != null) {
        final scriptLower = scriptType.toLowerCase();
        if ((scriptLower.contains('arabic') && (entry.key.contains('umayyad') || entry.key.contains('abbasid'))) ||
            (scriptLower.contains('greek') && (entry.key.contains('greek') || entry.key.contains('hellenistic'))) ||
            (scriptLower.contains('latin') && entry.key.contains('roman')) ||
            (scriptLower.contains('hebrew') && (entry.key.contains('hasmonean') || entry.key.contains('jewish')))) {
          score += 0.4;
        }
      }

      if (score > 0) {
        matches[entry.key] = score;
      }
    }

    // Sort by score
    final sortedMatches = matches.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedMatches.isEmpty) {
      return CoinAnalysisResult(
        isIdentified: false,
        confidence: 0,
        message: 'Could not identify coin period. Please provide more details.',
      );
    }

    final bestMatch = sortedMatches.first;
    final periodInfo = periodDatabase[bestMatch.key]!;
    final confidence = (bestMatch.value * 100).clamp(0, 100).toDouble();

    return CoinAnalysisResult(
      isIdentified: true,
      confidence: confidence,
      period: periodInfo.period,
      dateRange: periodInfo.dateRange,
      characteristics: periodInfo.characteristics,
      regions: periodInfo.regions,
      alternativePeriods: sortedMatches.skip(1).take(3).map((e) => periodDatabase[e.key]!.period).toList(),
    );
  }

  /// Search Numista database for coins (requires API key)
  Future<List<NumistaCoin>> searchCoins({
    required String query,
    String? category = 'coin',
    int? year,
    int count = 20,
  }) async {
    if (!hasApiKey) {
      throw Exception('Numista API key not set. Get one at https://en.numista.com/api/');
    }

    try {
      final params = {
        'q': query,
        'category': category ?? 'coin',
        'count': count.toString(),
        'lang': 'en',
      };
      if (year != null) {
        params['year'] = year.toString();
      }

      final uri = Uri.parse('$_baseUrl/types').replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {'Numista-API-Key': _apiKey!},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final types = data['types'] as List<dynamic>? ?? [];

        return types.map((t) => NumistaCoin.fromJson(t)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Invalid API key');
      } else {
        throw Exception('API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Numista API error: $e');
      rethrow;
    }
  }

  /// Get detailed coin information from Numista
  Future<NumistaCoinDetails?> getCoinDetails(int coinId) async {
    if (!hasApiKey) return null;

    try {
      final uri = Uri.parse('$_baseUrl/types/$coinId');
      final response = await http.get(
        uri,
        headers: {'Numista-API-Key': _apiKey!},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return NumistaCoinDetails.fromJson(data);
      }
    } catch (e) {
      debugPrint('Error getting coin details: $e');
    }
    return null;
  }

  /// Analyze a coin image locally (color and shape analysis)
  Future<Map<String, dynamic>> analyzeImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return {};

      // Analyze dominant colors
      final colorAnalysis = _analyzeColors(image);

      // Estimate material from color
      String? estimatedMaterial;
      if (colorAnalysis['isGolden'] == true) {
        estimatedMaterial = 'Gold or Bronze';
      } else if (colorAnalysis['isSilvery'] == true) {
        estimatedMaterial = 'Silver';
      } else if (colorAnalysis['isGreen'] == true) {
        estimatedMaterial = 'Bronze with patina';
      } else if (colorAnalysis['isBrown'] == true) {
        estimatedMaterial = 'Bronze or Copper';
      }

      return {
        'estimatedMaterial': estimatedMaterial,
        'colorAnalysis': colorAnalysis,
        'isCircular': true, // Assume coin shape
      };
    } catch (e) {
      debugPrint('Image analysis error: $e');
      return {};
    }
  }

  Map<String, dynamic> _analyzeColors(img.Image image) {
    int totalR = 0, totalG = 0, totalB = 0;
    int pixelCount = 0;

    // Sample every 10th pixel for performance
    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixel(x, y);
        totalR += pixel.r.toInt();
        totalG += pixel.g.toInt();
        totalB += pixel.b.toInt();
        pixelCount++;
      }
    }

    final avgR = totalR ~/ pixelCount;
    final avgG = totalG ~/ pixelCount;
    final avgB = totalB ~/ pixelCount;

    return {
      'avgR': avgR,
      'avgG': avgG,
      'avgB': avgB,
      'isGolden': avgR > 150 && avgG > 100 && avgB < 100,
      'isSilvery': avgR > 150 && avgG > 150 && avgB > 150 && (avgR - avgB).abs() < 30,
      'isGreen': avgG > avgR && avgG > avgB && avgG > 80,
      'isBrown': avgR > avgG && avgR > avgB && avgR < 180 && avgG < 150,
    };
  }
}

/// Information about a coin period
class CoinPeriodInfo {
  final String period;
  final String dateRange;
  final List<String> characteristics;
  final List<String> regions;

  const CoinPeriodInfo({
    required this.period,
    required this.dateRange,
    required this.characteristics,
    required this.regions,
  });
}

/// Result of coin analysis
class CoinAnalysisResult {
  final bool isIdentified;
  final double confidence;
  final String? period;
  final String? dateRange;
  final List<String>? characteristics;
  final List<String>? regions;
  final List<String>? alternativePeriods;
  final String? message;

  CoinAnalysisResult({
    required this.isIdentified,
    required this.confidence,
    this.period,
    this.dateRange,
    this.characteristics,
    this.regions,
    this.alternativePeriods,
    this.message,
  });

  Map<String, dynamic> toJson() => {
    'isIdentified': isIdentified,
    'confidence': confidence,
    'period': period,
    'dateRange': dateRange,
    'characteristics': characteristics,
    'regions': regions,
    'alternativePeriods': alternativePeriods,
    'message': message,
  };
}

/// Coin from Numista search
class NumistaCoin {
  final int id;
  final String title;
  final String? category;
  final String? issuer;
  final int? minYear;
  final int? maxYear;
  final String? obverseThumb;
  final String? reverseThumb;

  NumistaCoin({
    required this.id,
    required this.title,
    this.category,
    this.issuer,
    this.minYear,
    this.maxYear,
    this.obverseThumb,
    this.reverseThumb,
  });

  factory NumistaCoin.fromJson(Map<String, dynamic> json) {
    return NumistaCoin(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      category: json['category'],
      issuer: json['issuer']?['name'],
      minYear: json['min_year'],
      maxYear: json['max_year'],
      obverseThumb: json['obverse']?['thumbnail'],
      reverseThumb: json['reverse']?['thumbnail'],
    );
  }

  String get yearRange {
    if (minYear == null && maxYear == null) return 'Unknown';
    if (minYear == maxYear) return '$minYear';
    return '${minYear ?? '?'} - ${maxYear ?? '?'}';
  }
}

/// Detailed coin information from Numista
class NumistaCoinDetails {
  final int id;
  final String title;
  final String? issuer;
  final String? ruler;
  final String? type;
  final String? material;
  final String? weight;
  final String? diameter;
  final String? obverseDescription;
  final String? reverseDescription;
  final int? minYear;
  final int? maxYear;

  NumistaCoinDetails({
    required this.id,
    required this.title,
    this.issuer,
    this.ruler,
    this.type,
    this.material,
    this.weight,
    this.diameter,
    this.obverseDescription,
    this.reverseDescription,
    this.minYear,
    this.maxYear,
  });

  factory NumistaCoinDetails.fromJson(Map<String, dynamic> json) {
    return NumistaCoinDetails(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      issuer: json['issuer']?['name'],
      ruler: json['ruler']?['name'],
      type: json['type'],
      material: json['composition']?['text'],
      weight: json['weight']?.toString(),
      diameter: json['size']?.toString(),
      obverseDescription: json['obverse']?['description'],
      reverseDescription: json['reverse']?['description'],
      minYear: json['min_year'],
      maxYear: json['max_year'],
    );
  }
}

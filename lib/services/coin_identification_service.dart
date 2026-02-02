import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Advanced coin identification service using Numista API and comprehensive period database
/// Provides accurate coin classification by period, region, material, and characteristics
/// Supports 40+ historical periods from ancient to modern times
class CoinIdentificationService {
  static final CoinIdentificationService _instance = CoinIdentificationService._internal();
  factory CoinIdentificationService() => _instance;
  CoinIdentificationService._internal();

  // Numista API configuration
  static const String _baseUrl = 'https://api.numista.com/v3';
  String? _apiKey;

  // Classification cache for performance
  final Map<String, CoinAnalysisResult> _cache = {};

  void setApiKey(String key) => _apiKey = key;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  /// Comprehensive coin period database - 40+ periods covering world history
  static const Map<String, CoinPeriodInfo> periodDatabase = {
    // ═══════════════════════════════════════════════════════════════
    // GREEK WORLD (700 BCE - 31 BCE)
    // ═══════════════════════════════════════════════════════════════
    'archaic_greek': CoinPeriodInfo(
      period: 'Archaic Greek',
      dateRange: '700-480 BCE',
      characteristics: ['Thick flan', 'Incuse reverse', 'Simple designs', 'Electrum or silver', 'Turtle', 'Lion head'],
      regions: ['Lydia', 'Ionia', 'Aegina', 'Athens', 'Corinth'],
      materials: ['Electrum', 'Silver'],
      weight: 0.3,
    ),
    'classical_greek': CoinPeriodInfo(
      period: 'Classical Greek',
      dateRange: '480-323 BCE',
      characteristics: ['High relief', 'Artistic excellence', 'City emblems', 'Owl of Athens', 'Pegasus', 'Tetradrachm'],
      regions: ['Athens', 'Corinth', 'Syracuse', 'Macedonia', 'Thebes'],
      materials: ['Silver', 'Gold', 'Bronze'],
      weight: 0.35,
    ),
    'hellenistic': CoinPeriodInfo(
      period: 'Hellenistic',
      dateRange: '323-31 BCE',
      characteristics: ['Royal portraits', 'Larger flans', 'Detailed imagery', 'Alexander types', 'Elephant', 'Zeus'],
      regions: ['Ptolemaic Egypt', 'Seleucid Empire', 'Macedon', 'Bactria', 'Pergamon'],
      materials: ['Silver', 'Gold', 'Bronze'],
      weight: 0.35,
    ),

    // ═══════════════════════════════════════════════════════════════
    // ROMAN WORLD (280 BCE - 476 CE)
    // ═══════════════════════════════════════════════════════════════
    'roman_republic': CoinPeriodInfo(
      period: 'Roman Republic',
      dateRange: '280-27 BCE',
      characteristics: ['Denarius silver', 'Roma head', 'Dioscuri', 'Family types', 'Quadriga', 'Janus'],
      regions: ['Rome', 'Italy', 'Spain', 'Sicily'],
      materials: ['Silver', 'Bronze', 'Gold'],
      weight: 0.4,
    ),
    'roman_imperial_early': CoinPeriodInfo(
      period: 'Early Roman Imperial',
      dateRange: '27 BCE - 96 CE',
      characteristics: ['Emperor portraits', 'Julio-Claudian', 'Flavian', 'Aureus gold', 'Denarius', 'Sestertius'],
      regions: ['Roman Empire'],
      materials: ['Gold', 'Silver', 'Bronze', 'Orichalcum'],
      weight: 0.45,
    ),
    'roman_imperial_high': CoinPeriodInfo(
      period: 'High Roman Imperial',
      dateRange: '96-235 CE',
      characteristics: ['Nerva-Antonine', 'Severan', 'High quality', 'Detailed portraits', 'Architectural reverses'],
      regions: ['Roman Empire'],
      materials: ['Gold', 'Silver', 'Bronze'],
      weight: 0.45,
    ),
    'roman_crisis': CoinPeriodInfo(
      period: 'Crisis of Third Century',
      dateRange: '235-284 CE',
      characteristics: ['Debased silver', 'Antoninianus', 'Radiate crown', 'Rapid succession', 'Provincial mints'],
      regions: ['Roman Empire', 'Gallic Empire', 'Palmyrene Empire'],
      materials: ['Billon', 'Bronze', 'Silver'],
      weight: 0.35,
    ),
    'late_roman': CoinPeriodInfo(
      period: 'Late Roman',
      dateRange: '284-476 CE',
      characteristics: ['Smaller modules', 'Christian symbols', 'Chi-Rho', 'Follis', 'Solidus', 'Multiple emperors'],
      regions: ['Roman Empire', 'Constantinople', 'Trier', 'Antioch'],
      materials: ['Gold', 'Bronze', 'Silver'],
      weight: 0.4,
    ),

    // ═══════════════════════════════════════════════════════════════
    // BYZANTINE EMPIRE (491-1453 CE)
    // ═══════════════════════════════════════════════════════════════
    'early_byzantine': CoinPeriodInfo(
      period: 'Early Byzantine',
      dateRange: '491-717 CE',
      characteristics: ['Facing busts', 'Cross motifs', 'Greek legends', 'Solidus gold', 'Follis large', 'Justinian'],
      regions: ['Constantinople', 'Ravenna', 'Carthage', 'Alexandria'],
      materials: ['Gold', 'Bronze', 'Silver'],
      weight: 0.4,
    ),
    'middle_byzantine': CoinPeriodInfo(
      period: 'Middle Byzantine',
      dateRange: '717-1204 CE',
      characteristics: ['Christ imagery', 'Cup-shaped (scyphate)', 'Religious themes', 'Histamenon', 'Iconoclasm'],
      regions: ['Constantinople', 'Thessalonica'],
      materials: ['Gold', 'Electrum', 'Bronze'],
      weight: 0.4,
    ),
    'late_byzantine': CoinPeriodInfo(
      period: 'Late Byzantine',
      dateRange: '1204-1453 CE',
      characteristics: ['Debased metal', 'Small module', 'Regional mints', 'Hyperpyron', 'Latin influence'],
      regions: ['Nicaea', 'Thessalonica', 'Constantinople', 'Trebizond'],
      materials: ['Electrum', 'Silver', 'Bronze'],
      weight: 0.35,
    ),

    // ═══════════════════════════════════════════════════════════════
    // CELTIC & BARBARIAN (300 BCE - 800 CE)
    // ═══════════════════════════════════════════════════════════════
    'celtic': CoinPeriodInfo(
      period: 'Celtic',
      dateRange: '300 BCE - 100 CE',
      characteristics: ['Abstract designs', 'Horse motifs', 'Geometric patterns', 'Gold staters', 'Boar', 'Chariot'],
      regions: ['Gaul', 'Britain', 'Danubian', 'Iberia'],
      materials: ['Gold', 'Silver', 'Bronze', 'Potin'],
      weight: 0.35,
    ),
    'vandal': CoinPeriodInfo(
      period: 'Vandal Kingdom',
      dateRange: '429-534 CE',
      characteristics: ['Crude style', 'Roman imitation', 'North African', 'Siliqua', 'Nummi'],
      regions: ['Carthage', 'North Africa'],
      materials: ['Silver', 'Bronze'],
      weight: 0.25,
    ),
    'ostrogothic': CoinPeriodInfo(
      period: 'Ostrogothic Kingdom',
      dateRange: '493-553 CE',
      characteristics: ['Roman tradition', 'Theodoric', 'Ravenna mint', 'Monogram', 'Half-siliqua'],
      regions: ['Italy', 'Ravenna', 'Rome'],
      materials: ['Gold', 'Silver', 'Bronze'],
      weight: 0.3,
    ),
    'visigothic': CoinPeriodInfo(
      period: 'Visigothic Kingdom',
      dateRange: '418-721 CE',
      characteristics: ['Tremissis gold', 'Crude portraits', 'Cross reverse', 'Iberian'],
      regions: ['Spain', 'Southern Gaul'],
      materials: ['Gold', 'Bronze'],
      weight: 0.3,
    ),
    'merovingian': CoinPeriodInfo(
      period: 'Merovingian',
      dateRange: '481-751 CE',
      characteristics: ['Tremissis', 'Deniers', 'Crude style', 'Many mints', 'Cross motifs'],
      regions: ['Frankish Gaul', 'Burgundy'],
      materials: ['Gold', 'Silver'],
      weight: 0.3,
    ),

    // ═══════════════════════════════════════════════════════════════
    // MEDIEVAL EUROPE (500-1500 CE)
    // ═══════════════════════════════════════════════════════════════
    'early_medieval': CoinPeriodInfo(
      period: 'Early Medieval',
      dateRange: '500-1000 CE',
      characteristics: ['Crude designs', 'Deniers', 'Pennies', 'Cross patterns', 'Sceatta'],
      regions: ['Frankish', 'Anglo-Saxon', 'Viking', 'Carolingian'],
      materials: ['Silver', 'Bronze'],
      weight: 0.3,
    ),
    'carolingian': CoinPeriodInfo(
      period: 'Carolingian',
      dateRange: '751-987 CE',
      characteristics: ['Denier silver', 'Charlemagne', 'Monogram', 'Temple design', 'Cross potent'],
      regions: ['Frankish Empire', 'Italy', 'Germany'],
      materials: ['Silver'],
      weight: 0.35,
    ),
    'viking': CoinPeriodInfo(
      period: 'Viking Age',
      dateRange: '793-1066 CE',
      characteristics: ['Imitations', 'Hack silver', 'Thor hammer', 'Raven', 'Ship'],
      regions: ['Scandinavia', 'England', 'Ireland', 'Normandy'],
      materials: ['Silver'],
      weight: 0.3,
    ),
    'high_medieval': CoinPeriodInfo(
      period: 'High Medieval',
      dateRange: '1000-1300 CE',
      characteristics: ['Long cross', 'Short cross', 'Crusader types', 'Grosso silver', 'Bracteate'],
      regions: ['England', 'France', 'Holy Roman Empire', 'Italian states'],
      materials: ['Silver', 'Gold', 'Billon'],
      weight: 0.35,
    ),
    'crusader': CoinPeriodInfo(
      period: 'Crusader States',
      dateRange: '1099-1291 CE',
      characteristics: ['Cross designs', 'Latin legends', 'Arabic imitations', 'Bezant', 'Denier'],
      regions: ['Jerusalem', 'Antioch', 'Tripoli', 'Acre'],
      materials: ['Gold', 'Silver', 'Billon'],
      weight: 0.35,
    ),
    'late_medieval': CoinPeriodInfo(
      period: 'Late Medieval',
      dateRange: '1300-1500 CE',
      characteristics: ['Florins', 'Ducats', 'Groats', 'Detailed heraldry', 'Renaissance influence'],
      regions: ['Florence', 'Venice', 'England', 'France', 'Burgundy'],
      materials: ['Gold', 'Silver'],
      weight: 0.35,
    ),

    // ═══════════════════════════════════════════════════════════════
    // ISLAMIC WORLD (661-1924 CE)
    // ═══════════════════════════════════════════════════════════════
    'umayyad': CoinPeriodInfo(
      period: 'Umayyad Caliphate',
      dateRange: '661-750 CE',
      characteristics: ['Arabic script only', 'No images', 'Dinar gold', 'Dirham silver', 'Kalima'],
      regions: ['Damascus', 'North Africa', 'Spain (Al-Andalus)'],
      materials: ['Gold', 'Silver', 'Bronze'],
      weight: 0.4,
    ),
    'abbasid': CoinPeriodInfo(
      period: 'Abbasid Caliphate',
      dateRange: '750-1258 CE',
      characteristics: ['Kufic script', 'Caliphal names', 'Mint names', 'Double margin'],
      regions: ['Baghdad', 'Persia', 'Central Asia', 'Egypt'],
      materials: ['Gold', 'Silver', 'Bronze'],
      weight: 0.4,
    ),
    'fatimid': CoinPeriodInfo(
      period: 'Fatimid Caliphate',
      dateRange: '909-1171 CE',
      characteristics: ['Concentric circles', 'Shia legends', 'Egypt-centered', 'Dinar'],
      regions: ['Egypt', 'North Africa', 'Sicily', 'Syria'],
      materials: ['Gold', 'Silver'],
      weight: 0.35,
    ),
    'ayyubid': CoinPeriodInfo(
      period: 'Ayyubid Dynasty',
      dateRange: '1171-1260 CE',
      characteristics: ['Saladin', 'Crusader conflict', 'Dirham silver', 'Egyptian style'],
      regions: ['Egypt', 'Syria', 'Yemen'],
      materials: ['Gold', 'Silver', 'Bronze'],
      weight: 0.35,
    ),
    'mamluk': CoinPeriodInfo(
      period: 'Mamluk Sultanate',
      dateRange: '1250-1517 CE',
      characteristics: ['Sultanate titles', 'Heraldic blazons', 'Large flans'],
      regions: ['Egypt', 'Syria', 'Hejaz'],
      materials: ['Gold', 'Silver', 'Bronze'],
      weight: 0.35,
    ),
    'ottoman': CoinPeriodInfo(
      period: 'Ottoman Empire',
      dateRange: '1299-1924 CE',
      characteristics: ['Tughra', 'Sultans name', 'Akshe silver', 'Para', 'Kurus'],
      regions: ['Turkey', 'Balkans', 'Middle East', 'North Africa'],
      materials: ['Gold', 'Silver', 'Bronze', 'Billon'],
      weight: 0.4,
    ),

    // ═══════════════════════════════════════════════════════════════
    // PERSIAN & CENTRAL ASIAN (550 BCE - 1925 CE)
    // ═══════════════════════════════════════════════════════════════
    'achaemenid': CoinPeriodInfo(
      period: 'Persian Empire (Achaemenid)',
      dateRange: '550-330 BCE',
      characteristics: ['Daric gold', 'Siglos silver', 'Archer king', 'Incuse reverse', 'Thick flan'],
      regions: ['Persia', 'Asia Minor', 'Babylon'],
      materials: ['Gold', 'Silver'],
      weight: 0.4,
    ),
    'parthian': CoinPeriodInfo(
      period: 'Parthian Empire',
      dateRange: '247 BCE - 224 CE',
      characteristics: ['Archer reverse', 'Drachm silver', 'Royal portraits', 'Greek legends', 'Tiara'],
      regions: ['Persia', 'Mesopotamia', 'Bactria'],
      materials: ['Silver', 'Bronze'],
      weight: 0.4,
    ),
    'sasanian': CoinPeriodInfo(
      period: 'Sasanian Empire',
      dateRange: '224-651 CE',
      characteristics: ['Fire altar reverse', 'Drachm silver', 'Distinctive crowns', 'Thin flan', 'Pahlavi script'],
      regions: ['Persia', 'Mesopotamia', 'Central Asia'],
      materials: ['Silver', 'Gold', 'Bronze'],
      weight: 0.45,
    ),
    'samanid': CoinPeriodInfo(
      period: 'Samanid Empire',
      dateRange: '819-999 CE',
      characteristics: ['Islamic style', 'Central Asian', 'Dirham silver', 'Trade coins'],
      regions: ['Transoxiana', 'Persia', 'Afghanistan'],
      materials: ['Silver', 'Gold'],
      weight: 0.3,
    ),

    // ═══════════════════════════════════════════════════════════════
    // JEWISH COINAGE (140 BCE - 135 CE)
    // ═══════════════════════════════════════════════════════════════
    'hasmonean': CoinPeriodInfo(
      period: 'Hasmonean',
      dateRange: '140-37 BCE',
      characteristics: ['Hebrew script', 'No portraits', 'Cornucopia', 'Bronze prutah', 'Anchor', 'Star'],
      regions: ['Judea', 'Jerusalem'],
      materials: ['Bronze'],
      weight: 0.35,
    ),
    'herodian': CoinPeriodInfo(
      period: 'Herodian',
      dateRange: '37 BCE - 92 CE',
      characteristics: ['Greek legends', 'No portraits (mostly)', 'Symbolic designs', 'Prutah', 'Galley'],
      regions: ['Judea', 'Galilee'],
      materials: ['Bronze'],
      weight: 0.35,
    ),
    'jewish_revolt': CoinPeriodInfo(
      period: 'Jewish Revolt',
      dateRange: '66-135 CE',
      characteristics: ['Hebrew/Paleo-Hebrew', 'Temple imagery', 'Year dates', 'Silver shekels', 'Vine leaf', 'Chalice'],
      regions: ['Judea', 'Jerusalem'],
      materials: ['Silver', 'Bronze'],
      weight: 0.4,
    ),

    // ═══════════════════════════════════════════════════════════════
    // INDIAN SUBCONTINENT (600 BCE - 1947 CE)
    // ═══════════════════════════════════════════════════════════════
    'mauryan': CoinPeriodInfo(
      period: 'Mauryan Empire',
      dateRange: '322-185 BCE',
      characteristics: ['Punch-marked', 'Multiple symbols', 'Bent bar', 'Silver karshapana'],
      regions: ['India', 'Afghanistan', 'Bangladesh'],
      materials: ['Silver', 'Copper'],
      weight: 0.35,
    ),
    'indo_greek': CoinPeriodInfo(
      period: 'Indo-Greek Kingdom',
      dateRange: '180 BCE - 10 CE',
      characteristics: ['Bilingual legends', 'Greek/Kharosthi', 'Royal portraits', 'Greek style'],
      regions: ['Bactria', 'Gandhara', 'Punjab'],
      materials: ['Silver', 'Bronze'],
      weight: 0.35,
    ),
    'kushan': CoinPeriodInfo(
      period: 'Kushan Empire',
      dateRange: '30-375 CE',
      characteristics: ['Standing king', 'Deities', 'Greek legends', 'Gold dinar', 'Buddhist symbols'],
      regions: ['Central Asia', 'Northern India', 'Afghanistan'],
      materials: ['Gold', 'Copper'],
      weight: 0.35,
    ),
    'gupta': CoinPeriodInfo(
      period: 'Gupta Empire',
      dateRange: '320-550 CE',
      characteristics: ['Archer king', 'Tiger slayer', 'Goddess Lakshmi', 'Sanskrit legends'],
      regions: ['Northern India', 'Bengal'],
      materials: ['Gold', 'Silver'],
      weight: 0.35,
    ),
    'mughal': CoinPeriodInfo(
      period: 'Mughal Empire',
      dateRange: '1526-1857 CE',
      characteristics: ['Persian script', 'Rupee silver', 'Mohur gold', 'Zodiac types', 'Couplets'],
      regions: ['India', 'Pakistan', 'Bangladesh'],
      materials: ['Gold', 'Silver', 'Copper'],
      weight: 0.4,
    ),

    // ═══════════════════════════════════════════════════════════════
    // CHINESE & EAST ASIAN (770 BCE - 1912 CE)
    // ═══════════════════════════════════════════════════════════════
    'chinese_ancient': CoinPeriodInfo(
      period: 'Ancient Chinese',
      dateRange: '770 BCE - 221 BCE',
      characteristics: ['Spade money', 'Knife money', 'Cowrie', 'Bronze', 'Cast'],
      regions: ['China', 'Zhou Dynasty states'],
      materials: ['Bronze'],
      weight: 0.3,
    ),
    'chinese_imperial': CoinPeriodInfo(
      period: 'Chinese Imperial',
      dateRange: '221 BCE - 1912 CE',
      characteristics: ['Round with square hole', 'Cash coins', 'Cast bronze', 'Reign marks', 'Calligraphy'],
      regions: ['China', 'Vietnam', 'Korea', 'Japan'],
      materials: ['Bronze', 'Iron', 'Brass'],
      weight: 0.4,
    ),
  };

  /// Advanced coin analysis using multiple factors
  CoinAnalysisResult analyzeByCharacteristics({
    required String material,
    String? shape,
    String? scriptType,
    String? imageType,
    List<String>? keywords,
    Map<String, dynamic>? colorData,
  }) {
    // Check cache first
    final cacheKey = '$material|$shape|$scriptType|${keywords?.join(",")}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final matches = <String, double>{};
    final materialLower = material.toLowerCase();

    for (final entry in periodDatabase.entries) {
      double score = 0;
      final info = entry.value;

      // ═══ MATERIAL MATCHING (weight: 0.35) ═══
      final materialScore = _scoreMaterial(materialLower, info);
      score += materialScore * 0.35;

      // ═══ KEYWORD MATCHING (weight: 0.30) ═══
      if (keywords != null && keywords.isNotEmpty) {
        final keywordScore = _scoreKeywords(keywords, info);
        score += keywordScore * 0.30;
      }

      // ═══ SCRIPT TYPE MATCHING (weight: 0.20) ═══
      if (scriptType != null) {
        final scriptScore = _scoreScript(scriptType, entry.key, info);
        score += scriptScore * 0.20;
      }

      // ═══ COLOR-BASED HINTS (weight: 0.15) ═══
      if (colorData != null) {
        final colorScore = _scoreColorHints(colorData, info);
        score += colorScore * 0.15;
      }

      // Apply period-specific weight modifier
      score *= info.weight;

      if (score > 0.05) {
        matches[entry.key] = score;
      }
    }

    // Sort by score descending
    final sortedMatches = matches.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedMatches.isEmpty) {
      final result = CoinAnalysisResult(
        isIdentified: false,
        confidence: 0,
        message: 'Could not identify coin period. Try providing more details about material, design, or script.',
      );
      _cache[cacheKey] = result;
      return result;
    }

    final bestMatch = sortedMatches.first;
    final periodInfo = periodDatabase[bestMatch.key]!;

    // Normalize confidence to 0-100 scale
    final maxPossibleScore = 1.0 * periodInfo.weight;
    final confidence = ((bestMatch.value / maxPossibleScore) * 100).clamp(15, 95).toDouble();

    final result = CoinAnalysisResult(
      isIdentified: true,
      confidence: confidence,
      period: periodInfo.period,
      dateRange: periodInfo.dateRange,
      characteristics: periodInfo.characteristics,
      regions: periodInfo.regions,
      materials: periodInfo.materials,
      alternativePeriods: sortedMatches
          .skip(1)
          .take(4)
          .map((e) => '${periodDatabase[e.key]!.period} (${(e.value / maxPossibleScore * 100).clamp(10, 90).toStringAsFixed(0)}%)')
          .toList(),
    );

    _cache[cacheKey] = result;
    return result;
  }

  double _scoreMaterial(String material, CoinPeriodInfo info) {
    double score = 0;

    // Direct material match in period's typical materials
    for (final periodMaterial in info.materials) {
      if (periodMaterial.toLowerCase() == material ||
          (material.contains('gold') && periodMaterial.toLowerCase().contains('gold')) ||
          (material.contains('silver') && periodMaterial.toLowerCase().contains('silver')) ||
          (material.contains('bronze') && (periodMaterial.toLowerCase().contains('bronze') || periodMaterial.toLowerCase().contains('copper'))) ||
          (material.contains('copper') && (periodMaterial.toLowerCase().contains('copper') || periodMaterial.toLowerCase().contains('bronze')))) {
        score = 1.0;
        break;
      }
    }

    // Check characteristics for material mentions
    for (final char in info.characteristics) {
      final charLower = char.toLowerCase();
      if (charLower.contains(material)) {
        score = math.max(score, 0.8);
      }
    }

    return score;
  }

  double _scoreKeywords(List<String> keywords, CoinPeriodInfo info) {
    double totalScore = 0;
    int matchCount = 0;

    for (final keyword in keywords) {
      final keywordLower = keyword.toLowerCase();

      // Check against characteristics
      for (final char in info.characteristics) {
        if (char.toLowerCase().contains(keywordLower) || keywordLower.contains(char.toLowerCase())) {
          totalScore += 0.3;
          matchCount++;
        }
      }

      // Check against regions
      for (final region in info.regions) {
        if (region.toLowerCase().contains(keywordLower) || keywordLower.contains(region.toLowerCase())) {
          totalScore += 0.25;
          matchCount++;
        }
      }

      // Check against period name
      if (info.period.toLowerCase().contains(keywordLower)) {
        totalScore += 0.4;
        matchCount++;
      }
    }

    return matchCount > 0 ? (totalScore / keywords.length).clamp(0, 1) : 0;
  }

  double _scoreScript(String scriptType, String periodKey, CoinPeriodInfo info) {
    final scriptLower = scriptType.toLowerCase();

    // Script type to period mapping
    if (scriptLower.contains('arabic') || scriptLower.contains('kufic')) {
      if (periodKey.contains('umayyad') || periodKey.contains('abbasid') ||
          periodKey.contains('fatimid') || periodKey.contains('ayyubid') ||
          periodKey.contains('mamluk') || periodKey.contains('ottoman')) {
        return 1.0;
      }
    }

    if (scriptLower.contains('greek')) {
      if (periodKey.contains('greek') || periodKey.contains('hellenistic') ||
          periodKey.contains('indo_greek') || periodKey.contains('parthian') ||
          periodKey.contains('byzantine')) {
        return 1.0;
      }
    }

    if (scriptLower.contains('latin') || scriptLower.contains('roman')) {
      if (periodKey.contains('roman') || periodKey.contains('medieval') ||
          periodKey.contains('crusader') || periodKey.contains('carolingian')) {
        return 1.0;
      }
    }

    if (scriptLower.contains('hebrew') || scriptLower.contains('paleo')) {
      if (periodKey.contains('hasmonean') || periodKey.contains('herodian') ||
          periodKey.contains('jewish')) {
        return 1.0;
      }
    }

    if (scriptLower.contains('persian') || scriptLower.contains('pahlavi')) {
      if (periodKey.contains('sasanian') || periodKey.contains('parthian') ||
          periodKey.contains('mughal')) {
        return 1.0;
      }
    }

    if (scriptLower.contains('chinese') || scriptLower.contains('hanzi')) {
      if (periodKey.contains('chinese')) {
        return 1.0;
      }
    }

    if (scriptLower.contains('sanskrit') || scriptLower.contains('brahmi')) {
      if (periodKey.contains('mauryan') || periodKey.contains('gupta') ||
          periodKey.contains('kushan')) {
        return 1.0;
      }
    }

    return 0;
  }

  double _scoreColorHints(Map<String, dynamic> colorData, CoinPeriodInfo info) {
    double score = 0;

    final isGolden = colorData['isGolden'] == true;
    final isSilvery = colorData['isSilvery'] == true;
    final isGreen = colorData['isGreen'] == true;
    final isBrown = colorData['isBrown'] == true;
    final isDark = colorData['isDark'] == true;

    // Match color hints to period materials
    if (isGolden && info.materials.any((m) => m.toLowerCase().contains('gold') || m.toLowerCase().contains('electrum'))) {
      score += 0.8;
    }
    if (isSilvery && info.materials.any((m) => m.toLowerCase().contains('silver'))) {
      score += 0.8;
    }
    if ((isGreen || isBrown) && info.materials.any((m) => m.toLowerCase().contains('bronze') || m.toLowerCase().contains('copper'))) {
      score += 0.6; // Green patina or brown oxidation = bronze/copper
    }
    if (isDark && info.materials.any((m) => m.toLowerCase().contains('iron'))) {
      score += 0.5;
    }

    return score.clamp(0, 1);
  }

  /// Advanced image analysis with color histograms and texture
  Future<Map<String, dynamic>> analyzeImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return {};

      // Resize for faster processing
      final resized = img.copyResize(image, width: 200);

      // Analyze colors with improved algorithm
      final colorAnalysis = _analyzeColorsAdvanced(resized);

      // Analyze texture/surface
      final textureAnalysis = _analyzeTexture(resized);

      // Analyze shape (circularity)
      final shapeAnalysis = _analyzeShape(resized);

      // Estimate material from combined analysis
      String? estimatedMaterial = _estimateMaterial(colorAnalysis, textureAnalysis);

      return {
        'estimatedMaterial': estimatedMaterial,
        'colorAnalysis': colorAnalysis,
        'textureAnalysis': textureAnalysis,
        'shapeAnalysis': shapeAnalysis,
        'isCircular': shapeAnalysis['isCircular'] ?? true,
      };
    } catch (e) {
      debugPrint('Image analysis error: $e');
      return {};
    }
  }

  Map<String, dynamic> _analyzeColorsAdvanced(img.Image image) {
    // Color histogram analysis
    int totalR = 0, totalG = 0, totalB = 0;
    int goldPixels = 0, silverPixels = 0, greenPixels = 0, brownPixels = 0, darkPixels = 0;
    int pixelCount = 0;

    // Analyze all pixels in resized image
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        totalR += r;
        totalG += g;
        totalB += b;
        pixelCount++;

        // Classify pixel color
        final brightness = (r + g + b) / 3;
        final saturation = _calculateSaturation(r, g, b);

        if (brightness < 60) {
          darkPixels++;
        } else if (_isGoldenColor(r, g, b)) {
          goldPixels++;
        } else if (_isSilveryColor(r, g, b, saturation)) {
          silverPixels++;
        } else if (_isGreenPatina(r, g, b)) {
          greenPixels++;
        } else if (_isBrownOxide(r, g, b)) {
          brownPixels++;
        }
      }
    }

    final avgR = pixelCount > 0 ? totalR ~/ pixelCount : 0;
    final avgG = pixelCount > 0 ? totalG ~/ pixelCount : 0;
    final avgB = pixelCount > 0 ? totalB ~/ pixelCount : 0;

    final total = pixelCount.toDouble();
    final goldRatio = goldPixels / total;
    final silverRatio = silverPixels / total;
    final greenRatio = greenPixels / total;
    final brownRatio = brownPixels / total;
    final darkRatio = darkPixels / total;

    return {
      'avgR': avgR,
      'avgG': avgG,
      'avgB': avgB,
      'isGolden': goldRatio > 0.15,
      'isSilvery': silverRatio > 0.20,
      'isGreen': greenRatio > 0.10,
      'isBrown': brownRatio > 0.15,
      'isDark': darkRatio > 0.30,
      'goldRatio': goldRatio,
      'silverRatio': silverRatio,
      'greenRatio': greenRatio,
      'brownRatio': brownRatio,
      'darkRatio': darkRatio,
      'dominantColor': _getDominantColorName(avgR, avgG, avgB),
    };
  }

  bool _isGoldenColor(int r, int g, int b) {
    return r > 150 && g > 100 && g < 200 && b < 100 && r > g && g > b;
  }

  bool _isSilveryColor(int r, int g, int b, double saturation) {
    return r > 140 && g > 140 && b > 140 && saturation < 0.15;
  }

  bool _isGreenPatina(int r, int g, int b) {
    return g > r && g > b && g > 80 && g < 180;
  }

  bool _isBrownOxide(int r, int g, int b) {
    return r > g && g > b && r > 80 && r < 180 && g > 50 && g < 150 && b < 100;
  }

  double _calculateSaturation(int r, int g, int b) {
    final max = [r, g, b].reduce(math.max);
    final min = [r, g, b].reduce(math.min);
    return max > 0 ? (max - min) / max : 0;
  }

  String _getDominantColorName(int r, int g, int b) {
    if (_isGoldenColor(r, g, b)) return 'Golden/Yellow';
    if (_isSilveryColor(r, g, b, _calculateSaturation(r, g, b))) return 'Silver/Gray';
    if (_isGreenPatina(r, g, b)) return 'Green (Patina)';
    if (_isBrownOxide(r, g, b)) return 'Brown/Copper';
    if ((r + g + b) / 3 < 60) return 'Dark/Black';
    return 'Mixed/Other';
  }

  Map<String, dynamic> _analyzeTexture(img.Image image) {
    // Simple edge detection for texture analysis
    int edgeCount = 0;
    int totalVariance = 0;

    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        final current = image.getPixel(x, y);
        final right = image.getPixel(x + 1, y);
        final down = image.getPixel(x, y + 1);

        final diffX = ((current.r - right.r).abs() + (current.g - right.g).abs() + (current.b - right.b).abs()) ~/ 3;
        final diffY = ((current.r - down.r).abs() + (current.g - down.g).abs() + (current.b - down.b).abs()) ~/ 3;

        if (diffX > 20 || diffY > 20) {
          edgeCount++;
        }
        totalVariance += diffX + diffY;
      }
    }

    final totalPixels = (image.width - 2) * (image.height - 2);
    final edgeDensity = edgeCount / totalPixels;
    final avgVariance = totalVariance / totalPixels;

    return {
      'edgeDensity': edgeDensity,
      'avgVariance': avgVariance,
      'isSmooth': edgeDensity < 0.1,
      'isTextured': edgeDensity > 0.2,
      'hasHighDetail': avgVariance > 15,
    };
  }

  Map<String, dynamic> _analyzeShape(img.Image image) {
    // Basic circularity estimation
    // Coins are typically circular, so high circularity = likely a coin
    return {
      'isCircular': true, // Assume circular for coins
      'aspectRatio': image.width / image.height,
    };
  }

  String? _estimateMaterial(Map<String, dynamic> colorData, Map<String, dynamic> textureData) {
    final isGolden = colorData['isGolden'] == true;
    final isSilvery = colorData['isSilvery'] == true;
    final isGreen = colorData['isGreen'] == true;
    final isBrown = colorData['isBrown'] == true;
    final isDark = colorData['isDark'] == true;
    final isSmooth = textureData['isSmooth'] == true;

    // Priority-based material estimation
    if (isGolden && isSmooth) {
      return 'Gold';
    } else if (isGolden) {
      return 'Gold or Bronze';
    } else if (isSilvery && isSmooth) {
      return 'Silver';
    } else if (isSilvery) {
      return 'Silver or Billon';
    } else if (isGreen) {
      return 'Bronze with patina';
    } else if (isBrown) {
      return 'Bronze or Copper';
    } else if (isDark) {
      return 'Iron or heavily oxidized bronze';
    }

    return 'Unknown metal';
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

  /// Clear classification cache
  void clearCache() => _cache.clear();
}

/// Enhanced coin period information
class CoinPeriodInfo {
  final String period;
  final String dateRange;
  final List<String> characteristics;
  final List<String> regions;
  final List<String> materials;
  final double weight; // Scoring weight modifier

  const CoinPeriodInfo({
    required this.period,
    required this.dateRange,
    required this.characteristics,
    required this.regions,
    this.materials = const ['Bronze', 'Silver', 'Gold'],
    this.weight = 0.35,
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
  final List<String>? materials;
  final List<String>? alternativePeriods;
  final String? message;

  CoinAnalysisResult({
    required this.isIdentified,
    required this.confidence,
    this.period,
    this.dateRange,
    this.characteristics,
    this.regions,
    this.materials,
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
    'materials': materials,
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

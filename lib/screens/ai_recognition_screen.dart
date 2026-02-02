import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ai_classification_service.dart';
import '../services/coin_identification_service.dart';

/// AI-powered artifact recognition screen
/// Takes a photo and classifies the artifact using ML Kit
class AIRecognitionScreen extends StatefulWidget {
  const AIRecognitionScreen({super.key});

  @override
  State<AIRecognitionScreen> createState() => _AIRecognitionScreenState();
}

class _AIRecognitionScreenState extends State<AIRecognitionScreen> {
  final _aiService = AIClassificationService();
  final _coinService = CoinIdentificationService();
  final _imagePicker = ImagePicker();

  File? _selectedImage;
  ArtifactClassificationResult? _result;
  CoinClassificationResult? _coinResult;
  ComprehensiveCoinAnalysis? _comprehensiveAnalysis;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _aiService.initialize();
  }

  @override
  void dispose() {
    _aiService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
          _result = null;
          _coinResult = null;
          _comprehensiveAnalysis = null;
          _error = null;
        });
        await _classifyImage();
      }
    } catch (e) {
      setState(() => _error = 'Failed to pick image: $e');
    }
  }

  Future<void> _classifyImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
      _coinResult = null;
    });

    try {
      final result = await _aiService.classifyArtifact(_selectedImage!);
      setState(() {
        _result = result;
      });

      // If a coin is detected, run specialized coin classification AND comprehensive analysis
      if (result.artifactType == 'Coin') {
        final coinResult = await _aiService.classifyCoin(
          _selectedImage!,
          detectedMaterial: result.material,
        );

        // Run advanced comprehensive analysis (patina, grade, edge, side detection)
        final comprehensive = await _coinService.performComprehensiveAnalysis(_selectedImage!);

        setState(() {
          _coinResult = coinResult;
          _comprehensiveAnalysis = comprehensive;
        });
      }

      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Classification failed: $e';
        _isProcessing = false;
      });
    }
  }

  void _useClassification() {
    if (_result == null) return;

    // Use coin-specific period if available, otherwise use general classification
    final period = _coinResult?.period ?? _result!.suggestedPeriod;
    final dateRange = _coinResult?.dateRange;

    Navigator.pop(context, {
      'type': _result!.artifactType,
      'material': _coinResult?.material ?? _result!.material,
      'period': period,
      'dateRange': dateRange,
      'description': _coinResult != null
          ? _coinResult!.description
          : _aiService.generateDescription(_result!),
      'confidence': _coinResult != null
          ? _coinResult!.confidence / 100
          : (_result!.typeConfidence + _result!.materialConfidence) / 2,
      'imagePath': _selectedImage?.path,
      'isCoin': _coinResult?.isCoin ?? false,
      'characteristics': _coinResult?.characteristics,
      'regions': _coinResult?.regions,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D3A39),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D3A39),
        elevation: 0,
        title: const Text(
          'AI Recognition',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_result != null)
            TextButton(
              onPressed: _useClassification,
              child: const Text(
                'Use Result',
                style: TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image preview area
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF1C2523),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _result?.isHighConfidence == true
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFFFC107).withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: _selectedImage != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            _selectedImage!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (_isProcessing)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFFFFC107)),
                                  SizedBox(height: 16),
                                  Text(
                                    'Analyzing artifact...',
                                    style: TextStyle(color: Colors.white, fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Take or select a photo\nof an artifact to analyze',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            const SizedBox(height: 20),

            // Capture buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Take Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: const Color(0xFF0D3A39),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Error message
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],

            // Results
            if (_result != null) ...[
              const SizedBox(height: 24),
              _buildResultsCard(),
              if (_coinResult != null) ...[
                const SizedBox(height: 16),
                _buildCoinPeriodCard(),
              ],
              if (_comprehensiveAnalysis != null) ...[
                const SizedBox(height: 16),
                _buildAdvancedCoinAnalysisCard(),
              ],
              const SizedBox(height: 16),
              _buildLabelsCard(),
            ],

            // AI Info
            const SizedBox(height: 24),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2523),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _result!.isHighConfidence
              ? const Color(0xFF4CAF50).withOpacity(0.5)
              : const Color(0xFFFFC107).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _result!.isHighConfidence
                    ? Icons.check_circle_rounded
                    : Icons.help_outline_rounded,
                color: _result!.isHighConfidence
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFFC107),
              ),
              const SizedBox(width: 8),
              Text(
                _result!.isHighConfidence ? 'High Confidence' : 'Low Confidence',
                style: TextStyle(
                  color: _result!.isHighConfidence
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFFFC107),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Artifact Type
          _buildResultRow(
            'Artifact Type',
            _result!.artifactType ?? 'Unknown',
            _result!.typeConfidence,
            Icons.category_rounded,
          ),
          const SizedBox(height: 12),

          // Material
          _buildResultRow(
            'Material',
            _result!.material ?? 'Unknown',
            _result!.materialConfidence,
            Icons.texture_rounded,
          ),

          // Period
          if (_result!.suggestedPeriod != null) ...[
            const SizedBox(height: 12),
            _buildResultRow(
              'Suggested Period',
              _result!.suggestedPeriod!,
              0.6, // Period is always estimated
              Icons.history_rounded,
            ),
          ],

          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),

          // AI Description
          Text(
            'AI Analysis:',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _aiService.generateDescription(_result!),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinPeriodCard() {
    if (_coinResult == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF8B4513).withOpacity(0.3),
            const Color(0xFFD4AF37).withOpacity(0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD4AF37).withOpacity(0.5),
          width: 2,
        ),
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
                  color: const Color(0xFFD4AF37).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xFFD4AF37),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Coin Period Analysis',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_coinResult!.confidence.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Color(0xFFD4AF37),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),

          // Period & Date Range
          if (_coinResult!.period != null) ...[
            _buildCoinInfoRow(
              Icons.history_edu_rounded,
              'Period',
              _coinResult!.period!,
            ),
            const SizedBox(height: 8),
          ],
          if (_coinResult!.dateRange != null) ...[
            _buildCoinInfoRow(
              Icons.calendar_today_rounded,
              'Date Range',
              _coinResult!.dateRange!,
            ),
            const SizedBox(height: 8),
          ],
          _buildCoinInfoRow(
            Icons.texture_rounded,
            'Material',
            _coinResult!.material,
          ),

          // Characteristics
          if (_coinResult!.characteristics.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Characteristics',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _coinResult!.characteristics.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D3A39),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
                ),
                child: Text(
                  c,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              )).toList(),
            ),
          ],

          // Regions
          if (_coinResult!.regions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Common Regions',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _coinResult!.regions.join(' • '),
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],

          // Alternative Periods
          if (_coinResult!.alternativePeriods.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            Text(
              'Alternative Periods',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _coinResult!.alternativePeriods.join(', '),
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdvancedCoinAnalysisCard() {
    if (_comprehensiveAnalysis == null) return const SizedBox.shrink();

    final analysis = _comprehensiveAnalysis!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1565C0).withOpacity(0.3),
            const Color(0xFF0D47A1).withOpacity(0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF42A5F5).withOpacity(0.5),
          width: 2,
        ),
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
                  color: const Color(0xFF42A5F5).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.science_rounded,
                  color: Color(0xFF42A5F5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Advanced Numismatic Analysis',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),

          // Wear Grade Section
          if (analysis.grade != null) ...[
            _buildAnalysisSection(
              icon: Icons.grade_rounded,
              title: 'Condition Grade',
              color: const Color(0xFFFFD700),
              children: [
                _buildAnalysisRow(
                  'Grade',
                  _getGradeName(analysis.grade!),
                  Icons.star_rounded,
                ),
                if (analysis.sheldonNumber > 0)
                  _buildAnalysisRow(
                    'Sheldon #',
                    analysis.sheldonNumber.toString(),
                    Icons.tag_rounded,
                  ),
                _buildAnalysisRow(
                  'Confidence',
                  '${analysis.gradeConfidence.toStringAsFixed(0)}%',
                  Icons.verified_rounded,
                ),
                if (analysis.gradeDescription != null && analysis.gradeDescription!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      analysis.gradeDescription!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Patina Section
          if (analysis.patinaType != null && analysis.patinaType != PatinaType.none) ...[
            _buildAnalysisSection(
              icon: Icons.palette_rounded,
              title: 'Patina Analysis',
              color: const Color(0xFF4CAF50),
              children: [
                _buildAnalysisRow(
                  'Type',
                  _getPatinaTypeName(analysis.patinaType!),
                  Icons.color_lens_rounded,
                ),
                _buildAnalysisRow(
                  'Coverage',
                  '${analysis.patinaCoverage.toStringAsFixed(0)}%',
                  Icons.pie_chart_rounded,
                ),
                if (analysis.patinaQuality != null)
                  _buildAnalysisRow(
                    'Quality',
                    analysis.patinaQuality!.name.toUpperCase(),
                    Icons.high_quality_rounded,
                  ),
                if (analysis.isCleaningDetected)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_rounded, color: Colors.orange, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cleaning detected - may affect collector value',
                            style: TextStyle(
                              color: Colors.orange.shade200,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Edge Type Section
          if (analysis.edgeType != null && analysis.edgeType != EdgeType.unknown) ...[
            _buildAnalysisSection(
              icon: Icons.radio_button_unchecked,
              title: 'Edge Type',
              color: const Color(0xFF9C27B0),
              children: [
                _buildAnalysisRow(
                  'Type',
                  _getEdgeTypeName(analysis.edgeType!),
                  Icons.circle_outlined,
                ),
                if (analysis.edgeDescription != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      analysis.edgeDescription!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Coin Side Section
          if (analysis.coinSide != null && analysis.coinSide != CoinSide.unknown) ...[
            _buildAnalysisSection(
              icon: Icons.flip_rounded,
              title: 'Side Detection',
              color: const Color(0xFFFF9800),
              children: [
                _buildAnalysisRow(
                  'Showing',
                  analysis.coinSide == CoinSide.obverse ? 'OBVERSE (Heads)' : 'REVERSE (Tails)',
                  analysis.coinSide == CoinSide.obverse ? Icons.person_rounded : Icons.shield_rounded,
                ),
                _buildAnalysisRow(
                  'Confidence',
                  '${analysis.sideConfidence.toStringAsFixed(0)}%',
                  Icons.verified_rounded,
                ),
                if (analysis.possibleElements.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Possible elements:',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: analysis.possibleElements.take(4).map((e) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D3A39),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        e,
                        style: const TextStyle(color: Colors.white60, fontSize: 10),
                      ),
                    )).toList(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Material Section
          if (analysis.estimatedMaterial != null) ...[
            _buildAnalysisSection(
              icon: Icons.texture_rounded,
              title: 'Material Analysis',
              color: const Color(0xFF795548),
              children: [
                _buildAnalysisRow(
                  'Estimated',
                  analysis.estimatedMaterial!,
                  Icons.auto_awesome_rounded,
                ),
              ],
            ),
          ],

          // Wear Locations (if any)
          if (analysis.wearLocations.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            Text(
              'Wear observed on:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            ...analysis.wearLocations.map((loc) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.arrow_right_rounded, color: Colors.white38, size: 16),
                  Text(
                    loc,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 14),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getGradeName(CoinGrade grade) {
    switch (grade) {
      case CoinGrade.poor1: return 'Poor (P-1)';
      case CoinGrade.ag3: return 'About Good (AG-3)';
      case CoinGrade.g6: return 'Good (G-6)';
      case CoinGrade.vg10: return 'Very Good (VG-10)';
      case CoinGrade.f15: return 'Fine (F-15)';
      case CoinGrade.vf25: return 'Very Fine (VF-25)';
      case CoinGrade.vf35: return 'Choice VF (VF-35)';
      case CoinGrade.ef40: return 'Extremely Fine (EF-40)';
      case CoinGrade.ef45: return 'Choice EF (EF-45)';
      case CoinGrade.au50: return 'About Uncirculated (AU-50)';
      case CoinGrade.au58: return 'Choice AU (AU-58)';
      case CoinGrade.ms60: return 'Mint State (MS-60)';
      case CoinGrade.ms63: return 'Choice MS (MS-63)';
      case CoinGrade.ms65Plus: return 'Gem MS (MS-65+)';
      case CoinGrade.unknown: return 'Unknown';
    }
  }

  String _getPatinaTypeName(PatinaType type) {
    switch (type) {
      case PatinaType.greenVerdigris: return 'Green Verdigris';
      case PatinaType.redCuprite: return 'Red Cuprite';
      case PatinaType.blackOxide: return 'Black Oxide';
      case PatinaType.brownEarth: return 'Brown Earth';
      case PatinaType.desertPatina: return 'Desert Patina';
      case PatinaType.none: return 'None';
    }
  }

  String _getEdgeTypeName(EdgeType type) {
    switch (type) {
      case EdgeType.plain: return 'Plain/Smooth';
      case EdgeType.reeded: return 'Reeded';
      case EdgeType.lettered: return 'Lettered';
      case EdgeType.decorated: return 'Decorated';
      case EdgeType.unknown: return 'Unknown';
    }
  }

  Widget _buildCoinInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFD4AF37).withOpacity(0.7), size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 13,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value, double confidence, IconData icon) {
    final confidencePercent = (confidence * 100).toStringAsFixed(0);
    final confidenceColor = confidence > 0.7
        ? const Color(0xFF4CAF50)
        : confidence > 0.4
            ? const Color(0xFFFFC107)
            : Colors.red;

    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: confidenceColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$confidencePercent%',
            style: TextStyle(
              color: confidenceColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelsCard() {
    if (_result!.allLabels.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2523),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'All Detected Labels',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _result!.allLabels.take(12).map((label) {
              final confidence = (label.confidence * 100).toStringAsFixed(0);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D3A39),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  '${label.label} ($confidence%)',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF2196F3)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'AI recognition uses Google ML Kit for on-device analysis. Results are suggestions - always verify with expert knowledge.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

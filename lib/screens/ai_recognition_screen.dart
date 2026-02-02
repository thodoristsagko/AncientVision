import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ai_classification_service.dart';

/// AI-powered artifact recognition screen
/// Takes a photo and classifies the artifact using ML Kit
class AIRecognitionScreen extends StatefulWidget {
  const AIRecognitionScreen({super.key});

  @override
  State<AIRecognitionScreen> createState() => _AIRecognitionScreenState();
}

class _AIRecognitionScreenState extends State<AIRecognitionScreen> {
  final _aiService = AIClassificationService();
  final _imagePicker = ImagePicker();

  File? _selectedImage;
  ArtifactClassificationResult? _result;
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
    });

    try {
      final result = await _aiService.classifyArtifact(_selectedImage!);
      setState(() {
        _result = result;
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

    Navigator.pop(context, {
      'type': _result!.artifactType,
      'material': _result!.material,
      'period': _result!.suggestedPeriod,
      'description': _aiService.generateDescription(_result!),
      'confidence': (_result!.typeConfidence + _result!.materialConfidence) / 2,
      'imagePath': _selectedImage?.path,
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

import 'dart:io';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// AI-powered artifact classification using Google ML Kit
/// Provides on-device image labeling and object detection
class AIClassificationService {
  static final AIClassificationService _instance = AIClassificationService._internal();
  factory AIClassificationService() => _instance;
  AIClassificationService._internal();

  ImageLabeler? _imageLabeler;
  ObjectDetector? _objectDetector;

  // Archaeological artifact type mappings based on ML Kit labels
  static const Map<String, String> _labelToArtifactType = {
    // Coins & Currency
    'coin': 'Coin',
    'money': 'Coin',
    'currency': 'Coin',
    'medal': 'Coin',
    'token': 'Coin',

    // Pottery & Ceramics
    'pottery': 'Pottery',
    'ceramic': 'Pottery',
    'vase': 'Pottery',
    'bowl': 'Pottery',
    'jar': 'Pottery',
    'pot': 'Pottery',
    'cup': 'Pottery',
    'plate': 'Pottery',
    'dish': 'Pottery',
    'amphora': 'Pottery',
    'urn': 'Pottery',

    // Tools & Weapons
    'tool': 'Tool',
    'knife': 'Tool',
    'blade': 'Tool',
    'axe': 'Tool',
    'hammer': 'Tool',
    'sword': 'Weapon',
    'weapon': 'Weapon',
    'arrowhead': 'Weapon',
    'spear': 'Weapon',
    'dagger': 'Weapon',

    // Jewelry & Ornaments
    'jewelry': 'Jewelry',
    'ring': 'Jewelry',
    'bracelet': 'Jewelry',
    'necklace': 'Jewelry',
    'pendant': 'Jewelry',
    'brooch': 'Jewelry',
    'earring': 'Jewelry',
    'bead': 'Jewelry',
    'amulet': 'Jewelry',

    // Sculpture & Art
    'sculpture': 'Sculpture',
    'statue': 'Sculpture',
    'figurine': 'Sculpture',
    'bust': 'Sculpture',
    'relief': 'Sculpture',
    'carving': 'Sculpture',

    // Building Materials
    'brick': 'Building Material',
    'tile': 'Building Material',
    'stone': 'Stone',
    'rock': 'Stone',
    'marble': 'Stone',
    'granite': 'Stone',

    // Bone & Organic
    'bone': 'Bone/Organic',
    'skeleton': 'Bone/Organic',
    'shell': 'Bone/Organic',
    'ivory': 'Bone/Organic',
    'horn': 'Bone/Organic',
    'tooth': 'Bone/Organic',

    // Metal Objects
    'metal': 'Metal Object',
    'bronze': 'Metal Object',
    'iron': 'Metal Object',
    'copper': 'Metal Object',
    'gold': 'Metal Object',
    'silver': 'Metal Object',

    // Glass
    'glass': 'Glass',
    'bottle': 'Glass',

    // Textile
    'fabric': 'Textile',
    'textile': 'Textile',
    'cloth': 'Textile',
    'leather': 'Textile',
  };

  // Material detection mappings
  static const Map<String, String> _labelToMaterial = {
    'metal': 'Metal',
    'bronze': 'Bronze',
    'iron': 'Iron',
    'copper': 'Copper',
    'gold': 'Gold',
    'silver': 'Silver',
    'brass': 'Bronze',
    'ceramic': 'Ceramic',
    'pottery': 'Ceramic',
    'clay': 'Ceramic',
    'terracotta': 'Ceramic',
    'stone': 'Stone',
    'rock': 'Stone',
    'marble': 'Marble',
    'granite': 'Stone',
    'limestone': 'Stone',
    'sandstone': 'Stone',
    'bone': 'Bone',
    'ivory': 'Ivory',
    'wood': 'Wood',
    'glass': 'Glass',
    'leather': 'Leather',
    'fabric': 'Textile',
    'textile': 'Textile',
  };

  /// Initialize the ML Kit services
  Future<void> initialize() async {
    try {
      // Initialize image labeler with high confidence threshold
      final labelerOptions = ImageLabelerOptions(confidenceThreshold: 0.5);
      _imageLabeler = ImageLabeler(options: labelerOptions);

      // Initialize object detector for locating artifacts in image
      final detectorOptions = ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: true,
        multipleObjects: true,
      );
      _objectDetector = ObjectDetector(options: detectorOptions);

      debugPrint('AI Classification Service initialized');
    } catch (e) {
      debugPrint('Error initializing AI service: $e');
    }
  }

  /// Classify an artifact image and return predictions
  Future<ArtifactClassificationResult> classifyArtifact(File imageFile) async {
    if (_imageLabeler == null) {
      await initialize();
    }

    final inputImage = InputImage.fromFile(imageFile);
    final labels = await _imageLabeler?.processImage(inputImage) ?? [];
    final objects = await _objectDetector?.processImage(inputImage) ?? [];

    // Process labels to find artifact type and material
    String? detectedType;
    String? detectedMaterial;
    double typeConfidence = 0;
    double materialConfidence = 0;
    final allLabels = <ClassificationLabel>[];

    for (final label in labels) {
      final labelText = label.label.toLowerCase();
      final confidence = label.confidence;

      allLabels.add(ClassificationLabel(
        label: label.label,
        confidence: confidence,
      ));

      // Check for artifact type match
      for (final entry in _labelToArtifactType.entries) {
        if (labelText.contains(entry.key) && confidence > typeConfidence) {
          detectedType = entry.value;
          typeConfidence = confidence;
        }
      }

      // Check for material match
      for (final entry in _labelToMaterial.entries) {
        if (labelText.contains(entry.key) && confidence > materialConfidence) {
          detectedMaterial = entry.value;
          materialConfidence = confidence;
        }
      }
    }

    // Process detected objects
    final detectedObjects = <DetectedObject>[];
    for (final obj in objects) {
      detectedObjects.add(DetectedObject(
        boundingBox: obj.boundingBox,
        labels: obj.labels.map((l) => ClassificationLabel(
          label: l.text,
          confidence: l.confidence,
        )).toList(),
        trackingId: obj.trackingId,
      ));
    }

    // Generate suggested period based on common associations
    String? suggestedPeriod;
    if (detectedType == 'Coin' && detectedMaterial == 'Bronze') {
      suggestedPeriod = 'Roman/Byzantine';
    } else if (detectedType == 'Pottery') {
      suggestedPeriod = 'Classical/Hellenistic';
    } else if (detectedMaterial == 'Bronze' || detectedMaterial == 'Copper') {
      suggestedPeriod = 'Bronze Age';
    } else if (detectedMaterial == 'Iron') {
      suggestedPeriod = 'Iron Age';
    }

    return ArtifactClassificationResult(
      artifactType: detectedType,
      material: detectedMaterial,
      suggestedPeriod: suggestedPeriod,
      typeConfidence: typeConfidence,
      materialConfidence: materialConfidence,
      allLabels: allLabels,
      detectedObjects: detectedObjects,
      isHighConfidence: typeConfidence > 0.7 || materialConfidence > 0.7,
    );
  }

  /// Quick classification - returns just the top prediction
  Future<({String? type, String? material, double confidence})> quickClassify(File imageFile) async {
    final result = await classifyArtifact(imageFile);
    return (
      type: result.artifactType,
      material: result.material,
      confidence: (result.typeConfidence + result.materialConfidence) / 2,
    );
  }

  /// Get AI suggestions for a description based on classification
  String generateDescription(ArtifactClassificationResult result) {
    final parts = <String>[];

    if (result.artifactType != null) {
      parts.add('This appears to be a ${result.artifactType?.toLowerCase()}');
    }

    if (result.material != null) {
      if (parts.isNotEmpty) {
        parts.add('made of ${result.material?.toLowerCase()}');
      } else {
        parts.add('${result.material} artifact');
      }
    }

    if (result.suggestedPeriod != null) {
      parts.add('possibly from the ${result.suggestedPeriod} period');
    }

    if (parts.isEmpty) {
      return 'Unable to classify. Please enter details manually.';
    }

    return '${parts.join(', ')}. Confidence: ${((result.typeConfidence + result.materialConfidence) / 2 * 100).toStringAsFixed(0)}%';
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _imageLabeler?.close();
    await _objectDetector?.close();
    _imageLabeler = null;
    _objectDetector = null;
  }
}

/// Result of artifact classification
class ArtifactClassificationResult {
  final String? artifactType;
  final String? material;
  final String? suggestedPeriod;
  final double typeConfidence;
  final double materialConfidence;
  final List<ClassificationLabel> allLabels;
  final List<DetectedObject> detectedObjects;
  final bool isHighConfidence;

  ArtifactClassificationResult({
    this.artifactType,
    this.material,
    this.suggestedPeriod,
    required this.typeConfidence,
    required this.materialConfidence,
    required this.allLabels,
    required this.detectedObjects,
    required this.isHighConfidence,
  });

  Map<String, dynamic> toJson() => {
    'artifactType': artifactType,
    'material': material,
    'suggestedPeriod': suggestedPeriod,
    'typeConfidence': typeConfidence,
    'materialConfidence': materialConfidence,
    'allLabels': allLabels.map((l) => l.toJson()).toList(),
    'isHighConfidence': isHighConfidence,
  };
}

/// A classification label with confidence score
class ClassificationLabel {
  final String label;
  final double confidence;

  ClassificationLabel({
    required this.label,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'confidence': confidence,
  };
}

/// A detected object in the image
class DetectedObject {
  final Rect boundingBox;
  final List<ClassificationLabel> labels;
  final int? trackingId;

  DetectedObject({
    required this.boundingBox,
    required this.labels,
    this.trackingId,
  });
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tutorial step for guided tours
class TutorialStep {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final String? targetKey; // Key for highlighting UI element
  final String? imagePath;

  const TutorialStep({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.targetKey,
    this.imagePath,
  });
}

/// Help topic category
enum HelpCategory {
  gettingStarted('Getting Started', Icons.play_arrow),
  findings('Findings', Icons.search),
  photogrammetry('3D Scanning', Icons.view_in_ar),
  fieldwork('Fieldwork', Icons.landscape),
  dataManagement('Data & Export', Icons.folder),
  settings('Settings', Icons.settings),
  troubleshooting('Troubleshooting', Icons.help_outline);

  final String label;
  final IconData icon;

  const HelpCategory(this.label, this.icon);
}

/// Help article/topic
class HelpArticle {
  final String id;
  final String title;
  final String content;
  final HelpCategory category;
  final List<String> keywords;
  final String? videoUrl;

  const HelpArticle({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    this.keywords = const [],
    this.videoUrl,
  });
}

/// FAQ item
class FAQItem {
  final String question;
  final String answer;
  final HelpCategory category;

  const FAQItem({
    required this.question,
    required this.answer,
    required this.category,
  });
}

/// Service for tutorials, help, and onboarding
class TutorialService {
  static final TutorialService _instance = TutorialService._internal();
  factory TutorialService() => _instance;
  TutorialService._internal();

  static const String _onboardingCompleteKey = 'onboarding_complete';
  static const String _viewedTutorialsKey = 'viewed_tutorials';
  static const String _viewedArticlesKey = 'viewed_articles';

  // ========== ONBOARDING TUTORIAL ==========
  static const List<TutorialStep> onboardingSteps = [
    TutorialStep(
      id: 'welcome',
      title: 'Welcome to AncientVision',
      description: 'Your complete archaeological field companion. Record findings, create 3D models, and manage your excavation data.',
      icon: Icons.waving_hand,
    ),
    TutorialStep(
      id: 'findings',
      title: 'Record Findings',
      description: 'Document artifacts with photos, location, and detailed metadata. All data is saved locally and synced to the cloud.',
      icon: Icons.add_a_photo,
      targetKey: 'findings_tab',
    ),
    TutorialStep(
      id: 'photogrammetry',
      title: '3D Reconstruction',
      description: 'Create 3D models of artifacts using photogrammetry. Take 16+ photos around an object and let the app build a 3D model.',
      icon: Icons.view_in_ar,
      targetKey: 'tools_tab',
    ),
    TutorialStep(
      id: 'classification',
      title: 'Artifact Classification',
      description: 'Use our built-in archaeological database to classify artifacts by type, material, period, and condition.',
      icon: Icons.category,
    ),
    TutorialStep(
      id: 'export',
      title: 'Export & Share',
      description: 'Export your data as PDF reports, CSV, JSON, or GeoJSON. Share 3D models in OBJ or PLY format.',
      icon: Icons.share,
    ),
    TutorialStep(
      id: 'offline',
      title: 'Works Offline',
      description: 'All features work without internet. Data syncs automatically when you\'re back online.',
      icon: Icons.wifi_off,
    ),
  ];

  // ========== FEATURE TUTORIALS ==========
  static const Map<String, List<TutorialStep>> featureTutorials = {
    'photogrammetry': [
      TutorialStep(
        id: 'photo_prep',
        title: 'Prepare Your Object',
        description: 'Place the artifact on a plain, matte surface. Ensure good, even lighting without harsh shadows.',
        icon: Icons.lightbulb_outline,
      ),
      TutorialStep(
        id: 'photo_capture',
        title: 'Capture Photos',
        description: 'Take at least 16 photos, walking around the object in a circle. Keep the object centered in each shot.',
        icon: Icons.camera_alt,
      ),
      TutorialStep(
        id: 'photo_angles',
        title: 'Multiple Heights',
        description: 'Capture photos from different heights - eye level, above, and below. This ensures complete coverage.',
        icon: Icons.height,
      ),
      TutorialStep(
        id: 'photo_overlap',
        title: 'Overlap Images',
        description: 'Each photo should overlap with neighbors by 60-80%. This helps the algorithm match features.',
        icon: Icons.filter,
      ),
      TutorialStep(
        id: 'processing',
        title: 'Processing',
        description: 'Choose on-device or cloud processing. Cloud gives better results but requires internet.',
        icon: Icons.cloud_sync,
      ),
    ],
    'findings': [
      TutorialStep(
        id: 'add_finding',
        title: 'Add a Finding',
        description: 'Tap the + button to create a new finding. You can add photos, location, and detailed information.',
        icon: Icons.add_circle,
      ),
      TutorialStep(
        id: 'classify',
        title: 'Classify Your Find',
        description: 'Select the artifact type, material, period, and condition from our archaeological database.',
        icon: Icons.category,
      ),
      TutorialStep(
        id: 'measure',
        title: 'Add Measurements',
        description: 'Record dimensions using our measurement tool. Choose your preferred units.',
        icon: Icons.straighten,
      ),
      TutorialStep(
        id: 'context',
        title: 'Add Context',
        description: 'Link findings to stratigraphic contexts for proper archaeological documentation.',
        icon: Icons.layers,
      ),
    ],
    'context_sheet': [
      TutorialStep(
        id: 'context_type',
        title: 'Choose Context Type',
        description: 'Select whether this is a deposit, cut, fill, structure, or surface.',
        icon: Icons.layers,
      ),
      TutorialStep(
        id: 'soil_desc',
        title: 'Describe the Soil',
        description: 'Record soil type, Munsell color, compaction, and inclusions.',
        icon: Icons.terrain,
      ),
      TutorialStep(
        id: 'relationships',
        title: 'Stratigraphic Relationships',
        description: 'Record what this context is above, below, cuts, or is cut by.',
        icon: Icons.account_tree,
      ),
      TutorialStep(
        id: 'samples',
        title: 'Record Samples',
        description: 'Note if soil, flotation, or carbon samples were taken.',
        icon: Icons.science,
      ),
    ],
  };

  // ========== HELP ARTICLES ==========
  static const List<HelpArticle> helpArticles = [
    HelpArticle(
      id: 'getting_started',
      title: 'Getting Started with AncientVision',
      content: '''
AncientVision is a comprehensive archaeological field app designed to help you document, classify, and analyze archaeological findings.

**Key Features:**
- Record findings with photos and GPS location
- Create 3D models using photogrammetry
- Classify artifacts using our archaeological database
- Generate professional PDF reports
- Export data in multiple formats
- Works offline with automatic sync

**Quick Start:**
1. Create an account or sign in
2. Start recording findings using the + button
3. Use the camera to capture photos
4. Add classification and measurements
5. Export or share your data
      ''',
      category: HelpCategory.gettingStarted,
      keywords: ['start', 'begin', 'first', 'new', 'account'],
    ),
    HelpArticle(
      id: 'photogrammetry_tips',
      title: 'Tips for Better 3D Scans',
      content: '''
Getting good 3D reconstructions requires following some best practices:

**Lighting:**
- Use soft, diffused lighting
- Avoid harsh shadows
- Outdoor shade works well
- No direct sunlight on the object

**Object Selection:**
- Textured surfaces work best
- Avoid shiny, reflective objects
- Solid colors are challenging
- Detailed surfaces give best results

**Photography:**
- Minimum 16 photos recommended
- Walk in a complete circle
- Include multiple heights
- Keep object centered
- 60-80% overlap between photos

**Processing:**
- Cloud processing gives best results
- On-device works for simple objects
- Allow 5-15 minutes for cloud
      ''',
      category: HelpCategory.photogrammetry,
      keywords: ['3d', 'scan', 'photo', 'model', 'reconstruction'],
    ),
    HelpArticle(
      id: 'context_sheets',
      title: 'Recording Stratigraphic Contexts',
      content: '''
Context sheets are essential for proper archaeological documentation.

**Context Types:**
- **Deposit**: Natural or cultural accumulation
- **Cut**: Negative feature (pit, ditch, etc.)
- **Fill**: Material filling a cut
- **Structure**: Built feature (wall, floor)
- **Surface**: Activity or occupation surface

**Key Information:**
- Context number (unique identifier)
- Soil description (type, color, compaction)
- Stratigraphic relationships
- Dimensions and elevations
- Associated finds

**Munsell Colors:**
Use the built-in Munsell color chart to standardize soil color descriptions.

**Relationships:**
Record what each context is above, below, cuts, or is cut by to build the Harris Matrix.
      ''',
      category: HelpCategory.fieldwork,
      keywords: ['context', 'stratigraphy', 'soil', 'layer', 'harris'],
    ),
    HelpArticle(
      id: 'offline_mode',
      title: 'Working Offline',
      content: '''
AncientVision is designed to work fully offline in the field.

**What Works Offline:**
- Recording new findings
- Taking photos
- Classification and measurements
- Field journal entries
- Context sheets
- On-device 3D processing

**What Requires Internet:**
- Cloud 3D processing
- Syncing to Firebase
- Sharing exports

**Auto-Sync:**
When you reconnect to the internet, all your data syncs automatically. You can also trigger manual sync from the home screen.

**Data Safety:**
All data is saved locally first. Nothing is lost if you lose connection during fieldwork.
      ''',
      category: HelpCategory.dataManagement,
      keywords: ['offline', 'internet', 'sync', 'field', 'connection'],
    ),
    HelpArticle(
      id: 'export_options',
      title: 'Exporting Your Data',
      content: '''
Export your data in multiple formats for different purposes.

**Available Formats:**
- **PDF**: Professional reports with images
- **CSV**: Spreadsheet-compatible data
- **JSON**: Full data export for backup
- **GeoJSON**: For GIS applications
- **KML**: For Google Earth
- **OBJ/PLY**: 3D model formats

**Report Types:**
- Finding reports (individual artifacts)
- Site reports (complete excavation)
- Daily reports (day-by-day summary)
- Context sheets (stratigraphic forms)

**Sharing:**
Use the share button to send exports via email, cloud storage, or other apps.
      ''',
      category: HelpCategory.dataManagement,
      keywords: ['export', 'pdf', 'csv', 'report', 'share', 'backup'],
    ),
  ];

  // ========== FAQs ==========
  static const List<FAQItem> faqs = [
    FAQItem(
      question: 'How many photos do I need for 3D scanning?',
      answer: 'We recommend at least 16 photos for a basic 3D model. For better quality, take 30-50 photos from multiple heights. The more coverage you have, the better the result.',
      category: HelpCategory.photogrammetry,
    ),
    FAQItem(
      question: 'Why does my 3D model look incomplete?',
      answer: 'This usually happens when there are gaps in photo coverage. Make sure to photograph the object from all angles and heights. Shiny or textureless objects also cause problems.',
      category: HelpCategory.photogrammetry,
    ),
    FAQItem(
      question: 'Does the app work without internet?',
      answer: 'Yes! All core features work offline. Data syncs automatically when you reconnect. Cloud 3D processing is the only feature that requires internet.',
      category: HelpCategory.dataManagement,
    ),
    FAQItem(
      question: 'How do I backup my data?',
      answer: 'Go to Settings > Backup to create a full backup. You can also enable automatic backups. Backups are saved as ZIP files that can be restored later.',
      category: HelpCategory.dataManagement,
    ),
    FAQItem(
      question: 'What is the difference between cloud and on-device processing?',
      answer: 'Cloud processing uses professional servers and gives better results, but requires internet. On-device processing works offline but may produce simpler models.',
      category: HelpCategory.photogrammetry,
    ),
    FAQItem(
      question: 'How do I classify an unknown artifact?',
      answer: 'Select "Unknown/Unidentified" as the type. You can add notes and update the classification later when you have more information.',
      category: HelpCategory.findings,
    ),
    FAQItem(
      question: 'Can multiple team members use the app?',
      answer: 'Yes! Each team member can have their own account. Data is associated with the user who recorded it. Site directors can see all team data.',
      category: HelpCategory.gettingStarted,
    ),
    FAQItem(
      question: 'How accurate is the GPS location?',
      answer: 'GPS accuracy depends on your device and conditions. Typical accuracy is 3-5 meters outdoors. For precise positioning, consider using an external GPS receiver.',
      category: HelpCategory.fieldwork,
    ),
  ];

  // ========== SERVICE METHODS ==========

  /// Check if onboarding is complete
  Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompleteKey) ?? false;
  }

  /// Mark onboarding as complete
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, true);
  }

  /// Reset onboarding (show again)
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, false);
  }

  /// Check if a tutorial has been viewed
  Future<bool> isTutorialViewed(String tutorialId) async {
    final prefs = await SharedPreferences.getInstance();
    final viewed = prefs.getStringList(_viewedTutorialsKey) ?? [];
    return viewed.contains(tutorialId);
  }

  /// Mark a tutorial as viewed
  Future<void> markTutorialViewed(String tutorialId) async {
    final prefs = await SharedPreferences.getInstance();
    final viewed = prefs.getStringList(_viewedTutorialsKey) ?? [];
    if (!viewed.contains(tutorialId)) {
      viewed.add(tutorialId);
      await prefs.setStringList(_viewedTutorialsKey, viewed);
    }
  }

  /// Get unviewed feature tutorials
  Future<List<String>> getUnviewedTutorials() async {
    final prefs = await SharedPreferences.getInstance();
    final viewed = prefs.getStringList(_viewedTutorialsKey) ?? [];
    return featureTutorials.keys.where((t) => !viewed.contains(t)).toList();
  }

  /// Mark an article as read
  Future<void> markArticleRead(String articleId) async {
    final prefs = await SharedPreferences.getInstance();
    final read = prefs.getStringList(_viewedArticlesKey) ?? [];
    if (!read.contains(articleId)) {
      read.add(articleId);
      await prefs.setStringList(_viewedArticlesKey, read);
    }
  }

  /// Search help articles
  List<HelpArticle> searchArticles(String query) {
    final lowerQuery = query.toLowerCase();
    return helpArticles.where((article) {
      return article.title.toLowerCase().contains(lowerQuery) ||
          article.content.toLowerCase().contains(lowerQuery) ||
          article.keywords.any((k) => k.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// Search FAQs
  List<FAQItem> searchFAQs(String query) {
    final lowerQuery = query.toLowerCase();
    return faqs.where((faq) {
      return faq.question.toLowerCase().contains(lowerQuery) ||
          faq.answer.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Get articles by category
  List<HelpArticle> getArticlesByCategory(HelpCategory category) {
    return helpArticles.where((a) => a.category == category).toList();
  }

  /// Get FAQs by category
  List<FAQItem> getFAQsByCategory(HelpCategory category) {
    return faqs.where((f) => f.category == category).toList();
  }

  /// Get tutorial steps for a feature
  List<TutorialStep>? getFeatureTutorial(String feature) {
    return featureTutorials[feature];
  }

  /// Reset all tutorial progress
  Future<void> resetAllProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingCompleteKey);
    await prefs.remove(_viewedTutorialsKey);
    await prefs.remove(_viewedArticlesKey);
  }
}

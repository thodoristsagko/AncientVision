import 'package:flutter/material.dart';
import '../services/tutorial_service.dart';

/// Help and Tutorial Screen
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _tutorialService = TutorialService();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Help & Tutorials'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8B4513),
          tabs: const [
            Tab(text: 'Tutorials'),
            Tab(text: 'Help'),
            Tab(text: 'FAQ'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search help topics...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withAlpha(26),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTutorialsTab(),
                _buildHelpTab(),
                _buildFAQTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Getting Started
        _buildTutorialCard(
          'Getting Started',
          'Learn the basics of AncientVision',
          Icons.play_circle_filled,
          Colors.green,
          () => _showTutorial(TutorialService.onboardingSteps),
        ),

        // Feature tutorials
        ...TutorialService.featureTutorials.entries.map((entry) {
          String title;
          String description;
          IconData icon;
          Color color;

          switch (entry.key) {
            case 'photogrammetry':
              title = '3D Scanning Guide';
              description = 'Create professional 3D models';
              icon = Icons.view_in_ar;
              color = Colors.purple;
              break;
            case 'findings':
              title = 'Recording Findings';
              description = 'Document artifacts properly';
              icon = Icons.search;
              color = Colors.blue;
              break;
            case 'context_sheet':
              title = 'Context Sheets';
              description = 'Record stratigraphic data';
              icon = Icons.layers;
              color = Colors.orange;
              break;
            default:
              title = entry.key;
              description = 'Learn more about ${entry.key}';
              icon = Icons.school;
              color = Colors.grey;
          }

          return _buildTutorialCard(
            title,
            description,
            icon,
            color,
            () => _showTutorial(entry.value),
          );
        }),

        const SizedBox(height: 16),

        // Quick tips
        _buildSectionTitle('Quick Tips'),
        _buildQuickTips(),
      ],
    );
  }

  Widget _buildHelpTab() {
    final articles = _searchQuery.isEmpty
        ? TutorialService.helpArticles
        : _tutorialService.searchArticles(_searchQuery);

    if (articles.isEmpty) {
      return _buildEmptySearch();
    }

    // Group by category
    final grouped = <HelpCategory, List<HelpArticle>>{};
    for (final article in articles) {
      grouped.putIfAbsent(article.category, () => []).add(article);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCategoryHeader(entry.key),
            ...entry.value.map((article) => _buildArticleCard(article)),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildFAQTab() {
    final faqs = _searchQuery.isEmpty
        ? TutorialService.faqs
        : _tutorialService.searchFAQs(_searchQuery);

    if (faqs.isEmpty) {
      return _buildEmptySearch();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: faqs.length,
      itemBuilder: (context, index) {
        final faq = faqs[index];
        return _buildFAQCard(faq);
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTutorialCard(
    String title,
    String description,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(26),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withAlpha(51),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
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
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTips() {
    final tips = [
      ('Take 16+ photos', 'More photos = better 3D model', Icons.camera_alt),
      ('Good lighting', 'Even, diffused light works best', Icons.light_mode),
      ('Save often', 'Auto-save keeps your work safe', Icons.save),
      ('Use cloud', 'Cloud processing gives better results', Icons.cloud),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tips.map((tip) => Container(
        width: (MediaQuery.of(context).size.width - 48) / 2,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF8B4513).withAlpha(51),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(tip.$3, color: const Color(0xFF8B4513), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tip.$1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    tip.$2,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildCategoryHeader(HelpCategory category) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(category.icon, color: const Color(0xFF8B4513), size: 20),
          const SizedBox(width: 8),
          Text(
            category.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleCard(HelpArticle article) {
    return GestureDetector(
      onTap: () => _showArticle(article),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(13),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                article.title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQCard(FAQItem faq) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(
          faq.question,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        iconColor: Colors.white54,
        collapsedIconColor: Colors.white54,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              faq.answer,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySearch() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 60, color: Colors.white.withAlpha(77)),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 16),
          ),
          Text(
            'Try a different search term',
            style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _showTutorial(List<TutorialStep> steps) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2a2a3e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _TutorialViewer(steps: steps),
    );
  }

  void _showArticle(HelpArticle article) {
    _tutorialService.markArticleRead(article.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2a2a3e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(article.category.icon, color: const Color(0xFF8B4513)),
                  const SizedBox(width: 8),
                  Text(
                    article.category.label,
                    style: const TextStyle(color: Color(0xFF8B4513)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                article.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                article.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tutorial step viewer widget
class _TutorialViewer extends StatefulWidget {
  final List<TutorialStep> steps;

  const _TutorialViewer({required this.steps});

  @override
  State<_TutorialViewer> createState() => _TutorialViewerState();
}

class _TutorialViewerState extends State<_TutorialViewer> {
  int _currentStep = 0;
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          // Progress indicator
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: List.generate(
                widget.steps.length,
                (index) => Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: index <= _currentStep
                          ? const Color(0xFF8B4513)
                          : Colors.white.withAlpha(51),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Content
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.steps.length,
              onPageChanged: (index) => setState(() => _currentStep = index),
              itemBuilder: (context, index) {
                final step = widget.steps[index];
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B4513).withAlpha(51),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(step.icon, color: const Color(0xFF8B4513), size: 40),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        step.description,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Navigation
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip'),
                ),
                Row(
                  children: [
                    if (_currentStep > 0)
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_currentStep < widget.steps.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B4513),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        _currentStep < widget.steps.length - 1 ? 'Next' : 'Done',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

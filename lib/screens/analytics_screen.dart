import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/progress_service.dart';

/// Analytics and Statistics Dashboard Screen
/// Professional documentation statistics with beautiful visualizations
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _progressService = ProgressService();
  bool _isLoading = true;
  List<DailyStats> _weeklyStats = [];
  int _selectedPeriod = 0; // 0: Week, 1: Month, 2: All Time
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _progressService.initialize();
    _weeklyStats = await _progressService.getWeeklyStats();
    if (mounted) {
      setState(() => _isLoading = false);
      _animationController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFC107)))
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                // Custom App Bar with Stats Overview
                _buildSliverAppBar(),

                // Content
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Time Period Filter
                          _buildPeriodFilter(),
                          const SizedBox(height: 20),

                          // Quick Stats Cards
                          _buildQuickStatsRow(),
                          const SizedBox(height: 24),

                          // Weekly Activity Chart
                          _buildSectionHeader('Activity Overview', Icons.show_chart),
                          const SizedBox(height: 12),
                          _buildWeeklyChart(),
                          const SizedBox(height: 24),

                          // Category Breakdown
                          _buildSectionHeader('Documentation Breakdown', Icons.pie_chart),
                          const SizedBox(height: 12),
                          _buildCategoryBreakdown(),
                          const SizedBox(height: 24),

                          // Material Analysis
                          _buildSectionHeader('Material Analysis', Icons.category),
                          const SizedBox(height: 12),
                          _buildMaterialAnalysis(),
                          const SizedBox(height: 24),

                          // Period Distribution
                          _buildSectionHeader('Historical Periods', Icons.history),
                          const SizedBox(height: 12),
                          _buildPeriodDistribution(),
                          const SizedBox(height: 24),

                          // Data Quality Overview
                          _buildSectionHeader('Data Quality', Icons.verified),
                          const SizedBox(height: 12),
                          _buildDataQuality(),
                          const SizedBox(height: 24),

                          // Detailed Stats Grid
                          _buildSectionHeader('Detailed Statistics', Icons.analytics),
                          const SizedBox(height: 12),
                          _buildDetailedStatsGrid(),
                          const SizedBox(height: 24),

                          // Session Summary
                          _buildSectionHeader('Today\'s Session', Icons.today),
                          const SizedBox(height: 12),
                          _buildSessionSummary(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final progress = _progressService.progress;
    final totalItems = progress.totalFindings +
        progress.total3DModels +
        progress.totalContexts +
        progress.totalNotes;

    return SliverAppBar(
      expandedHeight: 200,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF0D3A39),
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0D3A39),
                const Color(0xFF1A5653),
                const Color(0xFF0D3A39).withAlpha(200),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107).withAlpha(30),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.analytics,
                          color: Color(0xFFFFC107),
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Documentation Analytics',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$totalItems total items documented',
                              style: TextStyle(
                                color: Colors.white.withAlpha(180),
                                fontSize: 14,
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildPeriodFilter() {
    final periods = ['This Week', 'This Month', 'All Time'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(periods.length, (index) {
          final isSelected = _selectedPeriod == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriod = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFFC107)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  periods[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildQuickStatsRow() {
    final today = _progressService.todayStats;
    final weekTotal = _weeklyStats.fold<int>(0, (sum, s) => sum + s.totalActions);
    final avgPerDay = _weeklyStats.isNotEmpty
        ? (weekTotal / _weeklyStats.length).round()
        : 0;

    return Row(
      children: [
        Expanded(
          child: _buildQuickStatCard(
            title: 'Today',
            value: today.totalActions,
            subtitle: 'actions',
            icon: Icons.today,
            color: const Color(0xFF4CAF50),
            trend: _calculateTodayTrend(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            title: 'This Week',
            value: weekTotal,
            subtitle: 'total',
            icon: Icons.date_range,
            color: const Color(0xFF2196F3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            title: 'Daily Avg',
            value: avgPerDay,
            subtitle: 'actions/day',
            icon: Icons.trending_up,
            color: const Color(0xFFFFC107),
          ),
        ),
      ],
    );
  }

  int _calculateTodayTrend() {
    if (_weeklyStats.length < 2) return 0;
    final today = _progressService.todayStats.totalActions;
    final yesterday = _weeklyStats.length >= 2
        ? _weeklyStats[_weeklyStats.length - 2].totalActions
        : 0;
    return today - yesterday;
  }

  Widget _buildQuickStatCard({
    required String title,
    required int value,
    required String subtitle,
    required IconData icon,
    required Color color,
    int? trend,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withAlpha(40),
            color.withAlpha(20),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 18),
              if (trend != null && trend != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: trend > 0
                        ? Colors.green.withAlpha(40)
                        : Colors.red.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trend > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 10,
                        color: trend > 0 ? Colors.green : Colors.red,
                      ),
                      Text(
                        '${trend.abs()}',
                        style: TextStyle(
                          color: trend > 0 ? Colors.green : Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 800),
            builder: (context, val, child) {
              return Text(
                '$val',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withAlpha(150),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFC107), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyChart() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxValue = _weeklyStats.fold<int>(
      1,
      (max, stat) => stat.totalActions > max ? stat.totalActions : max,
    );

    return Container(
      height: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Documentation Activity',
                style: TextStyle(
                  color: Colors.white.withAlpha(200),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_weeklyStats.fold<int>(0, (sum, s) => sum + s.totalActions)} total',
                  style: const TextStyle(
                    color: Color(0xFFFFC107),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxValue.toDouble() + 2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: const Color(0xFF1A5653),
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex >= _weeklyStats.length) return null;
                      final stat = _weeklyStats[groupIndex];
                      return BarTooltipItem(
                        '${stat.totalActions} actions\n'
                        '${stat.findingsRecorded} findings\n'
                        '${stat.photosCapture} photos',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < _weeklyStats.length) {
                          final dayIndex = _weeklyStats[index].date.weekday - 1;
                          final isToday = index == _weeklyStats.length - 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              days[dayIndex],
                              style: TextStyle(
                                color: isToday
                                    ? const Color(0xFFFFC107)
                                    : Colors.white.withAlpha(150),
                                fontSize: 11,
                                fontWeight:
                                    isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                      reservedSize: 28,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox();
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: Colors.white.withAlpha(100),
                            fontSize: 10,
                          ),
                        );
                      },
                      reservedSize: 28,
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxValue > 5 ? (maxValue / 3) : 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withAlpha(20),
                    strokeWidth: 1,
                    dashArray: [5, 5],
                  ),
                ),
                barGroups: List.generate(_weeklyStats.length, (index) {
                  final stat = _weeklyStats[index];
                  final isToday = index == _weeklyStats.length - 1;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: stat.totalActions.toDouble(),
                        gradient: LinearGradient(
                          colors: isToday
                              ? [const Color(0xFFFFC107), const Color(0xFFFF9800)]
                              : [const Color(0xFF4CAF50), const Color(0xFF2E7D32)],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxValue.toDouble() + 2,
                          color: Colors.white.withAlpha(10),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    final progress = _progressService.progress;
    final categories = [
      _CategoryData('Findings', progress.totalFindings, const Color(0xFF2196F3)),
      _CategoryData('Photos', progress.totalPhotos, const Color(0xFF00BCD4)),
      _CategoryData('3D Models', progress.total3DModels, const Color(0xFF9C27B0)),
      _CategoryData('Contexts', progress.totalContexts, const Color(0xFFFF9800)),
      _CategoryData('Notes', progress.totalNotes, const Color(0xFF4CAF50)),
      _CategoryData('Reports', progress.totalReports, const Color(0xFFF44336)),
    ];

    final total = categories.fold<int>(0, (sum, c) => sum + c.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Row(
        children: [
          // Pie Chart
          SizedBox(
            height: 140,
            width: 140,
            child: total > 0
                ? PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 35,
                      sections: categories
                          .where((c) => c.value > 0)
                          .map((c) => PieChartSectionData(
                                value: c.value.toDouble(),
                                color: c.color,
                                radius: 30,
                                showTitle: false,
                              ))
                          .toList(),
                    ),
                  )
                : Center(
                    child: Text(
                      'No data yet',
                      style: TextStyle(color: Colors.white.withAlpha(150)),
                    ),
                  ),
          ),
          const SizedBox(width: 20),
          // Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: categories.map((c) {
                final percentage =
                    total > 0 ? ((c.value / total) * 100).round() : 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.name,
                          style: TextStyle(
                            color: Colors.white.withAlpha(200),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        '${c.value}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '($percentage%)',
                        style: TextStyle(
                          color: Colors.white.withAlpha(120),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStatsGrid() {
    final progress = _progressService.progress;
    final stats = [
      _StatItem('Findings', progress.totalFindings, Icons.search,
          const Color(0xFF2196F3), 'Archaeological discoveries'),
      _StatItem('3D Models', progress.total3DModels, Icons.view_in_ar,
          const Color(0xFF9C27B0), 'Reconstructions created'),
      _StatItem('Contexts', progress.totalContexts, Icons.layers,
          const Color(0xFFFF9800), 'Stratigraphic records'),
      _StatItem('Notes', progress.totalNotes, Icons.note,
          const Color(0xFF4CAF50), 'Field observations'),
      _StatItem('Reports', progress.totalReports, Icons.description,
          const Color(0xFFF44336), 'PDF documents'),
      _StatItem('Photos', progress.totalPhotos, Icons.photo_library,
          const Color(0xFF00BCD4), 'Images captured'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: stat.color.withAlpha(60)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: stat.color.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(stat.icon, color: stat.color, size: 18),
                  ),
                  const Spacer(),
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: stat.value),
                    duration: const Duration(milliseconds: 1000),
                    builder: (context, val, child) {
                      return Text(
                        '$val',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    stat.description,
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMaterialAnalysis() {
    // Sample material distribution data
    final materials = [
      _MaterialData('Ceramic', 45, const Color(0xFFE57373)),
      _MaterialData('Stone', 28, const Color(0xFF64B5F6)),
      _MaterialData('Metal', 15, const Color(0xFFFFD54F)),
      _MaterialData('Bone', 8, const Color(0xFFAED581)),
      _MaterialData('Glass', 4, const Color(0xFFBA68C8)),
    ];

    final total = materials.fold(0, (sum, m) => sum + m.count);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Column(
        children: materials.map((m) {
          final percentage = total > 0 ? (m.count / total) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: m.color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          m.name,
                          style: TextStyle(
                            color: Colors.white.withAlpha(200),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${m.count} (${(percentage * 100).round()}%)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: Colors.white.withAlpha(30),
                    valueColor: AlwaysStoppedAnimation<Color>(m.color),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeriodDistribution() {
    // Sample period distribution data
    final periods = [
      _PeriodData('Hellenistic', 32, const Color(0xFF7986CB)),
      _PeriodData('Roman', 28, const Color(0xFFE57373)),
      _PeriodData('Byzantine', 18, const Color(0xFF4DB6AC)),
      _PeriodData('Classical', 15, const Color(0xFFFFB74D)),
      _PeriodData('Other', 7, const Color(0xFF90A4AE)),
    ];

    final total = periods.fold(0, (sum, p) => sum + p.count);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Column(
        children: [
          // Horizontal bar chart
          SizedBox(
            height: 40,
            child: Row(
              children: periods.map((p) {
                final width = total > 0 ? (p.count / total) : 0.0;
                return Expanded(
                  flex: (width * 100).round().clamp(1, 100),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: p.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: periods.map((p) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: p.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${p.name}: ${p.count}',
                  style: TextStyle(
                    color: Colors.white.withAlpha(180),
                    fontSize: 11,
                  ),
                ),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDataQuality() {
    // Data quality metrics
    final quality = [
      _QualityMetric('GPS Accuracy', 0.85, 'High precision coordinates', const Color(0xFF4CAF50)),
      _QualityMetric('Photo Coverage', 0.72, 'Photos per finding', const Color(0xFF2196F3)),
      _QualityMetric('Field Completeness', 0.68, 'Required fields filled', const Color(0xFFFF9800)),
      _QualityMetric('3D Model Quality', 0.90, 'Reconstruction success', const Color(0xFF9C27B0)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Column(
        children: quality.map((q) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              // Circular progress
              SizedBox(
                width: 50,
                height: 50,
                child: Stack(
                  children: [
                    CircularProgressIndicator(
                      value: q.score,
                      strokeWidth: 5,
                      backgroundColor: Colors.white.withAlpha(30),
                      valueColor: AlwaysStoppedAnimation<Color>(q.color),
                    ),
                    Center(
                      child: Text(
                        '${(q.score * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      q.description,
                      style: TextStyle(
                        color: Colors.white.withAlpha(150),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Quality indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: q.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  q.score >= 0.8 ? 'Excellent' : q.score >= 0.6 ? 'Good' : 'Needs Work',
                  style: TextStyle(
                    color: q.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildSessionSummary() {
    final today = _progressService.todayStats;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Column(
        children: [
          _buildSessionRow('Findings recorded', today.findingsRecorded,
              Icons.search, const Color(0xFF2196F3)),
          const SizedBox(height: 12),
          _buildSessionRow('Photos captured', today.photosCapture,
              Icons.camera_alt, const Color(0xFF00BCD4)),
          const SizedBox(height: 12),
          _buildSessionRow('3D scans created', today.modelsCreated,
              Icons.view_in_ar, const Color(0xFF9C27B0)),
          const SizedBox(height: 12),
          _buildSessionRow('Notes written', today.notesCreated, Icons.note_add,
              const Color(0xFF4CAF50)),
          const SizedBox(height: 12),
          _buildSessionRow('Contexts logged', today.contextsRecorded,
              Icons.layers, const Color(0xFFFF9800)),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Actions',
                style: TextStyle(
                  color: Colors.white.withAlpha(200),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${today.totalActions}',
                  style: const TextStyle(
                    color: Color(0xFFFFC107),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(String label, int value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(180),
              fontSize: 13,
            ),
          ),
        ),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _CategoryData {
  final String name;
  final int value;
  final Color color;

  _CategoryData(this.name, this.value, this.color);
}

class _StatItem {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String description;

  _StatItem(this.label, this.value, this.icon, this.color, this.description);
}

class _MaterialData {
  final String name;
  final int count;
  final Color color;

  _MaterialData(this.name, this.count, this.color);
}

class _PeriodData {
  final String name;
  final int count;
  final Color color;

  _PeriodData(this.name, this.count, this.color);
}

class _QualityMetric {
  final String name;
  final double score;
  final String description;
  final Color color;

  _QualityMetric(this.name, this.score, this.description, this.color);
}

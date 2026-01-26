import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/progress_service.dart';

/// Analytics and Statistics Dashboard Screen
/// Professional documentation statistics - no gamification
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _progressService = ProgressService();
  bool _isLoading = true;
  List<DailyStats> _weeklyStats = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _progressService.initialize();
    _weeklyStats = await _progressService.getWeeklyStats();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D3A39),
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFFFFC107),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Cards
                    _buildSummaryRow(),
                    const SizedBox(height: 24),

                    // Weekly Activity Chart
                    _buildSectionTitle('Weekly Activity'),
                    const SizedBox(height: 12),
                    _buildWeeklyChart(),
                    const SizedBox(height: 24),

                    // Documentation Stats
                    _buildSectionTitle('Documentation Statistics'),
                    const SizedBox(height: 12),
                    _buildStatsGrid(),
                    const SizedBox(height: 24),

                    // Session Summary
                    _buildSectionTitle('Session Summary'),
                    const SizedBox(height: 12),
                    _buildSessionSummary(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSummaryRow() {
    final progress = _progressService.progress;
    final today = _progressService.todayStats;

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Total Documented',
            '${progress.totalFindings}',
            'findings recorded',
            Icons.inventory_2,
            const Color(0xFFFFC107),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            'Today',
            '${today.findingsRecorded}',
            'new entries',
            Icons.today,
            const Color(0xFF4CAF50),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withAlpha(150),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxValue = _weeklyStats.fold<int>(
      1,
      (max, stat) => stat.totalActions > max ? stat.totalActions : max,
    );

    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Documentation Activity',
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 13,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxValue.toDouble() + 2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: const Color(0xFF0D3A39),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex >= _weeklyStats.length) return null;
                      final stat = _weeklyStats[groupIndex];
                      return BarTooltipItem(
                        '${stat.totalActions} actions\n${stat.findingsRecorded} findings',
                        const TextStyle(color: Colors.white, fontSize: 12),
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
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              days[dayIndex],
                              style: TextStyle(
                                color: Colors.white.withAlpha(180),
                                fontSize: 11,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                      reservedSize: 28,
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: List.generate(_weeklyStats.length, (index) {
                  final stat = _weeklyStats[index];
                  final isToday = index == _weeklyStats.length - 1;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: stat.totalActions.toDouble(),
                        color: isToday ? const Color(0xFFFFC107) : const Color(0xFF4CAF50),
                        width: 24,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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

  Widget _buildStatsGrid() {
    final progress = _progressService.progress;
    final stats = [
      _StatItem('Findings', progress.totalFindings, Icons.search, const Color(0xFF2196F3)),
      _StatItem('3D Models', progress.total3DModels, Icons.view_in_ar, const Color(0xFF9C27B0)),
      _StatItem('Contexts', progress.totalContexts, Icons.layers, const Color(0xFFFF9800)),
      _StatItem('Notes', progress.totalNotes, Icons.note, const Color(0xFF4CAF50)),
      _StatItem('Reports', progress.totalReports, Icons.description, const Color(0xFFF44336)),
      _StatItem('Photos', progress.totalPhotos, Icons.photo_library, const Color(0xFF00BCD4)),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stat.icon, color: stat.color, size: 24),
              const SizedBox(height: 8),
              Text(
                '${stat.value}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                stat.label,
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSessionSummary() {
    final today = _progressService.todayStats;
    final progress = _progressService.progress;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildSummaryRow2('Findings today', today.findingsRecorded, Icons.search),
          const SizedBox(height: 12),
          _buildSummaryRow2('3D scans today', today.modelsCreated, Icons.view_in_ar),
          const SizedBox(height: 12),
          _buildSummaryRow2('Notes created', today.notesCreated, Icons.note_add),
          const Divider(color: Colors.white24, height: 24),
          _buildSummaryRow2('Active days', progress.currentStreak, Icons.calendar_today),
          const SizedBox(height: 12),
          _buildSummaryRow2('Best streak', progress.longestStreak, Icons.trending_up),
        ],
      ),
    );
  }

  Widget _buildSummaryRow2(String label, int value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFC107), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(180),
              fontSize: 14,
            ),
          ),
        ),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _StatItem {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  _StatItem(this.label, this.value, this.icon, this.color);
}

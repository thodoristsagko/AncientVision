import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/context_sheet.dart';
import '../utils/app_styles.dart';

/// Harris Matrix Visualization Screen
/// Displays stratigraphic relationships as a visual diagram
class HarrisMatrixScreen extends StatefulWidget {
  const HarrisMatrixScreen({super.key});

  @override
  State<HarrisMatrixScreen> createState() => _HarrisMatrixScreenState();
}

class _HarrisMatrixScreenState extends State<HarrisMatrixScreen> {
  final TransformationController _transformController = TransformationController();
  List<ContextSheet> _contexts = [];
  bool _isLoading = true;
  String? _selectedContextId;

  // Layout positions for nodes
  final Map<String, Offset> _nodePositions = {};

  @override
  void initState() {
    super.initState();
    _loadContexts();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadContexts() async {
    // Load contexts from storage - for demo, create sample data
    await Future.delayed(const Duration(milliseconds: 500));

    // Sample contexts for demonstration
    _contexts = _createSampleContexts();
    _calculateLayout();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<ContextSheet> _createSampleContexts() {
    return [
      ContextSheet(
        id: '1',
        contextNumber: '001',
        type: ContextType.deposit,
        interpretation: 'Topsoil',
        below: ['002', '003'],
      ),
      ContextSheet(
        id: '2',
        contextNumber: '002',
        type: ContextType.deposit,
        interpretation: 'Occupation layer',
        above: ['001'],
        below: ['004'],
        cuts: ['005'],
      ),
      ContextSheet(
        id: '3',
        contextNumber: '003',
        type: ContextType.structure,
        interpretation: 'Wall foundation',
        above: ['001'],
        below: ['004'],
      ),
      ContextSheet(
        id: '4',
        contextNumber: '004',
        type: ContextType.deposit,
        interpretation: 'Floor surface',
        above: ['002', '003'],
        below: ['006'],
      ),
      ContextSheet(
        id: '5',
        contextNumber: '005',
        type: ContextType.cut,
        interpretation: 'Pit cut',
        cutBy: ['002'],
        filledBy: ['007'],
      ),
      ContextSheet(
        id: '6',
        contextNumber: '006',
        type: ContextType.natural,
        interpretation: 'Natural clay',
        above: ['004'],
      ),
      ContextSheet(
        id: '7',
        contextNumber: '007',
        type: ContextType.fill,
        interpretation: 'Pit fill',
        fills: ['005'],
      ),
    ];
  }

  void _calculateLayout() {
    if (_contexts.isEmpty) return;

    // Build adjacency map
    final Map<String, Set<String>> belowMap = {};
    final Map<String, int> levels = {};

    for (var ctx in _contexts) {
      belowMap[ctx.contextNumber] = {};
      if (ctx.below != null) {
        belowMap[ctx.contextNumber]!.addAll(ctx.below!);
      }
    }

    // Topological sort to determine levels
    Set<String> visited = {};

    int getLevel(String ctxNum) {
      if (levels.containsKey(ctxNum)) return levels[ctxNum]!;
      if (visited.contains(ctxNum)) return 0;
      visited.add(ctxNum);

      int maxChildLevel = -1;
      for (var below in belowMap[ctxNum] ?? <String>{}) {
        maxChildLevel = math.max(maxChildLevel, getLevel(below));
      }
      levels[ctxNum] = maxChildLevel + 1;
      return levels[ctxNum]!;
    }

    for (var ctx in _contexts) {
      getLevel(ctx.contextNumber);
    }

    // Group by level
    final Map<int, List<String>> levelGroups = {};
    for (var entry in levels.entries) {
      levelGroups.putIfAbsent(entry.value, () => []);
      levelGroups[entry.value]!.add(entry.key);
    }

    // Calculate positions
    const nodeWidth = 100.0;
    const nodeHeight = 60.0;
    const horizontalSpacing = 40.0;
    const verticalSpacing = 100.0;
    const startX = 150.0;
    const startY = 100.0;

    int maxLevel = levels.values.fold(0, math.max);

    for (int level = maxLevel; level >= 0; level--) {
      final nodesAtLevel = levelGroups[level] ?? [];
      final levelWidth = nodesAtLevel.length * (nodeWidth + horizontalSpacing) - horizontalSpacing;
      double x = startX + (500 - levelWidth) / 2; // Center nodes

      for (var ctxNum in nodesAtLevel) {
        _nodePositions[ctxNum] = Offset(x, startY + (maxLevel - level) * (nodeHeight + verticalSpacing));
        x += nodeWidth + horizontalSpacing;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Harris Matrix', style: AppTextStyles.h3),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _transformController.value = Matrix4.identity();
            },
            tooltip: 'Reset view',
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showLegend,
            tooltip: 'Legend',
          ),
        ],
      ),
      body: Container(
        decoration: AppDecorations.screenBackground,
        child: SafeArea(
          child: _isLoading
              ? AppWidgets.loading()
              : _contexts.isEmpty
                  ? _buildEmptyState()
                  : Column(
                      children: [
                        // Info bar
                        _buildInfoBar(),
                        // Matrix view
                        Expanded(
                          child: InteractiveViewer(
                            transformationController: _transformController,
                            boundaryMargin: const EdgeInsets.all(200),
                            minScale: 0.3,
                            maxScale: 3.0,
                            child: SizedBox(
                              width: 800,
                              height: 800,
                              child: CustomPaint(
                                painter: _HarrisMatrixPainter(
                                  contexts: _contexts,
                                  nodePositions: _nodePositions,
                                  selectedId: _selectedContextId,
                                ),
                                child: Stack(
                                  children: _contexts.map((ctx) => _buildContextNode(ctx)).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Selected context details
                        if (_selectedContextId != null) _buildSelectedDetails(),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildInfoBar() {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card,
      child: Row(
        children: [
          Icon(Icons.account_tree, color: AppColors.accent, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text('${_contexts.length} Contexts', style: AppTextStyles.body),
          const Spacer(),
          Text('Pinch to zoom, drag to pan', style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_tree_outlined, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text('No contexts recorded', style: AppTextStyles.subtitle),
          const SizedBox(height: AppSpacing.sm),
          Text('Add contexts with relationships to see the matrix', style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _buildContextNode(ContextSheet ctx) {
    final position = _nodePositions[ctx.contextNumber];
    if (position == null) return const SizedBox.shrink();

    final isSelected = _selectedContextId == ctx.id;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onTap: () => setState(() => _selectedContextId = isSelected ? null : ctx.id),
        child: Container(
          width: 100,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? ctx.type.color : ctx.type.color.withAlpha(200),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.accent : Colors.white24,
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.accent.withAlpha(100), blurRadius: 10)]
                : [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ctx.contextNumber,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ctx.type.label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedDetails() {
    final ctx = _contexts.firstWhere(
      (c) => c.id == _selectedContextId,
      orElse: () => _contexts.first,
    );

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ctx.type.color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Context ${ctx.contextNumber}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(ctx.type.icon, color: ctx.type.color, size: 20),
              const SizedBox(width: 4),
              Text(ctx.type.label, style: AppTextStyles.subtitle),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _selectedContextId = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (ctx.interpretation != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(ctx.interpretation!, style: AppTextStyles.body),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (ctx.above?.isNotEmpty ?? false)
                _buildRelationChip('Above: ${ctx.above!.join(", ")}', Colors.green),
              if (ctx.below?.isNotEmpty ?? false)
                _buildRelationChip('Below: ${ctx.below!.join(", ")}', Colors.blue),
              if (ctx.cuts?.isNotEmpty ?? false)
                _buildRelationChip('Cuts: ${ctx.cuts!.join(", ")}', Colors.red),
              if (ctx.cutBy?.isNotEmpty ?? false)
                _buildRelationChip('Cut by: ${ctx.cutBy!.join(", ")}', Colors.orange),
              if (ctx.fills?.isNotEmpty ?? false)
                _buildRelationChip('Fills: ${ctx.fills!.join(", ")}', Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRelationChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  void _showLegend() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: AppDecorations.bottomSheet,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Harris Matrix Legend', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.lg),

            Text('Context Types:', style: AppTextStyles.subtitle),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: ContextType.values.map((type) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: type.color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(type.icon, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(type.label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              )).toList(),
            ),

            const SizedBox(height: AppSpacing.lg),
            Text('Relationships:', style: AppTextStyles.subtitle),
            const SizedBox(height: AppSpacing.sm),
            _buildLegendLine('Solid line', 'Above/Below (stratigraphic)', Colors.white70),
            _buildLegendLine('Dashed line', 'Cuts/Cut by', Colors.red),
            _buildLegendLine('Dotted line', 'Fills/Filled by', Colors.purple),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendLine(String lineType, String meaning, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 2,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text('$lineType - $meaning', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

/// Custom painter for Harris Matrix lines
class _HarrisMatrixPainter extends CustomPainter {
  final List<ContextSheet> contexts;
  final Map<String, Offset> nodePositions;
  final String? selectedId;

  _HarrisMatrixPainter({
    required this.contexts,
    required this.nodePositions,
    this.selectedId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw relationships
    for (var ctx in contexts) {
      final fromPos = nodePositions[ctx.contextNumber];
      if (fromPos == null) continue;

      final fromCenter = Offset(fromPos.dx + 50, fromPos.dy + 30);

      // Draw "below" relationships (solid lines)
      if (ctx.below != null) {
        for (var toNum in ctx.below!) {
          final toPos = nodePositions[toNum];
          if (toPos == null) continue;
          final toCenter = Offset(toPos.dx + 50, toPos.dy);
          _drawLine(canvas, fromCenter.translate(0, 30), toCenter, Colors.white54, false, false);
        }
      }

      // Draw "cuts" relationships (dashed red lines)
      if (ctx.cuts != null) {
        for (var toNum in ctx.cuts!) {
          final toPos = nodePositions[toNum];
          if (toPos == null) continue;
          final toCenter = Offset(toPos.dx + 50, toPos.dy + 30);
          _drawLine(canvas, fromCenter, toCenter, Colors.red.shade400, true, false);
        }
      }

      // Draw "fills" relationships (dotted purple lines)
      if (ctx.fills != null) {
        for (var toNum in ctx.fills!) {
          final toPos = nodePositions[toNum];
          if (toPos == null) continue;
          final toCenter = Offset(toPos.dx + 50, toPos.dy + 30);
          _drawLine(canvas, fromCenter, toCenter, Colors.purple.shade300, false, true);
        }
      }
    }
  }

  void _drawLine(Canvas canvas, Offset from, Offset to, Color color, bool dashed, bool dotted) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (!dashed && !dotted) {
      // Solid line
      canvas.drawLine(from, to, paint);
    } else {
      // Dashed or dotted line
      final distance = (to - from).distance;
      final direction = (to - from) / distance;
      final dashLength = dashed ? 8.0 : 3.0;
      final gapLength = dashed ? 4.0 : 3.0;

      double drawn = 0;
      bool drawing = true;
      Offset current = from;

      while (drawn < distance) {
        final segmentLength = drawing ? dashLength : gapLength;
        final remaining = distance - drawn;
        final length = math.min(segmentLength, remaining);

        final next = current + direction * length;

        if (drawing) {
          canvas.drawLine(current, next, paint);
        }

        current = next;
        drawn += length;
        drawing = !drawing;
      }
    }

    // Draw arrow at end
    _drawArrow(canvas, from, to, color);
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final direction = (to - from);
    final normalized = direction / direction.distance;
    final perpendicular = Offset(-normalized.dy, normalized.dx);

    final arrowSize = 8.0;
    final arrowTip = to;
    final arrowLeft = to - normalized * arrowSize + perpendicular * arrowSize / 2;
    final arrowRight = to - normalized * arrowSize - perpendicular * arrowSize / 2;

    final path = Path()
      ..moveTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(arrowLeft.dx, arrowLeft.dy)
      ..lineTo(arrowRight.dx, arrowRight.dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HarrisMatrixPainter oldDelegate) {
    return oldDelegate.contexts.length != contexts.length ||
           oldDelegate.selectedId != selectedId;
  }
}

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pattern_service.dart';
import '../models/pattern_insight.dart';
import '../db/database_helper.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _ps = PatternService.instance;
  double _lifeScore = 0;
  Map<String, double> _breakdown = {};
  List<double> _scoreTrend = [];
  List<PatternInsight> _insights = [];
  String _eveningSummary = '';
  Map<String, dynamic> _lifetimeStats = {};
  bool _loading = true;

  // 7D / 30D toggle
  int _trendDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final results = await Future.wait([
      _ps.computeTodayScore(),
      _ps.getTodayScoreBreakdown(),
      _ps.getScoreTrend(days: _trendDays),
      _ps.generateInsights(),
      _ps.getLifetimeStats(),
    ]);

    final score = results[0] as double;
    final breakdown = results[1] as Map<String, double>;
    final trend = results[2] as List<double>;
    final insights = results[3] as List<PatternInsight>;
    final lifetimeStats = results[4] as Map<String, dynamic>;

    String summary = '';
    if (DateTime.now().hour >= 18) {
      summary = await _ps.generateEveningSummary();
    }

    if (!mounted) return;
    setState(() {
      _lifeScore = score;
      _breakdown = breakdown;
      _scoreTrend = trend;
      _insights = insights;
      _eveningSummary = summary;
      _lifetimeStats = lifetimeStats;
      _loading = false;
    });
  }

  Future<void> _switchTrend(int days) async {
    if (_trendDays == days) return;
    setState(() => _trendDays = days);
    final trend = await _ps.getScoreTrend(days: days);
    if (!mounted) return;
    setState(() => _scoreTrend = trend);
  }

  Color _scoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.teal;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  String _scoreLabel(double score) {
    if (score >= 80) return 'Outstanding';
    if (score >= 60) return 'Good Day';
    if (score >= 40) return 'Room to grow';
    return 'Start somewhere';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    // Build x-axis labels for the trend chart
    final trendLabels = List.generate(_trendDays, (i) {
      final d = now.subtract(Duration(days: _trendDays - 1 - i));
      return _trendDays <= 7
          ? DateFormat('E').format(d)
          : DateFormat('d').format(d);
    });

    // Score breakdown data for pie chart (weighted by actual completion)
    final habitsRaw = _breakdown['habits'] ?? 0;
    final stepsRaw = _breakdown['steps'] ?? 0;
    final waterRaw = _breakdown['water'] ?? 0;
    final todosRaw = _breakdown['todos'] ?? 0;

    // Weights: habits=30, steps=25, water=25, todos=20
    final pieTotal =
        habitsRaw * 0.30 + stepsRaw * 0.25 + waterRaw * 0.25 + todosRaw * 0.20;
    final pieHabits = habitsRaw * 0.30;
    final pieSteps = stepsRaw * 0.25;
    final pieWater = waterRaw * 0.25;
    final pieTodos = todosRaw * 0.20;

    // Lifetime stats
    final totalXp = (_lifetimeStats['totalXp'] as int? ?? 0);
    final bestStreak = (_lifetimeStats['bestStreak'] as int? ?? 0);
    final totalHabitsDone =
        (_lifetimeStats['totalHabitsCompleted'] as int? ?? 0);
    final avgScore = (_lifetimeStats['avgScore'] as double? ?? 0.0);
    final daysTracked = (_lifetimeStats['daysTracked'] as int? ?? 0);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // ── Lifetime Stats Chips ───────────────────────────────────────
            Text('Lifetime Stats',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatChip(
                    emoji: '⚡',
                    label: 'Total XP',
                    value: NumberFormat('#,##0').format(totalXp),
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    emoji: '🔥',
                    label: 'Best Streak',
                    value: '$bestStreak days',
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    emoji: '✅',
                    label: 'Habits Done',
                    value: NumberFormat('#,##0').format(totalHabitsDone),
                    color: Colors.green,
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    emoji: '📊',
                    label: 'Avg Score',
                    value: avgScore.toStringAsFixed(1),
                    color: Colors.teal,
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    emoji: '📅',
                    label: 'Days Tracked',
                    value: '$daysTracked',
                    color: Colors.blue,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Life Score Ring ────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('Life Score',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: CircularProgressIndicator(
                            value: _lifeScore / 100,
                            strokeWidth: 16,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: _scoreColor(_lifeScore),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_lifeScore.toStringAsFixed(0),
                                style: Theme.of(context)
                                    .textTheme
                                    .displaySmall
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: _scoreColor(_lifeScore))),
                            Text(_scoreLabel(_lifeScore),
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Score breakdown pills
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ScorePill(
                            label: 'Habits',
                            value: _breakdown['habits'] ?? 0,
                            color: Colors.purple),
                        _ScorePill(
                            label: 'Steps',
                            value: _breakdown['steps'] ?? 0,
                            color: Colors.teal),
                        _ScorePill(
                            label: 'Water',
                            value: _breakdown['water'] ?? 0,
                            color: Colors.blue),
                        _ScorePill(
                            label: 'Tasks',
                            value: _breakdown['todos'] ?? 0,
                            color: Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Score Breakdown Pie Chart ──────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Score Breakdown',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: pieTotal <= 0
                          ? const Center(
                              child: Text('No data yet for today',
                                  style: TextStyle(color: Colors.grey)))
                          : PieChart(
                              PieChartData(
                                sections: [
                                  PieChartSectionData(
                                    value: pieHabits,
                                    title:
                                        '${(pieHabits / pieTotal * 100).toStringAsFixed(0)}%',
                                    color: Colors.purple,
                                    radius: 60,
                                    titleStyle: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                  PieChartSectionData(
                                    value: pieSteps,
                                    title:
                                        '${(pieSteps / pieTotal * 100).toStringAsFixed(0)}%',
                                    color: Colors.teal,
                                    radius: 60,
                                    titleStyle: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                  PieChartSectionData(
                                    value: pieWater,
                                    title:
                                        '${(pieWater / pieTotal * 100).toStringAsFixed(0)}%',
                                    color: Colors.blue,
                                    radius: 60,
                                    titleStyle: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                  PieChartSectionData(
                                    value: pieTodos,
                                    title:
                                        '${(pieTodos / pieTotal * 100).toStringAsFixed(0)}%',
                                    color: Colors.orange,
                                    radius: 60,
                                    titleStyle: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                ],
                                centerSpaceRadius: 36,
                                sectionsSpace: 2,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: const [
                        _PieLegend(label: 'Habits (30%)', color: Colors.purple),
                        _PieLegend(label: 'Steps (25%)', color: Colors.teal),
                        _PieLegend(label: 'Water (25%)', color: Colors.blue),
                        _PieLegend(label: 'Tasks (20%)', color: Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Score Trend (7D / 30D) ─────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Score Trend',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 7, label: Text('7D')),
                            ButtonSegment(value: 30, label: Text('30D')),
                          ],
                          selected: {_trendDays},
                          onSelectionChanged: (s) => _switchTrend(s.first),
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 140,
                      child: _scoreTrend.isEmpty
                          ? const Center(
                              child: Text('No trend data yet',
                                  style: TextStyle(color: Colors.grey)))
                          : BarChart(
                              BarChartData(
                                maxY: 100,
                                barGroups: _scoreTrend.asMap().entries.map((e) {
                                  final score = e.value;
                                  return BarChartGroupData(
                                    x: e.key,
                                    barRods: [
                                      BarChartRodData(
                                        toY: score,
                                        color: _scoreColor(score),
                                        width:
                                            _trendDays <= 7 ? 22 : 8,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ],
                                  );
                                }).toList(),
                                gridData: const FlGridData(show: false),
                                borderData: FlBorderData(show: false),
                                titlesData: FlTitlesData(
                                  leftTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 22,
                                      getTitlesWidget: (v, _) {
                                        final idx = v.toInt();
                                        if (idx < 0 ||
                                            idx >= trendLabels.length) {
                                          return const SizedBox.shrink();
                                        }
                                        // For 30D, only show every 5th label to avoid crowding
                                        if (_trendDays == 30 && idx % 5 != 0) {
                                          return const SizedBox.shrink();
                                        }
                                        return Text(
                                          trendLabels[idx],
                                          style: const TextStyle(fontSize: 10),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Evening Summary ────────────────────────────────────────────
            if (_eveningSummary.isNotEmpty) ...[
              Card(
                color: scheme.inverseSurface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🌙', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Text('Your Day in Review',
                              style: TextStyle(
                                  color: scheme.onInverseSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(_eveningSummary,
                          style: TextStyle(
                              color: scheme.onInverseSurface, height: 1.5)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Bedtime Tamil Melody ───────────────────────────────────────
            if (now.hour >= 21) ...[
              Card(
                color: const Color(0xFF1A237E),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text('🎵', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bedtime Tamil Melody',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            Text('Wind down with peaceful Tamil music',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => launchUrl(
                          Uri.parse(
                              'https://www.youtube.com/results?search_query=tamil+lullaby+sleep+music'),
                          mode: LaunchMode.externalApplication,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1A237E),
                        ),
                        child: const Text('Play'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Hidden Patterns ────────────────────────────────────────────
            Text('Hidden Patterns',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text('Discovered from your daily activity',
                style:
                    TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 12),

            ..._insights.map((insight) => _InsightCard(insight: insight)),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── Lifetime Stat Chip ──────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }
}

// ── Pie Legend dot ──────────────────────────────────────────────────────────

class _PieLegend extends StatelessWidget {
  final String label;
  final Color color;

  const _PieLegend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ── Score Pill ──────────────────────────────────────────────────────────────

class _ScorePill extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _ScorePill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${value.toStringAsFixed(0)}%',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

// ── Insight Card ────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final PatternInsight insight;

  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = insight.isPositive ? Colors.green : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor.withOpacity(0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(insight.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(insight.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(insight.description,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: borderColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(insight.confidenceLabel,
                            style:
                                TextStyle(fontSize: 11, color: borderColor)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: insight.confidence,
                            minHeight: 4,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: borderColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

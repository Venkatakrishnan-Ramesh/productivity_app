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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final score = await _ps.computeTodayScore();
    final breakdown = await _ps.getTodayScoreBreakdown();
    final trend = await _ps.getScoreTrend(7);
    final insights = await _ps.generateInsights();
    String summary = '';
    if (DateTime.now().hour >= 18) {
      summary = await _ps.generateEveningSummary();
    }

    setState(() {
      _lifeScore = score;
      _breakdown = breakdown;
      _scoreTrend = trend;
      _insights = insights;
      _eveningSummary = summary;
      _loading = false;
    });
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
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final weekDays = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateFormat('E').format(d);
    });

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // Life Score Ring
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
                                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _scoreColor(_lifeScore))),
                            Text(_scoreLabel(_lifeScore),
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Breakdown
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ScorePill(label: 'Habits', value: _breakdown['habits'] ?? 0, color: Colors.purple),
                        _ScorePill(label: 'Steps', value: _breakdown['steps'] ?? 0, color: Colors.teal),
                        _ScorePill(label: 'Water', value: _breakdown['water'] ?? 0, color: Colors.blue),
                        _ScorePill(label: 'Tasks', value: _breakdown['todos'] ?? 0, color: Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 7-day trend
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('7-Day Trend',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 140,
                      child: BarChart(
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
                                  width: 22,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            );
                          }).toList(),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) => Text(
                                  weekDays[v.toInt()],
                                  style: const TextStyle(fontSize: 11),
                                ),
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

            // Evening summary (after 6 PM)
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

            // Bedtime Tamil melody card
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
                                    color: Colors.white, fontWeight: FontWeight.bold)),
                            Text('Wind down with peaceful Tamil music',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => launchUrl(
                          Uri.parse('https://www.youtube.com/results?search_query=tamil+lullaby+sleep+music'),
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

            // Hidden patterns
            Text('Hidden Patterns',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text('Discovered from your daily activity',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 12),

            ..._insights.map((insight) => _InsightCard(insight: insight)),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _ScorePill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${value.toStringAsFixed(0)}%',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(insight.description,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: borderColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(insight.confidenceLabel,
                            style: TextStyle(fontSize: 11, color: borderColor)),
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

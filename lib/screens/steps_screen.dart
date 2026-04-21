import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/step_service.dart';
import '../db/database_helper.dart';

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  final db = DatabaseHelper.instance;
  int _steps = 0;
  bool _hasPermission = false;
  bool _loading = true;
  List<Map<String, dynamic>> _weekHistory = [];
  static const int _goal = 10000;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final granted = await Permission.activityRecognition.isGranted;
    if (!granted) {
      final result = await StepService.requestPermission();
      if (!result) {
        setState(() { _loading = false; });
        return;
      }
    }
    setState(() => _hasPermission = true);
    await StepService.instance.init();
    StepService.instance.stepsStream.listen((s) {
      if (mounted) setState(() => _steps = s);
    });
    _steps = StepService.instance.dailySteps;
    await _loadHistory();
    setState(() => _loading = false);
  }

  Future<void> _loadHistory() async {
    final history = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dateStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final record = await db.getStepRecord(dateStr);
      history.add({
        'date': day,
        'steps': record != null ? (record['steps'] as int) : 0,
      });
    }
    if (mounted) setState(() => _weekHistory = history);
  }

  double get _distance => _steps * 0.000762; // km
  int get _calories => (_steps * 0.04).round();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasPermission) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_walk, size: 64, color: scheme.primary),
                const SizedBox(height: 16),
                const Text(
                  'Activity permission needed\nto track your steps.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _init,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Grant Permission'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final progress = min(1.0, _steps / _goal);
    final maxSteps = _weekHistory.isEmpty
        ? _goal.toDouble()
        : max(_goal.toDouble(), _weekHistory.map((e) => (e['steps'] as int).toDouble()).reduce(max));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          _steps = StepService.instance.dailySteps;
          await _loadHistory();
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Ring progress
            Center(
              child: SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 18,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: progress >= 1.0 ? Colors.green : scheme.primary,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_steps',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                        Text('of $_goal steps',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        if (progress >= 1.0)
                          const Text('🎉 Goal reached!',
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Stats row
            Row(
              children: [
                _StatCard(
                  icon: Icons.route,
                  label: 'Distance',
                  value: '${_distance.toStringAsFixed(2)} km',
                  color: Colors.teal,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.local_fire_department,
                  label: 'Calories',
                  value: '$_calories kcal',
                  color: Colors.orange,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Weekly chart
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This Week',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 160,
                      child: BarChart(
                        BarChartData(
                          maxY: maxSteps,
                          barGroups: _weekHistory.asMap().entries.map((e) {
                            final steps = (e.value['steps'] as int).toDouble();
                            return BarChartGroupData(
                              x: e.key,
                              barRods: [
                                BarChartRodData(
                                  toY: steps,
                                  color: steps >= _goal
                                      ? Colors.green
                                      : scheme.primary,
                                  width: 22,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            );
                          }).toList(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: _goal.toDouble(),
                            getDrawingHorizontalLine: (v) => FlLine(
                              color: Colors.green.withOpacity(0.3),
                              strokeWidth: 1,
                              dashArray: [4, 4],
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) {
                                  if (v.toInt() >= _weekHistory.length) return const SizedBox.shrink();
                                  final date = _weekHistory[v.toInt()]['date'] as DateTime;
                                  return Text(DateFormat('E').format(date),
                                      style: const TextStyle(fontSize: 11));
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

            // Tips card
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _steps < 3000
                            ? 'Take a short walk — even 10 minutes counts!'
                            : _steps < 7000
                                ? 'Halfway there! Keep moving.'
                                : _steps < _goal
                                    ? 'Almost at your goal — push through!'
                                    : 'Goal crushed! Harvey would approve.',
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
              Text(value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

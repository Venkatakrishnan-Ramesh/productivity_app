import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  int _goal = 10000;

  // Week navigation: 0 = this week, -1 = last week, etc.
  int _weekOffset = 0;
  List<Map<String, dynamic>> _weekHistory = [];

  // Streak
  int _currentStreak = 0;
  int _longestStreak = 0;

  // Summary stats
  double _weeklyAvg = 0;
  int _bestDay = 0;
  int _daysMetGoal = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Load goal from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedGoal = prefs.getInt('step_goal') ?? 10000;
    if (mounted) setState(() => _goal = savedGoal);

    final granted = await Permission.activityRecognition.isGranted;
    if (!granted) {
      final result = await StepService.requestPermission();
      if (!result) {
        if (mounted) setState(() => _loading = false);
        return;
      }
    }
    if (mounted) setState(() => _hasPermission = true);
    await StepService.instance.init();
    StepService.instance.stepsStream.listen((s) {
      if (mounted) setState(() => _steps = s);
    });
    _steps = StepService.instance.dailySteps;
    await _loadHistory();
    await _loadStreak();
    await _loadWeeklyStats();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadHistory() async {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final currentWeekMonday =
        todayMidnight.subtract(Duration(days: todayMidnight.weekday - 1));
    final targetMonday =
        currentWeekMonday.add(Duration(days: _weekOffset * 7));

    final history = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final day = targetMonday.add(Duration(days: i));
      final dateStr =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final record = await db.getStepRecord(dateStr);
      history.add({
        'date': day,
        'steps': record != null ? (record['steps'] as int) : 0,
      });
    }
    if (mounted) setState(() => _weekHistory = history);
  }

  Future<void> _loadStreak() async {
    final streakData = await db.getStepStreak(_goal);
    if (mounted) {
      setState(() {
        _currentStreak = (streakData['currentStreak'] as int?) ?? 0;
        _longestStreak = (streakData['longestStreak'] as int?) ?? 0;
      });
    }
  }

  Future<void> _loadWeeklyStats() async {
    final stats = await StepService.instance.getWeeklyStats();
    if (mounted) {
      setState(() {
        _weeklyAvg = (stats['weeklyAvg'] as double?) ?? 0.0;
        _bestDay = (stats['bestDay'] as int?) ?? 0;
        _daysMetGoal = (stats['daysMetGoal'] as int?) ?? 0;
      });
    }
  }

  double get _distance => _steps * 0.000762; // km
  int get _calories => (_steps * 0.04).round();

  String get _weekRangeLabel {
    if (_weekOffset == 0) return '7-Day History';
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final currentWeekMonday =
        todayMidnight.subtract(Duration(days: todayMidnight.weekday - 1));
    final targetMonday =
        currentWeekMonday.add(Duration(days: _weekOffset * 7));
    final targetSunday = targetMonday.add(const Duration(days: 6));
    final fmt = DateFormat('MMM d');
    return '${fmt.format(targetMonday)} – ${fmt.format(targetSunday)}';
  }

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
        : max(_goal.toDouble(),
            _weekHistory.map((e) => (e['steps'] as int).toDouble()).reduce(max));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          _steps = StepService.instance.dailySteps;
          await _loadHistory();
          await _loadStreak();
          await _loadWeeklyStats();
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Streak Card ─────────────────────────────────────────────────
            _StreakCard(
              currentStreak: _currentStreak,
              longestStreak: _longestStreak,
            ),

            const SizedBox(height: 20),

            // ── Ring progress ───────────────────────────────────────────────
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
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                        ),
                        Text('of $_goal steps',
                            style:
                                TextStyle(color: scheme.onSurfaceVariant)),
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

            const SizedBox(height: 20),

            // ── Distance / Calories row ─────────────────────────────────────
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

            const SizedBox(height: 16),

            // ── Summary stats row ───────────────────────────────────────────
            Row(
              children: [
                _SummaryChip(
                  label: 'Avg/day',
                  value: NumberFormat.compact().format(_weeklyAvg.round()),
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                _SummaryChip(
                  label: 'Best day',
                  value: NumberFormat.compact().format(_bestDay),
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 8),
                _SummaryChip(
                  label: 'Goal days',
                  value: '$_daysMetGoal / 7',
                  color: Colors.green,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Weekly chart ────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row with navigation arrows
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _weekRangeLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Previous week',
                          onPressed: () async {
                            setState(() => _weekOffset--);
                            await _loadHistory();
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Next week',
                          // Disable navigating into the future beyond current week
                          onPressed: _weekOffset < 0
                              ? () async {
                                  setState(() => _weekOffset++);
                                  await _loadHistory();
                                }
                              : null,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 160,
                      child: BarChart(
                        BarChartData(
                          maxY: maxSteps,
                          barGroups: _weekHistory.asMap().entries.map((e) {
                            final steps =
                                (e.value['steps'] as int).toDouble();
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
                                getTitlesWidget: (v, _) {
                                  if (v.toInt() >= _weekHistory.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final date = _weekHistory[v.toInt()]
                                      ['date'] as DateTime;
                                  return Text(
                                      DateFormat('E').format(date),
                                      style:
                                          const TextStyle(fontSize: 11));
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

            // ── Tips card ───────────────────────────────────────────────────
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
                        style:
                            TextStyle(color: scheme.onPrimaryContainer),
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

// ── Streak Card ────────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;

  const _StreakCard({
    required this.currentStreak,
    required this.longestStreak,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: currentStreak),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOut,
                        builder: (context, value, _) => Text(
                          '$value day streak',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.onSecondaryContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Longest: $longestStreak days',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSecondaryContainer
                              .withOpacity(0.7),
                        ),
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

// ── Summary Chip ───────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat Card ──────────────────────────────────────────────────────────────────

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

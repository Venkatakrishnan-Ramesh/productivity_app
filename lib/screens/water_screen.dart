import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';

class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key});

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen> {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _logs = [];
  int _totalMl = 0;
  int _goalMl = 2000;

  // Streak
  int _currentStreak = 0;
  int _longestStreak = 0;

  // Weekly chart data: index 0 = 6 days ago, index 6 = today
  List<int> _weeklyTotals = List.filled(7, 0);
  List<DateTime> _weeklyDates = [];

  // Customisable quick-add presets
  List<int> _presets = [250, 500, 750];

  static const String _presetsKey = 'water_presets';

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences().then((_) => _load());
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedGoal = prefs.getInt('water_goal') ?? 2000;
    final presetsJson = prefs.getString(_presetsKey);
    List<int> presets = [250, 500, 750];
    if (presetsJson != null) {
      try {
        presets = (jsonDecode(presetsJson) as List).cast<int>();
      } catch (_) {
        presets = [250, 500, 750];
      }
    }
    if (mounted) {
      setState(() {
        _goalMl = savedGoal;
        _presets = presets;
      });
    }
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetsKey, jsonEncode(_presets));
  }

  Future<void> _load() async {
    final logs = await db.getWaterLogs(_todayStr);
    final total = logs.fold(0, (sum, l) => sum + (l['amount_ml'] as int));
    await _loadStreak();
    await _loadWeeklyData();
    if (mounted) {
      setState(() {
        _logs = logs;
        _totalMl = total;
      });
    }
  }

  Future<void> _loadStreak() async {
    final streakData = await db.getWaterStreak();
    if (mounted) {
      setState(() {
        _currentStreak = (streakData['currentStreak'] as int?) ?? 0;
        _longestStreak = (streakData['longestStreak'] as int?) ?? 0;
      });
    }
  }

  Future<void> _loadWeeklyData() async {
    final now = DateTime.now();
    final dates = <DateTime>[];
    for (int i = 6; i >= 0; i--) {
      final day =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      dates.add(day);
    }
    final fromStr =
        '${dates.first.year}-${dates.first.month.toString().padLeft(2, '0')}-${dates.first.day.toString().padLeft(2, '0')}';
    final toStr =
        '${dates.last.year}-${dates.last.month.toString().padLeft(2, '0')}-${dates.last.day.toString().padLeft(2, '0')}';

    final rawLogs = await db.getWaterLogsByDateRange(fromStr, toStr);

    // Aggregate by date
    final Map<String, int> totalsMap = {};
    for (final log in rawLogs) {
      final d = log['date'] as String;
      totalsMap[d] = (totalsMap[d] ?? 0) + (log['amount_ml'] as int);
    }

    final totals = dates.map((day) {
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      return totalsMap[key] ?? 0;
    }).toList();

    if (mounted) {
      setState(() {
        _weeklyDates = dates;
        _weeklyTotals = totals;
      });
    }
  }

  Future<void> _addWater(int ml) async {
    await db.insertWaterLog({
      'id': const Uuid().v4(),
      'date': _todayStr,
      'logged_at': DateTime.now().toIso8601String(),
      'amount_ml': ml,
    });
    await _load();
  }

  Future<void> _deleteLog(String id) async {
    await db.deleteWaterLog(id);
    await _load();
  }

  double get _progress => (_totalMl / _goalMl).clamp(0.0, 1.0);
  int get _glasses => _totalMl ~/ 250;
  int get _goalGlasses => _goalMl ~/ 250;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = (_goalMl - _totalMl).clamp(0, _goalMl);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Streak Card ───────────────────────────────────────────────
            _WaterStreakCard(
              currentStreak: _currentStreak,
              longestStreak: _longestStreak,
            ),

            const SizedBox(height: 20),

            // ── Main progress ring ────────────────────────────────────────
            Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 18,
                        backgroundColor: Colors.blue.shade100,
                        color: _progress >= 1.0 ? Colors.green : Colors.blue,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('💧', style: TextStyle(fontSize: 32)),
                        Text('$_glasses / $_goalGlasses',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                        Text('glasses',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        if (_progress >= 1.0)
                          const Text('🎉 Goal met!',
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            Center(
              child: Text(
                remaining > 0
                    ? '${remaining}ml (${remaining ~/ 250} glasses) to go'
                    : 'Perfectly hydrated today!',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 24),

            // ── Quick add buttons ─────────────────────────────────────────
            Text('Quick Add',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Preset buttons (long-press to edit)
                ..._presets.asMap().entries.map((entry) {
                  final index = entry.key;
                  final amount = entry.value;
                  return _QuickAddButton(
                    label: '${amount}ml',
                    onTap: () => _addWater(amount),
                    onLongPress: () => _editPreset(index),
                    color: Colors.blue.shade300.withOpacity(1.0 - index * 0.1),
                  );
                }),
                // Custom button
                _QuickAddButton(
                  label: 'Custom',
                  onTap: _showCustomInput,
                  color: scheme.primary,
                  icon: Icons.edit,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Glasses visualisation ─────────────────────────────────────
            Text('Today\'s intake',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_goalGlasses, (i) {
                final filled = i < _glasses;
                return Icon(
                  filled ? Icons.water_drop : Icons.water_drop_outlined,
                  size: 36,
                  color: filled ? Colors.blue : Colors.blue.shade200,
                );
              }),
            ),

            const SizedBox(height: 24),

            // ── Weekly bar chart ──────────────────────────────────────────
            if (_weeklyDates.isNotEmpty) ...[
              Text('7-Day History',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: SizedBox(
                    height: 180,
                    child: _buildWeeklyChart(scheme),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Log history ───────────────────────────────────────────────
            if (_logs.isNotEmpty) ...[
              Text('Log',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._logs.reversed.map((log) {
                final time = DateTime.parse(log['logged_at'] as String);
                return Dismissible(
                  key: Key(log['id'] as String),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteLog(log['id'] as String),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: const Icon(Icons.water_drop, color: Colors.blue),
                      title: Text('${log['amount_ml']}ml'),
                      trailing: Text(
                        DateFormat('h:mm a').format(time),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart(ColorScheme scheme) {
    final maxVal = _weeklyTotals.isEmpty
        ? _goalMl.toDouble()
        : max(_goalMl.toDouble(),
            _weeklyTotals.map((t) => t.toDouble()).reduce(max));

    return BarChart(
      BarChartData(
        maxY: maxVal,
        barGroups: _weeklyTotals.asMap().entries.map((e) {
          final total = e.value.toDouble();
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: total,
                color: total >= _goalMl ? Colors.green : Colors.blue.shade400,
                width: 20,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: _goalMl.toDouble(),
              color: Colors.blue.withOpacity(0.5),
              strokeWidth: 1.5,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 4, bottom: 2),
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold),
                labelResolver: (_) => 'Goal',
              ),
            ),
          ],
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _goalMl.toDouble(),
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= _weeklyDates.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  DateFormat('E').format(_weeklyDates[idx]),
                  style: const TextStyle(fontSize: 11),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomInput() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom amount'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Amount (ml)',
              border: OutlineInputBorder(),
              suffixText: 'ml'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final ml = int.tryParse(ctrl.text.trim());
              if (ml != null && ml > 0) {
                Navigator.pop(ctx);
                _addWater(ml);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _editPreset(int index) {
    final ctrl = TextEditingController(text: _presets[index].toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit preset ${index + 1}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Amount (ml)',
              border: OutlineInputBorder(),
              suffixText: 'ml'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final ml = int.tryParse(ctrl.text.trim());
              if (ml != null && ml > 0) {
                Navigator.pop(ctx);
                setState(() => _presets[index] = ml);
                _savePresets();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── Water Streak Card ──────────────────────────────────────────────────────────

class _WaterStreakCard extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;

  const _WaterStreakCard({
    required this.currentStreak,
    required this.longestStreak,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const Text('💧', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: currentStreak),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    builder: (context, value, _) => Text(
                      '$value day streak',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Longest: $longestStreak days',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue.shade400,
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

// ── Quick Add Button ───────────────────────────────────────────────────────────

class _QuickAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final IconData? icon;

  const _QuickAddButton({
    required this.label,
    required this.onTap,
    this.onLongPress,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, color: color, size: 20)
            else
              const Icon(Icons.add, size: 16),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

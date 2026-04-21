import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/habit.dart';
import '../models/transaction.dart';
import '../models/level_helper.dart';
import '../data/suits_quotes.dart';
import '../services/step_service.dart';
import '../services/pattern_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final db = DatabaseHelper.instance;
  final ps = PatternService.instance;
  List<Habit> habits = [];
  List<FinanceTransaction> transactions = [];
  final fmt = NumberFormat('#,##0.00');
  int _steps = 0;
  int _waterMl = 0;
  double _lifeScore = 0;
  int _totalXp = 0;
  int _todayXp = 0;
  String? _intention;
  StreamSubscription? _stepSub;

  @override
  void initState() {
    super.initState();
    _load();
    _stepSub = StepService.instance.stepsStream.listen((s) {
      if (mounted) setState(() => _steps = s);
    });
    _steps = StepService.instance.dailySteps;
  }

  @override
  void dispose() {
    _stepSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final today = _todayStr();
    final habitMaps = await db.getHabits();
    final List<Habit> loadedHabits = [];
    for (final m in habitMaps) {
      final logs = await db.getLogsForHabit(m['id']);
      final logDates = logs.map((l) => l['date'] as String).toList();
      final doneToday = await db.isHabitLoggedToday(m['id'], today);
      loadedHabits.add(Habit(
        id: m['id'],
        name: m['name'],
        emoji: m['emoji'],
        xp: (m['xp'] as int? ?? 10),
        createdAt: m['created_at'],
        logs: logDates,
        doneToday: doneToday,
      ));
    }
    final txMaps = await db.getTransactions();
    final waterMl = await db.getTotalWaterToday(today);
    final score = await ps.computeTodayScore();
    final totalXp = await db.getTotalXP();
    final todayXp = await db.getTodayXP(today);
    final plan = await db.getDailyPlan(today);

    setState(() {
      habits = loadedHabits;
      transactions = txMaps
          .map((m) => FinanceTransaction(
                id: m['id'],
                title: m['title'],
                amount: m['amount'],
                category: m['category'],
                type: m['type'],
                date: m['date'],
              ))
          .toList();
      _waterMl = waterMl;
      _lifeScore = score;
      _totalXp = totalXp;
      _todayXp = todayXp;
      _intention = plan?['intention'] as String?;
    });
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String get _briefing {
    final h = DateTime.now().hour;
    if (h < 5) return 'It\'s late, Agent. Make it count.';
    if (h < 12) return 'Good morning, Agent. Your missions await.';
    if (h < 17) return 'Stay sharp, Agent. The day isn\'t over.';
    if (h < 21) return 'Evening debrief, Agent. How\'d you do?';
    return 'Night ops, Agent. Wrap up strong.';
  }

  Color _scoreColor(double s) {
    if (s >= 80) return Colors.green;
    if (s >= 60) return Colors.teal;
    if (s >= 40) return Colors.orange;
    return Colors.red;
  }

  double get totalIncome =>
      transactions.where((t) => t.isIncome).fold(0, (s, t) => s + t.amount);
  double get totalExpense =>
      transactions.where((t) => !t.isIncome).fold(0, (s, t) => s + t.amount);
  int get completedToday => habits.where((h) => h.doneToday).length;

  List<PieChartSectionData> _expensePieSections() {
    final Map<String, double> byCategory = {};
    for (final t in transactions.where((t) => !t.isIncome)) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
    }
    if (byCategory.isEmpty) return [];
    final colors = [
      Colors.red, Colors.orange, Colors.blue,
      Colors.green, Colors.purple, Colors.teal, Colors.pink
    ];
    final entries = byCategory.entries.toList();
    final total = byCategory.values.fold(0.0, (s, v) => s + v);
    return entries.asMap().entries.map((e) => PieChartSectionData(
          value: e.value.value,
          title: '${(e.value.value / total * 100).toStringAsFixed(0)}%',
          color: colors[e.key % colors.length],
          radius: 55,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        )).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final quote = getDailyQuote();
    final pieSections = _expensePieSections();
    final recentTx = transactions.take(3).toList();
    final levelTitle = LevelHelper.title(_totalXp);
    final levelNum = LevelHelper.number(_totalXp);
    final lvlProgress = LevelHelper.progress(_totalXp);
    final xpToNext = LevelHelper.xpToNext(_totalXp);
    final isPerfect = habits.isNotEmpty && completedToday == habits.length;

    final expenseByCategory = <String, double>{};
    for (final t in transactions.where((t) => !t.isIncome)) {
      expenseByCategory[t.category] =
          (expenseByCategory[t.category] ?? 0) + t.amount;
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Agent Briefing Header ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AGENT BRIEFING',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                            color: scheme.primary)),
                    const SizedBox(height: 2),
                    Text(DateFormat('EEEE, MMMM d').format(now),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(_briefing,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              // Level badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text('LVL $levelNum',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: scheme.primary)),
                    Text(levelTitle,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: scheme.primary)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── XP Progress Bar ───────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        const Text('⚡', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text('$_totalXp XP',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 8),
                        if (_todayXp > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('+$_todayXp today',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepPurple)),
                          ),
                      ]),
                      if (!LevelHelper.isMaxLevel(_totalXp))
                        Text('$xpToNext to LVL ${levelNum + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: lvlProgress,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Daily Game Plan ───────────────────────────────────────────────
          if (_intention != null)
            Card(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Text('🎯', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TODAY\'S GAME PLAN',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: scheme.onSecondaryContainer
                                      .withOpacity(0.7))),
                          const SizedBox(height: 2),
                          Text(_intention!,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSecondaryContainer)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // ── Operational Status ────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _lifeScore / 100,
                          strokeWidth: 8,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: _scoreColor(_lifeScore),
                          strokeCap: StrokeCap.round,
                        ),
                        Text(_lifeScore.toStringAsFixed(0),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: _scoreColor(_lifeScore))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('OPERATIONAL STATUS',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                                color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(_scoreSubtitle(_lifeScore),
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(children: [
                          _MiniMetric(
                              label: 'Missions',
                              value: '$completedToday/${habits.length}',
                              color: Colors.purple),
                          const SizedBox(width: 12),
                          _MiniMetric(
                              label: 'Steps',
                              value: '$_steps',
                              color: Colors.teal),
                          const SizedBox(width: 12),
                          _MiniMetric(
                              label: 'Water',
                              value: '${_waterMl ~/ 250}g',
                              color: Colors.blue),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Perfect Day Banner ────────────────────────────────────────────
          if (isPerfect)
            Card(
              color: Colors.green.shade700,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(children: [
                  Text('🎯', style: TextStyle(fontSize: 24)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PERFECT DAY',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                fontSize: 13)),
                        Text('All missions complete. Harvey would approve.',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),

          if (isPerfect) const SizedBox(height: 12),

          // ── Suits Quote ───────────────────────────────────────────────────
          Card(
            color: scheme.inverseSurface,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('⚖️', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text('DAILY INTEL',
                        style: TextStyle(
                            color: scheme.onInverseSurface.withOpacity(0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5)),
                  ]),
                  const SizedBox(height: 8),
                  Text('"${quote['quote']}"',
                      style: TextStyle(
                          color: scheme.onInverseSurface,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          height: 1.4)),
                  const SizedBox(height: 6),
                  Text('— ${quote['character']}',
                      style: TextStyle(
                          color: scheme.onInverseSurface.withOpacity(0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Finance ───────────────────────────────────────────────────────
          Row(children: [
            _SummaryCard(
              label: 'Balance',
              value: '\$${fmt.format(totalIncome - totalExpense)}',
              icon: Icons.account_balance_wallet,
              color: (totalIncome - totalExpense) >= 0 ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            _SummaryCard(
              label: 'This Month',
              value: '-\$${fmt.format(totalExpense)}',
              icon: Icons.trending_down,
              color: Colors.red,
            ),
          ]),

          const SizedBox(height: 20),

          if (pieSections.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Spending',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: PieChart(PieChartData(
                        sections: pieSections,
                        centerSpaceRadius: 35,
                        sectionsSpace: 2,
                      )),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: expenseByCategory.entries
                          .toList()
                          .asMap()
                          .entries
                          .map((e) {
                        final colors = [
                          Colors.red, Colors.orange, Colors.blue,
                          Colors.green, Colors.purple, Colors.teal, Colors.pink
                        ];
                        return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                      color: colors[e.key % colors.length],
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Text(e.value.key,
                                  style: const TextStyle(fontSize: 12)),
                            ]);
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

          if (recentTx.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recent Transactions',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    ...recentTx.map((t) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: t.isIncome
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                            child: Icon(
                                t.isIncome
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                size: 14,
                                color: t.isIncome
                                    ? Colors.green
                                    : Colors.red),
                          ),
                          title: Text(t.title,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(t.category,
                              style: const TextStyle(fontSize: 12)),
                          trailing: Text(
                              '${t.isIncome ? '+' : '-'}\$${fmt.format(t.amount)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: t.isIncome
                                      ? Colors.green
                                      : Colors.red)),
                        )),
                  ],
                ),
              ),
            ),
          ],

          // ── Top Streaks ───────────────────────────────────────────────────
          if (habits.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active Streaks',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...([...habits]
                          ..sort((a, b) => b.streak.compareTo(a.streak)))
                        .take(3)
                        .map((h) => ListTile(
                              dense: true,
                              leading: Text(h.emoji,
                                  style: const TextStyle(fontSize: 22)),
                              title: Text(h.name),
                              trailing: h.streak > 0
                                  ? Text('🔥 ${h.streak} days',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange))
                                  : Text('+${h.xp} XP',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey)),
                            )),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _scoreSubtitle(double score) {
    if (score >= 80) return 'Outstanding. Mission performance: elite.';
    if (score >= 60) return 'Solid execution. Keep the momentum.';
    if (score >= 40) return 'Room to improve. Lock in one mission.';
    return 'Start now. Every win counts.';
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniMetric(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 6),
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/habit.dart';
import '../models/transaction.dart';
import '../models/level_helper.dart';
import '../models/pattern_insight.dart';
import '../data/suits_quotes.dart';
import '../services/step_service.dart';
import '../services/pattern_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
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
  List<PatternInsight> _topInsights = [];
  bool _insightsLoading = true;
  StreamSubscription? _stepSub;

  // Staggered entrance animation controllers
  late final List<AnimationController> _entranceControllers;
  late final List<Animation<double>> _fadeAnims;
  late final List<Animation<Offset>> _slideAnims;

  // Level badge pulse controller
  late final AnimationController _badgePulseController;
  late final Animation<double> _badgePulseAnim;

  // Number of staggered card sections
  static const int _cardCount = 7;

  @override
  void initState() {
    super.initState();

    // Build staggered entrance controllers
    _entranceControllers = List.generate(
      _cardCount,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 450),
      ),
    );

    _fadeAnims = _entranceControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();

    _slideAnims = _entranceControllers.map((c) {
      return Tween<Offset>(
        begin: const Offset(0, 0.18),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeOut));
    }).toList();

    // Badge pulse — plays once on load
    _badgePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _badgePulseAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _badgePulseController, curve: Curves.easeInOut));

    _load();
    _stepSub = StepService.instance.stepsStream.listen((s) {
      if (mounted) setState(() => _steps = s);
    });
    _steps = StepService.instance.dailySteps;

    // Stagger each card entrance
    for (int i = 0; i < _cardCount; i++) {
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) _entranceControllers[i].forward();
      });
    }
    // Badge pulse after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _badgePulseController.forward();
    });
  }

  @override
  void dispose() {
    _stepSub?.cancel();
    for (final c in _entranceControllers) {
      c.dispose();
    }
    _badgePulseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final today = _todayStr();

    // Parallel load of all independent data
    final habitMapsResult = db.getHabits();
    final txMapsResult = db.getTransactions();
    final waterResult = db.getTotalWaterToday(today);
    final scoreResult = ps.computeTodayScore();
    final totalXpResult = db.getTotalXP();
    final todayXpResult = db.getTodayXP(today);
    final planResult = db.getDailyPlan(today);

    final results = await Future.wait([
      habitMapsResult,
      txMapsResult,
      waterResult,
      scoreResult,
      totalXpResult,
      todayXpResult,
      planResult,
    ]);

    final habitMaps = results[0] as List<Map<String, dynamic>>;
    final txMaps = results[1] as List<Map<String, dynamic>>;
    final waterMl = results[2] as int;
    final score = results[3] as double;
    final totalXp = results[4] as int;
    final todayXp = results[5] as int;
    final plan = results[6] as Map<String, dynamic>?;

    // Build habit objects (log queries per habit — parallelised too)
    final habitFutures = habitMaps.map((m) async {
      final logs = await db.getLogsForHabit(m['id']);
      final logDates = logs.map((l) => l['date'] as String).toList();
      final doneToday = await db.isHabitLoggedToday(m['id'], today);
      return Habit(
        id: m['id'],
        name: m['name'],
        emoji: m['emoji'],
        xp: (m['xp'] as int? ?? 10),
        createdAt: m['created_at'],
        logs: logDates,
        doneToday: doneToday,
      );
    });
    final loadedHabits = await Future.wait(habitFutures);

    if (!mounted) return;
    setState(() {
      habits = loadedHabits;
      transactions = txMaps.map(FinanceTransaction.fromMap).toList();
      _waterMl = waterMl;
      _lifeScore = score;
      _totalXp = totalXp;
      _todayXp = todayXp;
      _intention = plan?['intention'] as String?;
    });

    // Load top pattern insights in background
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    if (mounted) setState(() => _insightsLoading = true);
    final insights = await ps.generateInsights();
    if (!mounted) return;
    setState(() {
      _topInsights = insights.take(3).toList();
      _insightsLoading = false;
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

  /// Wraps [child] in a staggered FadeTransition + SlideTransition.
  Widget _staggered(int index, Widget child) {
    return FadeTransition(
      opacity: _fadeAnims[index],
      child: SlideTransition(
        position: _slideAnims[index],
        child: child,
      ),
    );
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

          // ── [0] Agent Briefing Header ──────────────────────────────────────
          _staggered(
            0,
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
                // Level badge with scale pulse
                ScaleTransition(
                  scale: _badgePulseAnim,
                  child: Container(
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
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── [1] XP Progress Bar (animated) ────────────────────────────────
          _staggered(
            1,
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
                    // Animated XP bar: 0 → lvlProgress over 800 ms
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: lvlProgress),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── [2] Daily Game Plan ────────────────────────────────────────────
          if (_intention != null)
            _staggered(
              2,
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
            ),

          if (_intention != null) const SizedBox(height: 12),

          // ── [3] Operational Status (animated life score ring) ──────────────
          _staggered(
            3,
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Animated circular life score
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _lifeScore),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOut,
                      builder: (context, animScore, _) {
                        return SizedBox(
                          width: 80,
                          height: 80,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: animScore / 100,
                                strokeWidth: 8,
                                backgroundColor:
                                    scheme.surfaceContainerHighest,
                                color: _scoreColor(animScore),
                                strokeCap: StrokeCap.round,
                              ),
                              Text(animScore.toStringAsFixed(0),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      color: _scoreColor(_lifeScore))),
                            ],
                          ),
                        );
                      },
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
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13)),
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
          ),

          const SizedBox(height: 12),

          // Perfect Day Banner
          if (isPerfect) ...[
            _staggered(
              3,
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
                              style:
                                  TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── [4] Suits Quote ────────────────────────────────────────────────
          _staggered(
            4,
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
          ),

          const SizedBox(height: 12),

          // ── [5] Finance ────────────────────────────────────────────────────
          _staggered(
            5,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _SummaryCard(
                    label: 'Balance',
                    value: '\$${fmt.format(totalIncome - totalExpense)}',
                    icon: Icons.account_balance_wallet,
                    color: (totalIncome - totalExpense) >= 0
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 12),
                  _SummaryCard(
                    label: 'This Month',
                    value: '-\$${fmt.format(totalExpense)}',
                    icon: Icons.trending_down,
                    color: Colors.red,
                  ),
                ]),
                const SizedBox(height: 16),
                // Spending chart or empty state
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
                        if (pieSections.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Column(
                                children: [
                                  Text('💳',
                                      style: TextStyle(fontSize: 32)),
                                  SizedBox(height: 8),
                                  Text('No spending data yet',
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14)),
                                ],
                              ),
                            ),
                          )
                        else ...[
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
                                Colors.green, Colors.purple, Colors.teal,
                                Colors.pink
                              ];
                              return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                            color:
                                                colors[e.key % colors.length],
                                            shape: BoxShape.circle)),
                                    const SizedBox(width: 4),
                                    Text(e.value.key,
                                        style:
                                            const TextStyle(fontSize: 12)),
                                  ]);
                            }).toList(),
                          ),
                        ],
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
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── [6] Active Streaks ─────────────────────────────────────────────
          _staggered(
            6,
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
                    if (habits.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Column(
                            children: [
                              Text('🎯', style: TextStyle(fontSize: 30)),
                              SizedBox(height: 8),
                              Text('No active missions yet',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 14)),
                            ],
                          ),
                        ),
                      )
                    else
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
                                            fontSize: 12,
                                            color: Colors.grey)),
                              )),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Intelligence Report ────────────────────────────────────────────
          _IntelligenceReport(
            loading: _insightsLoading,
            insights: _topInsights,
          ),

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

// ── Intelligence Report Section ─────────────────────────────────────────────

class _IntelligenceReport extends StatelessWidget {
  final bool loading;
  final List<PatternInsight> insights;

  const _IntelligenceReport({required this.loading, required this.insights});

  static const _insightIcons = <InsightType, IconData>{
    InsightType.wakeTime: Icons.wb_sunny_outlined,
    InsightType.sleepTime: Icons.nightlight_round,
    InsightType.habits: Icons.repeat,
    InsightType.spending: Icons.attach_money,
    InsightType.activity: Icons.directions_run,
    InsightType.water: Icons.water_drop_outlined,
    InsightType.productivity: Icons.task_alt,
    InsightType.lifestyle: Icons.trending_up,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Intelligence Report',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          const Text('🧠', style: TextStyle(fontSize: 16)),
        ]),
        const SizedBox(height: 10),
        if (loading)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Text('Analysing patterns…',
                      style:
                          TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
          )
        else if (insights.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Text('🔍', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Use the app for 7+ days to unlock intelligence insights.',
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ),
              ]),
            ),
          )
        else
          ...insights.map((insight) {
            final borderColor =
                insight.isPositive ? Colors.green : Colors.orange;
            final icon = _insightIcons[insight.type] ?? Icons.info_outline;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderColor.withOpacity(0.25), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: borderColor.withOpacity(0.12),
                      child: Text(insight.emoji,
                          style: const TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(insight.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 3),
                          Text(insight.description,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(icon, size: 18, color: borderColor.withOpacity(0.7)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

// ── Shared sub-widgets ───────────────────────────────────────────────────────

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

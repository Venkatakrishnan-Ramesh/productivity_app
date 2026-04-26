import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/workout_models.dart';

const _uuid = Uuid();

String _todayStr() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

String _weekStartStr([DateTime? from]) {
  final d = from ?? DateTime.now();
  final monday = d.subtract(Duration(days: d.weekday - 1));
  return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
}

String _weekEndStr([DateTime? from]) {
  final d = from ?? DateTime.now();
  final sunday = d.add(Duration(days: 7 - d.weekday));
  return '${sunday.year}-${sunday.month.toString().padLeft(2, '0')}-${sunday.day.toString().padLeft(2, '0')}';
}

// ── Default app-suggested plan ────────────────────────────────────────────────

List<Map<String, dynamic>> _suggestedDays(String planId) {
  final days = [
    {'dayName': 'Day 1', 'focus': 'Push', 'exercises': [
      {'name': 'Bench Press', 'sets': 4, 'reps': '8-12', 'target_muscle': 'Chest'},
      {'name': 'Incline Dumbbell Press', 'sets': 3, 'reps': '10-12', 'target_muscle': 'Chest'},
      {'name': 'Shoulder Press', 'sets': 3, 'reps': '8-12', 'target_muscle': 'Shoulders'},
      {'name': 'Lateral Raise', 'sets': 4, 'reps': '12-20', 'target_muscle': 'Shoulders'},
      {'name': 'Tricep Pushdown', 'sets': 3, 'reps': '10-15', 'target_muscle': 'Triceps'},
    ]},
    {'dayName': 'Day 2', 'focus': 'Pull', 'exercises': [
      {'name': 'Barbell Row', 'sets': 4, 'reps': '8-12', 'target_muscle': 'Back'},
      {'name': 'Pull-Ups', 'sets': 3, 'reps': '6-10', 'target_muscle': 'Back'},
      {'name': 'Cable Row', 'sets': 3, 'reps': '10-12', 'target_muscle': 'Back'},
      {'name': 'Face Pulls', 'sets': 4, 'reps': '15-20', 'target_muscle': 'Rear Delts'},
      {'name': 'Bicep Curl', 'sets': 3, 'reps': '10-15', 'target_muscle': 'Biceps'},
    ]},
    {'dayName': 'Day 3', 'focus': 'Legs', 'exercises': [
      {'name': 'Squat', 'sets': 4, 'reps': '8-12', 'target_muscle': 'Quads'},
      {'name': 'Romanian Deadlift', 'sets': 3, 'reps': '10-12', 'target_muscle': 'Hamstrings'},
      {'name': 'Leg Press', 'sets': 3, 'reps': '12-15', 'target_muscle': 'Quads'},
      {'name': 'Leg Curl', 'sets': 4, 'reps': '12-15', 'target_muscle': 'Hamstrings'},
      {'name': 'Calf Raises', 'sets': 4, 'reps': '15-20', 'target_muscle': 'Calves'},
    ]},
    {'dayName': 'Day 4', 'focus': 'Full Body', 'exercises': [
      {'name': 'Deadlift', 'sets': 3, 'reps': '6-8', 'target_muscle': 'Full Body'},
      {'name': 'Dumbbell Lunges', 'sets': 3, 'reps': '10-12', 'target_muscle': 'Legs'},
      {'name': 'Dumbbell Row', 'sets': 3, 'reps': '10-12', 'target_muscle': 'Back'},
      {'name': 'Plank', 'sets': 3, 'reps': '30-60s', 'target_muscle': 'Core'},
    ]},
  ];

  final result = <Map<String, dynamic>>[];
  for (int i = 0; i < days.length; i++) {
    final d = days[i];
    final dayId = _uuid.v4();
    result.add({
      'type': 'day',
      'id': dayId,
      'plan_id': planId,
      'day_name': d['dayName'],
      'focus': d['focus'],
      'sort_order': i,
      'exercises': (d['exercises'] as List).asMap().entries.map((e) => {
        'id': _uuid.v4(),
        'day_id': dayId,
        'name': e.value['name'],
        'sets': e.value['sets'],
        'reps': e.value['reps'],
        'target_muscle': e.value['target_muscle'],
        'sort_order': e.key,
        'rest_seconds': 90,
        'notes': '',
        'weight_kg': null,
      }).toList(),
    });
  }
  return result;
}

// =============================================================================
// WorkoutScreen
// =============================================================================

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen>
    with SingleTickerProviderStateMixin {
  final db = DatabaseHelper.instance;
  late final TabController _tab;

  WorkoutPlan? _plan;
  bool _loading = true;
  int _workoutsThisWeek = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final planMap = await db.getActiveWorkoutPlan();
    WorkoutPlan? plan;
    if (planMap != null) {
      plan = WorkoutPlan.fromMap(planMap);
      final dayMaps = await db.getWorkoutDays(plan.id);
      plan.days = await Future.wait(dayMaps.map((dm) async {
        final day = WorkoutDay.fromMap(dm);
        final exMaps = await db.getExercises(day.id);
        day.exercises = exMaps.map(Exercise.fromMap).toList();
        return day;
      }));
    }
    final count = await db.countWorkoutsForRange(_weekStartStr(), _weekEndStr());
    if (mounted) {
      setState(() {
        _plan = plan;
        _workoutsThisWeek = count;
        _loading = false;
      });
    }
  }

  Future<void> _createSuggestedPlan() async {
    final planId = _uuid.v4();
    final plan = WorkoutPlan(
      id: planId,
      name: 'App Suggested Plan',
      mode: WorkoutMode.appSuggested,
      workoutsPerWeek: 4,
      cardioPerWeek: 3,
      stepTarget: 10000,
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insertWorkoutPlan(plan.toMap());
    await db.setActivePlan(planId);
    for (final d in _suggestedDays(planId)) {
      await db.insertWorkoutDay({
        'id': d['id'],
        'plan_id': d['plan_id'],
        'day_name': d['day_name'],
        'focus': d['focus'],
        'sort_order': d['sort_order'],
      });
      for (final ex in d['exercises'] as List) {
        await db.insertExercise(Map<String, dynamic>.from(ex));
      }
    }
    await _load();
  }

  Future<void> _createBlankPlan(WorkoutMode mode, String name) async {
    final planId = _uuid.v4();
    final plan = WorkoutPlan(
      id: planId,
      name: name,
      mode: mode,
      createdAt: DateTime.now().toIso8601String(),
    );
    await db.insertWorkoutPlan(plan.toMap());
    await db.setActivePlan(planId);
    await _load();
  }

  void _showModeSetup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ModeSetupSheet(
        onAppSuggested: () {
          Navigator.pop(ctx);
          _createSuggestedPlan();
        },
        onTrainer: () {
          Navigator.pop(ctx);
          _createBlankPlan(WorkoutMode.trainerAssigned, 'Trainer Plan');
        },
        onCustom: () {
          Navigator.pop(ctx);
          _createBlankPlan(WorkoutMode.custom, 'My Custom Plan');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _WeeklyProgressBar(
                  plan: _plan,
                  workoutsThisWeek: _workoutsThisWeek,
                ),
                TabBar(
                  controller: _tab,
                  tabs: const [
                    Tab(icon: Icon(Icons.fitness_center, size: 18), text: 'Plan'),
                    Tab(icon: Icon(Icons.note_outlined, size: 18), text: 'Trainer Notes'),
                    Tab(icon: Icon(Icons.check_circle_outline, size: 18), text: 'Check-In'),
                  ],
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _PlanTab(
                        plan: _plan,
                        onSetup: _showModeSetup,
                        onRefresh: _load,
                        workoutsThisWeek: _workoutsThisWeek,
                      ),
                      _TrainerNotesTab(onRefresh: _load),
                      _CheckInTab(
                        plan: _plan,
                        workoutsThisWeek: _workoutsThisWeek,
                        onRefresh: _load,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// =============================================================================
// Weekly Progress Bar
// =============================================================================

class _WeeklyProgressBar extends StatelessWidget {
  final WorkoutPlan? plan;
  final int workoutsThisWeek;

  const _WeeklyProgressBar({required this.plan, required this.workoutsThisWeek});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = plan?.workoutsPerWeek ?? 4;
    final progress = (workoutsThisWeek / target).clamp(0.0, 1.0);
    final pct = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                plan == null ? 'TRAINING' : plan!.name.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: scheme.primary),
              ),
              if (plan != null)
                _ModeBadge(mode: plan!.mode),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$workoutsThisWeek / $target workouts this week',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: scheme.onPrimaryContainer.withOpacity(0.15),
                        color: pct >= 100 ? Colors.green : scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: pct >= 100 ? Colors.green : scheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$pct%',
                  style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final WorkoutMode mode;
  const _ModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (mode) {
      WorkoutMode.appSuggested => ('App Plan', Colors.blue),
      WorkoutMode.trainerAssigned => ('Trainer Plan', Colors.purple),
      WorkoutMode.custom => ('Custom', Colors.teal),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

// =============================================================================
// Plan Tab
// =============================================================================

class _PlanTab extends StatefulWidget {
  final WorkoutPlan? plan;
  final VoidCallback onSetup;
  final VoidCallback onRefresh;
  final int workoutsThisWeek;

  const _PlanTab({
    required this.plan,
    required this.onSetup,
    required this.onRefresh,
    required this.workoutsThisWeek,
  });

  @override
  State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  final db = DatabaseHelper.instance;
  final Set<String> _loggedToday = {};

  @override
  void initState() {
    super.initState();
    _loadTodayLogs();
  }

  @override
  void didUpdateWidget(_PlanTab old) {
    super.didUpdateWidget(old);
    _loadTodayLogs();
  }

  Future<void> _loadTodayLogs() async {
    if (widget.plan == null) return;
    final today = _todayStr();
    final logged = <String>{};
    for (final day in widget.plan!.days) {
      if (await db.isWorkoutLoggedToday(day.id, today)) {
        logged.add(day.id);
      }
    }
    if (mounted) setState(() => _loggedToday
      ..clear()
      ..addAll(logged));
  }

  Future<void> _toggleLog(WorkoutDay day) async {
    final today = _todayStr();
    if (_loggedToday.contains(day.id)) {
      await db.deleteWorkoutLog(day.id, today);
      setState(() => _loggedToday.remove(day.id));
    } else {
      await db.insertWorkoutLog({
        'id': _uuid.v4(),
        'plan_id': widget.plan!.id,
        'day_id': day.id,
        'date': today,
        'completed_at': DateTime.now().toIso8601String(),
        'notes': '',
        'is_completed': 1,
      });
      setState(() => _loggedToday.add(day.id));
      widget.onRefresh();
    }
  }

  void _showAddDayDialog() {
    final nameCtrl = TextEditingController();
    final focusCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Workout Day'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Day name (e.g. Monday, Push Day)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: focusCtrl,
              decoration: const InputDecoration(
                  labelText: 'Focus (e.g. Push, Pull, Legs)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await db.insertWorkoutDay({
                'id': _uuid.v4(),
                'plan_id': widget.plan!.id,
                'day_name': nameCtrl.text.trim(),
                'focus': focusCtrl.text.trim(),
                'sort_order': widget.plan!.days.length,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              widget.onRefresh();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.plan == null) {
      return _NoPlannSetup(onSetup: widget.onSetup);
    }

    final plan = widget.plan!;
    final isAppSuggested = plan.mode == WorkoutMode.appSuggested;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          if (isAppSuggested)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Suggested plan — can be edited or replaced.',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ...plan.days.map((day) => _WorkoutDayCard(
                day: day,
                isDoneToday: _loggedToday.contains(day.id),
                onToggleLog: () => _toggleLog(day),
                onRefresh: widget.onRefresh,
              )),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDayDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Day'),
      ),
    );
  }
}

// =============================================================================
// No Plan Setup
// =============================================================================

class _NoPlannSetup extends StatelessWidget {
  final VoidCallback onSetup;
  const _NoPlannSetup({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center,
                size: 64, color: scheme.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text('No workout plan yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Choose a plan type to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onSetup,
              icon: const Icon(Icons.add),
              label: const Text('Set Up Workout Plan'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Mode Setup Sheet
// =============================================================================

class _ModeSetupSheet extends StatelessWidget {
  final VoidCallback onAppSuggested;
  final VoidCallback onTrainer;
  final VoidCallback onCustom;

  const _ModeSetupSheet({
    required this.onAppSuggested,
    required this.onTrainer,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose Workout Mode',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('You can change this anytime.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13)),
          const SizedBox(height: 20),
          _ModeOption(
            icon: Icons.auto_awesome,
            color: Colors.blue,
            title: 'App Suggested Plan',
            subtitle: '4-day push/pull/legs/full split — edit freely',
            onTap: onAppSuggested,
          ),
          const SizedBox(height: 10),
          _ModeOption(
            icon: Icons.person_outline,
            color: Colors.purple,
            title: 'Trainer Assigned Plan',
            subtitle: 'Enter the plan your trainer gave you',
            onTap: onTrainer,
          ),
          const SizedBox(height: 10),
          _ModeOption(
            icon: Icons.build_outlined,
            color: Colors.teal,
            title: 'Custom Plan',
            subtitle: 'Build your own workout from scratch',
            onTap: onCustom,
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

// =============================================================================
// Workout Day Card
// =============================================================================

class _WorkoutDayCard extends StatefulWidget {
  final WorkoutDay day;
  final bool isDoneToday;
  final VoidCallback onToggleLog;
  final VoidCallback onRefresh;

  const _WorkoutDayCard({
    required this.day,
    required this.isDoneToday,
    required this.onToggleLog,
    required this.onRefresh,
  });

  @override
  State<_WorkoutDayCard> createState() => _WorkoutDayCardState();
}

class _WorkoutDayCardState extends State<_WorkoutDayCard> {
  final db = DatabaseHelper.instance;
  bool _expanded = false;

  void _showAddExerciseDialog() {
    final nameCtrl = TextEditingController();
    final setsCtrl = TextEditingController(text: '3');
    final repsCtrl = TextEditingController(text: '8-12');
    final weightCtrl = TextEditingController();
    final muscleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Exercise to ${widget.day.dayName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Field(controller: nameCtrl, label: 'Exercise name', autofocus: true),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Field(controller: setsCtrl, label: 'Sets', keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _Field(controller: repsCtrl, label: 'Reps (e.g. 8-12)')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Field(controller: weightCtrl, label: 'Weight (kg)', keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _Field(controller: muscleCtrl, label: 'Muscle group')),
              ]),
              const SizedBox(height: 10),
              _Field(controller: notesCtrl, label: 'Notes (optional)'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await db.insertExercise({
                'id': _uuid.v4(),
                'day_id': widget.day.id,
                'name': nameCtrl.text.trim(),
                'sets': int.tryParse(setsCtrl.text) ?? 3,
                'reps': repsCtrl.text.trim().isEmpty ? '8-12' : repsCtrl.text.trim(),
                'weight_kg': double.tryParse(weightCtrl.text),
                'rest_seconds': 90,
                'target_muscle': muscleCtrl.text.trim(),
                'notes': notesCtrl.text.trim(),
                'sort_order': widget.day.exercises.length,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              widget.onRefresh();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditExerciseDialog(Exercise ex) {
    final nameCtrl = TextEditingController(text: ex.name);
    final setsCtrl = TextEditingController(text: ex.sets.toString());
    final repsCtrl = TextEditingController(text: ex.reps);
    final weightCtrl = TextEditingController(
        text: ex.weightKg != null ? ex.weightKg.toString() : '');
    final muscleCtrl = TextEditingController(text: ex.targetMuscle);
    final notesCtrl = TextEditingController(text: ex.notes);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Exercise'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Field(controller: nameCtrl, label: 'Exercise name', autofocus: true),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Field(controller: setsCtrl, label: 'Sets', keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _Field(controller: repsCtrl, label: 'Reps')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Field(controller: weightCtrl, label: 'Weight (kg)', keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _Field(controller: muscleCtrl, label: 'Muscle group')),
              ]),
              const SizedBox(height: 10),
              _Field(controller: notesCtrl, label: 'Notes'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await db.updateExercise({
                'id': ex.id,
                'day_id': ex.dayId,
                'name': nameCtrl.text.trim(),
                'sets': int.tryParse(setsCtrl.text) ?? ex.sets,
                'reps': repsCtrl.text.trim().isEmpty ? ex.reps : repsCtrl.text.trim(),
                'weight_kg': double.tryParse(weightCtrl.text),
                'rest_seconds': ex.restSeconds,
                'target_muscle': muscleCtrl.text.trim(),
                'notes': notesCtrl.text.trim(),
                'sort_order': ex.sortOrder,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              widget.onRefresh();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final day = widget.day;
    final done = widget.isDoneToday;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: done
            ? BorderSide(color: Colors.green.withOpacity(0.5), width: 1.5)
            : BorderSide.none,
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: done
                          ? Colors.green.withOpacity(0.15)
                          : scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      done ? Icons.check : Icons.fitness_center,
                      size: 20,
                      color: done ? Colors.green : scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          day.dayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (day.focus.isNotEmpty)
                          Text(day.focus,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text('${day.exercises.length} exercises',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ...day.exercises.map((ex) => _ExerciseTile(
                  exercise: ex,
                  onEdit: () => _showEditExerciseDialog(ex),
                  onDelete: () async {
                    await db.deleteExercise(ex.id);
                    widget.onRefresh();
                  },
                )),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showAddExerciseDialog,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Exercise'),
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onToggleLog,
                      icon: Icon(
                          done ? Icons.undo : Icons.check,
                          size: 16),
                      label: Text(done ? 'Undo' : 'Log Done'),
                      style: FilledButton.styleFrom(
                        backgroundColor: done ? Colors.grey : Colors.green,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Exercise Tile
// =============================================================================

class _ExerciseTile extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExerciseTile({
    required this.exercise,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ex = exercise;
    final weightStr = ex.weightKg != null ? ' · ${ex.weightKg}kg' : '';
    final restStr = ex.restSeconds > 0 ? ' · ${ex.restSeconds}s rest' : '';

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      title: Text(ex.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        '${ex.sets} × ${ex.reps}$weightStr$restStr'
        '${ex.targetMuscle.isNotEmpty ? ' · ${ex.targetMuscle}' : ''}',
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: onEdit,
            color: scheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            onPressed: onDelete,
            color: Colors.red.withOpacity(0.7),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Trainer Notes Tab
// =============================================================================

const _noteCategories = [
  'instructions',
  'form_cues',
  'injuries',
  'avoid',
  'prioritize',
  'general',
];

const _noteCategoryLabels = {
  'instructions': '📋 Instructions',
  'form_cues': '🎯 Form Cues',
  'injuries': '🩹 Injuries/Limitations',
  'avoid': '🚫 Avoid',
  'prioritize': '⭐ Prioritize',
  'general': '📝 General',
};

const _noteCategoryColors = {
  'instructions': Colors.blue,
  'form_cues': Colors.purple,
  'injuries': Colors.orange,
  'avoid': Colors.red,
  'prioritize': Colors.green,
  'general': Colors.grey,
};

class _TrainerNotesTab extends StatefulWidget {
  final VoidCallback onRefresh;
  const _TrainerNotesTab({required this.onRefresh});

  @override
  State<_TrainerNotesTab> createState() => _TrainerNotesTabState();
}

class _TrainerNotesTabState extends State<_TrainerNotesTab> {
  final db = DatabaseHelper.instance;
  List<TrainerNote> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final maps = await db.getTrainerNotes();
    if (mounted) {
      setState(() {
        _notes = maps.map(TrainerNote.fromMap).toList();
        _loading = false;
      });
    }
  }

  void _showNoteDialog({TrainerNote? editing}) {
    final contentCtrl = TextEditingController(text: editing?.content ?? '');
    String selectedCat = editing?.category ?? 'general';
    final reviewCtrl =
        TextEditingController(text: editing?.nextReviewDate ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(editing == null ? 'Add Trainer Note' : 'Edit Note'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Category',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedCat,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: _noteCategories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(_noteCategoryLabels[c]!,
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setS(() => selectedCat = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  autofocus: true,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Note content',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reviewCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Next review date (optional, YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (contentCtrl.text.trim().isEmpty) return;
                final map = {
                  'id': editing?.id ?? _uuid.v4(),
                  'category': selectedCat,
                  'content': contentCtrl.text.trim(),
                  'created_at': editing?.createdAt ??
                      DateTime.now().toIso8601String(),
                  'next_review_date': reviewCtrl.text.trim().isEmpty
                      ? null
                      : reviewCtrl.text.trim(),
                };
                if (editing == null) {
                  await db.insertTrainerNote(map);
                } else {
                  await db.updateTrainerNote(map);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              },
              child: Text(editing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: _notes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.note_outlined,
                      size: 48,
                      color: scheme.onSurfaceVariant.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  Text('No trainer notes yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              itemCount: _notes.length,
              itemBuilder: (ctx, i) {
                final note = _notes[i];
                final color = _noteCategoryColors[note.category] ?? Colors.grey;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: color.withOpacity(0.3)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(0.12),
                      child: Text(
                        (_noteCategoryLabels[note.category] ?? '📝')
                            .split(' ')
                            .first,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    title: Text(
                      _noteCategoryLabels[note.category] ?? note.category,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(note.content, style: const TextStyle(fontSize: 13)),
                          if (note.nextReviewDate != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('Review: ${note.nextReviewDate}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant)),
                            ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          onPressed: () => _showNoteDialog(editing: note),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          color: Colors.red.withOpacity(0.7),
                          onPressed: () async {
                            await db.deleteTrainerNote(note.id);
                            await _load();
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNoteDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Note'),
      ),
    );
  }
}

// =============================================================================
// Check-In Tab
// =============================================================================

class _CheckInTab extends StatefulWidget {
  final WorkoutPlan? plan;
  final int workoutsThisWeek;
  final VoidCallback onRefresh;

  const _CheckInTab({
    required this.plan,
    required this.workoutsThisWeek,
    required this.onRefresh,
  });

  @override
  State<_CheckInTab> createState() => _CheckInTabState();
}

class _CheckInTabState extends State<_CheckInTab> {
  final db = DatabaseHelper.instance;
  List<WeeklyCheckIn> _history = [];
  WeeklyCheckIn? _thisWeek;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final weekStart = _weekStartStr();
    final maps = await db.getWeeklyCheckIns();
    final thisWeekMap = await db.getCheckInForWeek(weekStart);
    if (mounted) {
      setState(() {
        _history = maps.map(WeeklyCheckIn.fromMap).toList();
        _thisWeek =
            thisWeekMap != null ? WeeklyCheckIn.fromMap(thisWeekMap) : null;
        _loading = false;
      });
    }
  }

  void _showCheckInDialog() {
    final existing = _thisWeek;
    final weightCtrl = TextEditingController(
        text: existing?.weightKg?.toString() ?? '');
    final waistCtrl = TextEditingController(
        text: existing?.waistCm?.toString() ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    int energyLevel = existing?.energyLevel ?? 3;
    int workouts = existing?.workoutsCompleted ?? widget.workoutsThisWeek;
    int cardio = existing?.cardioCompleted ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Weekly Check-In'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: _Field(
                      controller: weightCtrl,
                      label: 'Weight (kg)',
                      keyboardType: TextInputType.number)),
                  const SizedBox(width: 10),
                  Expanded(child: _Field(
                      controller: waistCtrl,
                      label: 'Waist (cm)',
                      keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                const Text('Energy Level',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(5, (i) {
                    final level = i + 1;
                    final labels = ['😴', '😞', '😐', '😊', '🔥'];
                    final selected = energyLevel == level;
                    return GestureDetector(
                      onTap: () => setS(() => energyLevel = level),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selected
                              ? Theme.of(ctx)
                                  .colorScheme
                                  .primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: selected
                              ? Border.all(
                                  color: Theme.of(ctx).colorScheme.primary)
                              : null,
                        ),
                        child: Text(labels[i],
                            style: const TextStyle(fontSize: 24)),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Workouts done',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Row(children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: () => setS(() => workouts = (workouts - 1).clamp(0, 7)),
                          visualDensity: VisualDensity.compact,
                        ),
                        Text('$workouts', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => setS(() => workouts = (workouts + 1).clamp(0, 7)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ]),
                    ],
                  )),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cardio done',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Row(children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: () => setS(() => cardio = (cardio - 1).clamp(0, 7)),
                          visualDensity: VisualDensity.compact,
                        ),
                        Text('$cardio', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => setS(() => cardio = (cardio + 1).clamp(0, 7)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ]),
                    ],
                  )),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await db.upsertWeeklyCheckIn({
                  'id': existing?.id ?? _uuid.v4(),
                  'week_start': _weekStartStr(),
                  'weight_kg': double.tryParse(weightCtrl.text),
                  'waist_cm': double.tryParse(waistCtrl.text),
                  'energy_level': energyLevel,
                  'workouts_completed': workouts,
                  'cardio_completed': cardio,
                  'notes': notesCtrl.text.trim(),
                  'created_at': DateTime.now().toIso8601String(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          // This week card
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('This Week',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: _showCheckInDialog,
                        child: Text(
                            _thisWeek == null ? 'Log Check-In' : 'Update'),
                      ),
                    ],
                  ),
                  if (_thisWeek != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (_thisWeek!.weightKg != null)
                          _CheckInChip(
                              label: '⚖️ ${_thisWeek!.weightKg} kg',
                              color: Colors.blue),
                        if (_thisWeek!.waistCm != null)
                          _CheckInChip(
                              label: '📏 ${_thisWeek!.waistCm} cm',
                              color: Colors.teal),
                        if (_thisWeek!.energyLevel != null)
                          _CheckInChip(
                              label: ['', '😴', '😞', '😐', '😊', '🔥'][
                                      _thisWeek!.energyLevel!] +
                                  ' Energy ${_thisWeek!.energyLevel}/5',
                              color: Colors.orange),
                        _CheckInChip(
                            label:
                                '💪 ${_thisWeek!.workoutsCompleted} workouts',
                            color: Colors.purple),
                        _CheckInChip(
                            label:
                                '🏃 ${_thisWeek!.cardioCompleted} cardio',
                            color: Colors.green),
                      ],
                    ),
                    if (_thisWeek!.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_thisWeek!.notes,
                          style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      'No check-in logged yet this week.',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_history.length > 1) ...[
            const SizedBox(height: 12),
            Text('History',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._history.skip(1).map((c) => _CheckInHistoryTile(checkin: c)),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCheckInDialog,
        icon: const Icon(Icons.add),
        label: const Text('Check-In'),
      ),
    );
  }
}

class _CheckInChip extends StatelessWidget {
  final String label;
  final Color color;
  const _CheckInChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}

class _CheckInHistoryTile extends StatelessWidget {
  final WeeklyCheckIn checkin;
  const _CheckInHistoryTile({required this.checkin});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('Week of ${checkin.weekStart}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
          [
            if (checkin.weightKg != null) '${checkin.weightKg} kg',
            '${checkin.workoutsCompleted} workouts',
            if (checkin.energyLevel != null)
              'Energy ${checkin.energyLevel}/5',
          ].join(' · '),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// =============================================================================
// Shared helper widget
// =============================================================================

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool autofocus;

  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      );
}

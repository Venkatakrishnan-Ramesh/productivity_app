import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/habit.dart';
import '../models/level_helper.dart';
import '../services/notification_service.dart';

// ---------------------------------------------------------------------------
// Category helpers
// ---------------------------------------------------------------------------
const _kCategories = [
  'fitness',
  'health',
  'learning',
  'productivity',
  'personal',
  'general',
];

const _kCategoryLabels = {
  'fitness': '💪 Fitness',
  'health': '❤️ Health',
  'learning': '📚 Learning',
  'productivity': '⚡ Productivity',
  'personal': '🌱 Personal',
  'general': '⭐ General',
};

const _kCategoryColors = {
  'fitness': Color(0xFFEF5350),
  'health': Color(0xFFEC407A),
  'learning': Color(0xFF42A5F5),
  'productivity': Color(0xFFAB47BC),
  'personal': Color(0xFF66BB6A),
  'general': Color(0xFFFFCA28),
};

// ---------------------------------------------------------------------------
// Sort mode
// ---------------------------------------------------------------------------
enum _SortMode { defaultOrder, byStreak, byDifficulty }

// ---------------------------------------------------------------------------
// Template data for empty state
// ---------------------------------------------------------------------------
const _kTemplates = [
  {'emoji': '🏃', 'name': 'Morning Run', 'category': 'fitness', 'difficulty': 2},
  {'emoji': '📖', 'name': 'Read 20 mins', 'category': 'learning', 'difficulty': 1},
  {'emoji': '💧', 'name': 'Drink Water', 'category': 'health', 'difficulty': 1},
];

// ---------------------------------------------------------------------------
// Main screen widget
// ---------------------------------------------------------------------------
class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> with TickerProviderStateMixin {
  final db = DatabaseHelper.instance;
  List<Habit> habits = [];
  int totalXp = 0;
  int todayXp = 0;

  // Filter & sort state
  String _filterCategory = 'all';
  _SortMode _sortMode = _SortMode.defaultOrder;

  // Bouncing animation for empty state
  late final AnimationController _bounceCtrl;
  late final Animation<double> _bounceAnim;

  // Per-habit checkbox animations keyed by habit id
  final Map<String, AnimationController> _checkCtrl = {};
  final Map<String, Animation<double>> _checkAnim = {};

  // Floating XP overlay key
  final GlobalKey _listKey = GlobalKey();

  // Active floating XP widgets
  final List<_FloatingXpEntry> _floatingXps = [];

  String get todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    // Bouncing empty-state animation
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _bounceAnim = Tween<double>(begin: 0, end: -18).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut),
    );
    _load();
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    for (final c in _checkCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Ensure an AnimationController exists for the given habit id
  void _ensureCheckAnim(String id) {
    if (_checkCtrl.containsKey(id)) return;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // scale: 1.0 → 1.3 → 1.0
    final anim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    _checkCtrl[id] = ctrl;
    _checkAnim[id] = anim;
  }

  Future<void> _load() async {
    final maps = await db.getHabits();
    final List<Habit> loaded = [];
    for (final m in maps) {
      final logs = await db.getLogsForHabit(m['id']);
      final logDates = logs.map((l) => l['date'] as String).toList();
      final doneToday = await db.isHabitLoggedToday(m['id'], todayStr);
      loaded.add(Habit(
        id: m['id'],
        name: m['name'],
        emoji: m['emoji'],
        xp: (m['xp'] as int? ?? 10),
        createdAt: m['created_at'],
        logs: logDates,
        doneToday: doneToday,
        category: (m['category'] as String?) ?? 'general',
        difficulty: (m['difficulty'] as int?) ?? 1,
        isActive: ((m['is_active'] as int?) ?? 1) == 1,
        description: (m['description'] as String?) ?? '',
      ));
      _ensureCheckAnim(m['id'] as String);
    }
    final xp = await db.getTotalXP();
    final todXp = await db.getTodayXP(todayStr);
    setState(() {
      habits = loaded;
      totalXp = xp;
      todayXp = todXp;
    });
  }

  // Returns the filtered + sorted view of habits
  List<Habit> get _displayedHabits {
    List<Habit> list = _filterCategory == 'all'
        ? List.of(habits)
        : habits.where((h) => h.category == _filterCategory).toList();

    switch (_sortMode) {
      case _SortMode.byStreak:
        list.sort((a, b) => b.streak.compareTo(a.streak));
        break;
      case _SortMode.byDifficulty:
        list.sort((a, b) => b.difficulty.compareTo(a.difficulty));
        break;
      case _SortMode.defaultOrder:
        break;
    }
    return list;
  }

  Future<void> _toggleHabit(Habit habit, {Offset? tapOffset}) async {
    if (habit.doneToday) {
      await db.unlogHabit(habit.id, todayStr);
      await db.subtractXP(habit.xp);
    } else {
      // Completion path: haptic + animation + floating XP
      HapticFeedback.mediumImpact();
      _checkCtrl[habit.id]?.forward(from: 0);
      if (tapOffset != null) {
        _spawnFloatingXp(habit.xp, tapOffset);
      }
      await db.logHabit({
        'id': const Uuid().v4(),
        'habit_id': habit.id,
        'date': todayStr,
        'logged_at': DateTime.now().toIso8601String(),
      });
      await db.addXP(habit.xp);
    }
    await _load();
    // Perfect day check
    if (mounted) {
      final allDone = habits.isNotEmpty &&
          (await Future.wait(habits.map((h) => db.isHabitLoggedToday(h.id, todayStr))))
              .every((v) => v);
      if (allDone && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Text('🎯 ', style: TextStyle(fontSize: 18)),
            Text('Perfect Day! All missions complete.',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ));
      }
    }
  }

  void _spawnFloatingXp(int xp, Offset position) {
    final entry = _FloatingXpEntry(
      xp: xp,
      position: position,
      onDone: () => setState(() {
        _floatingXps.removeWhere((e) => e.position == position && e.xp == xp);
      }),
    );
    setState(() => _floatingXps.add(entry));
  }

  Future<void> _deleteHabit(Habit h) async {
    if (h.doneToday) await db.subtractXP(h.xp);
    await NotificationService.instance.cancelReminder(h.id.hashCode);
    await db.deleteHabit(h.id);
    await _load();
  }

  // Cycle sort mode
  void _cycleSortMode() {
    setState(() {
      _sortMode = _SortMode.values[(_sortMode.index + 1) % _SortMode.values.length];
    });
  }

  String get _sortTooltip {
    switch (_sortMode) {
      case _SortMode.defaultOrder:
        return 'Default order';
      case _SortMode.byStreak:
        return 'Sorted by streak';
      case _SortMode.byDifficulty:
        return 'Sorted by difficulty';
    }
  }

  IconData get _sortIcon {
    switch (_sortMode) {
      case _SortMode.defaultOrder:
        return Icons.sort;
      case _SortMode.byStreak:
        return Icons.local_fire_department;
      case _SortMode.byDifficulty:
        return Icons.star;
    }
  }

  // -------------------------------------------------------------------------
  // Add / edit dialog
  // -------------------------------------------------------------------------
  void _showHabitDialog({
    Habit? editing,
    String? prefillName,
    String? prefillEmoji,
    String? prefillCategory,
    int? prefillDifficulty,
  }) {
    final nameCtrl =
        TextEditingController(text: editing?.name ?? prefillName ?? '');
    String selectedEmoji = editing?.emoji ?? prefillEmoji ?? '🎯';
    int selectedXp = editing?.xp ?? 10;
    String selectedCategory =
        editing?.category ?? prefillCategory ?? 'general';
    int selectedDifficulty = editing?.difficulty ?? prefillDifficulty ?? 1;
    TimeOfDay? reminderTime;

    const emojis = [
      '🎯', '💪', '📚', '🏃', '💧', '🧘', '🍎', '😴', '🔥', '🎸',
      '✍️', '🧹', '🐕', '🌿', '🏋️', '🚴', '🧃', '💊', '🌅', '⚡',
    ];
    const xpOptions = [
      {'label': 'Easy', 'xp': 10, 'color': Colors.green},
      {'label': 'Medium', 'xp': 20, 'color': Colors.orange},
      {'label': 'Hard', 'xp': 30, 'color': Colors.red},
      {'label': 'Epic', 'xp': 50, 'color': Colors.purple},
    ];

    // Difficulty display helpers
    String _diffLabel(int d) => d == 1 ? 'Easy' : d == 2 ? 'Medium' : 'Hard';
    Color _diffColor(int d) =>
        d == 1 ? Colors.green : d == 2 ? Colors.orange : Colors.red;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            editing == null ? 'New Mission' : 'Edit Mission',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name field
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Mission name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // Emoji picker
                const Text('Icon',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: emojis
                      .map((e) => GestureDetector(
                            onTap: () => setS(() => selectedEmoji = e),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: selectedEmoji == e
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(e,
                                  style: const TextStyle(fontSize: 22)),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 14),

                // Category dropdown
                const Text('Category',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _kCategories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(_kCategoryLabels[c]!),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setS(() => selectedCategory = v);
                  },
                ),
                const SizedBox(height: 14),

                // Difficulty selector
                const Text('Difficulty',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  children: [1, 2, 3].map((d) {
                    final selected = selectedDifficulty == d;
                    final color = _diffColor(d);
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setS(() => selectedDifficulty = d),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withOpacity(0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? color
                                  : Colors.grey.withOpacity(0.3),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  d,
                                  (_) => Icon(Icons.star,
                                      size: 14,
                                      color: selected
                                          ? color
                                          : Colors.grey.withOpacity(0.4)),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _diffLabel(d),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selected ? color : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // XP reward selector
                const Text('Difficulty & XP reward',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: xpOptions.map((opt) {
                    final xp = opt['xp'] as int;
                    final color = opt['color'] as Color;
                    final selected = selectedXp == xp;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setS(() => selectedXp = xp),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withOpacity(0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? color
                                  : Colors.grey.withOpacity(0.3),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(opt['label'] as String,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: selected ? color : Colors.grey)),
                              Text('+$xp XP',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: selected ? color : Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // Reminder (new habit only)
                if (editing == null) ...[
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alarm),
                    title: Text(
                      reminderTime == null
                          ? 'Set daily reminder (optional)'
                          : 'Reminder: ${reminderTime!.format(ctx)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: const TimeOfDay(hour: 8, minute: 0),
                      );
                      if (picked != null) setS(() => reminderTime = picked);
                    },
                    trailing: reminderTime != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setS(() => reminderTime = null))
                        : null,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                if (editing != null) {
                  // Use insertHabit with ConflictAlgorithm.replace (upsert) so
                  // that the new category/difficulty fields are persisted without
                  // requiring a schema change to updateHabit.
                  await db.insertHabit({
                    'id': editing.id,
                    'name': nameCtrl.text.trim(),
                    'emoji': selectedEmoji,
                    'xp': selectedXp,
                    'created_at': editing.createdAt,
                    'category': selectedCategory,
                    'difficulty': selectedDifficulty,
                    'is_active': editing.isActive ? 1 : 0,
                    'description': editing.description,
                  });
                } else {
                  final id = const Uuid().v4();
                  await db.insertHabit({
                    'id': id,
                    'name': nameCtrl.text.trim(),
                    'emoji': selectedEmoji,
                    'xp': selectedXp,
                    'created_at': DateTime.now().toIso8601String(),
                    'category': selectedCategory,
                    'difficulty': selectedDifficulty,
                    'is_active': 1,
                    'description': '',
                  });
                  if (reminderTime != null) {
                    await NotificationService.instance
                        .scheduleDailyHabitReminder(
                      id: id.hashCode,
                      habitName: nameCtrl.text.trim(),
                      hour: reminderTime!.hour,
                      minute: reminderTime!.minute,
                    );
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              },
              child: Text(editing == null ? 'Create Mission' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final displayed = _displayedHabits;
    final completed = habits.where((h) => h.doneToday).length;
    final scheme = Theme.of(context).colorScheme;
    final levelTitle = LevelHelper.title(totalXp);
    final levelNum = LevelHelper.number(totalXp);
    final lvlProgress = LevelHelper.progress(totalXp);
    final xpToNext = LevelHelper.xpToNext(totalXp);
    final isPerfect = habits.isNotEmpty && completed == habits.length;

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // ── Agent status panel ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primaryContainer,
                      scheme.secondaryContainer,
                    ],
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MISSION BOARD',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                    color: scheme.primary)),
                            const SizedBox(height: 2),
                            Text(levelTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('⚡',
                                  style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              Text('LVL $levelNum',
                                  style: TextStyle(
                                      color: scheme.onPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$totalXp XP total',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer)),
                        if (!LevelHelper.isMaxLevel(totalXp))
                          Text('$xpToNext XP to next level',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onPrimaryContainer
                                      .withOpacity(0.7))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: lvlProgress,
                        minHeight: 6,
                        backgroundColor:
                            scheme.onPrimaryContainer.withOpacity(0.2),
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _StatChip(
                            label: 'Today',
                            value: '$completed/${habits.length}',
                            icon: Icons.check_circle_outline),
                        const SizedBox(width: 8),
                        _StatChip(
                            label: 'XP Today',
                            value: '+$todayXp',
                            icon: Icons.bolt),
                        if (isPerfect) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🎯',
                                    style: TextStyle(fontSize: 12)),
                                SizedBox(width: 4),
                                Text('Perfect Day',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Sort & Filter bar ─────────────────────────────────────
              _SortFilterBar(
                filterCategory: _filterCategory,
                sortMode: _sortMode,
                sortIcon: _sortIcon,
                sortTooltip: _sortTooltip,
                onFilterChanged: (cat) =>
                    setState(() => _filterCategory = cat),
                onSortTap: _cycleSortMode,
              ),

              // ── Habit list / empty state ──────────────────────────────
              Expanded(
                child: habits.isEmpty
                    ? _AnimatedEmptyState(
                        bounceAnim: _bounceAnim,
                        onTemplateTap: (t) => _showHabitDialog(
                          prefillName: t['name'] as String,
                          prefillEmoji: t['emoji'] as String,
                          prefillCategory: t['category'] as String,
                          prefillDifficulty: t['difficulty'] as int,
                        ),
                      )
                    : displayed.isEmpty
                        ? Center(
                            child: Text(
                              'No habits in this category.',
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 14),
                            ),
                          )
                        : ListView.builder(
                            key: _listKey,
                            padding:
                                const EdgeInsets.fromLTRB(12, 12, 12, 100),
                            itemCount: displayed.length,
                            itemBuilder: (ctx, i) {
                              final h = displayed[i];
                              return _HabitTile(
                                key: ValueKey(h.id),
                                habit: h,
                                checkAnim: _checkAnim[h.id],
                                onToggle: (offset) =>
                                    _toggleHabit(h, tapOffset: offset),
                                onEdit: () =>
                                    _showHabitDialog(editing: h),
                                onDelete: () => _deleteHabit(h),
                              );
                            },
                          ),
              ),
            ],
          ),

          // ── Floating XP overlays ─────────────────────────────────────
          ..._floatingXps.map((e) => _FloatingXpWidget(entry: e)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showHabitDialog(),
        icon: const Icon(Icons.add),
        label: const Text('New Mission'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort & Filter bar
// ---------------------------------------------------------------------------
class _SortFilterBar extends StatelessWidget {
  final String filterCategory;
  final _SortMode sortMode;
  final IconData sortIcon;
  final String sortTooltip;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onSortTap;

  const _SortFilterBar({
    required this.filterCategory,
    required this.sortMode,
    required this.sortIcon,
    required this.sortTooltip,
    required this.onFilterChanged,
    required this.onSortTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = ['all', ..._kCategories.where((c) => c != 'general')];

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: filters.map((cat) {
                  final selected = filterCategory == cat;
                  final label = cat == 'all'
                      ? 'All'
                      : (_kCategoryLabels[cat] ?? cat);
                  final color = cat == 'all'
                      ? scheme.primary
                      : (_kCategoryColors[cat] ?? scheme.primary);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? color : null,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) => onFilterChanged(cat),
                      selectedColor: color.withOpacity(0.15),
                      checkmarkColor: color,
                      side: BorderSide(
                        color: selected
                            ? color
                            : Colors.grey.withOpacity(0.3),
                        width: selected ? 1.5 : 1,
                      ),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Tooltip(
            message: sortTooltip,
            child: IconButton(
              icon: Icon(sortIcon, size: 20),
              color: sortMode != _SortMode.defaultOrder
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
              onPressed: onSortTap,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated empty state
// ---------------------------------------------------------------------------
class _AnimatedEmptyState extends StatelessWidget {
  final Animation<double> bounceAnim;
  final void Function(Map<String, dynamic> template) onTemplateTap;

  const _AnimatedEmptyState({
    required this.bounceAnim,
    required this.onTemplateTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bouncing icon
          AnimatedBuilder(
            animation: bounceAnim,
            builder: (_, __) => Transform.translate(
              offset: Offset(0, bounceAnim.value),
              child: Icon(Icons.rocket_launch_outlined,
                  size: 64,
                  color: scheme.onSurfaceVariant.withOpacity(0.4)),
            ),
          ),
          const SizedBox(height: 16),
          Text('No missions yet.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Create your first mission or pick a template below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 28),
          Text('Quick start',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          ..._kTemplates.map((t) {
            final cat = t['category'] as String;
            final color = _kCategoryColors[cat] ?? scheme.primary;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
              ),
              child: ListTile(
                onTap: () => onTemplateTap(t),
                leading: Text(t['emoji'] as String,
                    style: const TextStyle(fontSize: 28)),
                title: Text(t['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_kCategoryLabels[cat] ?? cat,
                    style: TextStyle(fontSize: 12, color: color)),
                trailing: Icon(Icons.add_circle_outline, color: color),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual habit tile (stateful for AnimatedBuilder)
// ---------------------------------------------------------------------------
class _HabitTile extends StatelessWidget {
  final Habit habit;
  final Animation<double>? checkAnim;
  final void Function(Offset tapOffset) onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HabitTile({
    super.key,
    required this.habit,
    required this.checkAnim,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final h = habit;
    final scheme = Theme.of(context).colorScheme;
    final catColor =
        _kCategoryColors[h.category] ?? scheme.primary;

    Widget checkboxWidget = Transform.scale(
      scale: 1.2,
      child: Checkbox(
        value: h.doneToday,
        shape: const CircleBorder(),
        activeColor: scheme.primary,
        onChanged: (_) {
          // Use a gesture detector for the offset instead
        },
      ),
    );

    // Wrap with scale animation when we have a controller
    if (checkAnim != null) {
      checkboxWidget = AnimatedBuilder(
        animation: checkAnim!,
        builder: (_, child) => Transform.scale(
          scale: checkAnim!.value,
          child: child,
        ),
        child: checkboxWidget,
      );
    }

    return Dismissible(
      key: Key(h.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Abort mission?'),
          content: Text('Remove "${h.name}"? Progress will be lost.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Abort'),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: h.doneToday
              ? BorderSide(
                  color: scheme.primary.withOpacity(0.4), width: 1.5)
              : BorderSide.none,
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(h.emoji, style: const TextStyle(fontSize: 30)),
              if (h.doneToday)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        size: 10, color: Colors.white),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  h.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    decoration:
                        h.doneToday ? TextDecoration.lineThrough : null,
                    color: h.doneToday ? scheme.onSurfaceVariant : null,
                  ),
                ),
              ),
              // Difficulty stars
              ...List.generate(
                h.difficulty,
                (_) => const Icon(Icons.star,
                    size: 13, color: Color(0xFFFFC107)),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              if (h.streak > 0) ...[
                Text('🔥 ${h.streak}d streak',
                    style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
              ],
              _XpBadge(xp: h.xp, done: h.doneToday),
              const SizedBox(width: 6),
              // Category chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: catColor.withOpacity(0.3)),
                ),
                child: Text(
                  _kCategoryLabels[h.category] ?? h.category,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: catColor),
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: scheme.onSurfaceVariant,
                onPressed: onEdit,
              ),
              // GestureDetector to capture tap position for floating XP
              GestureDetector(
                onTapUp: (details) =>
                    onToggle(details.globalPosition),
                child: checkboxWidget,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating XP entry model
// ---------------------------------------------------------------------------
class _FloatingXpEntry {
  final int xp;
  final Offset position;
  final VoidCallback onDone;
  _FloatingXpEntry({
    required this.xp,
    required this.position,
    required this.onDone,
  });
}

// ---------------------------------------------------------------------------
// Floating XP animated widget
// ---------------------------------------------------------------------------
class _FloatingXpWidget extends StatefulWidget {
  final _FloatingXpEntry entry;
  const _FloatingXpWidget({required this.entry});

  @override
  State<_FloatingXpWidget> createState() => _FloatingXpWidgetState();
}

class _FloatingXpWidgetState extends State<_FloatingXpWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _rise;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 20),
      TweenSequenceItem(
          tween: ConstantTween(1.0), weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 40),
    ]).animate(_ctrl);
    _rise = Tween<double>(begin: 0, end: -60).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward().then((_) => widget.entry.onDone());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Positioned(
        left: widget.entry.position.dx - 24,
        top: widget.entry.position.dy + _rise.value - 30,
        child: IgnorePointer(
          child: Opacity(
            opacity: _opacity.value.clamp(0.0, 1.0),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Text(
                '+${widget.entry.xp} XP',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------
class _XpBadge extends StatelessWidget {
  final int xp;
  final bool done;
  const _XpBadge({required this.xp, required this.done});

  Color get _color {
    if (xp >= 50) return Colors.purple;
    if (xp >= 30) return Colors.red;
    if (xp >= 20) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(done ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        '+$xp XP',
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: done ? _color.withOpacity(0.5) : _color),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatChip(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.onPrimaryContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/habit.dart';
import '../models/level_helper.dart';
import '../services/notification_service.dart';

class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  final db = DatabaseHelper.instance;
  List<Habit> habits = [];
  int totalXp = 0;
  int todayXp = 0;

  String get todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
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
      ));
    }
    final xp = await db.getTotalXP();
    final todXp = await db.getTodayXP(todayStr);
    setState(() {
      habits = loaded;
      totalXp = xp;
      todayXp = todXp;
    });
  }

  Future<void> _toggleHabit(Habit habit) async {
    if (habit.doneToday) {
      await db.unlogHabit(habit.id, todayStr);
      await db.subtractXP(habit.xp);
    } else {
      await db.logHabit({
        'id': const Uuid().v4(),
        'habit_id': habit.id,
        'date': todayStr,
        'logged_at': DateTime.now().toIso8601String(),
      });
      await db.addXP(habit.xp);
      if (mounted) {
        _showXpPop(habit.xp);
      }
    }
    await _load();
    // Check perfect day bonus
    if (mounted && habits.where((h) => h.id != habit.id || !habit.doneToday).every((h) => h.id == habit.id ? true : h.doneToday)) {
      final allDone = (await db.getHabits()).isNotEmpty &&
          (await Future.wait((habits).map((h) => db.isHabitLoggedToday(h.id, todayStr)))).every((v) => v);
      if (allDone && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Text('🎯 ', style: TextStyle(fontSize: 18)),
            Text('Perfect Day! All missions complete.', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ));
      }
    }
  }

  void _showXpPop(int xp) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Text('⚡ ', style: TextStyle(fontSize: 16)),
        Text('+$xp XP earned', style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
      backgroundColor: Colors.deepPurple,
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _deleteHabit(Habit h) async {
    if (h.doneToday) await db.subtractXP(h.xp);
    await NotificationService.instance.cancelReminder(h.id.hashCode);
    await db.deleteHabit(h.id);
    await _load();
  }

  void _showHabitDialog({Habit? editing}) {
    final nameCtrl = TextEditingController(text: editing?.name ?? '');
    String selectedEmoji = editing?.emoji ?? '🎯';
    int selectedXp = editing?.xp ?? 10;
    TimeOfDay? reminderTime;
    const emojis = [
      '🎯','💪','📚','🏃','💧','🧘','🍎','😴','🔥','🎸',
      '✍️','🧹','🐕','🌿','🏋️','🚴','🧃','💊','🌅','⚡',
    ];
    const xpOptions = [
      {'label': 'Easy', 'xp': 10, 'color': Colors.green},
      {'label': 'Medium', 'xp': 20, 'color': Colors.orange},
      {'label': 'Hard', 'xp': 30, 'color': Colors.red},
      {'label': 'Epic', 'xp': 50, 'color': Colors.purple},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(editing == null ? 'New Mission' : 'Edit Mission',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Mission name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Icon', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: emojis.map((e) => GestureDetector(
                    onTap: () => setS(() => selectedEmoji = e),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: selectedEmoji == e
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 14),
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
                            color: selected ? color.withOpacity(0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? color : Colors.grey.withOpacity(0.3),
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
                if (editing == null) ...[
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alarm),
                    title: Text(reminderTime == null
                        ? 'Set daily reminder (optional)'
                        : 'Reminder: ${reminderTime!.format(ctx)}',
                        style: const TextStyle(fontSize: 14)),
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
                            onPressed: () => setS(() => reminderTime = null))
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
                  await db.updateHabit(
                      editing.id, nameCtrl.text.trim(), selectedEmoji, selectedXp);
                } else {
                  final id = const Uuid().v4();
                  await db.insertHabit({
                    'id': id,
                    'name': nameCtrl.text.trim(),
                    'emoji': selectedEmoji,
                    'xp': selectedXp,
                    'created_at': DateTime.now().toIso8601String(),
                  });
                  if (reminderTime != null) {
                    await NotificationService.instance.scheduleDailyHabitReminder(
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

  @override
  Widget build(BuildContext context) {
    final completed = habits.where((h) => h.doneToday).length;
    final scheme = Theme.of(context).colorScheme;
    final levelTitle = LevelHelper.title(totalXp);
    final levelNum = LevelHelper.number(totalXp);
    final lvlProgress = LevelHelper.progress(totalXp);
    final xpToNext = LevelHelper.xpToNext(totalXp);
    final isPerfect = habits.isNotEmpty && completed == habits.length;

    return Scaffold(
      body: Column(
        children: [
          // Agent status panel
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('⚡', style: TextStyle(fontSize: 14)),
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
                              fontSize: 12, color: scheme.onPrimaryContainer.withOpacity(0.7))),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: lvlProgress,
                    minHeight: 6,
                    backgroundColor: scheme.onPrimaryContainer.withOpacity(0.2),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🎯', style: TextStyle(fontSize: 12)),
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

          // Missions list
          Expanded(
            child: habits.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.rocket_launch_outlined,
                            size: 64, color: scheme.onSurfaceVariant.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        Text('No missions yet.',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text('Create your first mission to start earning XP.',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    itemCount: habits.length,
                    itemBuilder: (ctx, i) {
                      final h = habits[i];
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
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red),
                                child: const Text('Abort'),
                              ),
                            ],
                          ),
                        ),
                        onDismissed: (_) => _deleteHabit(h),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: h.doneToday
                                ? BorderSide(color: scheme.primary.withOpacity(0.4), width: 1.5)
                                : BorderSide.none,
                          ),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.fromLTRB(14, 8, 8, 8),
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Text(h.emoji,
                                    style: const TextStyle(fontSize: 30)),
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
                            title: Text(h.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  decoration: h.doneToday
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: h.doneToday
                                      ? scheme.onSurfaceVariant
                                      : null,
                                )),
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
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  color: scheme.onSurfaceVariant,
                                  onPressed: () => _showHabitDialog(editing: h),
                                ),
                                Transform.scale(
                                  scale: 1.2,
                                  child: Checkbox(
                                    value: h.doneToday,
                                    shape: const CircleBorder(),
                                    activeColor: scheme.primary,
                                    onChanged: (_) => _toggleHabit(h),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
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
      child: Text('+$xp XP',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: done ? _color.withOpacity(0.5) : _color)),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatChip({required this.label, required this.value, required this.icon});

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
          Text('$value $label',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/todo_item.dart';
import '../models/habit.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final db = DatabaseHelper.instance;
  List<TodoItem> _todos = [];
  List<Habit> _habits = [];
  String? _intention;
  bool _loading = true;

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final todoMaps = await db.getTodosForDate(_todayStr);
    final habitMaps = await db.getHabits();
    final List<Habit> loadedHabits = [];
    for (final m in habitMaps) {
      final logs = await db.getLogsForHabit(m['id']);
      final logDates = logs.map((l) => l['date'] as String).toList();
      final doneToday = await db.isHabitLoggedToday(m['id'], _todayStr);
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
    final plan = await db.getDailyPlan(_todayStr);
    setState(() {
      _todos = todoMaps.map(TodoItem.fromMap).toList();
      _habits = loadedHabits;
      _intention = plan?['intention'] as String?;
      _loading = false;
    });
  }

  Future<void> _toggleTodo(TodoItem todo) async {
    final updated = todo.copyWith(
      completed: !todo.completed,
      completedAt: !todo.completed ? DateTime.now().toIso8601String() : null,
    );
    await db.updateTodo(updated.toMap());
    await _load();
  }

  Future<void> _deleteTodo(String id) async {
    await db.deleteTodo(id);
    await _load();
  }

  Future<void> _toggleHabit(Habit h) async {
    if (h.doneToday) {
      await db.unlogHabit(h.id, _todayStr);
      await db.subtractXP(h.xp);
    } else {
      await db.logHabit({
        'id': const Uuid().v4(),
        'habit_id': h.id,
        'date': _todayStr,
        'logged_at': DateTime.now().toIso8601String(),
      });
      await db.addXP(h.xp);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('⚡ ', style: TextStyle(fontSize: 14)),
            Text('+${h.xp} XP — ${h.name}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          backgroundColor: Colors.deepPurple,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    await _load();
  }

  void _showSetPlanDialog() {
    final ctrl = TextEditingController(text: _intention ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SET GAME PLAN',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 6),
            Text('What\'s your intention for today, Agent?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'e.g. "Ship the feature, hit the gym, sleep by midnight."',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  if (ctrl.text.trim().isEmpty) return;
                  await db.setDailyPlan(_todayStr, ctrl.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                },
                icon: const Icon(Icons.lock),
                label: const Text('Lock In Game Plan'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAddTodo() {
    final ctrl = TextEditingController();
    String priority = 'medium';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 24),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NEW OBJECTIVE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 6),
              Text('Add to today\'s mission.',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'What needs to be done?',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Priority: ',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                for (final p in ['high', 'medium', 'low'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p),
                      selected: priority == p,
                      selectedColor: _priorityColor(p).withOpacity(0.3),
                      onSelected: (_) => setS(() => priority = p),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (ctrl.text.trim().isEmpty) return;
                    await db.insertTodo(TodoItem(
                      id: const Uuid().v4(),
                      title: ctrl.text.trim(),
                      priority: priority,
                      date: _todayStr,
                      completed: false,
                      createdAt: DateTime.now().toIso8601String(),
                    ).toMap());
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  },
                  child: const Text('Add Objective'),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'high': return Colors.red;
      case 'medium': return Colors.orange;
      default: return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todosDone = _todos.where((t) => t.completed).length;
    final habitsDone = _habits.where((h) => h.doneToday).length;
    final totalItems = _todos.length + _habits.length;
    final doneItems = todosDone + habitsDone;
    final cleaningTip = _cleaningTips[now.weekday] ?? _cleaningTips[1]!;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // ── Header ──────────────────────────────────────────────────────
            Text('MISSION CONTROL',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                    color: scheme.primary)),
            const SizedBox(height: 2),
            Text(DateFormat('EEEE, MMMM d').format(now),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text('$doneItems/$totalItems objectives cleared',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),

            const SizedBox(height: 10),

            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: totalItems == 0 ? 0 : doneItems / totalItems,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),

            const SizedBox(height: 20),

            // ── Daily Game Plan ──────────────────────────────────────────────
            GestureDetector(
              onTap: _showSetPlanDialog,
              child: Card(
                color: _intention != null
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                          _intention != null ? '🎯' : '📋',
                          style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GAME PLAN',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                    color: _intention != null
                                        ? scheme.onSecondaryContainer.withOpacity(0.7)
                                        : scheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(
                                _intention ??
                                    'Tap to set your intention for today.',
                                style: TextStyle(
                                    fontWeight: _intention != null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _intention != null
                                        ? scheme.onSecondaryContainer
                                        : scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(
                          _intention != null
                              ? Icons.edit_outlined
                              : Icons.add,
                          color: scheme.onSurfaceVariant,
                          size: 20),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Active Missions ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ACTIVE MISSIONS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: scheme.onSurfaceVariant)),
                Text('$habitsDone/${_habits.length}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: habitsDone == _habits.length && _habits.isNotEmpty
                            ? Colors.green
                            : scheme.primary)),
              ],
            ),
            const SizedBox(height: 10),
            if (_habits.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    'No missions set. Add some in the Missions tab.',
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _habits.map((h) {
                  return GestureDetector(
                    onTap: () => _toggleHabit(h),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: h.doneToday
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: h.doneToday
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: h.doneToday ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(h.emoji, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(h.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                                color: h.doneToday
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurface,
                                decoration: h.doneToday
                                    ? TextDecoration.lineThrough
                                    : null,
                              )),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withOpacity(
                                  h.doneToday ? 0.08 : 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('+${h.xp}',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepPurple
                                        .withOpacity(h.doneToday ? 0.4 : 1))),
                          ),
                          if (h.doneToday) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.check_circle,
                                size: 14, color: scheme.primary),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 24),

            // ── Objectives (Tasks) ───────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('OBJECTIVES',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: scheme.onSurfaceVariant)),
                TextButton.icon(
                  onPressed: _showAddTodo,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (_todos.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 36, color: scheme.onSurfaceVariant.withOpacity(0.4)),
                      const SizedBox(height: 8),
                      Text('No objectives yet.',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              )
            else
              ...(_todos
                    ..sort((a, b) {
                      final pOrder = {'high': 0, 'medium': 1, 'low': 2};
                      if (a.completed != b.completed) return a.completed ? 1 : -1;
                      return (pOrder[a.priority] ?? 1)
                          .compareTo(pOrder[b.priority] ?? 1);
                    }))
                  .map((todo) => Dismissible(
                        key: Key(todo.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteTodo(todo.id),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: GestureDetector(
                              onTap: () => _toggleTodo(todo),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: todo.completed
                                        ? Colors.green
                                        : _priorityColor(todo.priority),
                                    width: 2,
                                  ),
                                  color: todo.completed
                                      ? Colors.green
                                      : Colors.transparent,
                                ),
                                child: todo.completed
                                    ? const Icon(Icons.check,
                                        size: 14, color: Colors.white)
                                    : null,
                              ),
                            ),
                            title: Text(
                              todo.title,
                              style: TextStyle(
                                decoration: todo.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: todo.completed
                                    ? scheme.onSurfaceVariant
                                    : null,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _priorityColor(todo.priority)
                                    .withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(todo.priority,
                                  style: TextStyle(
                                      color: _priorityColor(todo.priority),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      )),

            const SizedBox(height: 24),

            // ── Daily Tip ────────────────────────────────────────────────────
            Card(
              color: Colors.brown.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Text('🧹', style: TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cleaningTip['title']!,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(cleaningTip['tip']!,
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTodo,
        icon: const Icon(Icons.add_task),
        label: const Text('Add Objective'),
      ),
    );
  }

  static const _cleaningTips = {
    1: {'title': 'Clean your desk', 'tip': 'Clear desk, wipe surface, organize cables. 5 mins.'},
    2: {'title': 'Bedroom floor', 'tip': 'Quick sweep — clothes off the floor!'},
    3: {'title': 'Do laundry', 'tip': 'Any clothes to wash? Start a load now.'},
    4: {'title': 'Bathroom wipe', 'tip': 'Mirror, sink, countertop — 3 minutes, fresh results.'},
    5: {'title': 'Trash & clutter', 'tip': 'Take out trash. Clear one cluttered surface.'},
    6: {'title': 'Change bedsheets', 'tip': 'Fresh sheets = better sleep. Do it now.'},
    7: {'title': '10-min reset', 'tip': 'Put everything back where it belongs. Weekly refresh.'},
  };
}

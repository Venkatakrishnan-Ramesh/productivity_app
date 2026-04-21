import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/transaction.dart';
import '../services/pattern_service.dart';
import '../services/sms_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _db = DatabaseHelper.instance;
  final _patterns = PatternService.instance;
  final _input = TextEditingController();
  final _messages = <_AssistantMessage>[
    const _AssistantMessage(
      text:
          'JARVIS online. Ask for a briefing, finance summary, insights, or tell me to sync messages.',
      fromUser: false,
    ),
  ];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _runPrompt(String raw) async {
    final prompt = raw.trim();
    if (prompt.isEmpty || _busy) return;

    setState(() {
      _messages.add(_AssistantMessage(text: prompt, fromUser: true));
      _busy = true;
      _input.clear();
    });

    String response;
    final lower = prompt.toLowerCase();
    try {
      if (_wantsSmsSync(lower)) {
        response = await _syncMessages();
      } else if (lower.contains('finance') ||
          lower.contains('money') ||
          lower.contains('spend') ||
          lower.contains('budget')) {
        response = await _financeBriefing();
      } else if (lower.contains('insight') ||
          lower.contains('pattern') ||
          lower.contains('score')) {
        response = await _insightBriefing();
      } else if (lower.contains('habit') || lower.contains('mission')) {
        response = await _habitBriefing();
      } else {
        response = await _dailyBriefing();
      }
    } catch (e) {
      response = 'I hit a local error while handling that: $e';
    }

    if (!mounted) return;
    setState(() {
      _messages.add(_AssistantMessage(text: response, fromUser: false));
      _busy = false;
    });
  }

  bool _wantsSmsSync(String prompt) {
    return prompt.contains('sync') ||
        prompt.contains('message') ||
        prompt.contains('sms') ||
        prompt.contains('gpay') ||
        prompt.contains('upi');
  }

  Future<String> _dailyBriefing() async {
    final score = await _patterns.computeTodayScore();
    final todos = await _db.getTodosForDate(_todayStr);
    final doneTodos = todos.where((t) => t['completed'] == 1).length;
    final habits = await _db.getHabits();
    int doneHabits = 0;
    for (final h in habits) {
      if (await _db.isHabitLoggedToday(h['id'] as String, _todayStr)) {
        doneHabits++;
      }
    }
    final water = await _db.getTotalWaterToday(_todayStr);
    final steps = await _db.getStepRecord(_todayStr);
    final stepCount = (steps?['steps'] as int?) ?? 0;
    final plan = await _db.getDailyPlan(_todayStr);

    final planText = plan == null
        ? 'No game plan locked yet.'
        : 'Game plan: ${plan['intention']}';
    return [
      'Today score: ${score.toStringAsFixed(0)}/100.',
      'Missions: $doneHabits/${habits.length}. Tasks: $doneTodos/${todos.length}.',
      'Steps: $stepCount. Water: ${water}ml.',
      planText,
    ].join('\n');
  }

  Future<String> _habitBriefing() async {
    final habits = await _db.getHabits();
    if (habits.isEmpty)
      return 'No missions exist yet. Add your first habit from Missions.';

    final pending = <String>[];
    for (final h in habits) {
      final done = await _db.isHabitLoggedToday(h['id'] as String, _todayStr);
      if (!done) pending.add('${h['emoji']} ${h['name']}');
    }

    if (pending.isEmpty) return 'All missions are complete for today.';
    return 'Pending missions:\n${pending.take(6).join('\n')}';
  }

  Future<String> _financeBriefing() async {
    final now = DateTime.now();
    final txns = (await _db.getTransactions()).map(FinanceTransaction.fromMap);
    final monthTxns = txns.where((t) {
      final d = DateTime.parse(t.date);
      return d.year == now.year && d.month == now.month;
    }).toList();

    if (monthTxns.isEmpty) {
      return 'No transactions found for ${DateFormat('MMMM yyyy').format(now)}. Say "sync messages" to import UPI/GPay transactions from SMS.';
    }

    final income =
        monthTxns.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);
    final expense =
        monthTxns.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);
    final byCategory = <String, double>{};
    for (final t in monthTxns.where((t) => !t.isIncome)) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
    }
    final topCategory = byCategory.entries.isEmpty
        ? null
        : byCategory.entries.reduce((a, b) => a.value > b.value ? a : b);
    final fmt = NumberFormat('#,##0.00');

    return [
      'This month: income \$${fmt.format(income)}, expenses \$${fmt.format(expense)}, balance \$${fmt.format(income - expense)}.',
      if (topCategory != null)
        'Top spending category: ${topCategory.key} at \$${fmt.format(topCategory.value)}.',
      'Transactions tracked: ${monthTxns.length}.',
    ].join('\n');
  }

  Future<String> _insightBriefing() async {
    final insights = await _patterns.generateInsights();
    return insights
        .take(3)
        .map((i) => '${i.emoji} ${i.title}\n${i.description}')
        .join('\n\n');
  }

  Future<String> _syncMessages() async {
    final granted = await SmsService.requestPermission();
    if (!granted) {
      return 'SMS permission was not granted. I need SMS access before I can import UPI/GPay transactions.';
    }

    final found = await SmsService.fetchGPayTransactions();
    if (found.isEmpty) {
      return 'I checked your messages and did not find recent UPI/GPay transactions.';
    }

    var imported = 0;
    for (final t in found) {
      await _db.insertTransaction(FinanceTransaction(
        id: t.stableId,
        title: t.title,
        amount: t.amount,
        category: t.category,
        type: t.type,
        date: t.date.toIso8601String(),
        smsDate: t.date.toIso8601String(),
      ).toMap());
      imported++;
    }

    return 'Imported $imported message transactions into Finance. Re-running sync updates the same SMS records instead of duplicating them.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mini JARVIS'),
        centerTitle: true,
        backgroundColor: scheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.fromUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: message.fromUser
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(message.text),
                  ),
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PromptChip(
                        label: 'Briefing', onTap: () => _runPrompt('briefing')),
                    _PromptChip(
                        label: 'Finance', onTap: () => _runPrompt('finance')),
                    _PromptChip(
                        label: 'Sync SMS',
                        onTap: () => _runPrompt('sync messages')),
                    _PromptChip(
                        label: 'Insights', onTap: () => _runPrompt('insights')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: !_busy,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _runPrompt,
                        decoration: const InputDecoration(
                          hintText: 'Ask JARVIS...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _busy ? null : () => _runPrompt(_input.text),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantMessage {
  final String text;
  final bool fromUser;

  const _AssistantMessage({
    required this.text,
    required this.fromUser,
  });
}

class _PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PromptChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      avatar: const Icon(Icons.auto_awesome, size: 16),
    );
  }
}

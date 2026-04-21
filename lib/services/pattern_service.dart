import '../db/database_helper.dart';
import '../models/pattern_insight.dart';

class PatternService {
  static final PatternService instance = PatternService._();
  PatternService._();

  final db = DatabaseHelper.instance;

  static const _fullDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  // ── Life Score ──────────────────────────────────────────────────────────

  Future<double> computeTodayScore() async {
    final today = _todayStr();
    final habits = await _habitScore(today);
    final steps = await _stepsScore(today);
    final water = await _waterScore(today);
    final todos = await _todosScore(today);
    return (habits * 30 + steps * 25 + water * 25 + todos * 20).clamp(0, 100);
  }

  Future<double> computeScoreForDate(String date) async {
    final habits = await _habitScore(date);
    final steps = await _stepsScore(date);
    final water = await _waterScore(date);
    final todos = await _todosScore(date);
    return (habits * 30 + steps * 25 + water * 25 + todos * 20).clamp(0, 100);
  }

  /// Returns a list of daily life scores for the past [days] days (oldest first).
  Future<List<double>> getScoreTrend({int days = 7}) async {
    final scores = <double>[];
    final now = DateTime.now();
    for (int i = days - 1; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dateStr = _dateStr(day);
      scores.add(await computeScoreForDate(dateStr));
    }
    return scores;
  }

  Future<Map<String, double>> getTodayScoreBreakdown() async {
    final today = _todayStr();
    return {
      'habits': await _habitScore(today) * 100,
      'steps': await _stepsScore(today) * 100,
      'water': await _waterScore(today) * 100,
      'todos': await _todosScore(today) * 100,
    };
  }

  // ── Lifetime Stats ──────────────────────────────────────────────────────

  /// Returns aggregate lifetime stats from the database.
  Future<Map<String, dynamic>> getLifetimeStats() async {
    final dbInstance = await db.database;

    // Total XP from user_stats
    final xpRows = await dbInstance
        .query('user_stats', where: 'key = ?', whereArgs: ['total_xp']);
    final totalXp = xpRows.isEmpty ? 0 : (xpRows.first['value'] as int);

    // Total habits completed (count of all habit_logs rows)
    final habitCountRows =
        await dbInstance.rawQuery('SELECT COUNT(*) as cnt FROM habit_logs');
    final totalHabitsCompleted =
        (habitCountRows.first['cnt'] as int? ?? 0);

    // Best streak: compute per habit and take the max
    final habits = await db.getHabits();
    int bestStreak = 0;
    for (final h in habits) {
      final logs = await db.getLogsForHabit(h['id'] as String);
      if (logs.isEmpty) continue;
      final dates = logs
          .map((l) => l['date'] as String)
          .toSet()
          .map((s) => DateTime.parse(s))
          .toList()
        ..sort();

      int streak = 1;
      int maxStreak = 1;
      for (int i = 1; i < dates.length; i++) {
        final diff = dates[i].difference(dates[i - 1]).inDays;
        if (diff == 1) {
          streak++;
          if (streak > maxStreak) maxStreak = streak;
        } else if (diff > 1) {
          streak = 1;
        }
      }
      if (maxStreak > bestStreak) bestStreak = maxStreak;
    }

    // Days tracked: distinct dates in step_records OR habit_logs
    final daysRows = await dbInstance.rawQuery(
        'SELECT COUNT(DISTINCT date) as cnt FROM habit_logs');
    final stepDaysRows = await dbInstance
        .rawQuery('SELECT COUNT(*) as cnt FROM step_records');
    final habitDays = daysRows.first['cnt'] as int? ?? 0;
    final stepDays = stepDaysRows.first['cnt'] as int? ?? 0;
    final daysTracked = habitDays > stepDays ? habitDays : stepDays;

    // Average score over tracked days (use last 30 days max for performance)
    final lookback = daysTracked.clamp(1, 30);
    final trendScores = await getScoreTrend(days: lookback);
    final nonZero = trendScores.where((s) => s > 0).toList();
    final avgScore = nonZero.isEmpty
        ? 0.0
        : nonZero.reduce((a, b) => a + b) / nonZero.length;

    return {
      'totalXp': totalXp,
      'bestStreak': bestStreak,
      'totalHabitsCompleted': totalHabitsCompleted,
      'avgScore': avgScore,
      'daysTracked': daysTracked,
    };
  }

  // ── Wake / Sleep Patterns ───────────────────────────────────────────────

  Future<String?> getUsualWakeTime() async {
    final events = await db.getWakeEvents(14);
    if (events.length < 3) return null;

    final minutes = <int>[];
    for (final e in events) {
      try {
        final dt = DateTime.parse(e['first_step_at'] as String);
        final totalMin = dt.hour * 60 + dt.minute;
        // Only count reasonable wake times (4 AM - 12 PM)
        if (totalMin >= 240 && totalMin <= 720) minutes.add(totalMin);
      } catch (_) {}
    }
    if (minutes.length < 3) return null;

    final avg = minutes.reduce((a, b) => a + b) ~/ minutes.length;
    final h = avg ~/ 60;
    final m = avg % 60;
    final amPm = h < 12 ? 'AM' : 'PM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH:${m.toString().padLeft(2, '0')} $amPm';
  }

  Future<String?> getUsualSleepTime() async {
    final events = await db.getWakeEvents(14);
    if (events.length < 3) return null;

    final minutes = <int>[];
    for (final e in events) {
      final lastStep = e['last_step_at'];
      if (lastStep == null) continue;
      try {
        final dt = DateTime.parse(lastStep as String);
        int totalMin = dt.hour * 60 + dt.minute;
        // Normalize: times after midnight (0-3 AM) → add 24h for averaging
        if (dt.hour < 4) totalMin += 1440;
        if (totalMin >= 1200) minutes.add(totalMin); // after 8 PM
      } catch (_) {}
    }
    if (minutes.length < 3) return null;

    final avg = minutes.reduce((a, b) => a + b) ~/ minutes.length;
    final normalizedMin = avg % 1440;
    final h = normalizedMin ~/ 60;
    final m = normalizedMin % 60;
    final amPm = h < 12 ? 'AM' : 'PM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH:${m.toString().padLeft(2, '0')} $amPm';
  }

  // ── Habit Patterns ──────────────────────────────────────────────────────

  Future<String?> getMostProductiveDay() async {
    final logs = await db.getAllHabitLogs();
    if (logs.length < 7) return null;

    final byDay = <int, int>{};
    for (final log in logs) {
      try {
        final day = DateTime.parse(log['date'] as String).weekday - 1;
        byDay[day] = (byDay[day] ?? 0) + 1;
      } catch (_) {}
    }
    if (byDay.isEmpty) return null;

    final best = byDay.entries.reduce((a, b) => a.value > b.value ? a : b);
    return _fullDays[best.key];
  }

  Future<Map<String, String>> getHabitSkipPatterns() async {
    final habits = await db.getHabits();
    final result = <String, String>{};

    for (final habit in habits) {
      final logs = await db.getLogsForHabit(habit['id']);
      if (logs.length < 7) continue;

      final completedDays = <int>{};
      for (final log in logs) {
        try {
          completedDays.add(DateTime.parse(log['date'] as String).weekday - 1);
        } catch (_) {}
      }

      // Find the day least represented
      int? worstDay;
      int worstCount = 999;
      for (int d = 0; d < 7; d++) {
        final count = completedDays.where((dd) => dd == d).length;
        if (count < worstCount) {
          worstCount = count;
          worstDay = d;
        }
      }

      if (worstDay != null && worstCount == 0) {
        result[habit['name'] as String] = _fullDays[worstDay];
      }
    }
    return result;
  }

  Future<List<double>> getHabitCompletionByDay() async {
    final logs = await db.getAllHabitLogs();
    final habits = await db.getHabits();
    if (habits.isEmpty || logs.isEmpty) return List.filled(7, 0);

    final counts = List<int>.filled(7, 0);
    final dayCounts = List<int>.filled(7, 0);

    // Count how many days of each weekday exist in our data
    final now = DateTime.now();
    for (int i = 0; i < 28; i++) {
      final d = now.subtract(Duration(days: i));
      dayCounts[d.weekday - 1]++;
    }

    for (final log in logs) {
      try {
        final day = DateTime.parse(log['date'] as String).weekday - 1;
        counts[day]++;
      } catch (_) {}
    }

    return List.generate(7, (i) {
      if (dayCounts[i] == 0 || habits.isEmpty) return 0;
      return (counts[i] / (dayCounts[i] * habits.length)).clamp(0.0, 1.0);
    });
  }

  // ── Spending Patterns ───────────────────────────────────────────────────

  Future<String?> getPeakSpendingDay() async {
    final txns = await db.getTransactions();
    final expenses = txns.where((t) => t['type'] == 'expense').toList();
    if (expenses.length < 5) return null;

    final byDay = <int, double>{};
    for (final t in expenses) {
      try {
        final day = DateTime.parse(t['date'] as String).weekday - 1;
        byDay[day] = (byDay[day] ?? 0) + (t['amount'] as double);
      } catch (_) {}
    }
    if (byDay.isEmpty) return null;

    final peak = byDay.entries.reduce((a, b) => a.value > b.value ? a : b);
    return _fullDays[peak.key];
  }

  Future<String?> getPeakSpendingCategory() async {
    final txns = await db.getTransactions();
    final expenses = txns.where((t) => t['type'] == 'expense').toList();
    if (expenses.length < 5) return null;

    final byCategory = <String, double>{};
    for (final t in expenses) {
      final cat = t['category'] as String;
      byCategory[cat] = (byCategory[cat] ?? 0) + (t['amount'] as double);
    }

    final top = byCategory.entries.reduce((a, b) => a.value > b.value ? a : b);
    return top.key;
  }

  // ── Water Patterns ──────────────────────────────────────────────────────

  Future<String?> getPeakWaterHour() async {
    final now = DateTime.now();
    final from = _dateStr(now.subtract(const Duration(days: 14)));
    final to = _todayStr();
    final logs = await db.getWaterLogsByDateRange(from, to);
    if (logs.length < 10) return null;

    final byHour = <int, int>{};
    for (final log in logs) {
      try {
        final hour = DateTime.parse(log['logged_at'] as String).hour;
        byHour[hour] = (byHour[hour] ?? 0) + (log['amount_ml'] as int);
      } catch (_) {}
    }
    if (byHour.isEmpty) return null;

    final peak = byHour.entries.reduce((a, b) => a.value > b.value ? a : b);
    final h = peak.key;
    final amPm = h < 12 ? 'AM' : 'PM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH $amPm';
  }

  // ── Evening Summary ─────────────────────────────────────────────────────

  Future<String> generateEveningSummary() async {
    final today = _todayStr();
    final score = await computeTodayScore();

    // Habits
    final habits = await db.getHabits();
    final habitsDone = <String>[];
    for (final h in habits) {
      if (await db.isHabitLoggedToday(h['id'], today)) {
        habitsDone.add(h['name']);
      }
    }

    // Steps
    final stepRecord = await db.getStepRecord(today);
    final steps = stepRecord != null ? stepRecord['steps'] as int : 0;

    // Water
    final waterMl = await db.getTotalWaterToday(today);
    final waterGlasses = waterMl ~/ 250;

    // Todos
    final todos = await db.getTodosForDate(today);
    final todoDone = todos.where((t) => t['completed'] == 1).length;

    // Wake time
    final wakeEvents = await db.getWakeEvents(1);
    String wakeStr = '';
    if (wakeEvents.isNotEmpty) {
      try {
        final dt = DateTime.parse(wakeEvents.first['first_step_at'] as String);
        wakeStr = ' You started your day at ${_formatHour(dt)}.';
      } catch (_) {}
    }

    final scoreEmoji = score >= 80 ? '🔥' : score >= 60 ? '💪' : score >= 40 ? '📈' : '🌱';
    final greetings = [
      'Harvey would be proud.',
      "That's what winners do.",
      'Not bad. Now do better tomorrow.',
      'Suits don\'t make the man — habits do.',
    ];
    final closingLine = greetings[(DateTime.now().day) % greetings.length];

    final parts = <String>[];
    parts.add('$scoreEmoji Life Score: ${score.toStringAsFixed(0)}/100');
    if (wakeStr.isNotEmpty) parts.add(wakeStr);
    parts.add('Habits: ${habitsDone.length}/${habits.length} done'
        '${habitsDone.isNotEmpty ? ' (${habitsDone.take(2).join(', ')}${habitsDone.length > 2 ? '...' : ''})' : ''}.');
    parts.add('Steps: $steps${steps >= 10000 ? ' — goal crushed!' : steps >= 7000 ? ' — almost there.' : ' — aim higher tomorrow.'}');
    parts.add('Water: $waterGlasses glasses${waterGlasses >= 8 ? ' — perfectly hydrated!' : waterGlasses >= 5 ? '.' : ' — drink more!'}');
    if (todos.isNotEmpty) parts.add('Tasks: $todoDone/${todos.length} completed.');
    parts.add(closingLine);

    return parts.join(' ');
  }

  // ── Insights List ────────────────────────────────────────────────────────

  Future<List<PatternInsight>> generateInsights() async {
    final insights = <PatternInsight>[];

    final wakeTime = await getUsualWakeTime();
    if (wakeTime != null) {
      insights.add(PatternInsight(
        emoji: '🌅',
        title: 'You usually wake up around $wakeTime',
        description: 'Detected from your step activity over the last 2 weeks',
        confidence: 0.82,
        type: InsightType.wakeTime,
      ));
    }

    final sleepTime = await getUsualSleepTime();
    if (sleepTime != null) {
      insights.add(PatternInsight(
        emoji: '🌙',
        title: 'You usually wind down around $sleepTime',
        description: 'Based on when your daily movement stops',
        confidence: 0.75,
        type: InsightType.sleepTime,
      ));
    }

    final bestDay = await getMostProductiveDay();
    if (bestDay != null) {
      insights.add(PatternInsight(
        emoji: '🏆',
        title: '$bestDay is your most consistent habit day',
        description: 'You complete more habits on $bestDay than any other day',
        confidence: 0.78,
        type: InsightType.habits,
      ));
    }

    final skipPatterns = await getHabitSkipPatterns();
    for (final entry in skipPatterns.entries.take(2)) {
      insights.add(PatternInsight(
        emoji: '⚠️',
        title: 'You always skip "${entry.key}" on ${entry.value}s',
        description: 'You\'ve never logged this habit on a ${entry.value}',
        confidence: 0.90,
        type: InsightType.habits,
        isPositive: false,
      ));
    }

    final spendDay = await getPeakSpendingDay();
    final spendCat = await getPeakSpendingCategory();
    if (spendDay != null) {
      insights.add(PatternInsight(
        emoji: '💸',
        title: 'You spend the most on ${spendDay}s',
        description: spendCat != null
            ? 'Mostly on $spendCat — be mindful going into the weekend'
            : 'Track your spending triggers on this day',
        confidence: 0.71,
        type: InsightType.spending,
        isPositive: false,
      ));
    }

    final waterHour = await getPeakWaterHour();
    if (waterHour != null) {
      insights.add(PatternInsight(
        emoji: '💧',
        title: 'You drink the most water around $waterHour',
        description: 'Set reminders for the hours you tend to forget',
        confidence: 0.68,
        type: InsightType.water,
      ));
    }

    // Habit rate trend
    final trend = await getScoreTrend(days: 7);
    if (trend.length == 7) {
      final firstHalf = trend.take(3).reduce((a, b) => a + b) / 3;
      final secondHalf = trend.skip(4).reduce((a, b) => a + b) / 3;
      if (secondHalf > firstHalf + 10) {
        insights.add(PatternInsight(
          emoji: '📈',
          title: 'Your life score is trending up this week',
          description: 'You\'re consistently improving — keep the momentum',
          confidence: 0.85,
          type: InsightType.lifestyle,
        ));
      } else if (secondHalf < firstHalf - 10) {
        insights.add(PatternInsight(
          emoji: '📉',
          title: 'Your scores have dipped this week',
          description: 'You were stronger earlier in the week — reset tomorrow',
          confidence: 0.85,
          type: InsightType.lifestyle,
          isPositive: false,
        ));
      }
    }

    if (insights.isEmpty) {
      insights.add(PatternInsight(
        emoji: '🔍',
        title: 'Keep using the app — patterns need at least 7 days of data',
        description: 'Track your habits, steps, and water daily to unlock insights',
        confidence: 1.0,
        type: InsightType.lifestyle,
      ));
    }

    return insights;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<double> _habitScore(String date) async {
    final habits = await db.getHabits();
    if (habits.isEmpty) return 0.5;
    int done = 0;
    for (final h in habits) {
      if (await db.isHabitLoggedToday(h['id'], date)) done++;
    }
    return done / habits.length;
  }

  Future<double> _stepsScore(String date) async {
    final record = await db.getStepRecord(date);
    if (record == null) return 0;
    final steps = record['steps'] as int;
    return (steps / 10000).clamp(0.0, 1.0);
  }

  Future<double> _waterScore(String date) async {
    final ml = await db.getTotalWaterToday(date);
    return (ml / 2000).clamp(0.0, 1.0);
  }

  Future<double> _todosScore(String date) async {
    final todos = await db.getTodosForDate(date);
    if (todos.isEmpty) return 0.5;
    final done = todos.where((t) => t['completed'] == 1).length;
    return done / todos.length;
  }

  String _todayStr() {
    final now = DateTime.now();
    return _dateStr(now);
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatHour(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute;
    final amPm = h < 12 ? 'AM' : 'PM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH:${m.toString().padLeft(2, '0')} $amPm';
  }
}

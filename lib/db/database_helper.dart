import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('productivity.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 5, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''CREATE TABLE habits (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, emoji TEXT NOT NULL,
      xp INTEGER NOT NULL DEFAULT 10, created_at TEXT NOT NULL,
      category TEXT DEFAULT 'general',
      difficulty INTEGER DEFAULT 1,
      is_active INTEGER DEFAULT 1,
      description TEXT DEFAULT '')''');

    await db.execute('''CREATE TABLE habit_logs (
      id TEXT PRIMARY KEY, habit_id TEXT NOT NULL, date TEXT NOT NULL, logged_at TEXT,
      FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE)''');

    await db.execute('''CREATE TABLE transactions (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, amount REAL NOT NULL,
      category TEXT NOT NULL, type TEXT NOT NULL, date TEXT NOT NULL,
      is_recurring INTEGER DEFAULT 0,
      recurrence_pattern TEXT DEFAULT '',
      sms_date TEXT)''');

    await db.execute(
        'CREATE INDEX idx_transactions_date ON transactions(date)');
    await db.execute(
        'CREATE INDEX idx_transactions_category ON transactions(category)');

    await db.execute('''CREATE TABLE step_records (
      date TEXT PRIMARY KEY, baseline INTEGER NOT NULL DEFAULT 0,
      steps INTEGER NOT NULL DEFAULT 0)''');

    await db.execute('''CREATE TABLE wake_events (
      date TEXT PRIMARY KEY, first_step_at TEXT NOT NULL, last_step_at TEXT)''');

    await db.execute('''CREATE TABLE water_logs (
      id TEXT PRIMARY KEY, date TEXT NOT NULL, logged_at TEXT NOT NULL,
      amount_ml INTEGER NOT NULL)''');

    await db.execute('''CREATE TABLE todos (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, priority TEXT NOT NULL DEFAULT 'medium',
      date TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0,
      completed_at TEXT, created_at TEXT NOT NULL)''');

    await db.execute('''CREATE TABLE user_stats (
      key TEXT PRIMARY KEY, value INTEGER NOT NULL DEFAULT 0)''');
    await db.insert('user_stats', {'key': 'total_xp', 'value': 0});

    await db.execute('''CREATE TABLE daily_plans (
      date TEXT PRIMARY KEY, intention TEXT NOT NULL,
      committed_at TEXT NOT NULL)''');

    await db.execute('''CREATE TABLE budget_limits (
      category TEXT PRIMARY KEY,
      limit_amount REAL NOT NULL,
      alert_threshold REAL DEFAULT 0.8)''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''CREATE TABLE IF NOT EXISTS step_records (
        date TEXT PRIMARY KEY, baseline INTEGER NOT NULL DEFAULT 0,
        steps INTEGER NOT NULL DEFAULT 0)''');
    }
    if (oldVersion < 3) {
      try { await db.execute('ALTER TABLE habit_logs ADD COLUMN logged_at TEXT'); } catch (_) {}
      await db.execute('''CREATE TABLE IF NOT EXISTS wake_events (
        date TEXT PRIMARY KEY, first_step_at TEXT NOT NULL, last_step_at TEXT)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS water_logs (
        id TEXT PRIMARY KEY, date TEXT NOT NULL, logged_at TEXT NOT NULL,
        amount_ml INTEGER NOT NULL)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS todos (
        id TEXT PRIMARY KEY, title TEXT NOT NULL,
        priority TEXT NOT NULL DEFAULT 'medium',
        date TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT, created_at TEXT NOT NULL)''');
    }
    if (oldVersion < 4) {
      try { await db.execute('ALTER TABLE habits ADD COLUMN xp INTEGER NOT NULL DEFAULT 10'); } catch (_) {}
      await db.execute('''CREATE TABLE IF NOT EXISTS user_stats (
        key TEXT PRIMARY KEY, value INTEGER NOT NULL DEFAULT 0)''');
      await db.insert('user_stats', {'key': 'total_xp', 'value': 0},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.execute('''CREATE TABLE IF NOT EXISTS daily_plans (
        date TEXT PRIMARY KEY, intention TEXT NOT NULL,
        committed_at TEXT NOT NULL)''');
    }
    if (oldVersion < 5) {
      // habits: new metadata columns
      try { await db.execute("ALTER TABLE habits ADD COLUMN category TEXT DEFAULT 'general'"); } catch (_) {}
      try { await db.execute('ALTER TABLE habits ADD COLUMN difficulty INTEGER DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE habits ADD COLUMN is_active INTEGER DEFAULT 1'); } catch (_) {}
      try { await db.execute("ALTER TABLE habits ADD COLUMN description TEXT DEFAULT ''"); } catch (_) {}

      // transactions: recurring + SMS support
      try { await db.execute('ALTER TABLE transactions ADD COLUMN is_recurring INTEGER DEFAULT 0'); } catch (_) {}
      try { await db.execute("ALTER TABLE transactions ADD COLUMN recurrence_pattern TEXT DEFAULT ''"); } catch (_) {}
      try { await db.execute('ALTER TABLE transactions ADD COLUMN sms_date TEXT'); } catch (_) {}

      // indexes for transactions
      try { await db.execute('CREATE INDEX idx_transactions_date ON transactions(date)'); } catch (_) {}
      try { await db.execute('CREATE INDEX idx_transactions_category ON transactions(category)'); } catch (_) {}

      // budget limits table
      await db.execute('''CREATE TABLE IF NOT EXISTS budget_limits (
        category TEXT PRIMARY KEY,
        limit_amount REAL NOT NULL,
        alert_threshold REAL DEFAULT 0.8)''');
    }
  }

  // ── Habits ──────────────────────────────────────────────────────────────

  Future<void> insertHabit(Map<String, dynamic> h) async =>
      (await database).insert('habits', h, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, dynamic>>> getHabits() async =>
      (await database).query('habits', orderBy: 'created_at DESC');

  Future<void> updateHabit(String id, String name, String emoji, int xp) async =>
      (await database).update('habits', {'name': name, 'emoji': emoji, 'xp': xp},
          where: 'id = ?', whereArgs: [id]);

  Future<void> deleteHabit(String id) async =>
      (await database).delete('habits', where: 'id = ?', whereArgs: [id]);

  Future<void> logHabit(Map<String, dynamic> log) async =>
      (await database).insert('habit_logs', log, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> unlogHabit(String habitId, String date) async =>
      (await database).delete('habit_logs',
          where: 'habit_id = ? AND date = ?', whereArgs: [habitId, date]);

  Future<List<Map<String, dynamic>>> getLogsForHabit(String habitId) async =>
      (await database).query('habit_logs', where: 'habit_id = ?', whereArgs: [habitId]);

  Future<bool> isHabitLoggedToday(String habitId, String date) async =>
      ((await database).query('habit_logs',
              where: 'habit_id = ? AND date = ?', whereArgs: [habitId, date]))
          .then((r) => r.isNotEmpty);

  Future<List<Map<String, dynamic>>> getAllHabitLogs() async =>
      (await database).query('habit_logs', orderBy: 'date DESC');

  // ── XP / User Stats ──────────────────────────────────────────────────────

  Future<int> getTotalXP() async {
    final rows = await (await database)
        .query('user_stats', where: 'key = ?', whereArgs: ['total_xp']);
    return rows.isEmpty ? 0 : (rows.first['value'] as int);
  }

  Future<void> addXP(int amount) async {
    await (await database).rawUpdate(
        'UPDATE user_stats SET value = value + ? WHERE key = ?',
        [amount, 'total_xp']);
  }

  Future<void> subtractXP(int amount) async {
    await (await database).rawUpdate(
        'UPDATE user_stats SET value = MAX(0, value - ?) WHERE key = ?',
        [amount, 'total_xp']);
  }

  Future<int> getTodayXP(String date) async {
    final db = await database;
    final logs = await db.rawQuery('''
      SELECT h.xp FROM habit_logs hl
      JOIN habits h ON h.id = hl.habit_id
      WHERE hl.date = ?
    ''', [date]);
    return logs.fold<int>(0, (sum, row) => sum + (row['xp'] as int));
  }

  // ── Daily Plans ──────────────────────────────────────────────────────────

  Future<void> setDailyPlan(String date, String intention) async =>
      (await database).insert('daily_plans', {
        'date': date,
        'intention': intention,
        'committed_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Map<String, dynamic>?> getDailyPlan(String date) async {
    final rows = await (await database)
        .query('daily_plans', where: 'date = ?', whereArgs: [date]);
    return rows.isEmpty ? null : rows.first;
  }

  // ── Transactions ─────────────────────────────────────────────────────────

  Future<void> insertTransaction(Map<String, dynamic> txn) async =>
      (await database).insert('transactions', txn,
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, dynamic>>> getTransactions() async =>
      (await database).query('transactions', orderBy: 'date DESC');

  Future<void> updateTransaction(Map<String, dynamic> txn) async =>
      (await database).update('transactions', txn,
          where: 'id = ?', whereArgs: [txn['id']]);

  Future<void> deleteTransaction(String id) async =>
      (await database).delete('transactions', where: 'id = ?', whereArgs: [id]);

  Future<List<Map<String, dynamic>>> getExpensesByCategory(
      String fromDate, String toDate) async {
    final db = await database;
    return db.rawQuery(
      "SELECT category, SUM(amount) as total FROM transactions "
      "WHERE type = 'expense' AND date BETWEEN ? AND ? "
      "GROUP BY category ORDER BY total DESC",
      [fromDate, toDate],
    );
  }

  Future<List<Map<String, dynamic>>> getTransactionsByDateRange(
      String fromDate, String toDate) async {
    final db = await database;
    return db.rawQuery(
      'SELECT * FROM transactions WHERE date BETWEEN ? AND ? ORDER BY date DESC',
      [fromDate, toDate],
    );
  }

  Future<List<Map<String, dynamic>>> searchTransactions(String term) async {
    final db = await database;
    return db.rawQuery(
      "SELECT * FROM transactions WHERE title LIKE ? ORDER BY date DESC",
      ['%$term%'],
    );
  }

  Future<List<Map<String, dynamic>>> getBudgetLimits() async =>
      (await database).query('budget_limits');

  Future<void> setBudgetLimit(String category, double limit,
      {double threshold = 0.8}) async {
    final db = await database;
    await db.rawInsert(
      'INSERT OR REPLACE INTO budget_limits (category, limit_amount, alert_threshold) VALUES (?, ?, ?)',
      [category, limit, threshold],
    );
  }

  Future<List<Map<String, dynamic>>> getRecurringTransactions() async {
    final db = await database;
    return db.rawQuery(
      'SELECT * FROM transactions WHERE is_recurring = 1',
    );
  }

  Future<Map<String, dynamic>> getWaterStreak() async {
    final db = await database;
    // Fetch all dates and their total water intake, ordered ascending
    final rows = await db.rawQuery(
      'SELECT date, SUM(amount_ml) as total FROM water_logs GROUP BY date ORDER BY date ASC',
    );

    if (rows.isEmpty) return {'currentStreak': 0, 'longestStreak': 0};

    // Build a set of dates that met the 2000ml goal
    final goalDates = <DateTime>[];
    for (final row in rows) {
      final total = (row['total'] as num).toInt();
      if (total >= 2000) {
        final parts = (row['date'] as String).split('-');
        goalDates.add(DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])));
      }
    }

    if (goalDates.isEmpty) return {'currentStreak': 0, 'longestStreak': 0};

    goalDates.sort();

    // Calculate longest streak
    int longest = 1;
    int current = 1;
    for (int i = 1; i < goalDates.length; i++) {
      if (goalDates[i].difference(goalDates[i - 1]).inDays == 1) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }

    // Calculate current streak (streak ending today or yesterday)
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    int currentStreak = 0;
    DateTime checkDate = todayNorm;

    // Allow streak to include today or yesterday as the most recent entry
    if (goalDates.last == todayNorm ||
        goalDates.last == todayNorm.subtract(const Duration(days: 1))) {
      checkDate = goalDates.last;
      currentStreak = 1;
      for (int i = goalDates.length - 2; i >= 0; i--) {
        if (checkDate.difference(goalDates[i]).inDays == 1) {
          currentStreak++;
          checkDate = goalDates[i];
        } else {
          break;
        }
      }
    }

    return {'currentStreak': currentStreak, 'longestStreak': longest};
  }

  Future<Map<String, dynamic>> getStepStreak(int goal) async {
    final db = await database;
    // Fetch all step records ordered ascending
    final rows = await db.rawQuery(
      'SELECT date, steps FROM step_records ORDER BY date ASC',
    );

    if (rows.isEmpty) return {'currentStreak': 0, 'longestStreak': 0};

    // Build list of dates that met the goal
    final goalDates = <DateTime>[];
    for (final row in rows) {
      final steps = (row['steps'] as num).toInt();
      if (steps >= goal) {
        final parts = (row['date'] as String).split('-');
        goalDates.add(DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])));
      }
    }

    if (goalDates.isEmpty) return {'currentStreak': 0, 'longestStreak': 0};

    goalDates.sort();

    // Calculate longest streak
    int longest = 1;
    int current = 1;
    for (int i = 1; i < goalDates.length; i++) {
      if (goalDates[i].difference(goalDates[i - 1]).inDays == 1) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }

    // Calculate current streak
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    int currentStreak = 0;
    DateTime checkDate = todayNorm;

    if (goalDates.last == todayNorm ||
        goalDates.last == todayNorm.subtract(const Duration(days: 1))) {
      checkDate = goalDates.last;
      currentStreak = 1;
      for (int i = goalDates.length - 2; i >= 0; i--) {
        if (checkDate.difference(goalDates[i]).inDays == 1) {
          currentStreak++;
          checkDate = goalDates[i];
        } else {
          break;
        }
      }
    }

    return {'currentStreak': currentStreak, 'longestStreak': longest};
  }

  // ── Steps ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getStepRecord(String date) async {
    final rows = await (await database)
        .query('step_records', where: 'date = ?', whereArgs: [date]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertStepRecord(String date, int baseline, int steps) async =>
      (await database).insert('step_records',
          {'date': date, 'baseline': baseline, 'steps': steps},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, dynamic>>> getStepRecords(int days) async =>
      (await database).query('step_records', orderBy: 'date DESC', limit: days);

  // ── Wake Events ──────────────────────────────────────────────────────────

  Future<void> recordWakeEvent(String date, String firstStepAt) async {
    final db = await database;
    final existing =
        await db.query('wake_events', where: 'date = ?', whereArgs: [date]);
    if (existing.isEmpty) {
      await db.insert('wake_events',
          {'date': date, 'first_step_at': firstStepAt});
    } else {
      await db.update('wake_events', {'last_step_at': firstStepAt},
          where: 'date = ?', whereArgs: [date]);
    }
  }

  Future<void> updateLastStepTime(String date, String lastStepAt) async =>
      (await database).update('wake_events', {'last_step_at': lastStepAt},
          where: 'date = ?', whereArgs: [date]);

  Future<List<Map<String, dynamic>>> getWakeEvents(int days) async =>
      (await database).query('wake_events', orderBy: 'date DESC', limit: days);

  // ── Water ────────────────────────────────────────────────────────────────

  Future<void> insertWaterLog(Map<String, dynamic> log) async =>
      (await database).insert('water_logs', log,
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, dynamic>>> getWaterLogs(String date) async =>
      (await database).query('water_logs',
          where: 'date = ?', whereArgs: [date], orderBy: 'logged_at ASC');

  Future<int> getTotalWaterToday(String date) async {
    final logs = await getWaterLogs(date);
    int total = 0;
    for (final l in logs) total += l['amount_ml'] as int;
    return total;
  }

  Future<void> deleteWaterLog(String id) async =>
      (await database).delete('water_logs', where: 'id = ?', whereArgs: [id]);

  Future<List<Map<String, dynamic>>> getWaterLogsByDateRange(
          String from, String to) async =>
      (await database).query('water_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC');

  // ── Todos ────────────────────────────────────────────────────────────────

  Future<void> insertTodo(Map<String, dynamic> todo) async =>
      (await database).insert('todos', todo,
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, dynamic>>> getTodosForDate(String date) async =>
      (await database).query('todos',
          where: 'date = ?', whereArgs: [date], orderBy: 'created_at ASC');

  Future<List<Map<String, dynamic>>> getAllTodos() async =>
      (await database).query('todos', orderBy: 'date DESC, created_at ASC');

  Future<void> updateTodo(Map<String, dynamic> todo) async =>
      (await database).update('todos', todo,
          where: 'id = ?', whereArgs: [todo['id']]);

  Future<void> deleteTodo(String id) async =>
      (await database).delete('todos', where: 'id = ?', whereArgs: [id]);
}

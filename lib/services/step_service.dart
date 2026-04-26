import 'dart:async';
import 'dart:math';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';

class StepService {
  static final StepService instance = StepService._();
  StepService._();

  final _controller = StreamController<int>.broadcast();
  Stream<int> get stepsStream => _controller.stream;

  // Pedometer fallback state
  int _deviceSteps = 0;
  int? _cachedBaseline;
  String? _cachedDate;
  bool _initialized = false;
  bool _wakeRecordedToday = false;

  // Whether Health Connect is available and authorized
  bool _healthConnectAvailable = false;

  static Future<bool> requestPermission() async {
    final status = await Permission.activityRecognition.request();
    return status.isGranted;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Try Health Connect first
    _healthConnectAvailable = await _initHealthConnect();

    if (_healthConnectAvailable) {
      // Read today's steps from Health Connect immediately
      final steps = await _readHealthConnectSteps(_todayStr());
      if (steps != null) {
        _controller.add(steps);
        await _persistSteps(_todayStr(), steps);
      }
      // Still subscribe to pedometer for live updates during the session
      _subscribePedometer(liveOnly: true);
    } else {
      // Health Connect not available — use pedometer as full source
      final granted = await Permission.activityRecognition.isGranted;
      if (!granted) return;
      _subscribePedometer(liveOnly: false);
    }
  }

  Future<bool> _initHealthConnect() async {
    try {
      final health = Health();
      health.configure();

      final types = [HealthDataType.STEPS];
      final permissions = [HealthDataAccess.READ];

      final hasPermissions =
          await health.hasPermissions(types, permissions: permissions);
      if (hasPermissions == true) return true;

      final granted = await health.requestAuthorization(
        types,
        permissions: permissions,
      );
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Read steps from Health Connect for a specific date.
  Future<int?> _readHealthConnectSteps(String dateStr) async {
    try {
      final health = Health();
      final parts = dateStr.split('-');
      final date = DateTime(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      final dataPoints = await health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: startOfDay,
        endTime: endOfDay,
      );

      if (dataPoints.isEmpty) return null;

      // Sum all step intervals for the day
      int total = 0;
      for (final point in dataPoints) {
        final value = point.value;
        if (value is NumericHealthValue) {
          total += value.numericValue.toInt();
        }
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  void _subscribePedometer({required bool liveOnly}) {
    Pedometer.stepCountStream.listen(
      (event) => _onStep(event, liveOnly: liveOnly),
      onError: (_) => _controller.add(_deviceSteps > 0 ? dailySteps : 0),
    );
  }

  Future<void> _onStep(StepCount event, {bool liveOnly = false}) async {
    _deviceSteps = event.steps;
    final today = _todayStr();
    final now = DateTime.now();

    if (liveOnly) {
      // When Health Connect is primary, use pedometer only for delta updates
      // so the live count stays refreshed during the session
      final hcSteps = await _readHealthConnectSteps(today);
      if (hcSteps != null) {
        _controller.add(hcSteps);
        await _persistSteps(today, hcSteps);
        _recordWakeAndSleep(now, today);
        return;
      }
    }

    // Pedometer-only path
    if (_cachedDate != today) {
      _cachedDate = today;
      _wakeRecordedToday = false;
      final db = DatabaseHelper.instance;
      final record = await db.getStepRecord(today);
      if (record == null) {
        _cachedBaseline = _deviceSteps;
        await db.upsertStepRecord(today, _cachedBaseline!, 0);
      } else {
        _cachedBaseline = record['baseline'] as int;
      }
    }

    if (_deviceSteps < (_cachedBaseline ?? 0)) {
      _cachedBaseline = _deviceSteps;
      await DatabaseHelper.instance
          .upsertStepRecord(today, _cachedBaseline!, 0);
    }

    final daily = dailySteps;
    await _persistSteps(today, daily);
    _controller.add(daily);
    _recordWakeAndSleep(now, today);
  }

  Future<void> _persistSteps(String date, int steps) async {
    final db = DatabaseHelper.instance;
    final record = await db.getStepRecord(date);
    final baseline = record?['baseline'] as int? ?? 0;
    await db.upsertStepRecord(date, baseline, steps);
  }

  void _recordWakeAndSleep(DateTime now, String today) async {
    if (!_wakeRecordedToday && now.hour >= 4) {
      _wakeRecordedToday = true;
      await DatabaseHelper.instance
          .recordWakeEvent(today, now.toIso8601String());
    }
    if (now.hour >= 18 || now.hour < 4) {
      await DatabaseHelper.instance
          .updateLastStepTime(today, now.toIso8601String());
    }
  }

  /// Backfill past N days from Health Connect into the DB.
  Future<void> backfillFromHealthConnect({int days = 30}) async {
    if (!_healthConnectAvailable) return;
    final today = DateTime.now();
    for (int i = 1; i <= days; i++) {
      final day = today.subtract(Duration(days: i));
      final dateStr =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final existing = await DatabaseHelper.instance.getStepRecord(dateStr);
      if (existing != null && (existing['steps'] as int) > 0) continue;
      final steps = await _readHealthConnectSteps(dateStr);
      if (steps != null && steps > 0) {
        await DatabaseHelper.instance.upsertStepRecord(dateStr, 0, steps);
      }
    }
  }

  int get dailySteps =>
      max(0, _deviceSteps - (_cachedBaseline ?? _deviceSteps));

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<List<int>> getWeeklySteps(int weekOffset) async {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final currentWeekMonday =
        todayMidnight.subtract(Duration(days: todayMidnight.weekday - 1));
    final targetMonday =
        currentWeekMonday.add(Duration(days: weekOffset * 7));

    final List<int> result = [];
    for (int i = 0; i < 7; i++) {
      final day = targetMonday.add(Duration(days: i));
      final dateStr =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

      // Try Health Connect first, then DB
      int steps = 0;
      if (_healthConnectAvailable) {
        final hcSteps = await _readHealthConnectSteps(dateStr);
        if (hcSteps != null) {
          steps = hcSteps;
          if (steps > 0) {
            await DatabaseHelper.instance.upsertStepRecord(dateStr, 0, steps);
          }
        }
      }
      if (steps == 0) {
        final record = await DatabaseHelper.instance.getStepRecord(dateStr);
        steps = record != null ? (record['steps'] as int) : 0;
      }
      result.add(steps);
    }
    return result;
  }

  Future<Map<String, dynamic>> getWeeklyStats() async {
    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getInt('step_goal') ?? 10000;

    final steps = await getWeeklySteps(0);
    final nonZero = steps.where((s) => s > 0).toList();

    final double weeklyAvg =
        nonZero.isEmpty ? 0.0 : nonZero.reduce((a, b) => a + b) / nonZero.length;
    final int bestDay = steps.isEmpty ? 0 : steps.reduce(max);
    final int daysMetGoal = steps.where((s) => s >= goal).length;

    return {
      'weeklyAvg': weeklyAvg,
      'bestDay': bestDay,
      'daysMetGoal': daysMetGoal,
    };
  }

  bool get isHealthConnectActive => _healthConnectAvailable;
}

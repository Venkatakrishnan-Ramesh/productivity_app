import 'dart:async';
import 'dart:math';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';

class StepService {
  static final StepService instance = StepService._();
  StepService._();

  final _controller = StreamController<int>.broadcast();
  Stream<int> get stepsStream => _controller.stream;

  int _deviceSteps = 0;
  int? _cachedBaseline;
  String? _cachedDate;
  bool _initialized = false;
  bool _wakeRecordedToday = false;

  int get dailySteps => max(0, _deviceSteps - (_cachedBaseline ?? _deviceSteps));

  static Future<bool> requestPermission() async {
    final status = await Permission.activityRecognition.request();
    return status.isGranted;
  }

  Future<void> init() async {
    if (_initialized) return;
    final granted = await Permission.activityRecognition.isGranted;
    if (!granted) return;
    _initialized = true;
    Pedometer.stepCountStream.listen(_onStep, onError: (_) => _controller.add(0));
  }

  Future<void> _onStep(StepCount event) async {
    _deviceSteps = event.steps;
    final today = _todayStr();
    final now = DateTime.now();

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
      await DatabaseHelper.instance.upsertStepRecord(today, _cachedBaseline!, 0);
    }

    // Record first step of the day (wake event) if after 4 AM
    if (!_wakeRecordedToday && now.hour >= 4) {
      _wakeRecordedToday = true;
      await DatabaseHelper.instance.recordWakeEvent(today, now.toIso8601String());
    }

    // Update last step time (proxy for sleep time)
    if (now.hour >= 18 || now.hour < 4) {
      await DatabaseHelper.instance.updateLastStepTime(today, now.toIso8601String());
    }

    final daily = dailySteps;
    await DatabaseHelper.instance.upsertStepRecord(today, _cachedBaseline!, daily);
    _controller.add(daily);
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Returns a list of 7 step counts (Mon–Sun) for the given week offset.
  /// weekOffset 0 = current week, -1 = last week, etc.
  Future<List<int>> getWeeklySteps(int weekOffset) async {
    final now = DateTime.now();
    // Find Monday of the current week
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final currentWeekMonday =
        todayMidnight.subtract(Duration(days: todayMidnight.weekday - 1));
    // Apply offset (each offset unit = 7 days)
    final targetMonday =
        currentWeekMonday.add(Duration(days: weekOffset * 7));

    final List<int> result = [];
    for (int i = 0; i < 7; i++) {
      final day = targetMonday.add(Duration(days: i));
      final dateStr =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final record = await DatabaseHelper.instance.getStepRecord(dateStr);
      result.add(record != null ? (record['steps'] as int) : 0);
    }
    return result;
  }

  /// Returns weekly stats for the current week:
  /// - weeklyAvg: average steps per day (only days that have any steps)
  /// - bestDay: highest step count in the week
  /// - daysMetGoal: number of days where steps >= goal
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
}

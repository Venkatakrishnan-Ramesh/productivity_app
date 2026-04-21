import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _habitChannel = 'habit_reminders';
  static const _morningChannel = 'morning_brief';
  static const _eveningChannel = 'evening_recap';
  static const _waterChannel = 'water_reminders';
  static const _lifestyleChannel = 'lifestyle_tips';
  static const _financeChannel = 'finance_alerts';
  static const _smsChannel = 'sms_transactions';

  Future<void> init() async {
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
    await _createChannels();
  }

  Future<void> requestPermission() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    // Opens system settings so user can grant DND override access
    final dndStatus = await Permission.accessNotificationPolicy.status;
    if (!dndStatus.isGranted) {
      await Permission.accessNotificationPolicy.request();
    }
  }

  Future<void> _createChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    final channels = [
      const AndroidNotificationChannel(_habitChannel, 'Habit Reminders',
          description: 'Daily reminders for your habits',
          importance: Importance.high),
      const AndroidNotificationChannel(_morningChannel, 'Morning Briefing',
          description: 'Daily morning briefing',
          importance: Importance.high),
      const AndroidNotificationChannel(_eveningChannel, 'Evening Recap',
          description: 'Personalized end-of-day summary',
          importance: Importance.high),
      const AndroidNotificationChannel(_waterChannel, 'Water Reminders',
          description: 'Hydration reminders throughout the day',
          importance: Importance.high),
      const AndroidNotificationChannel(_financeChannel, 'Finance Alerts',
          description: 'Daily budget and spending reminders',
          importance: Importance.high),
      const AndroidNotificationChannel(_lifestyleChannel, 'Lifestyle Tips',
          description: 'Bedtime and lifestyle notifications',
          importance: Importance.defaultImportance),
      const AndroidNotificationChannel(_smsChannel, 'SMS Transactions',
          description: 'UPI/GPay transaction alerts from messages',
          importance: Importance.high),
    ];

    for (final ch in channels) {
      await androidPlugin.createNotificationChannel(ch);
    }
  }

  // ── Habit reminders ─────────────────────────────────────────────────────

  Future<void> scheduleDailyHabitReminder({
    required int id,
    required String habitName,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id,
      'Mission Alert ⚡',
      'Agent, "$habitName" is waiting. Lock it in.',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(_habitChannel, 'Habit Reminders',
            channelDescription: 'Daily reminders for your habits',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.reminder),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ── Morning briefing ─────────────────────────────────────────────────────

  Future<void> scheduleMorningBriefing({int hour = 7, int minute = 0}) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      1001,
      'Agent Briefing 🌅',
      'Morning. Set your game plan, lock in your missions.',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(_morningChannel, 'Morning Briefing',
            channelDescription: 'Daily morning briefing',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            color: const Color(0xFFFF9800)),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ── Evening recap ────────────────────────────────────────────────────────

  Future<void> scheduleEveningRecap({int hour = 22, int minute = 0}) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      1002,
      'Mission Debrief 🌟',
      'Agent, check your operational status. How\'d you perform?',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(_eveningChannel, 'Evening Recap',
            channelDescription: 'Personalized end-of-day summary',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            color: const Color(0xFF673AB7)),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ── Bedtime Tamil melody ─────────────────────────────────────────────────

  Future<void> scheduleBedtimeReminder({int hour = 22, int minute = 30}) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      1003,
      'Time to wind down 🌙',
      'Relax with Tamil melodies. Tap for your bedtime playlist.',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(_lifestyleChannel, 'Lifestyle Tips',
            channelDescription: 'Bedtime and lifestyle notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            color: const Color(0xFF1A237E)),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ── Water reminders ──────────────────────────────────────────────────────

  Future<void> scheduleWaterReminders() async {
    final hours = [8, 10, 12, 14, 16, 18, 20];
    for (int i = 0; i < hours.length; i++) {
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hours[i], 0);
      if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

      await _plugin.zonedSchedule(
        2000 + i,
        'Hydration check 💧',
        _waterMessages[i % _waterMessages.length],
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(_waterChannel, 'Water Reminders',
              channelDescription: 'Hydration reminders throughout the day',
              importance: Importance.high, priority: Priority.high,
              category: AndroidNotificationCategory.alarm,
              playSound: true,
              color: const Color(0xFF2196F3)),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  // ── Room cleaning tips ────────────────────────────────────────────────────

  Future<void> scheduleCleaningTips() async {
    for (final tip in _cleaningTips.entries) {
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9, 0);
      if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

      await _plugin.zonedSchedule(
        3000 + tip.key,
        '🧹 Quick clean: ${tip.value['title']}',
        tip.value['desc']!,
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(_lifestyleChannel, 'Lifestyle Tips',
              channelDescription: 'Bedtime and lifestyle notifications',
              importance: Importance.low, priority: Priority.low),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> showEveningMessage(String message) async {
    await _plugin.show(
      1002,
      'Your day in review 🌟',
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(_eveningChannel, 'Evening Recap',
            channelDescription: 'Personalized end-of-day summary',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            styleInformation: BigTextStyleInformation(message),
            color: const Color(0xFF673AB7)),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> showDailyCheckin() async {
    await _plugin.show(
      1010,
      'Hey, how was your day? 🌟',
      'Take a moment — log your mood, review your missions, reflect on the day.',
      NotificationDetails(
        android: AndroidNotificationDetails(_eveningChannel, 'Evening Recap',
            channelDescription: 'Personalized end-of-day summary',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            color: const Color(0xFF673AB7)),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> scheduleDailyCheckin({int hour = 20, int minute = 0}) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      1010,
      'Hey, how was your day? 🌟',
      'Take a moment — log your mood, review your missions, reflect on the day.',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(_eveningChannel, 'Evening Recap',
            channelDescription: 'Personalized end-of-day summary',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            color: const Color(0xFF673AB7)),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ── Midnight new-day nudge ────────────────────────────────────────────────

  Future<void> scheduleMidnightSummary() async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 0, 0);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      1004,
      'Midnight Reset 🌙',
      'Day over, Agent. Streaks reset in hours. Win tomorrow.',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(_eveningChannel, 'Evening Recap',
            channelDescription: 'Personalized end-of-day summary',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            color: const Color(0xFF1A237E)),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ── SMS transaction alerts ───────────────────────────────────────────────

  Future<void> showTransactionDetected({
    required String title,
    required double amount,
    required String type,
  }) async {
    final emoji = type == 'expense' ? '💸' : '💰';
    final label = type == 'expense' ? 'Spent' : 'Received';
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '$emoji New transaction detected',
      '$label ₹${amount.toStringAsFixed(2)} — $title',
      NotificationDetails(
        android: AndroidNotificationDetails(_smsChannel, 'SMS Transactions',
            channelDescription: 'UPI/GPay transaction alerts from messages',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.message,
            playSound: true,
            color: const Color(0xFF4CAF50)),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  // ── Finance alerts ───────────────────────────────────────────────────────

  Future<void> scheduleFinanceSummary({int hour = 21, int minute = 0}) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      1020,
      'Finance Check 💰',
      'Did you log today\'s spending? Stay on top of your budget.',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(_financeChannel, 'Finance Alerts',
            channelDescription: 'Daily budget and spending reminders',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            playSound: true,
            color: const Color(0xFF4CAF50)),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> showFinanceAlert(String title, String body) async {
    await _plugin.show(
      1021,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(_financeChannel, 'Finance Alerts',
            channelDescription: 'Daily budget and spending reminders',
            importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            playSound: true,
            color: const Color(0xFF4CAF50)),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> cancelReminder(int id) async => _plugin.cancel(id);
  Future<void> cancelAll() async => _plugin.cancelAll();

  static const _waterMessages = [
    'Start your morning right — drink a glass of water!',
    'Mid-morning hydration check. Have you had water?',
    'Lunch time — pair your meal with a full glass.',
    'Afternoon slump? Water helps more than coffee.',
    'Keep the hydration going — your body thanks you.',
    'Evening hydration — last push to hit your goal!',
    'Final reminder — finish your water before bed.',
  ];

  static const _cleaningTips = {
    1: {'title': 'Desk & workspace', 'desc': '5 mins: clear desk, wipe surface, organize cables.'},
    2: {'title': 'Bedroom floor', 'desc': 'Quick sweep or vacuum — clothes off the floor!'},
    3: {'title': 'Laundry check', 'desc': 'Any clothes to wash? Do a quick load today.'},
    4: {'title': 'Bathroom wipe-down', 'desc': '3 mins: mirror, sink, countertop — fresh and clean.'},
    5: {'title': 'Trash & clutter', 'desc': 'Take out trash, clear nightstand, declutter one drawer.'},
    6: {'title': 'Bedsheets', 'desc': 'Change or straighten your sheets for better sleep.'},
    7: {'title': 'General tidy', 'desc': '10 min reset — put everything back where it belongs.'},
  };
}

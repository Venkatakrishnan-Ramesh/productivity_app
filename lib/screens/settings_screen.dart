import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/sms_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onThemeToggle;
  final bool isDark;

  const SettingsScreen({
    super.key,
    this.onThemeToggle,
    required this.isDark,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Goals
  int _stepGoal = 10000;
  int _waterGoal = 2000;

  // Notifications
  bool _notifMorning = true;
  int _notifMorningHour = 7;
  bool _notifEvening = true;
  int _notifEveningHour = 22;
  bool _notifCheckin = true;
  int _notifCheckinHour = 20;
  bool _notifWater = true;
  bool _notifFinance = true;
  int _notifFinanceHour = 21;
  bool _notifBedtime = true;

  // Appearance
  late bool _themeDark;

  bool _smsGranted = false;
  PermissionStatus _smsStatus = PermissionStatus.denied;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _themeDark = widget.isDark;
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final smsStatus = await SmsService.permissionStatus();
    setState(() {
      _stepGoal = prefs.getInt('step_goal') ?? 10000;
      _waterGoal = prefs.getInt('water_goal') ?? 2000;
      _notifMorning = prefs.getBool('notif_morning') ?? true;
      _notifMorningHour = prefs.getInt('notif_morning_hour') ?? 7;
      _notifEvening = prefs.getBool('notif_evening') ?? true;
      _notifEveningHour = prefs.getInt('notif_evening_hour') ?? 22;
      _notifCheckin = prefs.getBool('notif_checkin') ?? true;
      _notifCheckinHour = prefs.getInt('notif_checkin_hour') ?? 20;
      _notifWater = prefs.getBool('notif_water') ?? true;
      _notifFinance = prefs.getBool('notif_finance') ?? true;
      _notifFinanceHour = prefs.getInt('notif_finance_hour') ?? 21;
      _notifBedtime = prefs.getBool('notif_bedtime') ?? true;
      _themeDark = prefs.getBool('theme_dark') ?? widget.isDark;
      _smsStatus = smsStatus;
      _smsGranted = smsStatus.isGranted;
      _loading = false;
    });
  }

  Future<void> _requestSmsAccess() async {
    final granted = await SmsService.requestPermission();
    final status = await SmsService.permissionStatus();
    setState(() {
      _smsStatus = status;
      _smsGranted = granted;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted
            ? 'Message access granted for finance import.'
            : 'Message access was not granted. Open app settings if Android has greyed it out.'),
      ),
    );
  }

  Future<void> _openSmsSettings() async {
    await SmsService.openSettings();
    final status = await SmsService.permissionStatus();
    if (!mounted) return;
    setState(() {
      _smsStatus = status;
      _smsGranted = status.isGranted;
    });
  }

  Future<void> _saveStepGoal(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('step_goal', value);
    setState(() => _stepGoal = value);
  }

  Future<void> _saveWaterGoal(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('water_goal', value);
    setState(() => _waterGoal = value);
  }

  Future<void> _saveNotifMorning(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_morning', value);
    setState(() => _notifMorning = value);
    if (value) {
      await NotificationService.instance
          .scheduleMorningBriefing(hour: _notifMorningHour);
    } else {
      await NotificationService.instance.cancelMorningBriefing();
    }
  }

  Future<void> _saveNotifMorningHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_morning_hour', hour);
    setState(() => _notifMorningHour = hour);
    if (_notifMorning) {
      await NotificationService.instance.scheduleMorningBriefing(hour: hour);
    }
  }

  Future<void> _saveNotifEvening(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_evening', value);
    setState(() => _notifEvening = value);
    if (value) {
      await NotificationService.instance
          .scheduleEveningRecap(hour: _notifEveningHour);
    } else {
      await NotificationService.instance.cancelEveningRecap();
    }
  }

  Future<void> _saveNotifEveningHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_evening_hour', hour);
    setState(() => _notifEveningHour = hour);
    if (_notifEvening) {
      await NotificationService.instance.scheduleEveningRecap(hour: hour);
    }
  }

  Future<void> _saveNotifCheckin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_checkin', value);
    setState(() => _notifCheckin = value);
    if (value) {
      await NotificationService.instance
          .scheduleDailyCheckin(hour: _notifCheckinHour);
    } else {
      await NotificationService.instance.cancelDailyCheckin();
    }
  }

  Future<void> _saveNotifCheckinHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_checkin_hour', hour);
    setState(() => _notifCheckinHour = hour);
    if (_notifCheckin) {
      await NotificationService.instance.scheduleDailyCheckin(hour: hour);
    }
  }

  Future<void> _saveNotifWater(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_water', value);
    setState(() => _notifWater = value);
    if (value) {
      await NotificationService.instance.scheduleWaterReminders();
    } else {
      await NotificationService.instance.cancelWaterReminders();
    }
  }

  Future<void> _saveNotifFinance(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_finance', value);
    setState(() => _notifFinance = value);
    if (value) {
      await NotificationService.instance
          .scheduleFinanceSummary(hour: _notifFinanceHour);
    } else {
      await NotificationService.instance.cancelFinanceSummary();
    }
  }

  Future<void> _saveNotifFinanceHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_finance_hour', hour);
    setState(() => _notifFinanceHour = hour);
    if (_notifFinance) {
      await NotificationService.instance.scheduleFinanceSummary(hour: hour);
    }
  }

  Future<void> _saveNotifBedtime(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_bedtime', value);
    setState(() => _notifBedtime = value);
    if (value) {
      await NotificationService.instance.scheduleBedtimeReminder();
    } else {
      await NotificationService.instance.cancelBedtimeReminder();
    }
  }

  Future<void> _saveThemeDark(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_dark', value);
    setState(() => _themeDark = value);
    // Only toggle if state differs from current app theme
    if (value != widget.isDark) {
      widget.onThemeToggle?.call();
    }
  }

  Future<void> _pickHour({
    required BuildContext context,
    required int currentHour,
    required String label,
    required Future<void> Function(int hour) onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentHour, minute: 0),
      helpText: 'Set time for $label',
    );
    if (picked != null) {
      await onPicked(picked.hour);
    }
  }

  String _formatHour(int hour) {
    final tod = TimeOfDay(hour: hour, minute: 0);
    final h = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:00 $period';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        backgroundColor: scheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _sectionHeader(context, 'Goals', Icons.flag_outlined),
                _buildStepGoalTile(scheme),
                _buildWaterGoalTile(scheme),
                const SizedBox(height: 8),
                _sectionHeader(context, 'Data Access', Icons.security_outlined),
                _buildSmsAccessTile(scheme),
                const SizedBox(height: 8),
                _sectionHeader(
                    context, 'Notifications', Icons.notifications_outlined),
                _buildNotifTile(
                  context: context,
                  scheme: scheme,
                  icon: Icons.wb_sunny_outlined,
                  iconColor: Colors.orange,
                  title: 'Morning Briefing',
                  subtitle: 'Daily morning agenda',
                  value: _notifMorning,
                  onChanged: _saveNotifMorning,
                  hour: _notifMorningHour,
                  label: 'Morning Briefing',
                  onHourPicked: _saveNotifMorningHour,
                ),
                _buildNotifTile(
                  context: context,
                  scheme: scheme,
                  icon: Icons.nights_stay_outlined,
                  iconColor: Colors.deepPurple,
                  title: 'Evening Recap',
                  subtitle: 'End-of-day summary',
                  value: _notifEvening,
                  onChanged: _saveNotifEvening,
                  hour: _notifEveningHour,
                  label: 'Evening Recap',
                  onHourPicked: _saveNotifEveningHour,
                ),
                _buildNotifTile(
                  context: context,
                  scheme: scheme,
                  icon: Icons.sentiment_satisfied_alt_outlined,
                  iconColor: Colors.teal,
                  title: 'Daily Check-in',
                  subtitle: 'How was your day?',
                  value: _notifCheckin,
                  onChanged: _saveNotifCheckin,
                  hour: _notifCheckinHour,
                  label: 'Daily Check-in',
                  onHourPicked: _saveNotifCheckinHour,
                ),
                _buildSimpleNotifTile(
                  scheme: scheme,
                  icon: Icons.water_drop_outlined,
                  iconColor: Colors.blue,
                  title: 'Water Reminders',
                  subtitle: 'Hourly hydration nudges',
                  value: _notifWater,
                  onChanged: _saveNotifWater,
                ),
                _buildNotifTile(
                  context: context,
                  scheme: scheme,
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: Colors.green,
                  title: 'Finance Reminder',
                  subtitle: 'Daily budget check',
                  value: _notifFinance,
                  onChanged: _saveNotifFinance,
                  hour: _notifFinanceHour,
                  label: 'Finance Reminder',
                  onHourPicked: _saveNotifFinanceHour,
                ),
                _buildSimpleNotifTile(
                  scheme: scheme,
                  icon: Icons.bedtime_outlined,
                  iconColor: Colors.indigo,
                  title: 'Bedtime Reminder',
                  subtitle: 'Wind-down nudge',
                  value: _notifBedtime,
                  onChanged: _saveNotifBedtime,
                ),
                const SizedBox(height: 8),
                _sectionHeader(context, 'Appearance', Icons.palette_outlined),
                _buildThemeTile(scheme),
                const SizedBox(height: 8),
                _sectionHeader(context, 'About', Icons.info_outlined),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.apps, color: scheme.onPrimaryContainer),
                  ),
                  title: const Text('App Version'),
                  subtitle: const Text('Life OS v1.0.0'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepGoalTile(ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.teal.withOpacity(0.15),
                  child: const Icon(Icons.directions_walk,
                      color: Colors.teal, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Daily Step Goal',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      Text(
                        '${_stepGoal.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} steps',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: _stepGoal.toDouble(),
              min: 1000,
              max: 30000,
              divisions: 29,
              label: _stepGoal.toString(),
              onChanged: (v) => setState(() => _stepGoal = v.round()),
              onChangeEnd: (v) => _saveStepGoal(v.round()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1,000',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text('30,000',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterGoalTile(ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blue.withOpacity(0.15),
                  child: const Icon(Icons.water_drop,
                      color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Daily Water Goal',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      Text(
                        '$_waterGoal ml  (${(_waterGoal / 250).round()} glasses)',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: _waterGoal.toDouble(),
              min: 500,
              max: 4000,
              divisions: 14, // steps of 250
              label: '$_waterGoal ml',
              onChanged: (v) {
                final snapped = (v / 250).round() * 250;
                setState(() => _waterGoal = snapped);
              },
              onChangeEnd: (v) {
                final snapped = (v / 250).round() * 250;
                _saveWaterGoal(snapped);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('500 ml',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text('4,000 ml',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotifTile({
    required BuildContext context,
    required ColorScheme scheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required Future<void> Function(bool) onChanged,
    required int hour,
    required String label,
    required Future<void> Function(int) onHourPicked,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Column(
        children: [
          SwitchListTile(
            secondary: CircleAvatar(
              radius: 18,
              backgroundColor: iconColor.withOpacity(0.15),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            title: Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: Text(subtitle,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            value: value,
            onChanged: onChanged,
          ),
          if (value)
            InkWell(
              onTap: () => _pickHour(
                context: context,
                currentHour: hour,
                label: label,
                onPicked: onHourPicked,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    const SizedBox(width: 52),
                    Icon(Icons.schedule, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Scheduled at ${_formatHour(hour)}',
                      style: TextStyle(color: scheme.primary, fontSize: 13),
                    ),
                    const Spacer(),
                    Icon(Icons.edit_outlined, size: 16, color: scheme.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSimpleNotifTile({
    required ColorScheme scheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: SwitchListTile(
        secondary: CircleAvatar(
          radius: 18,
          backgroundColor: iconColor.withOpacity(0.15),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(subtitle,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSmsAccessTile(ColorScheme scheme) {
    final needsSettings =
        _smsStatus.isPermanentlyDenied || _smsStatus.isRestricted;
    final subtitle = _smsGranted
        ? 'Enabled for UPI/GPay finance imports'
        : needsSettings
            ? 'Android has restricted this permission. Open app settings to enable it.'
            : 'Required to import finance transactions from SMS';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.green.withOpacity(0.15),
          child: const Icon(Icons.sms_outlined, color: Colors.green, size: 20),
        ),
        title: const Text('Message Access',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        trailing: _smsGranted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : FilledButton(
                onPressed: needsSettings ? _openSmsSettings : _requestSmsAccess,
                child: Text(needsSettings ? 'Settings' : 'Allow'),
              ),
      ),
    );
  }

  Widget _buildThemeTile(ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: SwitchListTile(
        secondary: CircleAvatar(
          radius: 18,
          backgroundColor: scheme.primaryContainer,
          child: Icon(
            _themeDark ? Icons.dark_mode : Icons.light_mode,
            color: scheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: const Text('Dark Mode',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(
          _themeDark ? 'Dark theme active' : 'Light theme active',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        value: _themeDark,
        onChanged: _saveThemeDark,
      ),
    );
  }
}

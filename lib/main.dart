import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/dashboard_screen.dart';
import 'screens/today_screen.dart';
import 'screens/habit_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/assistant_screen.dart';
import 'screens/steps_screen.dart';
import 'screens/water_screen.dart';
import 'screens/workout_screen.dart';
import 'services/notification_service.dart';
import 'services/step_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted theme preference before app starts
  final prefs = await SharedPreferences.getInstance();
  final savedThemeDark = prefs.getBool('theme_dark');

  try {
    // init() now calls rescheduleFromPrefs() internally, so we only need
    // to call the notifications that are NOT user-configurable here.
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermission();
    await NotificationService.instance.scheduleMidnightSummary();
    await NotificationService.instance.showDailyCheckin();
  } catch (_) {}

  try {
    await StepService.instance.init();
  } catch (_) {}

  runApp(ProductivityApp(initialThemeDark: savedThemeDark));
}

class ProductivityApp extends StatefulWidget {
  final bool? initialThemeDark;

  const ProductivityApp({super.key, this.initialThemeDark});

  static _ProductivityAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_ProductivityAppState>();

  @override
  State<ProductivityApp> createState() => _ProductivityAppState();
}

class _ProductivityAppState extends State<ProductivityApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    if (widget.initialThemeDark == null) {
      _themeMode = ThemeMode.system;
    } else {
      _themeMode = widget.initialThemeDark! ? ThemeMode.dark : ThemeMode.light;
    }
  }

  void toggleTheme() => setState(() {
        _themeMode =
            _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      });

  bool get isDark => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Life OS',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const MainNav(),
    );
  }
}

class MainNav extends StatefulWidget {
  const MainNav({super.key});

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  int _index = 0;

  final _titles = [
    'Briefing',
    'Mission Control',
    'Missions',
    'Finance',
    'Insights',
    'Training',
  ];

  @override
  Widget build(BuildContext context) {
    final app = ProductivityApp.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_index == 4) // Insights tab — show health submenu
            IconButton(
              icon: const Icon(Icons.favorite_outline),
              tooltip: 'Health',
              onPressed: () => _showHealthSheet(context),
            ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Mini JARVIS',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AssistantScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  isDark: app?.isDark == true,
                  onThemeToggle: () => app?.toggleTheme(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          TodayScreen(),
          HabitScreen(),
          FinanceScreen(),
          InsightsScreen(),
          WorkoutScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Briefing',
          ),
          NavigationDestination(
            icon: Icon(Icons.my_location_outlined),
            selectedIcon: Icon(Icons.my_location),
            label: 'Control',
          ),
          NavigationDestination(
            icon: Icon(Icons.rocket_launch_outlined),
            selectedIcon: Icon(Icons.rocket_launch),
            label: 'Missions',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Finance',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Training',
          ),
        ],
      ),
    );
  }

  void _showHealthSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Health Tracking',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.teal,
                child: Icon(Icons.directions_walk, color: Colors.white),
              ),
              title: const Text('Steps'),
              subtitle: const Text('Track your daily steps'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const StepsScreen()));
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.water_drop, color: Colors.white),
              ),
              title: const Text('Water'),
              subtitle: const Text('Track your hydration'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WaterScreen()));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

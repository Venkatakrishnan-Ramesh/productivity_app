# Life OS — Claude Agent Context

## What this is
Flutter personal productivity app ("Life OS"). Local-first, no backend. Targets Android.

## Repo
- GitHub: `Venkatakrishnan-Ramesh/productivity_app` (branch: `master`)
- CI: GitHub Actions → debug APK build

## Stack
- Flutter + Dart, Material 3
- SQLite (`sqflite`) — all persistent data
- `shared_preferences` — settings/theme
- `fl_chart` — charts in Insights
- `flutter_local_notifications` + `timezone` — scheduled notifications
- `pedometer` — step tracking
- `flutter_sms_inbox` — SMS finance import
- `url_launcher`, `permission_handler`, `uuid`, `intl`

## App structure
```
lib/
  main.dart              # entry point, MainNav (5 tabs), theme toggle
  db/database_helper.dart
  models/               # habit, transaction, todo_item, pattern_insight, level_helper
  screens/              # dashboard, today, habit, finance, insights, assistant, steps, water, settings
  services/             # notification, step, sms, pattern
  data/suits_quotes.dart
  widgets/
```

## Nav tabs
| Index | Label | Screen |
|-------|-------|--------|
| 0 | Briefing | DashboardScreen |
| 1 | Mission Control | TodayScreen |
| 2 | Missions | HabitScreen |
| 3 | Finance | FinanceScreen |
| 4 | Insights | InsightsScreen |

Mini JARVIS (AssistantScreen) + Settings accessible from AppBar.

## Key rules
- Keep everything local-first — no external API calls from app (JARVIS uses on-device or mocked logic)
- Use `sqflite` for any new persistent data
- Follow existing Material 3 theming — respect dark/light via `Theme.of(context)`
- Release signing is configured — don't break `key.properties` / `build.gradle` signing config
- GitHub Actions builds on push to master — keep pubspec.yaml version bumped on meaningful releases

## Local dev
```bash
cd /root/productivity_app
flutter pub get
flutter run                  # needs connected device/emulator
flutter build apk --debug    # debug APK
```

## Modified files (unstaged as of 2026-04-26)
- lib/db/database_helper.dart
- lib/screens/dashboard_screen.dart
- lib/screens/finance_screen.dart

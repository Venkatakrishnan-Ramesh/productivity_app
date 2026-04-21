class LevelHelper {
  static const _levels = [
    {'xp': 0,     'title': 'Rookie',           'num': 1},
    {'xp': 100,   'title': 'Intern',            'num': 2},
    {'xp': 300,   'title': 'Associate',         'num': 3},
    {'xp': 700,   'title': 'Senior Associate',  'num': 4},
    {'xp': 1400,  'title': 'Junior Partner',    'num': 5},
    {'xp': 2500,  'title': 'Partner',           'num': 6},
    {'xp': 4000,  'title': 'Senior Partner',    'num': 7},
    {'xp': 7000,  'title': 'Managing Partner',  'num': 8},
    {'xp': 12000, 'title': 'Harvey Specter',    'num': 9},
  ];

  static String title(int xp) {
    String t = 'Rookie';
    for (final l in _levels) {
      if (xp >= (l['xp'] as int)) t = l['title'] as String;
    }
    return t;
  }

  static int number(int xp) {
    int n = 1;
    for (final l in _levels) {
      if (xp >= (l['xp'] as int)) n = l['num'] as int;
    }
    return n;
  }

  static double progress(int xp) {
    for (int i = 0; i < _levels.length - 1; i++) {
      final start = _levels[i]['xp'] as int;
      final end = _levels[i + 1]['xp'] as int;
      if (xp < end) return (xp - start) / (end - start);
    }
    return 1.0;
  }

  static int xpToNext(int xp) {
    for (int i = 0; i < _levels.length - 1; i++) {
      final end = _levels[i + 1]['xp'] as int;
      if (xp < end) return end - xp;
    }
    return 0;
  }

  static int nextThreshold(int xp) {
    for (int i = 0; i < _levels.length - 1; i++) {
      final end = _levels[i + 1]['xp'] as int;
      if (xp < end) return end;
    }
    return _levels.last['xp'] as int;
  }

  static bool isMaxLevel(int xp) => xp >= (_levels.last['xp'] as int);
}

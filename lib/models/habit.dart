class Habit {
  final String id;
  final String name;
  final String emoji;
  final int xp;
  final String createdAt;
  List<String> logs;
  bool doneToday;
  final String category;
  final int difficulty;
  final bool isActive;
  final String description;

  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    this.xp = 10,
    required this.createdAt,
    this.logs = const [],
    this.doneToday = false,
    this.category = 'general',
    this.difficulty = 1,
    this.isActive = true,
    this.description = '',
  });

  int get streak {
    if (logs.isEmpty) return 0;
    final sorted = [...logs]..sort((a, b) => b.compareTo(a));
    final today = DateTime.now();
    int count = 0;
    for (int i = 0; i < sorted.length; i++) {
      final date = DateTime.parse(sorted[i]);
      final expected = today.subtract(Duration(days: i));
      if (date.year == expected.year &&
          date.month == expected.month &&
          date.day == expected.day) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  int get longestStreak {
    if (logs.isEmpty) return 0;
    final sorted = [...logs]
        .map((s) {
          final d = DateTime.parse(s);
          return DateTime(d.year, d.month, d.day);
        })
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));

    int longest = 1;
    int current = 1;
    for (int i = 1; i < sorted.length; i++) {
      final diff = sorted[i].difference(sorted[i - 1]).inDays;
      if (diff == 1) {
        current++;
        if (current > longest) longest = current;
      } else if (diff > 1) {
        current = 1;
      }
    }
    return longest;
  }

  factory Habit.fromMap(Map<String, dynamic> map, {List<String> logs = const []}) {
    return Habit(
      id: map['id'] as String,
      name: map['name'] as String,
      emoji: map['emoji'] as String,
      xp: (map['xp'] as int?) ?? 10,
      createdAt: map['created_at'] as String,
      logs: logs,
      category: (map['category'] as String?) ?? 'general',
      difficulty: (map['difficulty'] as int?) ?? 1,
      isActive: ((map['is_active'] as int?) ?? 1) == 1,
      description: (map['description'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'xp': xp,
        'created_at': createdAt,
        'category': category,
        'difficulty': difficulty,
        'is_active': isActive ? 1 : 0,
        'description': description,
      };
}

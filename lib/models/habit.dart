class Habit {
  final String id;
  final String name;
  final String emoji;
  final int xp;
  final String createdAt;
  List<String> logs;
  bool doneToday;

  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    this.xp = 10,
    required this.createdAt,
    this.logs = const [],
    this.doneToday = false,
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'xp': xp,
        'created_at': createdAt,
      };
}

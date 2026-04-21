class TodoItem {
  final String id;
  final String title;
  final String priority; // 'high', 'medium', 'low'
  final String date; // YYYY-MM-DD
  final bool completed;
  final String? completedAt;
  final String createdAt;

  const TodoItem({
    required this.id,
    required this.title,
    required this.priority,
    required this.date,
    required this.completed,
    this.completedAt,
    required this.createdAt,
  });

  bool get isOverdue =>
      !completed &&
      DateTime.parse(date).isBefore(DateTime.now().subtract(const Duration(days: 1)));

  TodoItem copyWith({bool? completed, String? completedAt}) => TodoItem(
        id: id,
        title: title,
        priority: priority,
        date: date,
        completed: completed ?? this.completed,
        completedAt: completedAt ?? this.completedAt,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'priority': priority,
        'date': date,
        'completed': completed ? 1 : 0,
        'completed_at': completedAt,
        'created_at': createdAt,
      };

  static TodoItem fromMap(Map<String, dynamic> m) => TodoItem(
        id: m['id'],
        title: m['title'],
        priority: m['priority'],
        date: m['date'],
        completed: m['completed'] == 1,
        completedAt: m['completed_at'],
        createdAt: m['created_at'],
      );
}

enum InsightType { wakeTime, sleepTime, habits, spending, activity, water, productivity, lifestyle }

class PatternInsight {
  final String emoji;
  final String title;
  final String description;
  final double confidence; // 0.0 to 1.0
  final InsightType type;
  final bool isPositive;

  const PatternInsight({
    required this.emoji,
    required this.title,
    required this.description,
    required this.confidence,
    required this.type,
    this.isPositive = true,
  });

  String get confidenceLabel {
    if (confidence >= 0.8) return 'Strong pattern';
    if (confidence >= 0.6) return 'Emerging pattern';
    return 'Early signal';
  }
}

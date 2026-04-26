enum WorkoutMode { appSuggested, trainerAssigned, custom }

class WorkoutPlan {
  final String id;
  final String name;
  final WorkoutMode mode;
  final int workoutsPerWeek;
  final int cardioPerWeek;
  final int stepTarget;
  final String createdAt;
  final bool isActive;
  List<WorkoutDay> days;

  WorkoutPlan({
    required this.id,
    required this.name,
    required this.mode,
    this.workoutsPerWeek = 4,
    this.cardioPerWeek = 3,
    this.stepTarget = 10000,
    required this.createdAt,
    this.isActive = true,
    this.days = const [],
  });

  factory WorkoutPlan.fromMap(Map<String, dynamic> m) => WorkoutPlan(
        id: m['id'] as String,
        name: m['name'] as String,
        mode: WorkoutMode.values.firstWhere(
          (e) => e.name == m['mode'],
          orElse: () => WorkoutMode.appSuggested,
        ),
        workoutsPerWeek: m['workouts_per_week'] as int? ?? 4,
        cardioPerWeek: m['cardio_per_week'] as int? ?? 3,
        stepTarget: m['step_target'] as int? ?? 10000,
        createdAt: m['created_at'] as String,
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'mode': mode.name,
        'workouts_per_week': workoutsPerWeek,
        'cardio_per_week': cardioPerWeek,
        'step_target': stepTarget,
        'created_at': createdAt,
        'is_active': isActive ? 1 : 0,
      };

  WorkoutPlan copyWith({
    String? name,
    WorkoutMode? mode,
    int? workoutsPerWeek,
    int? cardioPerWeek,
    int? stepTarget,
    bool? isActive,
    List<WorkoutDay>? days,
  }) =>
      WorkoutPlan(
        id: id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        workoutsPerWeek: workoutsPerWeek ?? this.workoutsPerWeek,
        cardioPerWeek: cardioPerWeek ?? this.cardioPerWeek,
        stepTarget: stepTarget ?? this.stepTarget,
        createdAt: createdAt,
        isActive: isActive ?? this.isActive,
        days: days ?? this.days,
      );
}

class WorkoutDay {
  final String id;
  final String planId;
  final String dayName;
  final String focus;
  final int sortOrder;
  List<Exercise> exercises;

  WorkoutDay({
    required this.id,
    required this.planId,
    required this.dayName,
    this.focus = '',
    this.sortOrder = 0,
    this.exercises = const [],
  });

  factory WorkoutDay.fromMap(Map<String, dynamic> m) => WorkoutDay(
        id: m['id'] as String,
        planId: m['plan_id'] as String,
        dayName: m['day_name'] as String,
        focus: m['focus'] as String? ?? '',
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'plan_id': planId,
        'day_name': dayName,
        'focus': focus,
        'sort_order': sortOrder,
      };

  WorkoutDay copyWith({
    String? dayName,
    String? focus,
    int? sortOrder,
    List<Exercise>? exercises,
  }) =>
      WorkoutDay(
        id: id,
        planId: planId,
        dayName: dayName ?? this.dayName,
        focus: focus ?? this.focus,
        sortOrder: sortOrder ?? this.sortOrder,
        exercises: exercises ?? this.exercises,
      );
}

class Exercise {
  final String id;
  final String dayId;
  final String name;
  final int sets;
  final String reps;
  final double? weightKg;
  final int restSeconds;
  final String notes;
  final String targetMuscle;
  final int sortOrder;

  Exercise({
    required this.id,
    required this.dayId,
    required this.name,
    this.sets = 3,
    this.reps = '8-12',
    this.weightKg,
    this.restSeconds = 60,
    this.notes = '',
    this.targetMuscle = '',
    this.sortOrder = 0,
  });

  factory Exercise.fromMap(Map<String, dynamic> m) => Exercise(
        id: m['id'] as String,
        dayId: m['day_id'] as String,
        name: m['name'] as String,
        sets: m['sets'] as int? ?? 3,
        reps: m['reps'] as String? ?? '8-12',
        weightKg: (m['weight_kg'] as num?)?.toDouble(),
        restSeconds: m['rest_seconds'] as int? ?? 60,
        notes: m['notes'] as String? ?? '',
        targetMuscle: m['target_muscle'] as String? ?? '',
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'day_id': dayId,
        'name': name,
        'sets': sets,
        'reps': reps,
        'weight_kg': weightKg,
        'rest_seconds': restSeconds,
        'notes': notes,
        'target_muscle': targetMuscle,
        'sort_order': sortOrder,
      };

  Exercise copyWith({
    String? name,
    int? sets,
    String? reps,
    double? weightKg,
    bool clearWeight = false,
    int? restSeconds,
    String? notes,
    String? targetMuscle,
    int? sortOrder,
  }) =>
      Exercise(
        id: id,
        dayId: dayId,
        name: name ?? this.name,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
        restSeconds: restSeconds ?? this.restSeconds,
        notes: notes ?? this.notes,
        targetMuscle: targetMuscle ?? this.targetMuscle,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class TrainerNote {
  final String id;
  final String category;
  final String content;
  final String createdAt;
  final String? nextReviewDate;

  TrainerNote({
    required this.id,
    required this.category,
    required this.content,
    required this.createdAt,
    this.nextReviewDate,
  });

  factory TrainerNote.fromMap(Map<String, dynamic> m) => TrainerNote(
        id: m['id'] as String,
        category: m['category'] as String? ?? 'general',
        content: m['content'] as String,
        createdAt: m['created_at'] as String,
        nextReviewDate: m['next_review_date'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category,
        'content': content,
        'created_at': createdAt,
        'next_review_date': nextReviewDate,
      };
}

class WeeklyCheckIn {
  final String id;
  final String weekStart;
  final double? weightKg;
  final double? waistCm;
  final int? energyLevel;
  final int workoutsCompleted;
  final int cardioCompleted;
  final String notes;
  final String createdAt;

  WeeklyCheckIn({
    required this.id,
    required this.weekStart,
    this.weightKg,
    this.waistCm,
    this.energyLevel,
    this.workoutsCompleted = 0,
    this.cardioCompleted = 0,
    this.notes = '',
    required this.createdAt,
  });

  factory WeeklyCheckIn.fromMap(Map<String, dynamic> m) => WeeklyCheckIn(
        id: m['id'] as String,
        weekStart: m['week_start'] as String,
        weightKg: (m['weight_kg'] as num?)?.toDouble(),
        waistCm: (m['waist_cm'] as num?)?.toDouble(),
        energyLevel: m['energy_level'] as int?,
        workoutsCompleted: m['workouts_completed'] as int? ?? 0,
        cardioCompleted: m['cardio_completed'] as int? ?? 0,
        notes: m['notes'] as String? ?? '',
        createdAt: m['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'week_start': weekStart,
        'weight_kg': weightKg,
        'waist_cm': waistCm,
        'energy_level': energyLevel,
        'workouts_completed': workoutsCompleted,
        'cardio_completed': cardioCompleted,
        'notes': notes,
        'created_at': createdAt,
      };
}

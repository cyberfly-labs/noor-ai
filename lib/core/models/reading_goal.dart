class ReadingGoal {
  const ReadingGoal({
    required this.id,
    required this.goalType,
    required this.target,
    this.startDate,
    this.endDate,
    this.createdAt,
    this.updatedAt,
    this.status,
  });

  final String id;
  final String goalType;
  final int target;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? status;

  String get goalTypeLabel {
    switch (goalType.trim().toLowerCase()) {
      case 'chapters':
      case 'chapter':
        return 'Chapters';
      case 'juzs':
      case 'juz':
        return 'Juz';
      case 'pages':
      case 'page':
      default:
        return 'Pages';
    }
  }

  bool get isActive {
    final normalizedStatus = status?.trim().toLowerCase();
    if (normalizedStatus == null || normalizedStatus.isEmpty) {
      return true;
    }
    return normalizedStatus != 'completed' &&
        normalizedStatus != 'archived' &&
        normalizedStatus != 'inactive';
  }

  factory ReadingGoal.fromJson(Map<String, dynamic> json) {
    return ReadingGoal(
      id: _firstString(json, const <String>[
            'id',
            'goal_id',
            'goalId',
          ]) ??
          '',
      goalType: _firstString(json, const <String>[
            'goal_type',
            'goalType',
            'type',
          ]) ??
          'pages',
      target: _firstInt(json, const <String>[
            'target',
            'target_count',
            'targetCount',
            'amount',
          ]) ??
          0,
      startDate: _firstDate(json, const <String>[
        'start_date',
        'startDate',
      ]),
      endDate: _firstDate(json, const <String>[
        'end_date',
        'endDate',
        'deadline',
      ]),
      createdAt: _firstDate(json, const <String>[
        'created_at',
        'createdAt',
      ]),
      updatedAt: _firstDate(json, const <String>[
        'updated_at',
        'updatedAt',
      ]),
      status: _firstString(json, const <String>[
        'status',
        'state',
      ]),
    );
  }
}

class ReadingGoalProgress {
  const ReadingGoalProgress({
    this.goalId,
    required this.goalType,
    required this.completed,
    required this.target,
    required this.progress,
    required this.remaining,
    required this.onTrack,
    this.recordedAt,
  });

  final String? goalId;
  final String goalType;
  final int completed;
  final int target;
  final double progress;
  final int remaining;
  final bool onTrack;
  final DateTime? recordedAt;

  String get goalTypeLabel {
    switch (goalType.trim().toLowerCase()) {
      case 'chapters':
      case 'chapter':
        return 'chapters';
      case 'juzs':
      case 'juz':
        return 'juz';
      case 'pages':
      case 'page':
      default:
        return 'pages';
    }
  }

  String get summaryLabel {
    if (target <= 0) {
      return '$completed completed';
    }
    return '$completed / $target $goalTypeLabel';
  }

  factory ReadingGoalProgress.fromJson(
    Map<String, dynamic> json, {
    ReadingGoal? goal,
  }) {
    final completed = _firstInt(json, const <String>[
          'completed',
          'completed_count',
          'completedCount',
          'progress',
          'current',
          'count',
        ]) ??
        0;
    final target = _firstInt(json, const <String>[
          'target',
          'target_count',
          'targetCount',
        ]) ??
        goal?.target ??
        0;
    final rawProgress = _firstDouble(json, const <String>[
      'completion',
      'completion_percent',
      'completionPercent',
      'progress_percent',
      'progressPercent',
    ]);
    final normalizedProgress = target <= 0
        ? (rawProgress ?? 0).clamp(0, 1).toDouble()
        : (rawProgress == null
            ? (completed / target)
            : rawProgress > 1
                ? rawProgress / 100
                : rawProgress)
            .clamp(0, 1)
            .toDouble();
    final remaining = target <= 0 ? 0 : (target - completed).clamp(0, target);

    return ReadingGoalProgress(
      goalId: _firstString(json, const <String>[
            'goal_id',
            'goalId',
            'id',
          ]) ??
          goal?.id,
      goalType: _firstString(json, const <String>[
            'goal_type',
            'goalType',
            'type',
          ]) ??
          goal?.goalType ??
          'pages',
      completed: completed,
      target: target,
      progress: normalizedProgress,
      remaining: remaining,
      onTrack: _firstBool(json, const <String>[
            'on_track',
            'onTrack',
            'is_on_track',
          ]) ??
          (target > 0 ? completed >= target : false),
      recordedAt: _firstDate(json, const <String>[
        'date',
        'recorded_at',
        'recordedAt',
        'updated_at',
        'updatedAt',
      ]),
    );
  }
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

int? _firstInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

double? _firstDouble(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

bool? _firstBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
  }
  return null;
}

DateTime? _firstDate(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}
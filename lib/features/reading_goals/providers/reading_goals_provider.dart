import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/reading_goal.dart';
import '../../../core/services/quran_user_sync_service.dart';

class ReadingGoalsState {
  const ReadingGoalsState({
    this.activeGoal,
    this.todayProgress,
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  final ReadingGoal? activeGoal;
  final ReadingGoalProgress? todayProgress;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  ReadingGoalsState copyWith({
    ReadingGoal? activeGoal,
    ReadingGoalProgress? todayProgress,
    bool? isLoading,
    bool? isSaving,
    Object? error = _unset,
  }) {
    return ReadingGoalsState(
      activeGoal: activeGoal ?? this.activeGoal,
      todayProgress: todayProgress ?? this.todayProgress,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  static const Object _unset = Object();
}

class ReadingGoalsNotifier extends StateNotifier<ReadingGoalsState> {
  ReadingGoalsNotifier() : super(const ReadingGoalsState());

  final QuranUserSyncService _sync = QuranUserSyncService.instance;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }

    if (!await _sync.isReadyForSync) {
      state = const ReadingGoalsState();
      return;
    }

    final goal = await _sync.fetchActiveReadingGoal();
    final progress = await _sync.fetchTodayGoalProgress(goal: goal);
    final error = _sync.lastGoalError;

    state = ReadingGoalsState(
      activeGoal: goal,
      todayProgress: progress,
      isLoading: false,
      isSaving: false,
      error: error,
    );
  }

  Future<bool> createGoal({
    required String type,
    required int target,
    required DateTime deadline,
  }) async {
    state = state.copyWith(isSaving: true, error: null);
    final goal = await _sync.createReadingGoal(
      type: type,
      target: target,
      deadline: deadline,
    );
    if (goal == null) {
      state = state.copyWith(
        isSaving: false,
        error: _sync.lastGoalError ?? 'Could not create reading goal.',
      );
      return false;
    }

    await load(silent: true);
    state = state.copyWith(isSaving: false, error: null);
    return true;
  }

  Future<bool> updateGoal({
    required ReadingGoal goal,
    required String type,
    required int target,
    required DateTime deadline,
  }) async {
    state = state.copyWith(isSaving: true, error: null);
    final nextGoal = await _sync.updateReadingGoal(
      goalId: goal.id,
      type: type,
      target: target,
      deadline: deadline,
    );
    if (nextGoal == null) {
      state = state.copyWith(
        isSaving: false,
        error: _sync.lastGoalError ?? 'Could not update reading goal.',
      );
      return false;
    }

    await load(silent: true);
    state = state.copyWith(isSaving: false, error: null);
    return true;
  }

  Future<bool> deleteGoal(String goalId) async {
    state = state.copyWith(isSaving: true, error: null);
    final success = await _sync.deleteReadingGoal(goalId);
    if (!success) {
      state = state.copyWith(
        isSaving: false,
        error: _sync.lastGoalError ?? 'Could not delete reading goal.',
      );
      return false;
    }

    await load(silent: true);
    state = state.copyWith(isSaving: false, error: null);
    return true;
  }
}

final readingGoalsProvider =
    StateNotifierProvider<ReadingGoalsNotifier, ReadingGoalsState>((ref) {
  return ReadingGoalsNotifier();
});
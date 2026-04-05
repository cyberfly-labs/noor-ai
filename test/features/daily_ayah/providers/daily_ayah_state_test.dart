import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/features/daily_ayah/providers/daily_ayah_provider.dart';

void main() {
  group('DailyAyahState.copyWith', () {
    test('clears nullable fields when explicitly set to null', () {
      const initial = DailyAyahState(
        reflection: 'A short reflection',
        explanation: 'A generated explanation',
        isExplaining: true,
      );

      final next = initial.copyWith(
        reflection: null,
        explanation: null,
        isExplaining: false,
      );

      expect(next.reflection, isNull);
      expect(next.explanation, isNull);
      expect(next.isExplaining, isFalse);
    });

    test('preserves nullable fields when omitted', () {
      const initial = DailyAyahState(
        reflection: 'A short reflection',
        explanation: 'A generated explanation',
      );

      final next = initial.copyWith(isLoading: true);

      expect(next.reflection, initial.reflection);
      expect(next.explanation, initial.explanation);
      expect(next.isLoading, isTrue);
    });
  });
}
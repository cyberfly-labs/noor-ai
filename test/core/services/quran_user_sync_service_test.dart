import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/services/quran_user_sync_service.dart';

void main() {
  group('buildQuranReflectPostPayload', () {
    test('omits room-only fields for standard reflections', () {
      final payload = buildQuranReflectPostPayload(
        body: 'Reflection body',
        verseKeys: const <String>[],
        publishedAt: DateTime.utc(2026, 4, 10, 12),
      );

      final post = payload['post'] as Map<String, dynamic>;

      expect(post['body'], 'Reflection body');
      expect(post['draft'], isFalse);
      expect(post.containsKey('roomPostStatus'), isFalse);
      expect(post.containsKey('roomId'), isFalse);
      expect(post['publishedAt'], '2026-04-10T12:00:00.000Z');
    });

    test('keeps only valid verse references', () {
      final payload = buildQuranReflectPostPayload(
        body: 'Reflection body',
        verseKeys: const <String>['2:255', 'bad', '0:5', '3:7'],
        publishedAt: DateTime.utc(2026, 4, 10, 12),
      );

      final post = payload['post'] as Map<String, dynamic>;
      final references = post['references'] as List<dynamic>;

      expect(references, hasLength(2));
      expect(references.first, <String, dynamic>{
        'chapterId': 2,
        'from': 255,
        'to': 255,
      });
      expect(references.last, <String, dynamic>{
        'chapterId': 3,
        'from': 7,
        'to': 7,
      });
    });
  });
}

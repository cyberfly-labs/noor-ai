import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/services/quran_user_session_service.dart';

void main() {
  group('QuranUserAuthConfig scope normalization', () {
    test('default scope includes only the supported post scope', () {
      expect(QuranUserAuthConfig.defaultScope, contains('post'));
      expect(QuranUserAuthConfig.defaultScope, isNot(contains('post.create')));
      expect(QuranUserAuthConfig.defaultScope, isNot(contains('post.read')));
      expect(QuranUserAuthConfig.defaultScope, isNot(contains('post.delete')));
    });

    test('normalizeScope drops unsupported granular post scopes', () {
      final normalized = QuranUserAuthConfig.normalizeScope(
        'post post.create post.read post.delete offline_access invalid_scope post',
      );

      expect(normalized, 'post offline_access');
    });

    test('withRequiredScopes appends only the supported post scope', () {
      final normalized = QuranUserAuthConfig.withRequiredScopes(
        'offline_access bookmark post.create post.read post.delete',
      );

      expect(normalized, contains('post'));
      expect(normalized, isNot(contains('post.create')));
      expect(normalized, isNot(contains('post.read')));
      expect(normalized, isNot(contains('post.delete')));
    });
  });
}

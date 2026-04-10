import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/services/model_manager.dart';

void main() {
  group('ModelManager.parseRemoteFileSizeFromHeaders', () {
    test('prefers total size from content-range for partial responses', () {
      final size = ModelManager.parseRemoteFileSizeFromHeaders(
        contentRange: 'bytes 512-1023/4096',
        contentLength: '512',
        linkedSize: null,
      );

      expect(size, 4096);
    });

    test('falls back to x-linked-size then content-length', () {
      expect(
        ModelManager.parseRemoteFileSizeFromHeaders(
          contentRange: null,
          contentLength: '128',
          linkedSize: '256',
        ),
        256,
      );

      expect(
        ModelManager.parseRemoteFileSizeFromHeaders(
          contentRange: null,
          contentLength: '128',
          linkedSize: null,
        ),
        128,
      );
    });

    test('parses total size from 416 content-range header', () {
      final size = ModelManager.parseRemoteFileSizeFromHeaders(
        contentRange: 'bytes */4096',
        contentLength: null,
        linkedSize: null,
      );

      expect(size, 4096);
    });
  });

  group('ModelManager.resolveResumePlan', () {
    test('appends when server honors requested range', () {
      final plan = ModelManager.resolveResumePlan(
        existingBytes: 1024,
        statusCode: 206,
        contentRange: 'bytes 1024-2047/4096',
      );

      expect(plan.shouldAppend, isTrue);
      expect(plan.startingBytes, 1024);
    });

    test('restarts when server ignores range and returns full response', () {
      final plan = ModelManager.resolveResumePlan(
        existingBytes: 1024,
        statusCode: 200,
        contentRange: null,
      );

      expect(plan.shouldAppend, isFalse);
      expect(plan.startingBytes, 0);
    });

    test('restarts when server responds from byte zero', () {
      final plan = ModelManager.resolveResumePlan(
        existingBytes: 1024,
        statusCode: 206,
        contentRange: 'bytes 0-2047/4096',
      );

      expect(plan.shouldAppend, isFalse);
      expect(plan.startingBytes, 0);
    });

    test('throws for unexpected resume offsets', () {
      expect(
        () => ModelManager.resolveResumePlan(
          existingBytes: 1024,
          statusCode: 206,
          contentRange: 'bytes 1536-2047/4096',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ModelManager.resolveRangeNotSatisfiableAction', () {
    test('recovers a completed partial when 416 matches total bytes', () {
      final action = ModelManager.resolveRangeNotSatisfiableAction(
        existingBytes: 4096,
        contentRange: 'bytes */4096',
      );

      expect(action, ModelDownloadRangeErrorAction.completePartial);
    });

    test('restarts when 416 indicates the stored offset is stale', () {
      final action = ModelManager.resolveRangeNotSatisfiableAction(
        existingBytes: 8192,
        contentRange: 'bytes */4096',
      );

      expect(action, ModelDownloadRangeErrorAction.restartDownload);
    });
  });
}

import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

void main() {
  test('blob replay reproduces the same failure', () async {
    String? reproduceBlob;

    // The body under test — extracted so both runs use the same function
    void body(TestCase tc) {
      final v = tc.draw(integers(min: 0, max: 1000));
      if (v >= 500) {
        throw StateError('Value too large');
      }
    }

    // Run a property that intentionally fails
    final runner1 = HegelRunner();
    try {
      await runner1.run(body, testCases: 100);
      fail('Expected test to fail');
    } on HegelTestFailure catch (e) {
      // Extract reproduce blob from new format: reproduce: 'BLOB'
      final reproduceMatch = RegExp(
        r"reproduce: '([^']+)'",
      ).firstMatch(e.message);
      expect(
        reproduceMatch,
        isNotNull,
        reason: 'Should contain reproduce blob',
      );
      reproduceBlob = reproduceMatch!.group(1);
      // Verify the original failure is a property failure
      expect(e.message, contains('Property failed'));
    }

    // Now replay using the blob — should fail with the same error
    final runner2 = HegelRunner();
    try {
      await runner2.run(body, reproduceBlob: reproduceBlob!);
      fail('Replay should also fail');
    } on HegelTestFailure catch (e) {
      // Blob replay now wraps the error with counterexample context.
      expect(e.message, contains('Value too large'));
      expect(e.message, contains('Counterexample'));
    }
  });

  test('nondeterministic blob replay retries and reports caveat', () async {
    var attempts = 0;
    final result = await HegelRunner().runWithResult(
      (tc) {
        attempts++;
        final v = tc.draw(integers(min: 0, max: 100));
        if (v >= 10 && attempts.isEven) {
          throw StateError('flaky failure');
        }
      },
      verbosity: Verbosity.quiet,
      testCases: 50,
      seed: 42,
      database: false,
    );

    expect(result.status, equals(RunStatus.failed));
    final blob = result.failures.first.reproductionBlob;
    expect(blob, isNotEmpty);
    expect(result.failures.first.message, contains('Caveat:'));

    var replayAttempts = 0;
    final replayResult = await HegelRunner().runWithResult(
      (tc) {
        replayAttempts++;
        final v = tc.draw(integers(min: 0, max: 100));
        if (v >= 10 && replayAttempts >= 2) {
          throw StateError('replayed flaky failure');
        }
      },
      reproduceBlob: blob,
      database: false,
    );

    expect(replayResult.status, equals(RunStatus.failed));
    expect(replayResult.testCasesRun, greaterThanOrEqualTo(2));
    expect(replayResult.failures.first.reproductionBlob, equals(blob));
    expect(
      replayResult.failures.first.message,
      allOf(contains('replayed flaky failure'), contains('Caveat:')),
    );
  });

  test(
    'non-reproducing blob replay ignores coverage variation across replay attempts',
    () async {
      final failResult = await HegelRunner().runWithResult(
        (tc) {
          final v = tc.draw(integers(min: 0, max: 100));
          if (v >= 50) {
            throw StateError('boom');
          }
        },
        testCases: 50,
        seed: 7,
        database: false,
      );
      expect(failResult.status, equals(RunStatus.failed));
      final blob = failResult.failures.first.reproductionBlob;
      expect(blob, isNotEmpty);

      var replayCalls = 0;
      final replayResult = await HegelRunner().runWithResult(
        (tc) {
          replayCalls++;
          tc.draw(integers(min: 0, max: 100));
          tc.cover(100.0, replayCalls == 1, 'only-first-attempt');
        },
        reproduceBlob: blob,
        database: false,
      );
      expect(replayResult.status, equals(RunStatus.passed));
      expect(replayResult.failures, isEmpty);
    },
  );
}

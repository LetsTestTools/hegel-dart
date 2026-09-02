import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  group('runHegelTest', () {
    test('returns RunStatus.passed for passing property', () async {
      final result = await runHegelTest((tc) {
        final a = tc.draw(integers());
        final b = tc.draw(integers());
        expect(a + b, equals(b + a));
      });

      expect(result.status, equals(RunStatus.passed));
      expect(result.testCasesRun, greaterThan(0));
      expect(result.failures, isEmpty);
    });

    test(
      'returns RunStatus.failed and populates failures for failing property',
      () async {
        final result = await runHegelTest((tc) {
          final a = tc.draw(integers());
          if (a < 0) {
            throw Exception('No negative numbers allowed!');
          }
        });

        expect(result.status, equals(RunStatus.failed));
        expect(result.testCasesRun, greaterThan(0));
        expect(result.failures, isNotEmpty);

        final failure = result.failures.first;
        expect(failure.message, contains('No negative numbers allowed!'));
        expect(failure.reproductionBlob, isNotEmpty);
        expect(failure.origin, isNotNull);
      },
    );

    test('reproduce blob replays a specific test case', () async {
      // First, get a failure to capture a blob.
      // Use a condition that will reliably fail (integers can be negative).
      final firstResult = await runHegelTest((tc) {
        final a = tc.draw(integers());
        if (a < 0) {
          throw Exception('Negative found!');
        }
      });

      expect(firstResult.status, equals(RunStatus.failed));
      final blob = firstResult.failures.first.reproductionBlob;
      expect(blob, isNotEmpty);

      // Replay the exact blob — should reproduce the same failure.
      final replayResult = await runHegelTest((tc) {
        final a = tc.draw(integers());
        if (a < 0) {
          throw Exception('Negative found on replay!');
        }
      }, reproduce: blob);

      expect(replayResult.status, equals(RunStatus.failed));
      expect(
        replayResult.failures.first.message,
        contains('Negative found on replay!'),
      );
    });
  });
}

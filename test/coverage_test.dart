import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  group('TestCase.classify', () {
    test('records observations conditionally', () async {
      final result = await runHegelTest((tc) {
        final x = tc.draw(integers(min: -10, max: 10));
        tc.classify(x < 0, 'negative');
        tc.classify(x == 0, 'zero');
        tc.classify(x > 0, 'positive');
      }, testCases: 50);

      expect(result.status, equals(RunStatus.passed));
      final counts = result.statistics[''] ?? {};
      expect(counts.keys, anyElement('negative'));
      expect(counts.keys, anyElement('positive'));
      // The sum of classified counts should match valid cases
      final total = counts.values.fold<int>(0, (sum, c) => sum + c);
      expect(total, equals(result.testCasesRun));
    });

    test('supports custom labels', () async {
      final result = await runHegelTest((tc) {
        final list = tc.draw(lists(integers(), minSize: 0, maxSize: 10));
        tc.classify(list.isEmpty, 'empty', label: 'shape');
        tc.classify(list.isNotEmpty, 'non-empty', label: 'shape');
      }, testCases: 30);

      expect(result.status, equals(RunStatus.passed));
      expect(result.statistics.containsKey('shape'), isTrue);
      final shapeCounts = result.statistics['shape']!;
      expect(
        shapeCounts.containsKey('empty') ||
            shapeCounts.containsKey('non-empty'),
        isTrue,
      );
    });
  });

  group('TestCase.cover', () {
    test('passes when coverage target is satisfied', () async {
      final result = await runHegelTest((tc) {
        final x = tc.draw(integers(min: 0, max: 9));
        // >= 0 always holds (100% >= 80%)
        tc.cover(80.0, x >= 0, 'non-negative');
      }, testCases: 50);

      expect(result.status, equals(RunStatus.passed));
      expect(result.failures, isEmpty);
      // Ensure internal __hegel_coverage__ is stripped from visible statistics
      expect(result.statistics.containsKey('__hegel_coverage__'), isFalse);
    });

    test('fails runHegelTest when coverage target is not reached', () async {
      final result = await runHegelTest((tc) {
        final x = tc.draw(integers(min: 0, max: 99));
        // Exactly 0 is ~1%, target is 50%
        tc.cover(50.0, x == 0, 'zeros');
      }, testCases: 50);

      expect(result.status, equals(RunStatus.failed));
      expect(result.failures, isNotEmpty);
      final failure = result.failures.first;
      expect(failure.exception, isA<InsufficientCoverageException>());
      final covEx = failure.exception as InsufficientCoverageException;
      expect(covEx.label, equals('zeros'));
      expect(covEx.requiredPercent, equals(50.0));
      expect(covEx.actualPercent, lessThan(50.0));
      expect(covEx.totalCount, equals(result.testCasesRun));
      expect(
        failure.message,
        contains('Insufficient test coverage for "zeros"'),
      );
    });

    test(
      'runner.run throws InsufficientCoverageException on coverage failure',
      () async {
        final runner = HegelRunner(loadHegelLibrary());
        expect(
          () => runner.run((tc) {
            final x = tc.draw(integers(min: 0, max: 100));
            tc.cover(99.0, x == 0, 'near-impossible');
          }, testCases: 30),
          throwsA(isA<InsufficientCoverageException>()),
        );
      },
    );

    test('validates minPercentage boundaries', () async {
      final resultZero = await runHegelTest((tc) {
        tc.cover(0.0, true, 'invalid-min');
      }, testCases: 5);
      expect(resultZero.status, equals(RunStatus.failed));
      expect(
        resultZero.failures.first.message,
        contains('Invalid argument (minPercentage)'),
      );

      final resultNegative = await runHegelTest((tc) {
        tc.cover(-5.0, true, 'negative');
      }, testCases: 5);
      expect(resultNegative.status, equals(RunStatus.failed));
      expect(
        resultNegative.failures.first.message,
        contains('Invalid argument (minPercentage)'),
      );

      final resultOver = await runHegelTest((tc) {
        tc.cover(101.0, true, 'over-hundred');
      }, testCases: 5);
      expect(resultOver.status, equals(RunStatus.failed));
      expect(
        resultOver.failures.first.message,
        contains('Invalid argument (minPercentage)'),
      );
    });

    test(
      'calculates coverage based only on valid test cases (respects assume)',
      () async {
        final result = await runHegelTest((tc) {
          final x = tc.draw(integers(min: -50, max: 50));
          // Assume x >= 0
          tc.assume(x >= 0);
          // Cover even numbers among valid cases (should be ~50%)
          tc.cover(20.0, x % 2 == 0, 'evens');
        }, testCases: 50);

        expect(result.status, equals(RunStatus.passed));
      },
    );
  });
}

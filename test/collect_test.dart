import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  group('TestCase.collect', () {
    test('gathers statistics for valid test cases', () async {
      final result = await runHegelTest((tc) {
        final x = tc.draw(integers(min: -10, max: 10));
        tc.collect(x < 0 ? 'negative' : (x == 0 ? 'zero' : 'positive'));
      }, testCases: 50);

      expect(result.status, equals(RunStatus.passed));
      expect(result.statistics, isNotEmpty);
      expect(result.statistics.containsKey(''), isTrue);

      final counts = result.statistics['']!;
      final total = counts.values.fold<int>(0, (sum, c) => sum + c);
      expect(total, equals(result.testCasesRun));
      expect(total, greaterThan(0));
      expect(counts.keys, anyElement('negative'));
      expect(counts.keys, anyElement('positive'));

      final formatted = result.formatStatistics();
      expect(formatted, contains('% negative'));
      expect(formatted, contains('% positive'));
    });

    test('gathers statistics across multiple named labels', () async {
      final result = await runHegelTest((tc) {
        final items = tc.draw(lists(integers(), minSize: 0, maxSize: 20));
        tc.collect(
          items.isEmpty ? 'empty' : (items.length < 5 ? 'short' : 'long'),
          label: 'length',
        );
        tc.collect(
          items.any((e) => e < 0) ? 'has_negative' : 'all_non_negative',
          label: 'sign',
        );
      }, testCases: 40);

      expect(result.status, equals(RunStatus.passed));
      expect(result.statistics.containsKey('length'), isTrue);
      expect(result.statistics.containsKey('sign'), isTrue);

      final formatted = result.formatStatistics();
      expect(formatted, contains('length:'));
      expect(formatted, contains('sign:'));
    });

    test('discards observations when tc.assume fails', () async {
      final result = await runHegelTest((tc) {
        final x = tc.draw(integers(min: -10, max: 10));
        // Collect before assume
        tc.collect(x < 0 ? 'negative' : 'non-negative');
        // Discard all negatives
        tc.assume(x >= 0);
      }, testCases: 30);

      expect(result.status, equals(RunStatus.passed));
      final counts = result.statistics[''] ?? {};
      // All negative observations should have been discarded
      expect(counts.containsKey('negative'), isFalse);
      expect(counts.containsKey('non-negative'), isTrue);
      final total = counts.values.fold<int>(0, (sum, c) => sum + c);
      // Valid cases should be fewer than total attempts since negatives were discarded
      expect(total, lessThan(result.testCasesRun));
      expect(total, greaterThan(0));
    });

    test(
      'formatStatistics returns empty string when no data collected',
      () async {
        final result = await runHegelTest((tc) {
          tc.draw(integers());
        }, testCases: 10);

        expect(result.statistics, isEmpty);
        expect(result.formatStatistics(), isEmpty);
      },
    );

    test('statistics maps are unmodifiable', () async {
      final result = await runHegelTest((tc) {
        tc.collect('event');
      }, testCases: 5);

      expect(
        () => result.statistics[''] = {},
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => result.statistics['']!['event'] = 999,
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

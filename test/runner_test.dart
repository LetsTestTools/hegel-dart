import 'dart:async';
import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

void main() {
  group('runner basics', () {
    hegelTest('sync body works', (tc) {
      final x = tc.draw(integers());
      expect(x, isA<int>());
    });

    hegelTest('async body works', (tc) async {
      final x = tc.draw(integers());
      await Future.delayed(const Duration(milliseconds: 1));
      expect(x, isA<int>());
    });

    hegelTest('multiple draws per test case', (tc) {
      final a = tc.draw(integers());
      final b = tc.draw(text(minSize: 0, maxSize: 10));
      final c = tc.draw(booleans());
      expect(a, isA<int>());
      expect(b, isA<String>());
      expect(c, isA<bool>());
    });

    hegelTest('nested generator draws work', (tc) {
      final nested = tc.draw(
        lists(
          lists(integers(min: 0, max: 10), minSize: 0, maxSize: 3),
          minSize: 0,
          maxSize: 3,
        ),
      );
      expect(nested, isA<List<List<int>>>());
    });
  });

  group('failure detection', () {
    test('detects failure and provides origin + reproduce', () async {
      final runner = HegelRunner();
      await expectLater(
        runner.run((tc) {
          final v = tc.draw(integers());
          if (v < 0) throw StateError('negative!');
        }),
        throwsA(
          isA<HegelTestFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('Origin'), contains('reproduce:')),
          ),
        ),
      );
    });

    test('detects assertion failure', () async {
      final runner = HegelRunner();
      await expectLater(
        runner.run((tc) {
          final v = tc.draw(integers(min: -100, max: 100));
          expect(v, greaterThan(50)); // Will fail for v <= 50
        }),
        throwsA(
          isA<HegelTestFailure>().having(
            (e) => e.message,
            'message',
            contains('Property failed'),
          ),
        ),
      );
    });
  });

  group('TestCase API', () {
    hegelTest('target API does not throw', (tc) {
      final v = tc.draw(integers(min: 0, max: 100));
      tc.target(v.toDouble(), label: 'test_value');
    });

    hegelTest('span API does not throw', (tc) {
      tc.startSpan(12345);
      final v = tc.draw(integers());
      expect(v, isA<int>());
      tc.stopSpan();
    });
  });

  group('assume', () {
    hegelTest('filters invalid test cases', (tc) {
      final x = tc.draw(integers(min: 0, max: 200));
      tc.assume(x > 50);
      expect(x, greaterThan(50));
    }, suppressHealthChecks: {HealthCheck.filterTooMuch});
  });

  group('settings', () {
    hegelTest('testCases controls iterations', (tc) {
      tc.draw(integers());
    }, testCases: 25);

    test('seed makes runs deterministic', () async {
      int? firstVal1;
      int? firstVal2;

      final runner1 = HegelRunner();
      await runner1.run(
        (tc) {
          firstVal1 = tc.draw(integers());
        },
        seed: 12345,
        testCases: 1,
      );

      final runner2 = HegelRunner();
      await runner2.run(
        (tc) {
          firstVal2 = tc.draw(integers());
        },
        seed: 12345,
        testCases: 1,
      );

      expect(firstVal1, isNotNull);
      expect(firstVal1, equals(firstVal2));
    });

    test('Verbosity enum values match libhegel 0.53 ABI', () {
      expect(Verbosity.normal.value, equals(0));
      expect(Verbosity.quiet.value, equals(1));
      expect(Verbosity.verbose.value, equals(2));
      expect(Verbosity.debug.value, equals(3));
    });

    test('RunResult.errorKind classifies errored runs', () async {
      final unsatisfiable = await runHegelTest(
        (tc) {
          tc.draw(integers(min: 0, max: 10));
          tc.assume(false);
        },
        testCases: 5,
        suppressHealthChecks: {HealthCheck.filterTooMuch},
        database: false,
      );
      expect(unsatisfiable.status, equals(RunStatus.error));
      expect(unsatisfiable.errorKind, equals(RunErrorKind.unsatisfiable));
      expect(unsatisfiable.errorMessage, isNotEmpty);

      final filterHealthCheck = await runHegelTest(
        (tc) {
          final x = tc.draw(integers(min: 0, max: 100));
          tc.assume(x < -1);
        },
        testCases: 50,
        database: false,
      );
      expect(filterHealthCheck.status, equals(RunStatus.error));
      expect(filterHealthCheck.errorKind, equals(RunErrorKind.healthCheck));
    });
  });
}

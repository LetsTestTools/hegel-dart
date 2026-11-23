import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  test('failure message includes counterexample values', () async {
    final runner = HegelRunner();

    await expectLater(
      runner.run((tc) {
        final v = tc.draw(integers(min: -100, max: 100));
        if (v < 0) throw StateError('negative!');
      }),
      throwsA(
        isA<HegelTestFailure>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Counterexample'),
            contains('draw #1'),
            contains('IntegerGenerator'),
          ),
        ),
      ),
    );
  });

  test('failure message includes reproduce blob', () async {
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
          contains('reproduce:'),
        ),
      ),
    );
  });

  test('failure message includes tc.note() diagnostic notes', () async {
    final runner = HegelRunner();

    final result = await runner.runWithResult(
      (tc) {
        final v = tc.draw(integers(min: 0, max: 100));
        tc.note('drawn v=$v');
        if (v > 10) {
          tc.note('failing diagnostic');
          throw StateError('too big');
        }
      },
      testCases: 100,
      database: false,
    );

    expect(result.status, equals(RunStatus.failed));
    final failure = result.failures.first;
    expect(
      failure.message,
      allOf(contains('Notes:'), contains('failing diagnostic')),
    );

    // Also verify blob replay includes tc.note() output
    final replayResult = await runner.runWithResult(
      (tc) {
        final v = tc.draw(integers(min: 0, max: 100));
        tc.note('drawn v=$v');
        if (v > 10) {
          tc.note('failing diagnostic');
          throw StateError('too big');
        }
      },
      reproduceBlob: failure.reproductionBlob,
      database: false,
    );
    expect(replayResult.status, equals(RunStatus.failed));
    expect(
      replayResult.failures.first.message,
      allOf(contains('Notes:'), contains('failing diagnostic')),
    );
  });

  test(
    'failure message keeps tc.note() under quiet verbosity and avoids duplication under normal verbosity',
    () async {
      void body(TestCase tc) {
        final v = tc.draw(integers(min: 0, max: 100));
        tc.note('drawn v=$v');
        if (v > 10) {
          tc.note('failing diagnostic');
          throw StateError('too big');
        }
      }

      final quietResult = await HegelRunner().runWithResult(
        body,
        verbosity: Verbosity.quiet,
        testCases: 100,
        database: false,
      );
      expect(quietResult.status, equals(RunStatus.failed));
      expect(
        quietResult.failures.first.message,
        allOf(contains('Notes:'), contains('failing diagnostic')),
      );

      final normalResult = await HegelRunner().runWithResult(
        body,
        verbosity: Verbosity.normal,
        testCases: 100,
        database: false,
      );
      expect(normalResult.status, equals(RunStatus.failed));
      expect(
        'failing diagnostic'
            .allMatches(normalResult.failures.first.message)
            .length,
        equals(1),
      );
    },
  );

  test(
    'debug run tolerates errors whose toString() throws and reports fallback',
    () async {
      final result = await HegelRunner().runWithResult(
        (tc) {
          tc.draw(integers(min: 0, max: 0));
          throw _UnprintableError();
        },
        verbosity: Verbosity.debug,
        testCases: 1,
        database: false,
      );
      expect(result.status, equals(RunStatus.failed));
      expect(result.failures, hasLength(1));
      expect(result.failures.first.message, contains('toString() threw'));

      final secondCallResult = await HegelRunner().runWithResult(
        (tc) {
          tc.draw(integers(min: 0, max: 0));
          throw _SecondCallThrowsError();
        },
        verbosity: Verbosity.debug,
        testCases: 1,
        database: false,
      );
      expect(secondCallResult.status, equals(RunStatus.failed));
      expect(secondCallResult.failures, hasLength(1));
      expect(
        secondCallResult.failures.first.message,
        contains('first call ok'),
      );
    },
  );

  test(
    'nested runWithResult on shared HegelRunner preserves outer diagnostics',
    () async {
      final runner = HegelRunner();
      final outerResult = await runner.runWithResult(
        (tc) {
          final v = tc.draw(integers(min: 1, max: 100));
          if (v >= 1) {
            throw StateError('outer boom');
          }
        },
        testCases: 5,
        database: false,
        tearDownEach: () async {
          final innerResult = await runner.runWithResult(
            (tc) {
              tc.draw(integers(min: 0, max: 5));
            },
            testCases: 1,
            database: false,
          );
          expect(innerResult.status, equals(RunStatus.passed));
        },
      );
      expect(outerResult.status, equals(RunStatus.failed));
      expect(outerResult.failures.first.message, contains('outer boom'));
      expect(outerResult.failures.first.message, contains('Counterexample'));
    },
  );
}

class _UnprintableError implements Exception {
  @override
  String toString() => throw StateError('cannot format');
}

class _SecondCallThrowsError implements Exception {
  int _calls = 0;

  @override
  String toString() {
    _calls++;
    if (_calls > 1) {
      throw StateError('cannot format twice');
    }
    return 'first call ok';
  }
}

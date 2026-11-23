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
}

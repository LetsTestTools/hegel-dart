import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';
import 'package:hegeltest/src/ffi/library_loader.dart';
import 'package:hegeltest/src/core/runner.dart' show HegelRunner;

void main() {
  test('failure message includes counterexample values', () async {
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);

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
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);

    await expectLater(
      runner.run((tc) {
        final v = tc.draw(integers());
        if (v < 0) throw StateError('negative!');
      }),
      throwsA(
        isA<HegelTestFailure>().having(
          (e) => e.message,
          'message',
          contains("reproduce:"),
        ),
      ),
    );
  });
}

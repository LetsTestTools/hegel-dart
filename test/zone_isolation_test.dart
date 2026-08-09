import 'dart:async';
import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';
import 'package:hegeltest/src/ffi/library_loader.dart';
import 'package:hegeltest/src/core/runner.dart';

void main() {
  test('unawaited async errors are caught in zone', () async {
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);

    // This should fail because of the unawaited Future.error,
    // NOT crash the test runner.
    await expectLater(
      runner.run((tc) {
        final v = tc.draw(integers(min: 0, max: 100));
        if (v > 50) {
          // Fire-and-forget async error — zone should catch it
          unawaited(Future.error(StateError('async boom')));
        }
      }),
      throwsA(isA<HegelTestFailure>()),
    );
  });

  test('tearDownEach failure marks test as interesting', () async {
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);

    await expectLater(
      runner.run(
        (tc) {
          tc.draw(integers(min: 0, max: 10));
          // Body passes...
        },
        tearDownEach: () => throw StateError('teardown failed'),
      ),
      throwsA(isA<HegelTestFailure>()),
    );
  });
}

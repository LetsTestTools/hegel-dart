import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';
import 'package:hegeltest/src/core/runner.dart';
import 'package:hegeltest/src/core/exceptions.dart';
import 'package:hegeltest/src/ffi/library_loader.dart';

void main() {
  test('failing test shrinks toward minimum counterexample', () async {
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);

    int lastFailingValue = -1;

    try {
      await runner.run((tc) {
        final v = tc.draw(integers(min: 0, max: 10000));
        lastFailingValue = v;
        if (v > 100) {
          throw StateError('Value too large: $v');
        }
      }, testCases: 1000);
      fail('Expected test to fail');
    } on HegelTestFailure catch (_) {
      // The shrunk value should be near the boundary (101-ish),
      // not a random large value. Allow some margin for shrinking
      // heuristics, but it should be dramatically smaller than 10000.
      expect(lastFailingValue, greaterThan(100));
      expect(lastFailingValue, lessThan(200),
          reason: 'Shrunk value should be near boundary, got $lastFailingValue');
    }
  });
}

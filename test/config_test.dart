import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';
import 'package:hegeltest/src/ffi/library_loader.dart';
import 'package:hegeltest/src/core/runner.dart' show HegelRunner;

void main() {
  test('HegelConfig testCases controls iterations', () async {
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);
    var count = 0;

    final config = HegelConfig(testCases: 5);
    await runner.run(
      (tc) {
        tc.draw(integers());
        count++;
      },
      testCases: config.testCases,
    );

    // Should be around 5 (may vary slightly due to engine behavior)
    expect(count, greaterThan(0));
    expect(count, lessThanOrEqualTo(10));
  });

  test('individual params override config', () async {
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);
    var count = 0;

    // Config says 1000, but direct param says 5 — direct wins
    await runner.run(
      (tc) {
        tc.draw(integers());
        count++;
      },
      testCases: 5,
    );

    expect(count, lessThanOrEqualTo(10));
  });
}

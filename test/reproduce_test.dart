import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';
import 'package:hegeltest/src/core/runner.dart';
import 'package:hegeltest/src/core/exceptions.dart';
import 'package:hegeltest/src/ffi/library_loader.dart';

void main() {
  test('blob replay reproduces the same failure', () async {
    final lib = loadHegelLibrary();

    String? reproduceBlob;

    // The body under test — extracted so both runs use the same function
    void body(TestCase tc) {
      final v = tc.draw(integers(min: 0, max: 1000));
      if (v >= 500) {
        throw StateError('Value too large');
      }
    }

    // Run a property that intentionally fails
    final runner1 = HegelRunner(lib);
    try {
      await runner1.run(body, testCases: 100);
      fail('Expected test to fail');
    } on HegelTestFailure catch (e) {
      // Extract reproduce blob
      final reproduceMatch = RegExp(r"@reproduce\('([^']+)'\)").firstMatch(e.message);
      expect(reproduceMatch, isNotNull, reason: 'Should contain reproduce blob');
      reproduceBlob = reproduceMatch!.group(1);
      // Verify the original failure is a property failure
      expect(e.message, contains('Property failed'));
    }

    // Now replay using the blob — should fail with the same error
    final runner2 = HegelRunner(lib);
    try {
      await runner2.run(body, reproduceBlob: reproduceBlob);
      fail('Replay should also fail');
    } on StateError catch (e) {
      // With blob replay rethrow fix, the original exception is
      // thrown directly so users can debug the actual error.
      expect(e.message, contains('Value too large'));
    }
  });
}

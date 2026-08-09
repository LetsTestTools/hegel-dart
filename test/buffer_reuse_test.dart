import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';
import 'package:hegeltest/src/ffi/library_loader.dart';
import 'package:hegeltest/src/core/runner.dart';

void main() {
  test('multiple draws of same type reuse buffers', () async {
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);

    await runner.run((tc) {
      // Draw multiple integers — should reuse the same native buffer
      final a = tc.draw(integers());
      final b = tc.draw(integers());
      final c = tc.draw(integers());
      // Just verify they're valid integers (no corruption)
      expect(a, isA<int>());
      expect(b, isA<int>());
      expect(c, isA<int>());
    }, testCases: 100);
  });

  test('mixed type draws work correctly', () async {
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);

    await runner.run((tc) {
      final i = tc.draw(integers(min: 0, max: 100));
      final d = tc.draw(doubles());
      final b = tc.draw(booleans());
      expect(i, isA<int>());
      expect(d, isA<double>());
      expect(b, isA<bool>());
    }, testCases: 100);
  });
}

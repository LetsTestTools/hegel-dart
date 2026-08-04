import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';
import 'package:hegeltest/src/core/runner.dart';
import 'package:hegeltest/src/core/exceptions.dart';
import 'package:hegeltest/src/ffi/library_loader.dart';

void main() {
  group('TestCase lifecycle', () {
    test('draw after run completes throws StateError', () async {
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);
      TestCase? captured;
      
      await runner.run((tc) {
        captured = tc;
        tc.draw(integers()); // should work
      }, testCases: 1);
      
      // tc is now invalidated by the runner
      expect(captured, isNotNull);
      expect(
        () => captured!.draw(integers()),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('after disposal'),
        )),
      );
    });
    
    test('target after run completes throws StateError', () async {
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);
      TestCase? captured;
      
      await runner.run((tc) {
        captured = tc;
      }, testCases: 1);
      
      expect(
        () => captured!.target(1.0, label: 'x'),
        throwsA(isA<StateError>()),
      );
    });
    
    test('clone after run completes throws StateError', () async {
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);
      TestCase? captured;
      
      await runner.run((tc) {
        captured = tc;
      }, testCases: 1);
      
      expect(
        () => captured!.clone(),
        throwsA(isA<StateError>()),
      );
    });
    
    test('clone and dispose lifecycle works', () async {
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);
      
      await runner.run((tc) {
        final v1 = tc.draw(integers(min: 0, max: 100));
        final cloned = tc.clone();
        try {
          final v2 = cloned.draw(integers(min: 0, max: 100));
          // Both should produce valid integers
          expect(v1, isA<int>());
          expect(v2, isA<int>());
        } finally {
          cloned.dispose();
        }
      }, testCases: 5);
    });
    
    test('dispose is idempotent', () async {
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);
      
      await runner.run((tc) {
        final cloned = tc.clone();
        cloned.dispose();
        // Second dispose should not throw
        cloned.dispose();
      }, testCases: 1);
    });
    
    test('draw on disposed clone throws StateError', () async {
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);
      
      await runner.run((tc) {
        final cloned = tc.clone();
        cloned.dispose();
        expect(
          () => cloned.draw(integers()),
          throwsA(isA<StateError>()),
        );
      }, testCases: 1);
    });
  });
}

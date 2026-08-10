import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  hegelTest('reverse is involutory', (tc) {
    final xs = tc.draw(lists(integers()));
    final reversed = xs.reversed.toList();
    final doubleReversed = reversed.reversed.toList();
    expect(doubleReversed, equals(xs));
  });

  hegelTest('addition is commutative', (tc) {
    final a = tc.draw(integers(min: -1000, max: 1000));
    final b = tc.draw(integers(min: -1000, max: 1000));
    expect(a + b, equals(b + a));
  });

  hegelTest('sort is idempotent', (tc) {
    final xs = tc.draw(lists(integers()));
    final sorted1 = List.of(xs)..sort();
    final sorted2 = List.of(sorted1)..sort();
    expect(sorted2, equals(sorted1));
  });

  hegelTest('string encode/decode roundtrip', (tc) {
    final s = tc.draw(text(maxSize: 200));
    final encoded = Uri.encodeComponent(s);
    final decoded = Uri.decodeComponent(encoded);
    expect(decoded, equals(s));
  });

  hegelTest('map preserves keys', (tc) {
    final m = tc.draw(maps(text(minSize: 1, maxSize: 10), integers()));
    for (final key in m.keys) {
      expect(m.containsKey(key), isTrue);
    }
  });

  // Reusable config — share settings across tests
  final thorough = HegelConfig(testCases: 10000);

  hegelTest(
    'concatenation length',
    (tc) {
      final a = tc.draw(text(maxSize: 50));
      final b = tc.draw(text(maxSize: 50));
      expect((a + b).length, equals(a.length + b.length));
    },
    config: thorough,
  );

  // Per-iteration isolation — use setUpEach/tearDownEach, NOT setUp/tearDown.
  //
  // IMPORTANT: package:test's setUp() runs once per *property*, not once per
  // generated test case. If your property mutates state, use setUpEach to
  // reset it before each iteration:
  hegelTest(
    'stateful counter resets each iteration',
    (TestCase tc) {
      final n = tc.draw(integers(min: 1, max: 100));
      _counter += n;
      expect(_counter, equals(n)); // Only works if reset each time
    },
    setUpEach: () => _counter = 0,
    tearDownEach: () => _counter = 0,
  );
}

int _counter = 0;

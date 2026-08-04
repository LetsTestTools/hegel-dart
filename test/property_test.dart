import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

/// Real property-based test patterns demonstrating hegeltest in action.
void main() {
  group('list properties', () {
    hegelTest('reverse-reverse is identity', (tc) {
      final xs = tc.draw(lists(integers(min: -100, max: 100), minSize: 0, maxSize: 20));
      final reversedTwice = xs.reversed.toList().reversed.toList();
      expect(reversedTwice, equals(xs));
    });

    hegelTest('sort is idempotent', (tc) {
      final xs = tc.draw(lists(integers(min: -100, max: 100), minSize: 0, maxSize: 20));
      final sortedOnce = List<int>.from(xs)..sort();
      final sortedTwice = List<int>.from(sortedOnce)..sort();
      expect(sortedOnce, equals(sortedTwice));
    });

    hegelTest('sort preserves length', (tc) {
      final xs = tc.draw(lists(integers(min: -100, max: 100), minSize: 0, maxSize: 20));
      final sorted = List<int>.from(xs)..sort();
      expect(sorted.length, equals(xs.length));
    });

    hegelTest('sort preserves elements', (tc) {
      final xs = tc.draw(lists(integers(min: -100, max: 100), minSize: 0, maxSize: 20));
      final sorted = List<int>.from(xs)..sort();
      expect(sorted.toSet(), equals(xs.toSet()));
    });

    hegelTest('concatenation is associative', (tc) {
      final a = tc.draw(lists(integers(min: 0, max: 10), minSize: 0, maxSize: 5));
      final b = tc.draw(lists(integers(min: 0, max: 10), minSize: 0, maxSize: 5));
      final c = tc.draw(lists(integers(min: 0, max: 10), minSize: 0, maxSize: 5));
      final left = [...[...a, ...b], ...c];
      final right = [...a, ...[...b, ...c]];
      expect(left, equals(right));
    });
  });

  group('arithmetic properties', () {
    hegelTest('addition is commutative', (tc) {
      final a = tc.draw(integers(min: -1000000, max: 1000000));
      final b = tc.draw(integers(min: -1000000, max: 1000000));
      expect(a + b, equals(b + a));
    });

    hegelTest('addition is associative (small ints)', (tc) {
      final a = tc.draw(integers(min: -10000, max: 10000));
      final b = tc.draw(integers(min: -10000, max: 10000));
      final c = tc.draw(integers(min: -10000, max: 10000));
      expect((a + b) + c, equals(a + (b + c)));
    });

    hegelTest('multiplication is commutative', (tc) {
      final a = tc.draw(integers(min: -1000, max: 1000));
      final b = tc.draw(integers(min: -1000, max: 1000));
      expect(a * b, equals(b * a));
    });

    hegelTest('multiplication distributes over addition', (tc) {
      final a = tc.draw(integers(min: -100, max: 100));
      final b = tc.draw(integers(min: -100, max: 100));
      final c = tc.draw(integers(min: -100, max: 100));
      expect(a * (b + c), equals(a * b + a * c));
    });
  });

  group('string properties', () {
    hegelTest('concatenation length is additive', (tc) {
      final a = tc.draw(text(minSize: 0, maxSize: 20));
      final b = tc.draw(text(minSize: 0, maxSize: 20));
      expect((a + b).length, equals(a.length + b.length));
    });

    hegelTest('split-join roundtrip', (tc) {
      final s = tc.draw(text(minSize: 0, maxSize: 30, minCodepoint: 0x41, maxCodepoint: 0x5A));
      // Split on a character not in range, so join is identity
      expect(s.split('|').join('|'), equals(s));
    });
  });

  group('set properties', () {
    hegelTest('union is commutative', (tc) {
      final a = tc.draw(sets(integers(min: 0, max: 50), minSize: 0, maxSize: 10));
      final b = tc.draw(sets(integers(min: 0, max: 50), minSize: 0, maxSize: 10));
      expect(a.union(b), equals(b.union(a)));
    });

    hegelTest('intersection is subset of union', (tc) {
      final a = tc.draw(sets(integers(min: 0, max: 50), minSize: 0, maxSize: 10));
      final b = tc.draw(sets(integers(min: 0, max: 50), minSize: 0, maxSize: 10));
      final inter = a.intersection(b);
      final union = a.union(b);
      expect(union.containsAll(inter), isTrue);
    });

    hegelTest('|A ∪ B| + |A ∩ B| = |A| + |B|', (tc) {
      final a = tc.draw(sets(integers(min: 0, max: 50), minSize: 0, maxSize: 10));
      final b = tc.draw(sets(integers(min: 0, max: 50), minSize: 0, maxSize: 10));
      expect(
        a.union(b).length + a.intersection(b).length,
        equals(a.length + b.length),
      );
    });
  });

  group('map properties', () {
    hegelTest('fromEntries/entries roundtrip', (tc) {
      final m = tc.draw(maps(
        integers(min: 0, max: 100),
        integers(min: 0, max: 100),
        minSize: 0,
        maxSize: 10,
      ));
      final roundtripped = Map.fromEntries(m.entries);
      expect(roundtripped, equals(m));
    });
  });
}

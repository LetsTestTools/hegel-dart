import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

void main() {
  group('lists', () {
    hegelTest('empty allowed', (tc) {
      final v = tc.draw(lists(integers(), minSize: 0, maxSize: 5));
      expect(v, isA<List<int>>());
      expect(v.length, lessThanOrEqualTo(5));
    });

    hegelTest('minSize respected', (tc) {
      final v = tc.draw(lists(integers(), minSize: 3, maxSize: 10));
      expect(v.length, greaterThanOrEqualTo(3));
    });

    hegelTest('maxSize respected', (tc) {
      final v = tc.draw(lists(integers(), minSize: 0, maxSize: 5));
      expect(v.length, lessThanOrEqualTo(5));
    });

    hegelTest('element bounds respected', (tc) {
      final v =
          tc.draw(lists(integers(min: 0, max: 10), minSize: 1, maxSize: 5));
      for (final e in v) {
        expect(e, greaterThanOrEqualTo(0));
        expect(e, lessThanOrEqualTo(10));
      }
    });

    hegelTest('empty list when maxSize is 0', (tc) {
      final v = tc.draw(lists(integers(), minSize: 0, maxSize: 0));
      expect(v, isEmpty);
    });

    hegelTest('single element list', (tc) {
      final v = tc.draw(lists(integers(), minSize: 1, maxSize: 1));
      expect(v.length, equals(1));
    });
  });

  group('sets', () {
    hegelTest('all elements unique', (tc) {
      final v =
          tc.draw(sets(integers(min: 0, max: 100), minSize: 1, maxSize: 10));
      expect(v.length, equals(v.toSet().length));
    });

    hegelTest('size bounds respected', (tc) {
      final v =
          tc.draw(sets(integers(min: 0, max: 1000), minSize: 2, maxSize: 8));
      expect(v.length, greaterThanOrEqualTo(2));
      expect(v.length, lessThanOrEqualTo(8));
    });

    hegelTest('element bounds respected', (tc) {
      final v =
          tc.draw(sets(integers(min: 0, max: 50), minSize: 1, maxSize: 5));
      for (final e in v) {
        expect(e, greaterThanOrEqualTo(0));
        expect(e, lessThanOrEqualTo(50));
      }
    });
  });

  group('maps', () {
    hegelTest('keys unique', (tc) {
      final v = tc.draw(maps(
        integers(min: 0, max: 100),
        integers(min: 0, max: 100),
        minSize: 1,
        maxSize: 8,
      ));
      expect(v.keys.toSet().length, equals(v.length));
    });

    hegelTest('size bounds respected', (tc) {
      final v = tc.draw(maps(
        integers(min: 0, max: 1000),
        booleans(),
        minSize: 1,
        maxSize: 5,
      ));
      expect(v.length, greaterThanOrEqualTo(1));
      expect(v.length, lessThanOrEqualTo(5));
    });

    hegelTest('values from generator', (tc) {
      final v = tc.draw(maps(
        integers(min: 0, max: 10),
        integers(min: 100, max: 200),
        minSize: 1,
        maxSize: 5,
      ));
      for (final val in v.values) {
        expect(val, greaterThanOrEqualTo(100));
        expect(val, lessThanOrEqualTo(200));
      }
    });
  });

  group('nested collections', () {
    hegelTest('list of lists', (tc) {
      final v = tc.draw(lists(
        lists(integers(min: 0, max: 10), minSize: 0, maxSize: 3),
        minSize: 1,
        maxSize: 3,
      ));
      expect(v, isA<List<List<int>>>());
      for (final inner in v) {
        expect(inner.length, lessThanOrEqualTo(3));
        for (final e in inner) {
          expect(e, greaterThanOrEqualTo(0));
          expect(e, lessThanOrEqualTo(10));
        }
      }
    });

    hegelTest('map with list values', (tc) {
      final v = tc.draw(maps(
        integers(min: 0, max: 10),
        lists(booleans(), minSize: 0, maxSize: 3),
        minSize: 1,
        maxSize: 3,
      ));
      expect(v, isA<Map<int, List<bool>>>());
    });
  });
}

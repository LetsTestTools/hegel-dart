import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';
import 'package:hegeltest/generators.dart';

void main() {
  group('map combinator', () {
    hegelTest('transforms values correctly', (tc) {
      final v = tc.draw(integers(min: 0, max: 100).map((i) => i * 2));
      expect(v % 2, equals(0)); // always even
      expect(v, greaterThanOrEqualTo(0));
      expect(v, lessThanOrEqualTo(200));
    });

    hegelTest('transforms type', (tc) {
      final v = tc.draw(integers(min: 1, max: 100).map((i) => i.toString()));
      expect(v, isA<String>());
      expect(int.parse(v), greaterThanOrEqualTo(1));
    });
  });

  group('where combinator', () {
    hegelTest('filtered values satisfy predicate', (tc) {
      final v = tc.draw(integers(min: 0, max: 100).where((i) => i > 50));
      expect(v, greaterThan(50));
    }, suppressHealthChecks: {HealthCheck.filterTooMuch});

    hegelTest('even numbers only', (tc) {
      final v = tc.draw(integers(min: 0, max: 100).where((i) => i % 2 == 0));
      expect(v % 2, equals(0));
    }, suppressHealthChecks: {HealthCheck.filterTooMuch});
  });

  group('flatMap combinator', () {
    hegelTest('dependent generation', (tc) {
      // Generate a length, then a list of that exact length
      final v = tc.draw(
        integers(min: 1, max: 5).flatMap(
          (len) => lists(integers(min: 0, max: 10), minSize: len, maxSize: len),
        ),
      );
      expect(v, isA<List<int>>());
      expect(v.length, greaterThanOrEqualTo(1));
      expect(v.length, lessThanOrEqualTo(5));
    });
  });

  group('oneOf', () {
    hegelTest('picks from generators', (tc) {
      final v = tc.draw(oneOf([
        integers(min: 0, max: 0),
        integers(min: 100, max: 100),
      ]));
      expect(v, anyOf(equals(0), equals(100)));
    });

    hegelTest('value always from one of the generators', (tc) {
      final v = tc.draw(oneOf([
        integers(min: 0, max: 0),
        integers(min: 100, max: 100),
        integers(min: 200, max: 200),
      ]));
      expect(v, anyOf(equals(0), equals(100), equals(200)));
    });
  });

  group('sampled', () {
    hegelTest('picks from values', (tc) {
      final v = tc.draw(sampled(['alpha', 'beta', 'gamma']));
      expect(v, isIn(['alpha', 'beta', 'gamma']));
    });

    hegelTest('single element list', (tc) {
      final v = tc.draw(sampled([42]));
      expect(v, equals(42));
    });
  });

  group('nullable', () {
    hegelTest('produces valid type', (tc) {
      final v = tc.draw(nullable(integers(min: 0, max: 100)));
      if (v != null) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(100));
      }
    });

    hegelTest('type is correct', (tc) {
      final v = tc.draw(nullable(integers(min: 0, max: 100)));
      if (v != null) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(100));
      }
    });
  });

  group('tuples', () {
    hegelTest('tuples2 produces pairs', (tc) {
      final v = tc.draw(tuples2(
        integers(min: 0, max: 10),
        booleans(),
      ));
      expect(v.$1, greaterThanOrEqualTo(0));
      expect(v.$1, lessThanOrEqualTo(10));
      expect(v.$2, isA<bool>());
    });

    hegelTest('tuples3 produces triples', (tc) {
      final v = tc.draw(tuples3(
        integers(min: 0, max: 10),
        integers(min: 100, max: 200),
        booleans(),
      ));
      expect(v.$1, lessThanOrEqualTo(10));
      expect(v.$2, greaterThanOrEqualTo(100));
      expect(v.$3, isA<bool>());
    });

    hegelTest('tuples4 produces quadruples', (tc) {
      final v = tc.draw(tuples4(
        integers(min: 0, max: 5),
        integers(min: 10, max: 15),
        integers(min: 20, max: 25),
        integers(min: 30, max: 35),
      ));
      expect(v.$1, lessThanOrEqualTo(5));
      expect(v.$2, greaterThanOrEqualTo(10));
      expect(v.$3, greaterThanOrEqualTo(20));
      expect(v.$4, greaterThanOrEqualTo(30));
    });
  });

  group('frequency', () {
    hegelTest('values from weighted generators', (tc) {
      final v = tc.draw(frequency([
        (3, integers(min: 0, max: 10)),
        (1, integers(min: 1000, max: 2000)),
      ]));
      expect(v, anyOf(
        allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(10)),
        allOf(greaterThanOrEqualTo(1000), lessThanOrEqualTo(2000)),
      ));
    });
  });
}

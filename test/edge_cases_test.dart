import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';
import 'package:hegeltest/generators.dart';

void main() {
  group('boundary values', () {
    hegelTest('empty list', (tc) {
      final xs = tc.draw(lists(integers(), minSize: 0, maxSize: 0));
      expect(xs, isEmpty);
    });

    hegelTest('single element list', (tc) {
      final xs = tc.draw(lists(integers(), minSize: 1, maxSize: 1));
      expect(xs.length, equals(1));
    });

    hegelTest('zero-range integer', (tc) {
      final x = tc.draw(integers(min: 42, max: 42));
      expect(x, equals(42));
    });

    hegelTest('negative zero-range integer', (tc) {
      final x = tc.draw(integers(min: -7, max: -7));
      expect(x, equals(-7));
    });

    hegelTest('empty text', (tc) {
      final s = tc.draw(text(minSize: 0, maxSize: 0));
      expect(s, isEmpty);
    });

    hegelTest('empty bytes', (tc) {
      final b = tc.draw(bytes(minSize: 0, maxSize: 0));
      expect(b, isEmpty);
    });
  });

  group('stress tests', () {
    hegelTest('50+ draws per test case', (tc) {
      for (var i = 0; i < 50; i++) {
        final val = tc.draw(integers(min: 0, max: 1000));
        expect(val, greaterThanOrEqualTo(0));
      }
    });

    hegelTest('many draws of different types', (tc) {
      for (var i = 0; i < 10; i++) {
        tc.draw(integers());
        tc.draw(booleans());
        tc.draw(text(minSize: 0, maxSize: 5));
      }
    });

    hegelTest('large test case count', (tc) {
      tc.draw(integers());
    }, testCases: 500);
  });

  group('composite generators', () {
    hegelTest('point record via composite', (tc) {
      final point = tc.draw(Generator.composite<({int x, int y})>((tc) {
        final x = tc.draw(integers(min: -100, max: 100));
        final y = tc.draw(integers(min: -100, max: 100));
        return (x: x, y: y);
      }));
      expect(point.x, greaterThanOrEqualTo(-100));
      expect(point.x, lessThanOrEqualTo(100));
      expect(point.y, greaterThanOrEqualTo(-100));
      expect(point.y, lessThanOrEqualTo(100));
    });

    hegelTest('person model via composite', (tc) {
      final person = tc.draw(Generator.composite<({String name, int age, bool active})>((tc) {
        return (
          name: tc.draw(text(minSize: 1, maxSize: 20, minCodepoint: 0x41, maxCodepoint: 0x5A)),
          age: tc.draw(integers(min: 0, max: 120)),
          active: tc.draw(booleans()),
        );
      }));
      expect(person.name, isNotEmpty);
      expect(person.age, greaterThanOrEqualTo(0));
      expect(person.age, lessThanOrEqualTo(120));
    });
  });

  group('chained combinators', () {
    hegelTest('map then where', (tc) {
      final v = tc.draw(
        integers(min: 0, max: 100)
            .map((i) => i * 2)
            .where((i) => i > 50),
      );
      expect(v, greaterThan(50));
      expect(v % 2, equals(0));
    }, suppressHealthChecks: {HealthCheck.filterTooMuch});

    hegelTest('double map chain', (tc) {
      final v = tc.draw(
        integers(min: 1, max: 10)
            .map((i) => i.toString())
            .map((s) => 'item_$s'),
      );
      expect(v, startsWith('item_'));
    });
  });
}

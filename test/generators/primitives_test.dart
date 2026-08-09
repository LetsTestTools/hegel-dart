import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

void main() {
  group('integers', () {
    hegelTest('bounds respected', (tc) {
      final value = tc.draw(integers(min: 5, max: 10));
      expect(value, greaterThanOrEqualTo(5));
      expect(value, lessThanOrEqualTo(10));
    });

    hegelTest('negative ranges', (tc) {
      final value = tc.draw(integers(min: -20, max: -10));
      expect(value, greaterThanOrEqualTo(-20));
      expect(value, lessThanOrEqualTo(-10));
    });

    hegelTest('single value (min==max)', (tc) {
      final value = tc.draw(integers(min: 42, max: 42));
      expect(value, equals(42));
    });

    hegelTest('full int64 range', (tc) {
      final min = -9223372036854775808;
      final max = 9223372036854775807;
      final value = tc.draw(integers(min: min, max: max));
      expect(value, greaterThanOrEqualTo(min));
      expect(value, lessThanOrEqualTo(max));
    });
  });

  group('doubles', () {
    hegelTest('bounds respected', (tc) {
      final value = tc.draw(
          doubles(min: 1.5, max: 5.5, allowNan: false, allowInfinity: false));
      expect(value, greaterThanOrEqualTo(1.5));
      expect(value, lessThanOrEqualTo(5.5));
    });

    hegelTest('NaN possible when allowed', (tc) {
      final val = tc.draw(doubles(allowNan: true));
      // Just verify it doesn't crash; NaN is a valid output
      expect(val, isA<double>());
    });

    hegelTest('no NaN when disallowed', (tc) {
      final value = tc.draw(doubles(allowNan: false));
      expect(value.isNaN, isFalse);
    });

    hegelTest('infinity handling', (tc) {
      final value = tc.draw(doubles(allowInfinity: true, allowNan: false));
      // Verify it's a valid double (finite or infinite)
      expect(value, isA<double>());
      expect(value.isNaN, isFalse);
    });

    hegelTest('excludeMin/Max', (tc) {
      final value = tc.draw(doubles(
          min: 0.0,
          max: 1.0,
          excludeMin: true,
          excludeMax: true,
          allowNan: false,
          allowInfinity: false));
      expect(value, greaterThan(0.0));
      expect(value, lessThan(1.0));
    });

    hegelTest('smallestNonzero', (tc) {
      final value = tc.draw(doubles(
          min: -1.0,
          max: 1.0,
          smallestNonzeroMagnitude: 0.5,
          allowNan: false,
          allowInfinity: false));
      if (value != 0.0) {
        expect(value.abs(), greaterThanOrEqualTo(0.5));
      }
    });

    hegelTest('zero-width range', (tc) {
      final value = tc.draw(
          doubles(min: 3.14, max: 3.14, allowNan: false, allowInfinity: false));
      expect(value, equals(3.14));
    });
  });

  group('booleans', () {
    hegelTest('valid bool', (tc) {
      final value = tc.draw(booleans());
      expect(value, isA<bool>());
    });

    hegelTest('bias p=0.0 always false', (tc) {
      final value = tc.draw(booleans(p: 0.0));
      expect(value, isFalse);
    });

    hegelTest('bias p=1.0 always true', (tc) {
      final value = tc.draw(booleans(p: 1.0));
      expect(value, isTrue);
    });
  });

  group('bigIntegers', () {
    hegelTest('bounds respected', (tc) {
      final min = BigInt.from(100);
      final max = BigInt.from(1000);
      final value = tc.draw(bigIntegers(min: min, max: max));
      expect(value, greaterThanOrEqualTo(min));
      expect(value, lessThanOrEqualTo(max));
    });

    hegelTest('large range (2^128)', (tc) {
      final min = -BigInt.two.pow(128);
      final max = BigInt.two.pow(128);
      final value = tc.draw(bigIntegers(min: min, max: max));
      expect(value, greaterThanOrEqualTo(min));
      expect(value, lessThanOrEqualTo(max));
    });
  });
}

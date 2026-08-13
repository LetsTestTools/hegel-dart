import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

void main() {
  group('input validation', () {
    // integers
    test('integers rejects inverted bounds', () {
      expect(() => integers(min: 10, max: 0), throwsArgumentError);
    });
    test('integers accepts equal bounds', () {
      // Should NOT throw
      integers(min: 5, max: 5);
    });

    // doubles
    test('doubles rejects inverted bounds', () {
      expect(() => doubles(min: 10.0, max: 0.0), throwsArgumentError);
    });
    test('doubles rejects NaN bounds', () {
      expect(() => doubles(min: double.nan), throwsArgumentError);
      expect(() => doubles(max: double.nan), throwsArgumentError);
    });

    // bigIntegers
    test('bigIntegers rejects inverted bounds', () {
      expect(
        () => bigIntegers(min: BigInt.from(100), max: BigInt.from(0)),
        throwsArgumentError,
      );
    });

    // text
    test('text rejects negative minSize', () {
      expect(() => text(minSize: -1), throwsArgumentError);
    });
    test('text rejects inverted sizes', () {
      expect(() => text(minSize: 10, maxSize: 5), throwsArgumentError);
    });
    test('text rejects codepoint > 0x10FFFF', () {
      expect(() => text(maxCodepoint: 0x110000), throwsArgumentError);
    });
    test('text rejects inverted codepoints', () {
      expect(
        () => text(minCodepoint: 100, maxCodepoint: 50),
        throwsArgumentError,
      );
    });

    // lists
    test('lists rejects negative minSize', () {
      expect(() => lists(integers(), minSize: -1), throwsArgumentError);
    });
    test('lists rejects inverted sizes', () {
      expect(
        () => lists(integers(), minSize: 10, maxSize: 5),
        throwsArgumentError,
      );
    });

    // sets
    test('sets rejects negative minSize', () {
      expect(() => sets(integers(), minSize: -1), throwsArgumentError);
    });
    test('sets rejects inverted sizes', () {
      expect(
        () => sets(integers(), minSize: 10, maxSize: 5),
        throwsArgumentError,
      );
    });

    // maps
    test('maps rejects negative minSize', () {
      expect(
        () => maps(integers(), integers(), minSize: -1),
        throwsArgumentError,
      );
    });
    test('maps rejects inverted sizes', () {
      expect(
        () => maps(integers(), integers(), minSize: 10, maxSize: 5),
        throwsArgumentError,
      );
    });

    // frequency
    test('frequency rejects empty list', () {
      expect(() => frequency<int>([]), throwsArgumentError);
    });
    test('frequency rejects all-zero weights', () {
      expect(() => frequency<int>([(0, integers())]), throwsArgumentError);
    });
    test('frequency rejects negative weights', () {
      expect(
        () => frequency<int>([(-1, integers()), (10, integers())]),
        throwsArgumentError,
      );
    });

    // sampled
    test('sampled rejects empty list', () {
      expect(() => sampled<int>([]), throwsArgumentError);
    });

    // oneOf
    test('oneOf rejects empty list', () {
      expect(() => oneOf<int>([]), throwsArgumentError);
    });
    // probability validation
    test('booleans rejects probability < 0', () {
      expect(() => booleans(p: -0.1), throwsArgumentError);
    });
    test('booleans rejects probability > 1', () {
      expect(() => booleans(p: 1.1), throwsArgumentError);
    });
    test('booleans accepts p=0 and p=1', () {
      booleans(p: 0.0);
      booleans(p: 1.0);
    });
    test('nullable rejects nullProbability < 0', () {
      expect(
        () => nullable(integers(), nullProbability: -0.5),
        throwsArgumentError,
      );
    });
    test('nullable rejects nullProbability > 1', () {
      expect(
        () => nullable(integers(), nullProbability: 1.5),
        throwsArgumentError,
      );
    });
  });
}

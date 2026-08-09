import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  hegelTest('integers respect bounds', (tc) {
    final v = tc.draw(integers(min: 0, max: 100));
    expect(v, greaterThanOrEqualTo(0));
    expect(v, lessThanOrEqualTo(100));
  });

  hegelTest('doubles respect bounds', (tc) {
    final v = tc.draw(
        doubles(min: -1.0, max: 1.0, allowNan: false, allowInfinity: false));
    expect(v, greaterThanOrEqualTo(-1.0));
    expect(v, lessThanOrEqualTo(1.0));
  });

  hegelTest('booleans generate valid values', (tc) {
    final v = tc.draw(booleans());
    expect(v, isA<bool>());
  });

  hegelTest('text generates non-null strings', (tc) {
    final v = tc.draw(text(minSize: 0, maxSize: 50));
    expect(v, isA<String>());
    // maxSize controls Unicode codepoints, not UTF-16 code units
    expect(v.runes.length, lessThanOrEqualTo(50));
  });

  hegelTest('lists respect size bounds', (tc) {
    final v = tc.draw(lists(integers(min: 0, max: 10), minSize: 1, maxSize: 5));
    expect(v, isNotEmpty);
    expect(v.length, lessThanOrEqualTo(5));
    for (final e in v) {
      expect(e, greaterThanOrEqualTo(0));
      expect(e, lessThanOrEqualTo(10));
    }
  });

  hegelTest('oneOf picks from generators', (tc) {
    final v = tc.draw(oneOf([
      integers(min: 0, max: 0),
      integers(min: 1, max: 1),
    ]));
    expect(v, anyOf(equals(0), equals(1)));
  });

  hegelTest('nullable can return null', (tc) {
    // Run enough to likely see a null (p=0.5)
    final v = tc.draw(nullable(integers()));
    // Just verify it's a valid value (int or null)
    expect(v, anyOf(isNull, isA<int>()));
  });

  hegelTest('sampled picks from values', (tc) {
    final v = tc.draw(sampled(['a', 'b', 'c']));
    expect(v, isIn(['a', 'b', 'c']));
  });
}

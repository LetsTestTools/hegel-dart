import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

void main() {
  group('text', () {
    hegelTest('allows empty strings', (tc) {
      final v = tc.draw(text(minSize: 0, maxSize: 10));
      expect(v, isA<String>());
    });

    hegelTest('non-empty when minSize > 0', (tc) {
      final v = tc.draw(text(minSize: 1, maxSize: 50));
      expect(v, isNotEmpty);
    });

    hegelTest('respects max codepoint count', (tc) {
      final v = tc.draw(text(minSize: 0, maxSize: 20));
      expect(v.runes.length, lessThanOrEqualTo(20));
    });

    hegelTest('ASCII only with codepoint range', (tc) {
      final v = tc.draw(
        text(minSize: 1, maxSize: 20, minCodepoint: 0x20, maxCodepoint: 0x7E),
      );
      for (final rune in v.runes) {
        expect(rune, greaterThanOrEqualTo(0x20));
        expect(rune, lessThanOrEqualTo(0x7E));
      }
    });
  });

  group('fromRegex', () {
    hegelTest('matches hex pattern', (tc) {
      final v = tc.draw(fromRegex('[0-9a-f]+'));
      expect(v, matches(RegExp(r'^[0-9a-f]+$')));
    });

    hegelTest('matches digit pattern', (tc) {
      final v = tc.draw(fromRegex('[0-9]{3}'));
      expect(v.length, equals(3));
      expect(v, matches(RegExp(r'^[0-9]{3}$')));
    });
  });

  group('emails', () {
    hegelTest('contains @', (tc) {
      final v = tc.draw(emails());
      expect(v, contains('@'));
    });

    hegelTest('has local and domain parts', (tc) {
      final v = tc.draw(emails());
      final parts = v.split('@');
      expect(parts.length, equals(2));
      expect(parts[0], isNotEmpty);
      expect(parts[1], isNotEmpty);
    });
  });

  group('uuids', () {
    hegelTest('has correct format', (tc) {
      final v = tc.draw(uuids());
      expect(v.length, equals(36));
      expect(v[8], equals('-'));
      expect(v[13], equals('-'));
      expect(v[18], equals('-'));
      expect(v[23], equals('-'));
    });

    hegelTest('matches uuid regex', (tc) {
      final v = tc.draw(uuids());
      expect(
        v,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('domains', () {
    hegelTest('non-empty', (tc) {
      final v = tc.draw(domains());
      expect(v, isNotEmpty);
    });
  });

  group('urls', () {
    hegelTest('parses as valid URI', (tc) {
      final v = tc.draw(urls());
      final uri = Uri.tryParse(v);
      expect(uri, isNotNull);
      expect(uri!.scheme, isNotEmpty);
    });
  });

  group('bytes', () {
    hegelTest('respects size bounds', (tc) {
      final v = tc.draw(bytes(minSize: 5, maxSize: 20));
      expect(v.length, greaterThanOrEqualTo(5));
      expect(v.length, lessThanOrEqualTo(20));
    });

    hegelTest('empty allowed', (tc) {
      final v = tc.draw(bytes(minSize: 0, maxSize: 0));
      expect(v.length, equals(0));
    });
  });
}

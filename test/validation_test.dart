import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';
import 'package:hegeltest/src/core/origin.dart';

void main() {
  group('extractOrigin', () {
    test(
      'skips flutter_test and hegeltest_flutter frames and strips parentheses',
      () {
        final fakeTrace = StackTrace.fromString('''
#0      fail (package:matcher/src/expect/expect.dart:187:31)
#1      _expect (package:matcher/src/expect/expect.dart:182:3)
#2      expect (package:flutter_test/src/widget_tester.dart:473:18)
#3      hegelFlutterLayoutSweepTest.<anonymous closure> (package:hegeltest_flutter/src/layout_sweep.dart:357:28)
#4      main.<anonymous closure> (file:///Users/ab/code/app/test/my_widget_test.dart:42:9)
''');
        expect(
          extractOrigin(fakeTrace),
          equals('file:///Users/ab/code/app/test/my_widget_test.dart:42:9'),
        );
      },
    );
  });

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

    // frequency / oneOfWeighted
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
    test('oneOfWeighted rejects empty list', () {
      expect(() => oneOfWeighted<int>([]), throwsArgumentError);
    });

    // sampled
    test('sampled rejects empty list', () {
      expect(() => sampled<int>([]), throwsArgumentError);
    });

    // sampledWeighted
    test('sampledWeighted rejects empty list', () {
      expect(() => sampledWeighted<int>([]), throwsArgumentError);
    });
    test('sampledWeighted rejects all-zero weights', () {
      expect(() => sampledWeighted<int>([(0, 42)]), throwsArgumentError);
    });
    test('sampledWeighted rejects negative weights', () {
      expect(
        () => sampledWeighted<int>([(-1, 1), (5, 2)]),
        throwsArgumentError,
      );
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

    test(
      'runHegelTest failure message reports winning shrunk counterexample',
      () async {
        final result = await runHegelTest(
          (tc) {
            final width = tc.draw(integers(min: 100, max: 500));
            if (width > 200) {
              throw StateError('overflow by ${width - 200}');
            }
          },
          testCases: 20,
          seed: 42,
          database: false,
        );

        expect(result.status, equals(RunStatus.failed));
        expect(result.failures, isNotEmpty);
        expect(result.failures.first.message, contains('overflow by 1'));
        expect(
          result.failures.first.message,
          contains('draw #1 (IntegerGenerator): 201'),
        );
      },
    );
  });
}

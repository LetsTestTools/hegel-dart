import 'dart:io';

import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

// To see how reproduce blocks work, run this file:
// `dart test example/reproduce_example.dart`
//
// It will fail because the sum of two positive integers is not always less than 100.
// Hegel will print a snippet of code like:
//
//   hegelTest(
//     'intentional failure',
//     (tc) { ... },
//     reproduce: '...',
//   );
//
// You can then paste that reproduce block here to deterministically reproduce the
// exact failing test case without searching for it again.

void main() {
  hegelTest(
    'intentional failure to show reproduce blob',
    (tc) {
      final a = tc.draw(integers(min: 1, max: 100));
      final b = tc.draw(integers(min: 1, max: 100));

      // This is a contrived bug!
      expect(a + b, lessThan(100), reason: 'a + b should be < 100');
    },
    // Uncomment and paste your reproduce block here to pin the failing case!
    // reproduce: '...',
  );

  // Alternatively, you can use the environment variable HEGEL_SEED=123456
  // in CI or your local environment to globally fix the seed for all tests,
  // making the entire suite run deterministically.
  hegelTest('seeded randomness', (tc) {
    final a = tc.draw(integers());

    // Check if HEGEL_SEED is set
    final seed = Platform.environment['HEGEL_SEED'];
    if (seed != null) {
      print('Running with fixed HEGEL_SEED=$seed');
    }

    expect(a, isA<int>());
  });
}

import 'package:hegeltest/hegeltest.dart';

void main() async {
  // Collect observation statistics programmatically with runHegelTest
  final result = await runHegelTest((tc) {
    final xs = tc.draw(
      lists(integers(min: -50, max: 50), minSize: 0, maxSize: 30),
    );

    // 1. Tally list length distribution
    tc.collect(switch (xs.length) {
      0 => 'empty (0)',
      < 5 => 'short (1-4)',
      < 15 => 'medium (5-14)',
      _ => 'large (15+)',
    }, label: 'list length');

    // 2. Tally content distribution
    final hasNeg = xs.any((n) => n < 0);
    final hasZero = xs.any((n) => n == 0);
    tc.collect(
      hasNeg ? 'contains negative' : 'all non-negative',
      label: 'sign breakdown',
    );
    if (hasZero) {
      tc.collect('contains zero', label: 'zero presence');
    }

    // Invariant: reversing a list preserves its length
    if (xs.reversed.length != xs.length) {
      throw StateError('Invariant violated: length changed on reverse');
    }
  }, testCases: 200);

  print('Status: ${result.status}');
  print('Test cases run: ${result.testCasesRun}');
  print('\nCollected distribution statistics:');
  print(result.formatStatistics());
}

import 'dart:async';

import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

/// Simulated async function to test.
Future<String> processAsync(String input) async {
  await Future<void>.delayed(const Duration(milliseconds: 1));
  return input.toUpperCase();
}

void main() {
  hegelTest('async processing preserves length', (tc) async {
    final input = tc.draw(text(minSize: 0, maxSize: 100));
    final result = await processAsync(input);
    expect(result.length, equals(input.length));
  });

  hegelTest('async processing is idempotent', (tc) async {
    final input = tc.draw(text(maxSize: 50));
    final once = await processAsync(input);
    final twice = await processAsync(once);
    expect(twice, equals(once));
  });
}

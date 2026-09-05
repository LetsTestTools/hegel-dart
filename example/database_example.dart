import 'dart:io';

import 'package:hegeltest/hegeltest.dart';

void main() async {
  // Use a local database directory to demonstrate persistence
  final dbDir = Directory('.hegel_demo_db');
  if (dbDir.existsSync()) {
    dbDir.deleteSync(recursive: true);
  }

  print('=== Run 1: Discovering and saving failing counterexample ===');
  var iterationsRun1 = 0;
  final result1 = await runHegelTest(
    (tc) {
      iterationsRun1++;
      final n = tc.draw(integers(min: 0, max: 1000));
      // Simulate a bug found only when n is 314
      if (n == 314) {
        throw StateError('Bug found: n cannot be 314!');
      }
    },
    database: true,
    databasePath: dbDir.path,
    databaseKey: 'demo_test_314',
    testCases: 500,
    seed: 42,
  );

  print('Run 1 Status: ${result1.status}');
  print('Run 1 Iterations until failure: $iterationsRun1');
  print(
    'Run 1 Failure message: ${result1.failures.first.message.split('\n').first}',
  );

  print('\n=== Run 2: Instant regression replay from database cache ===');
  var iterationsRun2 = 0;
  final result2 = await runHegelTest(
    (tc) {
      iterationsRun2++;
      final n = tc.draw(integers(min: 0, max: 1000));
      if (n == 314) {
        throw StateError('Bug found: n cannot be 314!');
      }
    },
    database: true,
    databasePath: dbDir.path,
    databaseKey: 'demo_test_314',
    testCases: 500,
    seed: 9999, // Completely different seed!
  );

  print('Run 2 Status: ${result2.status}');
  print(
    'Run 2 Iterations until failure: $iterationsRun2 (replayed instantly!)',
  );

  // Clean up demo directory
  try {
    dbDir.deleteSync(recursive: true);
  } catch (_) {}
}

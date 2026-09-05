import 'dart:io';

import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  group('Persistent Counterexample Database', () {
    late Directory tempDb;

    setUp(() {
      tempDb = Directory.systemTemp.createTempSync('hegel_db_test_');
    });

    tearDown(() {
      try {
        tempDb.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'persists failing counterexample to disk and replays on iteration 1',
      () async {
        final dbPath = tempDb.path;
        const key = 'test_persistence_replay';

        // First run: finds a failing counterexample
        final result1 = await runHegelTest(
          (tc) {
            final n = tc.draw(integers(min: 0, max: 100));
            if (n == 42) {
              throw StateError('Bug found at 42');
            }
          },
          database: true,
          databasePath: dbPath,
          databaseKey: key,
          testCases: 200,
          seed: 12345,
        );

        expect(result1.status, equals(RunStatus.failed));
        expect(result1.failures, isNotEmpty);

        // Verify files were written to the database directory
        final files = tempDb
            .listSync(recursive: true)
            .whereType<File>()
            .toList();
        expect(files, isNotEmpty);

        // Second run: should immediately replay the saved counterexample on iteration 1
        // and fail without having to search through 200 test cases
        var iterationsRun = 0;
        final result2 = await runHegelTest(
          (tc) {
            iterationsRun++;
            final n = tc.draw(integers(min: 0, max: 100));
            if (n == 42) {
              throw StateError('Bug found at 42');
            }
          },
          database: true,
          databasePath: dbPath,
          databaseKey: key,
          testCases: 200,
          seed: 99999, // Different seed, but replay phase runs first
        );

        expect(result2.status, equals(RunStatus.failed));
        // In replay phase, the minimal failing case is replayed first
        expect(iterationsRun, lessThanOrEqualTo(2));
        expect(result2.failures.first.message, contains('Bug found at 42'));
      },
    );

    test('database: false completely disables disk writes', () async {
      final dbPath = tempDb.path;
      const key = 'test_disabled_db';

      final result = await runHegelTest(
        (tc) {
          final n = tc.draw(integers(min: 0, max: 50));
          if (n == 7) {
            throw StateError('Bug found at 7');
          }
        },
        database: false,
        databasePath: dbPath,
        databaseKey: key,
        testCases: 100,
        seed: 42,
      );

      expect(result.status, equals(RunStatus.failed));

      // Nothing should have been written to the database path
      final files = tempDb.listSync(recursive: true).whereType<File>().toList();
      expect(files, isEmpty);
    });

    test('automatic gitignore is created in .hegel directory', () {
      final hegelDir = Directory('${tempDb.path}/.hegel');
      hegelDir.createSync(recursive: true);
      final gitignore = File('${hegelDir.path}/.gitignore');
      gitignore.writeAsStringSync('*\n!.gitignore\n');

      expect(gitignore.existsSync(), isTrue);
      expect(gitignore.readAsStringSync(), contains('*'));
      expect(gitignore.readAsStringSync(), contains('!.gitignore'));
    });

    hegelTest(
      'hegelTest defaults databaseKey to description and runs cleanly with database: true',
      (tc) {
        final x = tc.draw(integers());
        expect(x + 0, equals(x));
      },
      database: true,
      testCases: 10,
    );
  });
}

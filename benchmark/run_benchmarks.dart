import 'dart:io';
import 'package:hegeltest/hegeltest.dart';
import 'benchmark_harness.dart';

class User {
  final int id;
  final String name;
  final String email;
  final bool active;
  final List<String> tags;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.active,
    required this.tags,
  });
}

void main(List<String> args) async {
  final formatArg = args.firstWhere(
    (a) => a.startsWith('--format='),
    orElse: () => '--format=table',
  );
  final format = formatArg.split('=').last;

  final harness = BenchmarkHarness();

  if (format == 'table') {
    print(
      'Running Hegeltest performance benchmarks (this may take 10-20 seconds)...\n',
    );
  }

  // =========================================================================
  // Vector 1: Property Test Iteration Throughput
  // =========================================================================

  // 1.1 Pure loop overhead (no draws)
  await harness.measureAsync(
    name: 'empty_property_iteration',
    category: 'Throughput',
    warmup: 2,
    trials: 5,
    opsPerTrial: 10000,
    body: () async {
      await runHegelTest((tc) {}, testCases: 10000, database: false);
    },
  );

  // 1.2 Single integer draw
  await harness.measureAsync(
    name: 'integers_single_draw',
    category: 'Throughput',
    warmup: 2,
    trials: 5,
    opsPerTrial: 10000,
    body: () async {
      await runHegelTest(
        (tc) {
          final x = tc.draw(integers());
          if (x + 0 != x) throw StateError('Identity failed');
        },
        testCases: 10000,
        database: false,
      );
    },
  );

  // 1.3 Sampled weighted choice
  await harness.measureAsync(
    name: 'sampled_weighted_choice',
    category: 'Throughput',
    warmup: 2,
    trials: 5,
    opsPerTrial: 10000,
    body: () async {
      await runHegelTest(
        (tc) {
          final tier = tc.draw(
            sampledWeighted([(70, 'free'), (25, 'pro'), (5, 'enterprise')]),
          );
          if (tier.isEmpty) throw StateError('Empty tier');
        },
        testCases: 10000,
        database: false,
      );
    },
  );

  // 1.4 Composite user object
  await harness.measureAsync(
    name: 'composite_domain_object',
    category: 'Throughput',
    warmup: 2,
    trials: 5,
    opsPerTrial: 2500,
    body: () async {
      await runHegelTest(
        (tc) {
          final user = User(
            id: tc.draw(integers(min: 1, max: 100000)),
            name: tc.draw(text(minSize: 3, maxSize: 15)),
            email: tc.draw(emails()),
            active: tc.draw(booleans()),
            tags: tc.draw(
              lists(text(minSize: 2, maxSize: 8), minSize: 0, maxSize: 5),
            ),
          );
          if (user.id <= 0) throw StateError('Invalid id');
        },
        testCases: 2500,
        database: false,
      );
    },
  );

  // 1.5 Regex synthesizer
  await harness.measureAsync(
    name: 'regex_synthesizer',
    category: 'Throughput',
    warmup: 2,
    trials: 5,
    opsPerTrial: 1000,
    body: () async {
      await runHegelTest(
        (tc) {
          final s = tc.draw(fromRegex(r'[a-z0-9_-]{5,15}@[a-z]{3,8}\.org'));
          if (!s.contains('@')) throw StateError('Invalid email');
        },
        testCases: 1000,
        database: false,
      );
    },
  );

  // 1.6 Telemetry: classify & cover overhead
  await harness.measureAsync(
    name: 'coverage_contracts_telemetry',
    category: 'Throughput',
    warmup: 2,
    trials: 5,
    opsPerTrial: 5000,
    body: () async {
      await runHegelTest(
        (tc) {
          final n = tc.draw(integers(min: 0, max: 100));
          tc.classify(n == 0, 'zero');
          tc.classify(n > 50, 'upper');
          tc.cover(10.0, n > 50, 'upper half');
          tc.cover(0.5, n == 0, 'zero value');
        },
        testCases: 5000,
        database: false,
      );
    },
  );

  // =========================================================================
  // Vector 2: Shrinking Latency & Minimization Efficiency
  // =========================================================================

  // 2.1 Shrink integer failure (x > 50 -> 51)
  await harness.measureAsync(
    name: 'shrink_integer_boundary',
    category: 'Shrinking',
    warmup: 2,
    trials: 7,
    opsPerTrial: 1,
    body: () async {
      final res = await runHegelTest(
        (tc) {
          final x = tc.draw(integers(min: 0, max: 1000000));
          if (x > 50) throw StateError('Value exceeded 50: ');
        },
        testCases: 200,
        database: false,
      );
      if (res.status != RunStatus.failed) {
        throw StateError('Expected test failure');
      }
    },
  );

  // 2.2 Shrink list failure (find minimal failing list)
  await harness.measureAsync(
    name: 'shrink_list_element',
    category: 'Shrinking',
    warmup: 2,
    trials: 7,
    opsPerTrial: 1,
    body: () async {
      final res = await runHegelTest(
        (tc) {
          final xs = tc.draw(
            lists(integers(min: -100, max: 100), minSize: 10, maxSize: 50),
          );
          if (xs.any((v) => v < 0)) throw StateError('Negative element found');
        },
        testCases: 200,
        database: false,
      );
      if (res.status != RunStatus.failed) {
        throw StateError('Expected test failure');
      }
    },
  );

  // 2.3 Shrink string failure (find minimal offending character)
  await harness.measureAsync(
    name: 'shrink_string_delimiter',
    category: 'Shrinking',
    warmup: 2,
    trials: 7,
    opsPerTrial: 1,
    body: () async {
      final res = await runHegelTest(
        (tc) {
          final s = tc.draw(text(minSize: 10, maxSize: 50));
          if (s.contains('!')) throw StateError('Exclamation mark found');
        },
        testCases: 200,
        database: false,
      );
      if (res.status != RunStatus.failed) {
        throw StateError('Expected test failure');
      }
    },
  );

  // =========================================================================
  // Vector 3: Persistent Database Replay Velocity
  // =========================================================================

  final tmpDir = await Directory.systemTemp.createTemp('hegel_bench_db_');
  try {
    // Prime the database with a failing test case
    const dbKey = 'benchmark_replay_target';
    await runHegelTest(
      (tc) {
        final val = tc.draw(integers(min: 0, max: 1000));
        if (val > 100) throw StateError('Over 100: ');
      },
      testCases: 50,
      database: true,
      databasePath: tmpDir.path,
      databaseKey: dbKey,
    );

    // Benchmark Phase.reuse replay on iteration 1
    await harness.measureAsync(
      name: 'database_replay_cached_failure',
      category: 'Database',
      warmup: 3,
      trials: 10,
      opsPerTrial: 1,
      body: () async {
        final res = await runHegelTest(
          (tc) {
            final val = tc.draw(integers(min: 0, max: 1000));
            if (val > 100) throw StateError('Over 100: ');
          },
          testCases: 50,
          database: true,
          databasePath: tmpDir.path,
          databaseKey: dbKey,
        );
        if (res.status != RunStatus.failed) {
          throw StateError('Expected cached replay failure');
        }
      },
    );
  } finally {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  }

  // =========================================================================
  // Output Results
  // =========================================================================
  switch (format) {
    case 'json':
      stdout.writeln(harness.formatJson());
      break;
    case 'markdown':
      stdout.writeln(harness.formatMarkdown());
      break;
    case 'table':
    default:
      stdout.writeln(harness.formatTable());
      break;
  }
}

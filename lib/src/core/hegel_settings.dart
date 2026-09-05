import 'settings.dart';

/// Reusable configuration for hegelTest runs.
///
/// Extract shared settings to avoid repeating parameters:
/// ```dart
/// final fast = HegelConfig(testCases: 100);
/// final thorough = HegelConfig(testCases: 100000);
///
/// hegelTest('quick check', (tc) { ... }, config: fast);
/// hegelTest('exhaustive check', (tc) { ... }, config: thorough);
/// ```
class HegelConfig {
  /// The maximum number of test cases to run.
  final int? testCases;

  /// The PRNG seed to use for determinism.
  final int? seed;

  /// Whether to avoid randomizing generation if possible.
  final bool? derandomize;

  /// The property testing phases to execute.
  final Set<Phase>? phases;

  /// Control the verbosity of test output.
  final Verbosity? verbosity;

  /// A set of health checks to suppress.
  final Set<HealthCheck>? suppressHealthChecks;

  /// Whether to report all failures instead of stopping at the first.
  final bool? reportMultipleFailures;

  /// A specific reproduction blob to replay.
  final String? reproduce;

  /// An identifier for saving/loading from the database.
  final String? databaseKey;

  /// Whether to persist and replay counterexamples using the on-disk database.
  final bool? database;

  /// Custom path to the database directory (defaults to `.hegel/examples`).
  final String? databasePath;

  const HegelConfig({
    this.testCases,
    this.seed,
    this.derandomize,
    this.phases,
    this.verbosity,
    this.suppressHealthChecks,
    this.reportMultipleFailures,
    this.reproduce,
    this.databaseKey,
    this.database,
    this.databasePath,
  });
}

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
  final int? testCases;
  final int? seed;
  final bool? derandomize;
  final Set<Phase>? phases;
  final Verbosity? verbosity;
  final Set<HealthCheck>? suppressHealthChecks;
  final bool? reportMultipleFailures;
  final String? reproduce;
  final String? databaseKey;
  final String? database;

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
  });
}

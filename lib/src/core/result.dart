/// Status of a completed property test run.
enum RunStatus { passed, failed, error }

/// Structured classification for errored runs ([RunStatus.error]).
enum RunErrorKind {
  none,
  healthCheck,
  flaky,
  nondeterministic,
  unsatisfiable,
  usage,
  internal,
}

/// A falsifying test failure captured during a property test run.
class Failure {
  /// Formatted failure message including counterexample values and notes.
  final String message;

  /// Stack frame location where the failure originated.
  final String origin;

  /// Opaque base64 blob that deterministically replays this failure.
  final String reproductionBlob;

  /// Underlying exception or assertion error thrown by the test body, if any.
  final Object? exception;

  /// Creates a failure record for a falsified test case.
  const Failure({
    required this.message,
    required this.origin,
    required this.reproductionBlob,
    this.exception,
  });
}

/// Summary of a completed property test run from `runHegelTest`.
class RunResult {
  /// Overall outcome of the run.
  final RunStatus status;

  /// Structured error category when [status] is [RunStatus.error].
  final RunErrorKind errorKind;

  /// Diagnostic error message when [status] is [RunStatus.error], or `null`.
  final String? errorMessage;

  /// Recorded failures for falsified test cases (empty when passing).
  final List<Failure> failures;

  /// Total number of test cases executed during the run.
  final int testCasesRun;

  /// Observation distribution statistics collected via `TestCase.collect()`.
  ///
  /// Outer key is the label (or `""` for the default label).
  /// Inner map maps each observed value to its count.
  final Map<String, Map<String, int>> statistics;

  /// Creates a run result summary.
  const RunResult({
    required this.status,
    required this.testCasesRun,
    this.errorKind = RunErrorKind.none,
    this.errorMessage,
    this.failures = const [],
    this.statistics = const {},
  });

  /// Formatted percentage distribution of collected statistics.
  ///
  /// Returns an empty string if no statistics were collected.
  String formatStatistics() {
    if (statistics.isEmpty) return '';
    final buf = StringBuffer();
    for (final entry in statistics.entries) {
      final label = entry.key;
      final counts = entry.value;
      final total = counts.values.fold<int>(0, (sum, c) => sum + c);
      if (total == 0) continue;
      if (label.isNotEmpty) {
        buf.writeln('  $label:');
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final item in sorted) {
        final pct = (item.value / total * 100).toStringAsFixed(1);
        final prefix = label.isNotEmpty ? '    ' : '  ';
        buf.writeln('$prefix$pct% ${item.key}');
      }
    }
    return buf.toString();
  }
}

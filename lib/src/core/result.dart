enum RunStatus {
  passed,
  failed,
  error,

  // From hegel_run_status_t
  // 0 => PASSED
  // 1 => FAILED
  // 2 => ERROR
}

class Failure {
  final String message;
  final String origin;
  final String reproductionBlob;

  const Failure({
    required this.message,
    required this.origin,
    required this.reproductionBlob,
  });
}

class RunResult {
  final RunStatus status;
  final String? errorMessage;
  final List<Failure> failures;
  final int testCasesRun;

  /// Observation distribution statistics collected via `TestCase.collect()`.
  ///
  /// Outer key is the label (or `""` for the default label).
  /// Inner map maps each observed value to its count.
  final Map<String, Map<String, int>> statistics;

  const RunResult({
    required this.status,
    required this.testCasesRun,
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

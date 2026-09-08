import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Statistical measurement for a completed benchmark.
class BenchmarkResult {
  final String name;
  final String category;
  final int totalOps;
  final Duration totalElapsed;
  final List<double> trialDurationsMs;

  const BenchmarkResult({
    required this.name,
    required this.category,
    required this.totalOps,
    required this.totalElapsed,
    required this.trialDurationsMs,
  });

  double get opsPerSecond {
    final seconds = totalElapsed.inMicroseconds / 1000000.0;
    return seconds > 0 ? totalOps / seconds : 0;
  }

  double get meanMs {
    if (trialDurationsMs.isEmpty) return 0;
    return trialDurationsMs.reduce((a, b) => a + b) / trialDurationsMs.length;
  }

  double get medianMs {
    if (trialDurationsMs.isEmpty) return 0;
    final sorted = List<double>.from(trialDurationsMs)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[mid];
    } else {
      return (sorted[mid - 1] + sorted[mid]) / 2.0;
    }
  }

  double get p95Ms {
    if (trialDurationsMs.isEmpty) return 0;
    final sorted = List<double>.from(trialDurationsMs)..sort();
    final idx = ((sorted.length - 1) * 0.95).round();
    return sorted[idx];
  }

  double get minMs {
    if (trialDurationsMs.isEmpty) return 0;
    return trialDurationsMs.reduce((a, b) => a < b ? a : b);
  }

  double get maxMs {
    if (trialDurationsMs.isEmpty) return 0;
    return trialDurationsMs.reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'totalOps': totalOps,
    'totalElapsedMs': totalElapsed.inMicroseconds / 1000.0,
    'opsPerSecond': opsPerSecond,
    'meanMs': meanMs,
    'medianMs': medianMs,
    'p95Ms': p95Ms,
    'minMs': minMs,
    'maxMs': maxMs,
  };
}

/// Zero-dependency statistical benchmark harness for Hegel performance testing.
class BenchmarkHarness {
  final List<BenchmarkResult> _results = [];

  List<BenchmarkResult> get results => List.unmodifiable(_results);

  /// Run an asynchronous benchmark with warmup cycles and multiple trials.
  Future<BenchmarkResult> measureAsync({
    required String name,
    required String category,
    required FutureOr<void> Function() body,
    int warmup = 2,
    int trials = 7,
    int opsPerTrial = 1,
  }) async {
    // 1. Warmup cycles to warm up JIT, FFI call sites, and memory buffers
    for (var i = 0; i < warmup; i++) {
      await body();
    }

    // 2. Timed measurement trials
    final trialDurationsMs = <double>[];
    final totalWatch = Stopwatch()..start();

    for (var i = 0; i < trials; i++) {
      final trialWatch = Stopwatch()..start();
      await body();
      trialWatch.stop();
      trialDurationsMs.add(trialWatch.elapsedMicroseconds / 1000.0);
    }
    totalWatch.stop();

    final result = BenchmarkResult(
      name: name,
      category: category,
      totalOps: trials * opsPerTrial,
      totalElapsed: totalWatch.elapsed,
      trialDurationsMs: trialDurationsMs,
    );

    _results.add(result);
    return result;
  }

  /// Format all collected results into a terminal table.
  String formatTable() {
    final buf = StringBuffer();
    buf.writeln(
      '========================================================================================================',
    );
    buf.writeln(' LETSTESTTOOLS / HEGELTEST PERFORMANCE BENCHMARKS');
    buf.writeln(
      ' Platform: ${Platform.operatingSystem} (${Platform.version.split(" ").first})',
    );
    buf.writeln(
      '========================================================================================================',
    );
    buf.writeln(
      '${'Category'.padRight(16)} | ${'Benchmark'.padRight(36)} | ${'Ops/Sec'.padLeft(12)} | ${'Median'.padLeft(10)} | ${'P95'.padLeft(10)} | ${'Trials'.padLeft(6)}',
    );
    buf.writeln(
      '-----------------+--------------------------------------+--------------+------------+------------+-------',
    );

    String? currentCategory;
    for (final r in _results) {
      if (currentCategory != null && currentCategory != r.category) {
        buf.writeln(
          '-----------------+--------------------------------------+--------------+------------+------------+-------',
        );
      }
      currentCategory = r.category;

      final opsStr = r.opsPerSecond >= 10000
          ? '${(r.opsPerSecond / 1000.0).toStringAsFixed(1)}k/s'
          : '${r.opsPerSecond.toStringAsFixed(0)}/s';
      final medianStr = '${r.medianMs.toStringAsFixed(3)}ms';
      final p95Str = '${r.p95Ms.toStringAsFixed(3)}ms';

      buf.writeln(
        '${r.category.padRight(16)} | ${r.name.padRight(36)} | ${opsStr.padLeft(12)} | ${medianStr.padLeft(10)} | ${p95Str.padLeft(10)} | ${r.trialDurationsMs.length.toString().padLeft(6)}',
      );
    }
    buf.writeln(
      '========================================================================================================',
    );
    return buf.toString();
  }

  /// Format all collected results into a GitHub-flavored Markdown table.
  String formatMarkdown() {
    final buf = StringBuffer();
    buf.writeln('### Hegeltest Benchmark Results');
    buf.writeln();
    buf.writeln(
      '| Category | Benchmark | Throughput | Median Latency | P95 Latency | Samples |',
    );
    buf.writeln('|:---|:---|---:|---:|---:|---:|');

    for (final r in _results) {
      final opsStr = r.opsPerSecond >= 10000
          ? '${(r.opsPerSecond / 1000.0).toStringAsFixed(1)}k ops/s'
          : '${r.opsPerSecond.toStringAsFixed(0)} ops/s';
      buf.writeln(
        '| **${r.category}** | `${r.name}` | **$opsStr** | ${r.medianMs.toStringAsFixed(3)} ms | ${r.p95Ms.toStringAsFixed(3)} ms | ${r.trialDurationsMs.length} |',
      );
    }
    buf.writeln();
    return buf.toString();
  }

  /// Export results as formatted JSON string.
  String formatJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'dartVersion': Platform.version,
      'benchmarks': _results.map((r) => r.toJson()).toList(),
    });
  }
}

/// Stub implementation for platforms that don't support dart:ffi (e.g., web).
///
/// This file is conditionally imported when dart.library.io is not available.
/// All functions throw [UnsupportedError] at runtime.
library;

// ignore_for_file: avoid_unused_constructor_parameters

import 'result.dart';

/// Throws [UnsupportedError] — hegeltest requires dart:ffi.
Never _unsupported() => throw UnsupportedError(
  'hegeltest requires dart:ffi and is not supported on web. '
  'Use hegeltest only in VM-based test environments (dart test, flutter test on mobile/desktop).',
);

/// Stub for [hegelTest] on unsupported platforms.
///
/// Accepts the same parameters as the real implementation so that
/// code compiles on web even though it cannot run.
void hegelTest(
  String description,
  Function body, {
  dynamic timeout,
  dynamic tags,
  dynamic skip,
  dynamic onPlatform,
  dynamic retry,
  dynamic config,
  int? testCases,
  int? seed,
  bool? derandomize,
  dynamic phases,
  dynamic verbosity,
  dynamic suppressHealthChecks,
  bool? reportMultipleFailures,
  String? reproduce,
  String? databaseKey,
  bool? database,
  String? databasePath,
  dynamic Function()? setUpEach,
  dynamic Function()? tearDownEach,
}) => _unsupported();

/// Stub for [runHegelTest] on unsupported platforms.
Future<RunResult> runHegelTest(
  Function body, {
  dynamic config,
  int? testCases,
  int? seed,
  bool? derandomize,
  dynamic phases,
  dynamic verbosity,
  dynamic suppressHealthChecks,
  bool? reportMultipleFailures,
  String? reproduce,
  String? databaseKey,
  bool? database,
  String? databasePath,
  dynamic Function()? setUpEach,
  dynamic Function()? tearDownEach,
}) => _unsupported();

/// Stub for [HegelRunner] on unsupported platforms.
class HegelRunner {
  HegelRunner(dynamic lib);

  /// Stub — throws [UnsupportedError].
  Future<void> run(
    Function body, {
    String? reproduceBlob,
    int? testCases,
    int? seed,
    bool? derandomize,
    dynamic phases,
    dynamic verbosity,
    dynamic suppressHealthChecks,
    bool? reportMultipleFailures,
    String? databaseKey,
    bool? database,
    String? databasePath,
    dynamic Function()? setUpEach,
    dynamic Function()? tearDownEach,
  }) => _unsupported();

  /// Stub — throws [UnsupportedError].
  Future<RunResult> runWithResult(
    Function body, {
    String? reproduceBlob,
    int? testCases,
    int? seed,
    bool? derandomize,
    dynamic phases,
    dynamic verbosity,
    dynamic suppressHealthChecks,
    bool? reportMultipleFailures,
    String? databaseKey,
    bool? database,
    String? databasePath,
    dynamic Function()? setUpEach,
    dynamic Function()? tearDownEach,
  }) => _unsupported();
}

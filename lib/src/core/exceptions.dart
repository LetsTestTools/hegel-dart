/// Exceptions for the Hegel property-based testing framework.
library;

import 'dart:ffi';

import 'package:test/test.dart' show TestFailure;

import '../ffi/hegel_bindings.g.dart';
import '../ffi/string_helpers.dart';

/// Thrown when the engine's choice budget is exhausted.
///
/// The test body should stop drawing and return. This is an internal
/// control flow signal — users should not catch this.
class HegelStopTest implements Exception {
  const HegelStopTest();

  @override
  String toString() => 'HegelStopTest: choice budget exhausted';
}

/// Thrown when a [TestCase.assume] precondition fails.
///
/// The current test case is discarded and a new one is drawn.
class HegelAssumptionViolated implements Exception {
  const HegelAssumptionViolated();

  @override
  String toString() => 'HegelAssumptionViolated';
}

/// Thrown for engine-level errors from libhegel.
///
/// Wraps a human-readable error message and the native result code.
class HegelException implements Exception {
  /// A human-readable description of the error.
  final String message;

  /// The native `hegel_result_t` error code.
  final int resultCode;

  const HegelException(this.message, [this.resultCode = 0]);

  @override
  String toString() => 'HegelException($resultCode): $message';
}

/// Thrown when a property-based test finds a counterexample.
///
/// Extends [TestFailure] from `package:test_api` so that `package:test`
/// displays the failure message cleanly without framework stack traces.
class HegelTestFailure extends TestFailure {
  @override
  // ignore: overridden_fields
  final String message;

  HegelTestFailure(this.message) : super(message);
}

/// Thrown when a property test fails to meet a registered coverage target ([TestCase.cover]).
class InsufficientCoverageException extends HegelTestFailure {
  final String label;
  final double requiredPercent;
  final double actualPercent;
  final int hitCount;
  final int totalCount;

  InsufficientCoverageException({
    required this.label,
    required this.requiredPercent,
    required this.actualPercent,
    required this.hitCount,
    required this.totalCount,
  }) : super(
         'Insufficient test coverage for "$label": required ${requiredPercent.toStringAsFixed(1)}%, '
         'got ${actualPercent.toStringAsFixed(1)}% ($hitCount/$totalCount cases).',
       );
}

/// Extracts the last error message from the native engine context.
///
/// Returns `null` if the error message is empty. The returned string is
/// copied immediately into Dart memory before the next `libhegel` call
/// invalidates the context's internal buffer.
String? nativeErrorDetail(Pointer<hegel_context_t> ctx) {
  final err = hegel_context_last_error(ctx);
  final msg = readHegelString(err);
  return msg.isEmpty ? null : msg;
}

/// Creates a [HegelException] enriched with the native engine's
/// last error diagnostic when available.
HegelException hegelExceptionWithDetail(
  Pointer<hegel_context_t> ctx,
  String message,
  int resultCode,
) {
  final detail = nativeErrorDetail(ctx);
  final fullMessage = detail != null ? '$message ($detail)' : message;
  return HegelException(fullMessage, resultCode);
}

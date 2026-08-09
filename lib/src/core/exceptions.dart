/// Exceptions for the Hegel property-based testing framework.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';

/// Thrown when the engine's choice budget is exhausted.
///
/// The test body should stop drawing and return. This is an internal
/// control flow signal — users should not catch this.
class HegelStopTest implements Exception {
  const HegelStopTest();

  @override
  String toString() => 'HegelStopTest: choice budget exhausted';
}

/// Thrown when an [TestCase.assume] precondition fails.
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
class HegelTestFailure implements Exception {
  /// Human-readable failure message including origin and reproduce blob.
  final String message;

  const HegelTestFailure(this.message);

  @override
  String toString() => message;
}

/// Extract the last error message from the native engine context.
///
/// Returns `null` if the pointer is null or the string is empty.
/// The returned pointer borrows `ctx`'s internal buffer and is
/// invalidated by the next libhegel call — we copy to a Dart string
/// immediately.
String? nativeErrorDetail(LibHegel lib, Pointer<hegel_context_t> ctx) {
  final errPtr = lib.hegel_context_last_error(ctx);
  if (errPtr == nullptr) return null;
  final msg = errPtr.cast<Utf8>().toDartString();
  return msg.isEmpty ? null : msg;
}

/// Create a [HegelException] enriched with the native engine's
/// last error diagnostic when available.
HegelException hegelExceptionWithDetail(
  LibHegel lib,
  Pointer<hegel_context_t> ctx,
  String message,
  int resultCode,
) {
  final detail = nativeErrorDetail(lib, ctx);
  final fullMessage = detail != null ? '$message ($detail)' : message;
  return HegelException(fullMessage, resultCode);
}

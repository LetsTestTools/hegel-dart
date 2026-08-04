/// Exceptions for the Hegel property-based testing framework.

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

import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../ffi/hegel_bindings.g.dart';
import '../generators/generator.dart';
import 'exceptions.dart';

/// Resource handle for GC-based cleanup of cloned test cases.
class _OwnedTestCaseResource {
  final LibHegel lib;
  final Pointer<hegel_context_t> ctx;
  final Pointer<hegel_test_case_t> handle;

  _OwnedTestCaseResource(this.lib, this.ctx, this.handle);
}

/// GC safety net: if a cloned TestCase is collected without dispose(),
/// the native handle is freed automatically.
final Finalizer<_OwnedTestCaseResource> _testCaseFinalizer =
    Finalizer((res) {
  res.lib.hegel_test_case_free(res.ctx, res.handle);
});

/// A wrapper around a Hegel test case handle.
///
/// Cloned test cases (from [clone]) own their handle and MUST be
/// disposed via [dispose] when no longer needed. A GC finalizer
/// provides a safety net but should not be relied upon.
///
/// All methods throw [StateError] if called after [invalidate] or
/// [dispose].
class TestCase {
  final Pointer<hegel_context_t> _ctx;
  final Pointer<hegel_test_case_t> _handle;
  final LibHegel _lib;
  final bool _isOwned;
  bool _isDisposed = false;

  TestCase(this._ctx, this._handle, this._lib, {bool isOwned = false})
      : _isOwned = isOwned;

  /// Internal accessors used by generators.
  Pointer<hegel_context_t> get ctx {
    _checkNotDisposed();
    return _ctx;
  }

  Pointer<hegel_test_case_t> get handle {
    _checkNotDisposed();
    return _handle;
  }

  LibHegel get lib {
    _checkNotDisposed();
    return _lib;
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError(
        'TestCase used after disposal. Do not capture TestCase '
        'references outside the test body or unawaited Futures.',
      );
    }
  }

  /// Draw a value from the given generator.
  T draw<T>(Generator<T> gen, {String? name}) {
    _checkNotDisposed();
    return gen.generate(this);
  }

  /// Assume a condition holds. If it doesn't, this test case is discarded.
  void assume(bool condition) {
    if (!condition) {
      throw const HegelAssumptionViolated();
    }
  }

  /// Record a numeric observation for the engine's targeting phase.
  void target(double value, {required String label}) {
    _checkNotDisposed();
    using((Arena arena) {
      final labelPtr = label.toNativeUtf8(allocator: arena).cast<Char>();
      final result = _lib.hegel_target(_ctx, _handle, value, labelPtr);
      if (result.value != hegel_result_t.HEGEL_OK.value) {
        throw StateError('Failed to record target: ${result.value}');
      }
    });
  }

  /// Clone this test case onto an independent stream.
  ///
  /// The caller is responsible for calling [dispose] on the returned
  /// test case to free native memory. A GC finalizer provides a safety
  /// net, but timely disposal is strongly recommended.
  TestCase clone() {
    _checkNotDisposed();
    return using((Arena arena) {
      final outTestCase = arena<Pointer<hegel_test_case_t>>();
      final result = _lib.hegel_test_case_clone(_ctx, _handle, outTestCase);
      if (result.value != hegel_result_t.HEGEL_OK.value) {
        throw StateError('Failed to clone test case: ${result.value}');
      }
      final cloned = TestCase(_ctx, outTestCase.value, _lib, isOwned: true);
      // Attach GC finalizer as safety net
      final resource = _OwnedTestCaseResource(_lib, _ctx, outTestCase.value);
      _testCaseFinalizer.attach(cloned, resource, detach: cloned);
      return cloned;
    });
  }

  /// Free this test case's native handle.
  ///
  /// Only valid for cloned test cases. The runner manages the lifecycle
  /// of primary test cases.
  void dispose() {
    if (_isDisposed) return; // idempotent
    if (_isOwned) {
      _testCaseFinalizer.detach(this);
      _lib.hegel_test_case_free(_ctx, _handle);
    }
    _isDisposed = true;
  }

  /// Mark this test case as no longer usable.
  ///
  /// Called by the runner after each test case completes to prevent
  /// zombie usage from captured closures.
  void invalidate() {
    _isDisposed = true;
  }

  /// Open a labeled span around a group of draws.
  void startSpan(int label) {
    _checkNotDisposed();
    final result = _lib.hegel_start_span(_ctx, _handle, label);
    if (result.value != hegel_result_t.HEGEL_OK.value) {
      throw StateError('Failed to start span: ${result.value}');
    }
  }

  /// Close the most-recently opened span.
  void stopSpan({bool discard = false}) {
    _checkNotDisposed();
    final result = _lib.hegel_stop_span(_ctx, _handle, discard);
    if (result.value != hegel_result_t.HEGEL_OK.value) {
      throw StateError('Failed to stop span: ${result.value}');
    }
  }
}

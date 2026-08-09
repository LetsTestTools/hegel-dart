import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../ffi/hegel_bindings.g.dart';
import '../generators/generator.dart';
import 'exceptions.dart';

/// Shared lifecycle state between the runner and all test cases
/// (primary + clones) created during a single run.
///
/// The runner sets [isAlive] to `false` before freeing the native
/// context, which prevents both zombie usage AND the GC finalizer
/// from touching freed memory.
@internal
class RunLifecycle {
  bool isAlive = true;
}

/// Resource handle for GC-based cleanup of cloned test cases.
class _OwnedTestCaseResource {
  final LibHegel lib;
  final Pointer<hegel_context_t> ctx;
  final Pointer<hegel_test_case_t> handle;
  final RunLifecycle lifecycle;

  _OwnedTestCaseResource(this.lib, this.ctx, this.handle, this.lifecycle);
}

/// GC safety net: if a cloned TestCase is collected without dispose(),
/// the native handle is freed automatically — but only if the run is
/// still alive (i.e. the context hasn't been freed yet).
final Finalizer<_OwnedTestCaseResource> _testCaseFinalizer = Finalizer((res) {
  if (res.lifecycle.isAlive) {
    stderr.writeln(
      '[hegeltest] Warning: A cloned TestCase was not disposed. '
      'Call dispose() explicitly to ensure deterministic cleanup. '
      'GC-triggered disposal may cause non-deterministic behavior.',
    );
    res.lib.hegel_test_case_free(res.ctx, res.handle);
  }
  // If the run has ended, ctx is already freed — skip to avoid UAF.
});

/// A wrapper around a Hegel test case handle.
///
/// Cloned test cases (from [clone]) own their handle and MUST be
/// disposed via [dispose] when no longer needed. A GC finalizer
/// provides a safety net but should not be relied upon.
///
/// All methods throw [StateError] if called after the run completes,
/// after [invalidate], or after [dispose].
class TestCase {
  final Pointer<hegel_context_t> _ctx;
  final Pointer<hegel_test_case_t> _handle;
  final LibHegel _lib;
  final bool _isOwned;
  final RunLifecycle _lifecycle;
  bool _isDisposed = false;

  /// Shared buffer cache — owned by the runner, survives across iterations.
  /// Cloned test cases get their own private cache.
  final Map<String, Pointer<Void>> _bufferCache;

  /// Get or allocate a reusable native buffer by a string key.
  ///
  /// This avoids per-draw calloc/free overhead. Buffers are
  /// freed by the runner at end-of-run (for primary test cases)
  /// or by dispose() (for clones).
  @internal
  Pointer<T> reuseBuffer<T extends NativeType>(
      String key, Pointer<T> Function() allocate) {
    _checkNotDisposed();
    final existing = _bufferCache[key];
    if (existing != null) return existing.cast<T>();
    final ptr = allocate();
    _bufferCache[key] = ptr.cast<Void>();
    return ptr;
  }

  /// Log of drawn values for counterexample reporting.
  /// Stores raw objects; formatting is deferred until failure.
  final List<(String label, Object? value)> _drawLog = [];

  /// Creates a test case wrapper.
  ///
  /// This constructor is internal — only [HegelRunner] should
  /// instantiate test cases.
  @internal
  TestCase(
    this._ctx,
    this._handle,
    this._lib,
    this._lifecycle, {
    bool isOwned = false,
    Map<String, Pointer<Void>>? bufferCache,
  })  : _isOwned = isOwned,
        _bufferCache = bufferCache ?? {};

  /// Internal accessors used by generators.
  @internal
  Pointer<hegel_context_t> get ctx {
    _checkNotDisposed();
    return _ctx;
  }

  @internal
  Pointer<hegel_test_case_t> get handle {
    _checkNotDisposed();
    return _handle;
  }

  @internal
  LibHegel get lib {
    _checkNotDisposed();
    return _lib;
  }

  void _checkNotDisposed() {
    if (_isDisposed || !_lifecycle.isAlive) {
      throw StateError(
        'TestCase used after disposal. Do not capture TestCase '
        'references outside the test body or unawaited Futures.',
      );
    }
  }

  /// Draw a value from the given generator.
  ///
  /// Each draw is recorded in the draw log for counterexample reporting.
  /// Value formatting is deferred until a failure actually occurs to
  /// avoid allocating strings on the ~99.9% passing path.
  T draw<T>(Generator<T> gen, {String? label}) {
    _checkNotDisposed();
    final value = gen.generate(this);
    final drawLabel = label ?? gen.runtimeType.toString();
    _drawLog.add((drawLabel, value));
    return value;
  }

  /// The recorded draws for this test case iteration, formatted for display.
  ///
  /// Used by the runner to include counterexample values in failure messages.
  /// Formatting happens here (on failure) instead of in draw() (on every call).
  @internal
  List<(String, String)> get drawLog =>
      _drawLog.map((e) => (e.$1, _formatValue(e.$2))).toList(growable: false);

  /// Reset the draw log for the next iteration.
  @internal
  void resetDrawLog() => _drawLog.clear();

  static String _formatValue(Object? value) {
    final s = value.toString();
    // Truncate very long values to keep output readable.
    return s.length > 200 ? '${s.substring(0, 200)}...' : s;
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
    if (label.contains('\x00')) {
      throw ArgumentError.value(
        label,
        'label',
        'must not contain null bytes — they cause silent '
            'truncation at the FFI boundary',
      );
    }
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
  @internal
  TestCase clone() {
    _checkNotDisposed();
    return using((Arena arena) {
      final outTestCase = arena<Pointer<hegel_test_case_t>>();
      final result = _lib.hegel_test_case_clone(_ctx, _handle, outTestCase);
      if (result.value != hegel_result_t.HEGEL_OK.value) {
        throw StateError('Failed to clone test case: ${result.value}');
      }
      final cloned = TestCase(
        _ctx,
        outTestCase.value,
        _lib,
        _lifecycle,
        isOwned: true,
      );
      // Attach GC finalizer as safety net
      final resource = _OwnedTestCaseResource(
        _lib,
        _ctx,
        outTestCase.value,
        _lifecycle,
      );
      _testCaseFinalizer.attach(cloned, resource, detach: cloned);
      return cloned;
    });
  }

  /// Free this test case's native handle.
  ///
  /// Only valid for cloned test cases. The runner manages the lifecycle
  /// of primary test cases.
  @internal
  void dispose() {
    if (_isDisposed) return; // idempotent
    // Free clone's own buffer cache to prevent FFI memory leaks.
    if (_isOwned) {
      _freeBufferCache();
    }
    if (_isOwned && _lifecycle.isAlive) {
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
    _drawLog.clear();
    _isDisposed = true;
    // NOTE: buffer cache is NOT freed here — it's owned by the runner
    // and shared across iterations for performance.
  }

  /// Free all native buffers in the cache.
  void _freeBufferCache() {
    for (final ptr in _bufferCache.values) {
      calloc.free(ptr);
    }
    _bufferCache.clear();
  }

  /// Open a labeled span around a group of draws.
  @internal
  void startSpan(int label) {
    _checkNotDisposed();
    final result = _lib.hegel_start_span(_ctx, _handle, label);
    if (result.value != hegel_result_t.HEGEL_OK.value) {
      throw StateError('Failed to start span: ${result.value}');
    }
  }

  /// Close the most-recently opened span.
  @internal
  void stopSpan({bool discard = false}) {
    _checkNotDisposed();
    final result = _lib.hegel_stop_span(_ctx, _handle, discard);
    if (result.value != hegel_result_t.HEGEL_OK.value) {
      throw StateError('Failed to stop span: ${result.value}');
    }
  }

  /// Close a span safely in a `finally` block.
  ///
  /// Only swallows [StateError] when [hadError] is `true`,
  /// meaning an exception is already propagating. On the happy
  /// path ([hadError] = `false`), errors bubble up normally so
  /// span mismatches and engine corruption are never hidden.
  @internal
  void safeStopSpan({bool discard = false, bool hadError = true}) {
    if (hadError) {
      try {
        stopSpan(discard: discard);
      } on StateError {
        // Engine in terminal state — swallow to avoid masking.
      }
    } else {
      stopSpan(discard: discard);
    }
  }
}

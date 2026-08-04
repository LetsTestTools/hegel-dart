import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../ffi/hegel_bindings.g.dart';
import '../generators/generator.dart';
import 'exceptions.dart';

/// A wrapper around a Hegel test case handle.
class TestCase {
  final Pointer<hegel_context_t> _ctx;
  final Pointer<hegel_test_case_t> _handle;
  final LibHegel _lib;

  TestCase(this._ctx, this._handle, this._lib);

  /// Internal accessors used by generators.
  Pointer<hegel_context_t> get ctx => _ctx;
  Pointer<hegel_test_case_t> get handle => _handle;
  LibHegel get lib => _lib;

  /// Draw a value from the given generator.
  T draw<T>(Generator<T> gen, {String? name}) {
    // We ignore the name for now, or we could start a span if it's provided.
    // However, span labels are ints (hegel_label_t). So name might just be conceptual.
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
    using((Arena arena) {
      final labelPtr = label.toNativeUtf8(allocator: arena).cast<Char>();
      final result = _lib.hegel_target(_ctx, _handle, value, labelPtr);
      if (result.value != hegel_result_t.HEGEL_OK.value) {
        throw StateError('Failed to record target: ${result.value}');
      }
    });
  }

  /// Clone this test case onto an independent stream.
  TestCase clone() {
    return using((Arena arena) {
      final outTestCase = arena<Pointer<hegel_test_case_t>>();
      final result = _lib.hegel_test_case_clone(_ctx, _handle, outTestCase);
      if (result.value != hegel_result_t.HEGEL_OK.value) {
        throw StateError('Failed to clone test case: ${result.value}');
      }
      return TestCase(_ctx, outTestCase.value, _lib);
    });
  }

  /// Open a labeled span around a group of draws.
  void startSpan(int label) {
    final result = _lib.hegel_start_span(_ctx, _handle, label);
    if (result.value != hegel_result_t.HEGEL_OK.value) {
      throw StateError('Failed to start span: ${result.value}');
    }
  }

  /// Close the most-recently opened span.
  void stopSpan({bool discard = false}) {
    final result = _lib.hegel_stop_span(_ctx, _handle, discard);
    if (result.value != hegel_result_t.HEGEL_OK.value) {
      throw StateError('Failed to stop span: ${result.value}');
    }
  }
}

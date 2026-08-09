import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class BytesGenerator extends Generator<Uint8List> {
  final int minSize;
  final int maxSize;

  const BytesGenerator(this.minSize, this.maxSize);

  @override
  Uint8List generate(TestCase tc) {
    return using((Arena arena) {
      final outResult = arena<hegel_generate_bytes_result_t>();
      final result = tc.lib.hegel_generate_bytes(
        tc.ctx,
        tc.handle,
        minSize,
        maxSize,
        outResult,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate bytes: ${result.value}');
      }

      try {
        final data = outResult.ref.data;
        final len = outResult.ref.len;
        if (len == 0) return Uint8List(0);
        
        final uint8List = data.asTypedList(len);
        return Uint8List.fromList(uint8List);
      } finally {
        tc.lib.hegel_generate_bytes_result_free(tc.ctx, outResult);
      }
    });
  }
}

/// Generates a Uint8List of random bytes.
///
/// ```dart
/// tc.draw(bytes(minSize: 16, maxSize: 16))
/// ```
Generator<Uint8List> bytes({int minSize = 0, int maxSize = 100}) {
  return BytesGenerator(minSize, maxSize);
}

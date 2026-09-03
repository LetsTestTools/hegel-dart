import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class IntegerGenerator extends Generator<int> {
  final int min;
  final int max;

  IntegerGenerator(this.min, this.max) {
    if (min > max) {
      throw ArgumentError('integers: min ($min) must be <= max ($max)');
    }
  }

  @override
  int generate(TestCase tc) {
    final outValue = tc.reuseBuffer<ffi.Int64>(
      'int64',
      () => calloc<ffi.Int64>(),
    );
    final result = tc.lib.hegel_generate_integer(
      tc.ctx,
      tc.handle,
      min,
      max,
      outValue,
    );

    if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
      throw const HegelStopTest();
    }
    if (result != hegel_result_t.HEGEL_OK) {
      throw HegelException('Failed to generate integer: ${result.value}');
    }

    return outValue.value;
  }
}

/// Generates random integers.
///
/// By default, generates across the full Int64 range.
///
/// ```dart
/// tc.draw(integers(min: 0, max: 100))
/// ```
Generator<int> integers({
  int min = -9223372036854775808,
  int max = 9223372036854775807,
}) {
  return IntegerGenerator(min, max);
}

class DoubleGenerator extends Generator<double> {
  final double min;
  final double max;
  final bool allowNan;
  final bool allowInfinity;
  final bool excludeMin;
  final bool excludeMax;
  final double smallestNonzeroMagnitude;

  DoubleGenerator(
    this.min,
    this.max,
    this.allowNan,
    this.allowInfinity,
    this.excludeMin,
    this.excludeMax,
    this.smallestNonzeroMagnitude,
  ) {
    if (min.isNaN || max.isNaN) {
      throw ArgumentError('doubles: min and max must not be NaN');
    }
    if (min > max) {
      throw ArgumentError('doubles: min ($min) must be <= max ($max)');
    }
  }

  @override
  double generate(TestCase tc) {
    final outValue = tc.reuseBuffer<ffi.Double>(
      'double',
      () => calloc<ffi.Double>(),
    );
    final result = tc.lib.hegel_generate_float(
      tc.ctx,
      tc.handle,
      64,
      min,
      max,
      allowNan,
      allowInfinity,
      excludeMin,
      excludeMax,
      smallestNonzeroMagnitude,
      outValue,
    );

    if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
      throw const HegelStopTest();
    }
    if (result != hegel_result_t.HEGEL_OK) {
      throw HegelException('Failed to generate double: ${result.value}');
    }

    return outValue.value;
  }
}

/// Generates random double-precision floating-point numbers.
///
/// By default, generates from negative infinity to infinity, allowing NaN.
///
/// ```dart
/// tc.draw(doubles(min: 0.0, max: 1.0))
/// ```
Generator<double> doubles({
  double min = double.negativeInfinity,
  double max = double.infinity,
  bool allowNan = true,
  bool allowInfinity = true,
  bool excludeMin = false,
  bool excludeMax = false,
  double smallestNonzeroMagnitude = 5e-324,
}) {
  return DoubleGenerator(
    min,
    max,
    allowNan,
    allowInfinity,
    excludeMin,
    excludeMax,
    smallestNonzeroMagnitude,
  );
}

class BooleanGenerator extends Generator<bool> {
  final double p;

  BooleanGenerator(this.p) {
    if (p < 0.0 || p > 1.0) {
      throw ArgumentError('booleans: probability p ($p) must be in [0.0, 1.0]');
    }
  }

  @override
  bool generate(TestCase tc) {
    final outValue = tc.reuseBuffer<ffi.Bool>('bool', () => calloc<ffi.Bool>());
    final result = tc.lib.hegel_generate_boolean(
      tc.ctx,
      tc.handle,
      p,
      false, // forced
      false, // has_forced
      outValue,
    );

    if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
      throw const HegelStopTest();
    }
    if (result != hegel_result_t.HEGEL_OK) {
      throw HegelException('Failed to generate boolean: ${result.value}');
    }

    return outValue.value;
  }
}

/// Generates random boolean values.
///
/// By default, generates true or false with equal probability (p=0.5).
///
/// ```dart
/// tc.draw(booleans())
/// ```
Generator<bool> booleans({double p = 0.5}) {
  return BooleanGenerator(p);
}

class BigIntGenerator extends Generator<BigInt> {
  final BigInt min;
  final BigInt max;
  late final Uint8List _minBytes;
  late final Uint8List _maxBytes;

  BigIntGenerator(this.min, this.max) {
    if (min > max) {
      throw ArgumentError('bigIntegers: min ($min) must be <= max ($max)');
    }
    _minBytes = _toTwosComplementLittleEndian(min, (min.bitLength + 8) ~/ 8);
    _maxBytes = _toTwosComplementLittleEndian(max, (max.bitLength + 8) ~/ 8);
  }

  @override
  BigInt generate(TestCase tc) {
    return using((Arena arena) {
      final minBuf = arena<ffi.Uint8>(_minBytes.length);
      for (var i = 0; i < _minBytes.length; i++) {
        minBuf[i] = _minBytes[i];
      }

      final maxBuf = arena<ffi.Uint8>(_maxBytes.length);
      for (var i = 0; i < _maxBytes.length; i++) {
        maxBuf[i] = _maxBytes[i];
      }

      int outCap = _minBytes.length > _maxBytes.length
          ? _minBytes.length
          : _maxBytes.length;
      outCap += 1; // Extra capacity just in case
      final outBuf = arena<ffi.Uint8>(outCap);
      final outLen = arena<ffi.Size>();

      final result = tc.lib.hegel_generate_integer_big(
        tc.ctx,
        tc.handle,
        minBuf,
        _minBytes.length,
        maxBuf,
        _maxBytes.length,
        outBuf,
        outCap,
        outLen,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate big integer: ${result.value}');
      }

      if (outLen.value > outCap) {
        throw HegelException(
          'BigInt generation returned length ${outLen.value} exceeding capacity $outCap',
        );
      }

      final bytes = Uint8List(outLen.value);
      for (var i = 0; i < outLen.value; i++) {
        bytes[i] = outBuf[i];
      }
      return _fromTwosComplementLittleEndian(bytes);
    });
  }

  static Uint8List _toTwosComplementLittleEndian(BigInt value, int byteCount) {
    // Convert to unsigned representation for two's complement
    if (value < BigInt.zero) {
      value = (BigInt.one << (byteCount * 8)) + value;
    }
    final bytes = Uint8List(byteCount);
    for (var i = 0; i < byteCount; i++) {
      bytes[i] = (value & BigInt.from(0xFF)).toInt();
      value = value >> 8;
    }
    return bytes;
  }

  static BigInt _fromTwosComplementLittleEndian(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    // Check sign bit for two's complement
    if (bytes.isNotEmpty && bytes.last & 0x80 != 0) {
      result -= BigInt.one << (bytes.length * 8);
    }
    return result;
  }
}

/// Generates random BigInt values.
///
/// Defaults to the signed 64-bit integer range (−2⁶³ to 2⁶³−1),
/// matching [integers]. Specify custom bounds for larger ranges.
///
/// ```dart
/// tc.draw(bigIntegers()) // full int64 range
/// tc.draw(bigIntegers(min: BigInt.zero, max: BigInt.from(1000)))
/// ```
Generator<BigInt> bigIntegers({BigInt? min, BigInt? max}) {
  return BigIntGenerator(
    min ?? BigInt.from(-9223372036854775808),
    max ?? BigInt.from(9223372036854775807),
  );
}

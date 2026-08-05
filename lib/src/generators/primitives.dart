import 'dart:ffi' as ffi;
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
    return using((Arena arena) {
      final outValue = arena<ffi.Int64>();
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
    });
  }
}

Generator<int> integers({int min = -9223372036854775808, int max = 9223372036854775807}) {
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
    return using((Arena arena) {
      final outValue = arena<ffi.Double>();
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
    });
  }
}

Generator<double> doubles({
  double min = double.negativeInfinity,
  double max = double.infinity,
  bool allowNan = true,
  bool allowInfinity = true,
  bool excludeMin = false,
  bool excludeMax = false,
  double smallestNonzeroMagnitude = 5e-324,
}) {
  return DoubleGenerator(min, max, allowNan, allowInfinity, excludeMin, excludeMax, smallestNonzeroMagnitude);
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
    return using((Arena arena) {
      final outValue = arena<ffi.Bool>();
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
    });
  }
}

Generator<bool> booleans({double p = 0.5}) {
  return BooleanGenerator(p);
}

class BigIntGenerator extends Generator<BigInt> {
  final BigInt min;
  final BigInt max;

  BigIntGenerator(this.min, this.max) {
    if (min > max) {
      throw ArgumentError('bigIntegers: min ($min) must be <= max ($max)');
    }
  }

  @override
  BigInt generate(TestCase tc) {
    return using((Arena arena) {
      // BigInt in dart doesn't have an easy two's complement little endian export,
      // but we need to pass a buffer. For the sake of simplicity, we'll convert
      // BigInt to a string and then to bytes, but the API expects two's complement little endian.
      // We will write a helper or assume one exists. For now, we will do a crude conversion.
      final minBytes = _toTwosComplementLittleEndian(min);
      final maxBytes = _toTwosComplementLittleEndian(max);

      final minBuf = arena<ffi.Uint8>(minBytes.length);
      for (var i = 0; i < minBytes.length; i++) minBuf[i] = minBytes[i];

      final maxBuf = arena<ffi.Uint8>(maxBytes.length);
      for (var i = 0; i < maxBytes.length; i++) maxBuf[i] = maxBytes[i];

      int outCap = minBytes.length > maxBytes.length ? minBytes.length : maxBytes.length;
      outCap += 1; // Extra capacity just in case
      final outBuf = arena<ffi.Uint8>(outCap);
      final outLen = arena<ffi.Size>();

      final result = tc.lib.hegel_generate_integer_big(
        tc.ctx,
        tc.handle,
        minBuf,
        minBytes.length,
        maxBuf,
        maxBytes.length,
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

      return _fromTwosComplementLittleEndian(outBuf, outLen.value);
    });
  }

  List<int> _toTwosComplementLittleEndian(BigInt value) {
    if (value == BigInt.zero) return [0];

    final isNegative = value.isNegative;
    var hex = value.toRadixString(16);
    if (isNegative) {
      // Two's complement for negative: mask to byte-aligned width
      final bitLength = value.bitLength + 1;
      final mask = (BigInt.one << ((bitLength + 7) ~/ 8 * 8)) - BigInt.one;
      hex = (value & mask).toRadixString(16);
    }

    if (hex.length % 2 != 0) hex = '0$hex';
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }

    // For positive values, if MSB is set (e.g., 255 = 0xFF), prepend 0x00
    // to prevent misinterpretation as negative in two's complement.
    if (!isNegative && bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      bytes.insert(0, 0);
    }

    // Reverse for little endian
    return bytes.reversed.toList();
  }

  BigInt _fromTwosComplementLittleEndian(ffi.Pointer<ffi.Uint8> buf, int len) {
    if (len == 0) return BigInt.zero;
    
    // Read bytes
    final bytes = <int>[];
    for (var i = 0; i < len; i++) {
      bytes.add(buf[i]);
    }
    
    // Reverse to big endian
    final beBytes = bytes.reversed.toList();
    
    // Check sign bit (highest bit of the most significant byte)
    final isNegative = (beBytes[0] & 0x80) != 0;
    
    final hexBuf = StringBuffer();
    for (var b in beBytes) {
      hexBuf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    final hex = hexBuf.toString();
    
    var result = BigInt.parse(hex, radix: 16);
    if (isNegative) {
      final mask = (BigInt.one << (len * 8));
      result = result - mask;
    }
    return result;
  }
}

Generator<BigInt> bigIntegers({required BigInt min, required BigInt max}) {
  return BigIntGenerator(min, max);
}

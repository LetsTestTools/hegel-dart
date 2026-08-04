import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:convert';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

abstract class _BaseNativeStringGenerator extends Generator<String> {
  const _BaseNativeStringGenerator();

  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc);

  @override
  String generate(TestCase tc) {
    // Build a fresh handle per-generate. Handles are bound to a
    // hegel_context_t which is freed after each run, so caching
    // across runs would create dangling pointers.
    final genHandle = _build(tc);
    try {
      return using((Arena arena) {
        final outResult = arena<hegel_generate_string_result_t>();
        final result = tc.lib.hegel_generate_string(
          tc.ctx,
          tc.handle,
          genHandle,
          outResult,
        );

        if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
          throw const HegelStopTest();
        }
        if (result != hegel_result_t.HEGEL_OK) {
          throw HegelException('Failed to generate string: ${result.value}');
        }

        try {
          final data = outResult.ref.data;
          final len = outResult.ref.len;
          if (len == 0) return '';
          final uint8List = data.cast<ffi.Uint8>().asTypedList(len);
          return utf8.decode(uint8List);
        } finally {
          tc.lib.hegel_generate_string_result_free(tc.ctx, outResult);
        }
      });
    } finally {
      tc.lib.hegel_string_generator_free(tc.ctx, genHandle);
    }
  }
}

class TextGenerator extends _BaseNativeStringGenerator {
  final int minSize;
  final int maxSize;
  final int minCodepoint;
  final int maxCodepoint;

  TextGenerator(this.minSize, this.maxSize, this.minCodepoint, this.maxCodepoint) {
    if (minSize < 0) {
      throw ArgumentError('text: minSize ($minSize) must be >= 0');
    }
    if (minSize > maxSize) {
      throw ArgumentError('text: minSize ($minSize) must be <= maxSize ($maxSize)');
    }
    if (minCodepoint < 0 || minCodepoint > 0x10FFFF) {
      throw ArgumentError('text: minCodepoint ($minCodepoint) must be in [0, 0x10FFFF]');
    }
    if (maxCodepoint < 0 || maxCodepoint > 0x10FFFF) {
      throw ArgumentError('text: maxCodepoint ($maxCodepoint) must be in [0, 0x10FFFF]');
    }
    if (minCodepoint > maxCodepoint) {
      throw ArgumentError('text: minCodepoint ($minCodepoint) must be <= maxCodepoint ($maxCodepoint)');
    }
  }

  @override
  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc) {
    return using((Arena arena) {
      final outGen = arena<ffi.Pointer<hegel_string_generator_t>>();
      final result = tc.lib.hegel_string_generator_text(
        tc.ctx,
        minSize,
        maxSize,
        ffi.nullptr, // codec
        minCodepoint,
        maxCodepoint,
        ffi.nullptr, // categories
        0,
        ffi.nullptr, // exclude categories
        0,
        ffi.nullptr, // include characters
        0,
        ffi.nullptr, // exclude characters
        0,
        outGen,
      );
      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to build text generator: ${result.value}');
      }
      return outGen.value;
    });
  }
}

Generator<String> text({int minSize = 0, int maxSize = 100, int minCodepoint = 0, int maxCodepoint = 0x10FFFF}) {
  return TextGenerator(minSize, maxSize, minCodepoint, maxCodepoint);
}

class RegexGenerator extends _BaseNativeStringGenerator {
  final String pattern;
  final bool fullmatch;

  const RegexGenerator(this.pattern, this.fullmatch);

  @override
  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc) {
    return using((Arena arena) {
      final outGen = arena<ffi.Pointer<hegel_string_generator_t>>();
      final patternPtr = pattern.toNativeUtf8(allocator: arena).cast<ffi.Char>();
      final result = tc.lib.hegel_string_generator_regex(
        tc.ctx,
        patternPtr,
        fullmatch,
        ffi.nullptr,
        outGen,
      );
      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to build regex generator: ${result.value}');
      }
      return outGen.value;
    });
  }
}

Generator<String> fromRegex(String pattern, {bool fullmatch = true}) {
  return RegexGenerator(pattern, fullmatch);
}

class EmailGenerator extends _BaseNativeStringGenerator {
  const EmailGenerator();

  @override
  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc) {
    return using((Arena arena) {
      final outGen = arena<ffi.Pointer<hegel_string_generator_t>>();
      final result = tc.lib.hegel_string_generator_email(tc.ctx, outGen);
      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to build email generator: ${result.value}');
      }
      return outGen.value;
    });
  }
}

Generator<String> emails() => EmailGenerator();

class UrlGenerator extends _BaseNativeStringGenerator {
  const UrlGenerator();

  @override
  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc) {
    return using((Arena arena) {
      final outGen = arena<ffi.Pointer<hegel_string_generator_t>>();
      final result = tc.lib.hegel_string_generator_url(tc.ctx, outGen);
      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to build url generator: ${result.value}');
      }
      return outGen.value;
    });
  }
}

Generator<String> urls() => UrlGenerator();

class DomainGenerator extends _BaseNativeStringGenerator {
  final int maxLength;
  const DomainGenerator(this.maxLength);

  @override
  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc) {
    return using((Arena arena) {
      final outGen = arena<ffi.Pointer<hegel_string_generator_t>>();
      final result = tc.lib.hegel_string_generator_domain(tc.ctx, maxLength, outGen);
      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to build domain generator: ${result.value}');
      }
      return outGen.value;
    });
  }
}

Generator<String> domains({int maxLength = 255}) => DomainGenerator(maxLength);

class UuidGenerator extends Generator<String> {
  const UuidGenerator();

  @override
  String generate(TestCase tc) {
    return using((Arena arena) {
      final outBytes = arena<ffi.Uint8>(16);
      final result = tc.lib.hegel_generate_uuid(
        tc.ctx,
        tc.handle,
        0, // version
        false, // has_version
        outBytes,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate UUID: ${result.value}');
      }

      final buf = outBytes.asTypedList(16);
      final hex = buf.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
      return '${hex.sublist(0,4).join()}-${hex.sublist(4,6).join()}-${hex.sublist(6,8).join()}-${hex.sublist(8,10).join()}-${hex.sublist(10,16).join()}';
    });
  }
}

Generator<String> uuids() => UuidGenerator();

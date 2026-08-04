import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:convert';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

// Since hegel_string_generator_free takes two arguments (ctx, generator),
// we cannot use dart:ffi NativeFinalizer directly. We use Dart's Finalizer instead.
// Also, string generators require a hegel_context_t to be built, so we build them lazily
// on the first call to generate().

class _StringGenResource {
  final LibHegel lib;
  final ffi.Pointer<hegel_string_generator_t> handle;

  _StringGenResource(this.lib, this.handle);
}

final Finalizer<_StringGenResource> _stringGenFinalizer = Finalizer((res) {
  res.lib.hegel_string_generator_free(ffi.nullptr, res.handle);
});

abstract class _BaseNativeStringGenerator extends Generator<String> {
  ffi.Pointer<hegel_string_generator_t>? _genHandle;

  _BaseNativeStringGenerator();

  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc);

  @override
  String generate(TestCase tc) {
    if (_genHandle == null) {
      _genHandle = _build(tc);
      _stringGenFinalizer.attach(this, _StringGenResource(tc.lib, _genHandle!), detach: this);
    }

    return using((Arena arena) {
      final outResult = arena<hegel_generate_string_result_t>();
      final result = tc.lib.hegel_generate_string(
        tc.ctx,
        tc.handle,
        _genHandle!,
        outResult,
      );

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
  }
}

class TextGenerator extends _BaseNativeStringGenerator {
  final int minSize;
  final int maxSize;
  final int minCodepoint;
  final int maxCodepoint;

  TextGenerator(this.minSize, this.maxSize, this.minCodepoint, this.maxCodepoint);

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

  RegexGenerator(this.pattern, this.fullmatch);

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
  EmailGenerator();

  @override
  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc) {
    return using((Arena arena) {
      final outGen = arena<ffi.Pointer<hegel_string_generator_t>>();
      final result = tc.lib.hegel_string_generator_email(tc.ctx, outGen);
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to build email generator: ${result.value}');
      }
      return outGen.value;
    });
  }
}

Generator<String> emails() => EmailGenerator();

class UrlGenerator extends _BaseNativeStringGenerator {
  UrlGenerator();

  @override
  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc) {
    return using((Arena arena) {
      final outGen = arena<ffi.Pointer<hegel_string_generator_t>>();
      final result = tc.lib.hegel_string_generator_url(tc.ctx, outGen);
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
  DomainGenerator(this.maxLength);

  @override
  ffi.Pointer<hegel_string_generator_t> _build(TestCase tc) {
    return using((Arena arena) {
      final outGen = arena<ffi.Pointer<hegel_string_generator_t>>();
      final result = tc.lib.hegel_string_generator_domain(tc.ctx, maxLength, outGen);
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to build domain generator: ${result.value}');
      }
      return outGen.value;
    });
  }
}

Generator<String> domains({int maxLength = 255}) => DomainGenerator(maxLength);

class UuidGenerator extends Generator<String> {
  UuidGenerator();

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

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'hegel_bindings.g.dart';

LibHegel? _cachedLib;

/// The minimum libhegel major.minor version this Dart package is compatible with.
///
/// Bumped whenever the C API has breaking changes.
const _minMajor = 0;
const _minMinor = 30;

/// Loads the libhegel native library and returns [LibHegel] bindings.
///
/// Resolution order:
/// 1. `HEGEL_LIBHEGEL_PATH` environment variable (for dev/custom builds)
/// 2. Native Assets: binary registered by `hook/build.dart` and placed
///    in `.dart_tool/lib/` by the Dart SDK
/// 3. System library path fallback
///
/// After loading, the library's ABI version is verified to ensure
/// compatibility with this Dart package.
LibHegel loadHegelLibrary() {
  if (_cachedLib != null) return _cachedLib!;

  LibHegel lib;

  // 1. Check env override (runtime only — not in build hook, per E9 review)
  final envPath = Platform.environment['HEGEL_LIBHEGEL_PATH'];
  if (envPath != null && envPath.isNotEmpty) {
    final file = File(envPath);
    if (!file.existsSync()) {
      throw StateError(
        'HEGEL_LIBHEGEL_PATH=$envPath does not exist.\n'
        'Build libhegel with: cargo build --release -p hegeltest-c',
      );
    }
    if (file.statSync().type != FileSystemEntityType.file) {
      throw StateError('HEGEL_LIBHEGEL_PATH=$envPath is not a regular file.');
    }
    stderr.writeln('[hegeltest] Using custom libhegel: $envPath');
    lib = LibHegel(DynamicLibrary.open(envPath));
  } else {
    // 2. Native Assets: SDK placed the binary via hook/build.dart
    //    The asset is registered under the ID
    //    'package:hegeltest/src/ffi/hegel_bindings.g.dart'.
    //    Try loading from the .dart_tool/lib/ directory first,
    //    then fall back to system path.
    final libName = _platformLibName();
    lib = _tryNativeAssets(libName) ?? _trySystemPath(libName);
  }

  // Verify ABI compatibility (catches outdated custom binaries too)
  _verifyAbiVersion(lib);

  return _cachedLib = lib;
}

/// Attempts to load the native library from the Native Assets location.
///
/// The Dart SDK copies the binary to `.dart_tool/lib/` when using build hooks
/// during `dart test` and `dart run`. This is correct for hegeltest because
/// it is a test-only package (dev_dependency) — never compiled into production
/// builds where `.dart_tool/` wouldn't exist.
///
/// Long-term: migrate to `@Native(assetId: ...)` annotations (v0.6.0).
LibHegel? _tryNativeAssets(String libName) {
  try {
    // The Dart SDK places native assets in .dart_tool/lib/ relative to the
    // project root when running `dart test` or `dart run`.
    final dartToolLib = File('.dart_tool/lib/$libName');
    if (dartToolLib.existsSync()) {
      return LibHegel(DynamicLibrary.open(dartToolLib.absolute.path));
    }
  } catch (_) {
    // Fall through to system path
  }
  return null;
}

/// Attempts to load the native library from the system library path.
LibHegel _trySystemPath(String libName) {
  try {
    return LibHegel(DynamicLibrary.open(libName));
  } on ArgumentError {
    throw UnsupportedError(
      'hegeltest: no native binary available for '
      '${Platform.operatingSystem} ${_currentArch}.\n'
      '\n'
      'Supported platforms: macOS arm64, Linux x64/arm64, '
      'Windows x64/arm64.\n'
      '\n'
      'If you installed hegeltest from pub.dev, try:\n'
      '  dart pub cache clean hegeltest && dart pub get\n'
      '\n'
      'Set HEGEL_LIBHEGEL_PATH to provide a custom binary.',
    );
  }
}

/// Calls `hegel_version()` and verifies the native library is compatible.
///
/// We require the same major version and at least [_minMinor] minor version.
/// This prevents segfaults from mismatched struct layouts or removed symbols.
/// Also catches outdated custom binaries via HEGEL_LIBHEGEL_PATH (P2 fix).
void _verifyAbiVersion(LibHegel lib) {
  final ctx = lib.hegel_context_new();
  if (ctx == nullptr) {
    stderr.writeln(
      '[hegeltest] Warning: Could not create context to verify ABI version.',
    );
    return;
  }

  try {
    final outVersion = calloc<Pointer<Char>>();
    try {
      final result = lib.hegel_version(ctx, outVersion);
      if (result != hegel_result_t.HEGEL_OK) {
        stderr.writeln(
          '[hegeltest] Warning: hegel_version() failed (${result.value}). '
          'Cannot verify ABI compatibility.',
        );
        return;
      }

      final versionStr = outVersion.value.cast<Utf8>().toDartString();
      final parts = versionStr.split('.');
      if (parts.length < 2) {
        stderr.writeln(
          '[hegeltest] Warning: Unexpected version format: $versionStr',
        );
        return;
      }

      final major = int.tryParse(parts[0]) ?? -1;
      final minor = int.tryParse(parts[1]) ?? -1;

      if (major != _minMajor || minor < _minMinor) {
        throw StateError(
          'Incompatible libhegel version: $versionStr\n'
          'This hegeltest package requires libhegel >= $_minMajor.$_minMinor.0\n'
          '\n'
          'Update the native library or reinstall hegeltest from pub.dev.',
        );
      }
    } finally {
      calloc.free(outVersion);
    }
  } finally {
    lib.hegel_context_free(ctx);
  }
}

String _platformLibName() {
  if (Platform.isMacOS) return 'libhegel_c.dylib';
  if (Platform.isLinux) return 'libhegel_c.so';
  if (Platform.isWindows) return 'hegel_c.dll';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

String get _currentArch {
  final abi = Abi.current();
  if (abi == Abi.macosArm64 ||
      abi == Abi.linuxArm64 ||
      abi == Abi.windowsArm64) {
    return 'arm64';
  }
  if (abi == Abi.macosX64 || abi == Abi.linuxX64 || abi == Abi.windowsX64) {
    return 'x64';
  }
  return abi.toString();
}

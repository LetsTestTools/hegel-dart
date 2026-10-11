import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

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
///    in `.dart_tool/lib/` by the Dart SDK, or resolved directly from the
///    package's bundled `native/<os>_<arch>/` directory (used by `flutter test`)
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
    //    Try loading from the .dart_tool/lib/ directory or bundled package
    //    native directory first, then fall back to system path.
    final libName = _platformLibName();
    lib = _tryNativeAssets(libName) ?? _trySystemPath(libName);
  }

  // Verify ABI compatibility (catches outdated custom binaries too)
  _verifyAbiVersion(lib);

  return _cachedLib = lib;
}

/// Attempts to load the native library from the Native Assets location
/// or from the package's bundled `native/<os>_<arch>/` directory.
///
/// The Dart SDK copies the binary to `.dart_tool/lib/` when using build hooks
/// during `dart test` and `dart run`. Under `flutter test`, `.dart_tool/lib/`
/// is not populated, so we fall back to resolving the `hegeltest` package root
/// to locate the bundled binary directly.
///
/// Long-term: migrate to `@Native(assetId: ...)` annotations (v0.6.0).
LibHegel? _tryNativeAssets(String libName) {
  try {
    // 1. The Dart SDK places native assets in .dart_tool/lib/ relative to the
    //    project root when running `dart test` or `dart run`.
    final dartToolLib = File('.dart_tool/lib/$libName');
    if (dartToolLib.existsSync()) {
      return LibHegel(DynamicLibrary.open(dartToolLib.absolute.path));
    }

    // 2. Fallback for `flutter test`, which does not populate `.dart_tool/lib/`.
    final packageRootUri = _resolveHegeltestPackageRoot();
    if (packageRootUri != null) {
      final dirName = '${Platform.operatingSystem}_$_currentArch';
      final bundledUri = packageRootUri.resolve('native/$dirName/$libName');
      final bundledFile = File.fromUri(bundledUri);
      if (bundledFile.existsSync()) {
        return LibHegel(DynamicLibrary.open(bundledFile.absolute.path));
      }
    }
  } catch (_) {
    // Fall through to system path
  }
  return null;
}

Uri? _resolveHegeltestPackageRoot() {
  try {
    final packageLibUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:hegeltest/hegeltest.dart'),
    );
    if (packageLibUri != null) {
      return packageLibUri.resolve('../');
    }
  } catch (_) {
    // Isolate.resolvePackageUriSync throws UnsupportedError in flutter_tester
  }

  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) return null;

  final decoded = jsonDecode(configFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) return null;
  final packages = decoded['packages'];
  if (packages is! List) return null;

  for (final pkg in packages) {
    if (pkg is Map<String, dynamic> && pkg['name'] == 'hegeltest') {
      final rootUriStr = pkg['rootUri'];
      if (rootUriStr is String && rootUriStr.isNotEmpty) {
        final normalized = rootUriStr.endsWith('/')
            ? rootUriStr
            : '$rootUriStr/';
        return configFile.absolute.uri.resolve(normalized);
      }
    }
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
      '${Platform.operatingSystem} $_currentArch.\n'
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
    throw StateError(
      '[hegeltest] Could not create context to verify ABI version.\n'
      'The native binary may be corrupt or incompatible.',
    );
  }

  try {
    final outVersion = calloc<Pointer<Char>>();
    try {
      final result = lib.hegel_version(ctx, outVersion);
      if (result != hegel_result_t.HEGEL_OK) {
        throw StateError(
          '[hegeltest] hegel_version() failed (${result.value}).\n'
          'Cannot verify ABI compatibility. The native binary may be corrupt.',
        );
      }

      final versionPtr = outVersion.value;
      if (versionPtr == nullptr) {
        throw StateError(
          '[hegeltest] hegel_version() returned no version string.\n'
          'Cannot verify ABI compatibility.',
        );
      }

      final versionStr = versionPtr.cast<Utf8>().toDartString();
      final parts = versionStr.split('.');
      if (parts.length != 3 ||
          parts.any((part) => int.tryParse(part) == null)) {
        throw StateError(
          '[hegeltest] Unexpected version format: $versionStr\n'
          'Expected semver (e.g. "0.30.0").',
        );
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

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
/// 1. `HEGEL_LIBHEGEL_PATH` environment variable (validated)
/// 2. Bundled binary in `native/<platform>/` relative to package root
/// 3. Bundled binary resolved via `Isolate.resolvePackageUri` (pub cache)
/// 4. System library path fallback
///
/// After loading, the library's ABI version is verified to ensure
/// compatibility with this Dart package.
LibHegel loadHegelLibrary() {
  if (_cachedLib != null) return _cachedLib!;
  final envPath = Platform.environment['HEGEL_LIBHEGEL_PATH'];

  LibHegel lib;

  // 1. Check env override
  if (envPath != null && envPath.isNotEmpty) {
    final file = File(envPath);
    if (!file.existsSync()) {
      throw StateError(
        'HEGEL_LIBHEGEL_PATH=$envPath does not exist.\n'
        'Build libhegel with: cargo build --release -p hegeltest-c',
      );
    }
    if (file.statSync().type != FileSystemEntityType.file) {
      throw StateError(
        'HEGEL_LIBHEGEL_PATH=$envPath is not a regular file.',
      );
    }
    stderr.writeln('[hegeltest] Using custom libhegel: $envPath');
    lib = LibHegel(DynamicLibrary.open(envPath));
  } else {
    // 2. Try platform-specific bundled binary relative to CWD
    final libName = _platformLibName();
    final platformDir = _platformDirName();
    final cwdCandidate = 'native/$platformDir/$libName';

    final cwdFile = File(cwdCandidate);
    if (cwdFile.existsSync()) {
      lib = LibHegel(DynamicLibrary.open(cwdFile.absolute.path));
    } else {
      // 3. Resolve via package URI (works when installed from pub cache)
      final packageLib = _resolveFromPackageUri(platformDir, libName);
      if (packageLib != null) {
        lib = packageLib;
      } else {
        // 4. System library path fallback
        try {
          lib = LibHegel(DynamicLibrary.open(libName));
        } catch (_) {
          throw StateError(
            'Could not find the hegeltest native library ($libName).\n'
            '\n'
            'If you installed hegeltest from pub.dev, this is a bug — please file an issue.\n'
            '\n'
            'If you are developing hegeltest locally:\n'
            '  1. Build the native library: cd <hegel-rust> && cargo build --release -p hegeltest-c\n'
            '  2. Set the path: export HEGEL_LIBHEGEL_PATH=<hegel-rust>/target/release/$libName',
          );
        }
      }
    }
  }

  // Verify ABI compatibility
  _verifyAbiVersion(lib);

  return _cachedLib = lib;
}

/// Calls `hegel_version()` and verifies the native library is compatible.
///
/// We require the same major version and at least [_minMinor] minor version.
/// This prevents segfaults from mismatched struct layouts or removed symbols.
void _verifyAbiVersion(LibHegel lib) {
  // hegel_version requires a context, but we can create a temporary one
  final ctx = lib.hegel_context_new();
  if (ctx == nullptr) {
    // Can't verify — proceed with a warning
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

/// Resolves the native library path using Dart's package resolution.
///
/// This correctly locates the native binary when the package is
/// installed from pub cache (not just when running from the repo root).
LibHegel? _resolveFromPackageUri(String platformDir, String libName) {
  // Strategy 1: Use Isolate.resolvePackageUriSync (works in standalone Dart)
  try {
    final packageUri = Uri.parse('package:hegeltest/hegeltest.dart');
    final resolvedUri = Isolate.resolvePackageUriSync(packageUri);
    if (resolvedUri != null) {
      // resolvedUri points to lib/hegeltest.dart
      // Resolve symlinks first (handles Nix flakes, symlinked pub caches,
      // and monorepo setups where the pub cache path is a symlink).
      final resolvedFile = File.fromUri(resolvedUri);
      final realPath = resolvedFile.existsSync()
          ? File(resolvedFile.resolveSymbolicLinksSync())
          : resolvedFile;

      // Navigate up to package root: lib/ -> package root
      final libDir = realPath.parent; // lib/
      final packageRoot = libDir.parent; // package root
      final nativePath = '${packageRoot.path}/native/$platformDir/$libName';

      final nativeFile = File(nativePath);
      if (nativeFile.existsSync()) {
        return LibHegel(DynamicLibrary.open(nativeFile.absolute.path));
      }
    }
  } catch (_) {
    // Isolate-based resolution failed — try fallback
  }

  // Strategy 2: Parse .dart_tool/package_config.json (works in flutter test)
  try {
    final packageConfig = File('.dart_tool/package_config.json');
    if (packageConfig.existsSync()) {
      final content = packageConfig.readAsStringSync();
      final config = json.decode(content) as Map<String, dynamic>;
      final packages = config['packages'] as List<dynamic>? ?? [];
      for (final pkg in packages) {
        if (pkg is Map<String, dynamic> && pkg['name'] == 'hegeltest') {
          final rootUri = pkg['rootUri'] as String?;
          if (rootUri == null) continue;
          // rootUri might be relative to .dart_tool/ or absolute
          String packageRoot;
          if (rootUri.startsWith('file://')) {
            packageRoot = Uri.parse(rootUri).toFilePath();
          } else {
            // Relative URI — resolve relative to .dart_tool/
            packageRoot = File('.dart_tool/$rootUri')
                .resolveSymbolicLinksSync();
          }
          final nativePath = '$packageRoot/native/$platformDir/$libName';
          final nativeFile = File(nativePath);
          if (nativeFile.existsSync()) {
            return LibHegel(DynamicLibrary.open(nativeFile.absolute.path));
          }
          break;
        }
      }
    }
  } catch (_) {
    // package_config.json resolution failed — fall through
  }

  return null;
}

String _platformLibName() {
  if (Platform.isMacOS) return 'libhegel_c.dylib';
  if (Platform.isLinux) return 'libhegel_c.so';
  if (Platform.isWindows) return 'hegel_c.dll';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

String _platformDirName() {
  final abi = Abi.current();
  switch (abi) {
    case Abi.macosArm64:
      return 'macos_arm64';
    case Abi.macosX64:
      return 'macos_x64';
    case Abi.linuxX64:
      return 'linux_x64';
    case Abi.linuxArm64:
      return 'linux_arm64';
    case Abi.windowsX64:
      return 'windows_x64';
    case Abi.windowsArm64:
      return 'windows_arm64';
    default:
      throw UnsupportedError('Unsupported ABI: $abi');
  }
}

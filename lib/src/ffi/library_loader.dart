import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'hegel_bindings.g.dart';

LibHegel? _cachedLib;

/// Loads the libhegel native library and returns [LibHegel] bindings.
///
/// Resolution order:
/// 1. `HEGEL_LIBHEGEL_PATH` environment variable (validated)
/// 2. Bundled binary in `native/<platform>/` relative to package root
/// 3. Bundled binary resolved via `Isolate.resolvePackageUri` (pub cache)
/// 4. System library path fallback
LibHegel loadHegelLibrary() {
  if (_cachedLib != null) return _cachedLib!;
  final envPath = Platform.environment['HEGEL_LIBHEGEL_PATH'];

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
    return _cachedLib = LibHegel(DynamicLibrary.open(envPath));
  }

  // 2. Try platform-specific bundled binary relative to CWD
  final libName = _platformLibName();
  final platformDir = _platformDirName();
  final cwdCandidate = 'native/$platformDir/$libName';

  final cwdFile = File(cwdCandidate);
  if (cwdFile.existsSync()) {
    return _cachedLib = LibHegel(DynamicLibrary.open(cwdFile.absolute.path));
  }

  // 3. Resolve via package URI (works when installed from pub cache)
  final packageLib = _resolveFromPackageUri(platformDir, libName);
  if (packageLib != null) {
    return _cachedLib = packageLib;
  }

  // 4. System library path fallback
  try {
    return _cachedLib = LibHegel(DynamicLibrary.open(libName));
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

/// Resolves the native library path using Dart's package resolution.
///
/// This correctly locates the native binary when the package is
/// installed from pub cache (not just when running from the repo root).
LibHegel? _resolveFromPackageUri(String platformDir, String libName) {
  try {
    final packageUri = Uri.parse('package:hegeltest/hegeltest.dart');
    final resolvedUri = Isolate.resolvePackageUriSync(packageUri);
    if (resolvedUri == null) return null;

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
    final nativePath =
        '${packageRoot.path}/native/$platformDir/$libName';

    final nativeFile = File(nativePath);
    if (nativeFile.existsSync()) {
      return LibHegel(DynamicLibrary.open(nativeFile.absolute.path));
    }
  } catch (_) {
    // Package resolution failed — fall through to system path
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

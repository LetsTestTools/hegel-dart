import 'dart:ffi';
import 'dart:io';

import 'hegel_bindings.g.dart';

LibHegel? _cachedLib;

/// Loads the libhegel native library and returns [LibHegel] bindings.
///
/// Resolution order:
/// 1. `HEGEL_LIBHEGEL_PATH` environment variable (validated)
/// 2. Bundled binary in `native/<platform>/` relative to package root
/// 3. System library path fallback
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

  // 2. Try platform-specific bundled binary
  final libName = _platformLibName();
  final platformDir = _platformDirName();

  // Walk up from the script location to find the package root
  final candidates = <String>[
    // Relative to CWD (common in dart test)
    'native/$platformDir/$libName',
    // Relative to package root via pub cache
    '.dart_tool/package_config.json', // marker
  ];

  for (final candidate in candidates) {
    if (candidate.endsWith('.json')) continue;
    final file = File(candidate);
    if (file.existsSync()) {
      return _cachedLib = LibHegel(DynamicLibrary.open(file.absolute.path));
    }
  }

  // 3. System library path fallback
  try {
    return _cachedLib = LibHegel(DynamicLibrary.open(libName));
  } catch (_) {
    throw StateError(
      'Could not find libhegel. Set HEGEL_LIBHEGEL_PATH or run:\n'
      '  cd <hegel-rust> && cargo build --release -p hegeltest-c\n'
      '  export HEGEL_LIBHEGEL_PATH=<hegel-rust>/target/release/$libName',
    );
  }
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

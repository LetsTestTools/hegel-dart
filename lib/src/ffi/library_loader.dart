import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'hegel_bindings.g.dart';
import 'string_helpers.dart';

String? _verifiedVersion;

/// The minimum libhegel major.minor version this Dart package is compatible with.
///
/// Bumped whenever the C API has breaking changes.
const _minMajor = 0;
const _minMinor = 53;

/// Verifies that the bundled `@Native` libhegel asset loads cleanly and
/// satisfies the minimum ABI version required by `hegeltest`.
///
/// Throws [UnsupportedError] if the current platform has no bundled binary
/// and no `hooks.user_defines.hegeltest.libhegel_path` override was provided,
/// or [StateError] if the binary is corrupt or ABI-incompatible.
void ensureHegelLibraryVerified() {
  if (_verifiedVersion != null) return;

  final Pointer<hegel_context_t> ctx;
  try {
    ctx = hegel_context_new();
  } on ArgumentError catch (e) {
    throw UnsupportedError(
      'hegeltest: failed to resolve native libhegel asset for '
      '${Platform.operatingSystem} (${Abi.current()}): $e\n'
      '\n'
      'Supported platforms with bundled binaries: macOS arm64, Linux x64/arm64, '
      'Windows x64/arm64.\n'
      '\n'
      'To supply a custom binary, configure `hooks.user_defines.hegeltest.libhegel_path` '
      'in your pubspec.yaml.',
    );
  }

  if (ctx == nullptr) {
    throw StateError(
      '[hegeltest] Could not create context to verify libhegel ABI version.\n'
      'The native binary may be corrupt or incompatible.',
    );
  }

  try {
    final outVersion = calloc<hegel_string_t>();
    try {
      final result = hegel_version(ctx, outVersion);
      if (result != hegel_result_t.HEGEL_OK) {
        throw StateError(
          '[hegeltest] hegel_version() failed (${result.value}).\n'
          'Cannot verify ABI compatibility. The native binary may be corrupt.',
        );
      }

      final versionStr = readHegelString(outVersion.ref);
      if (versionStr.isEmpty) {
        throw StateError(
          '[hegeltest] hegel_version() returned an empty version string.\n'
          'Cannot verify ABI compatibility.',
        );
      }

      final parts = versionStr.split('.');
      if (parts.length != 3 ||
          parts.any((part) => int.tryParse(part) == null)) {
        throw StateError(
          '[hegeltest] Unexpected libhegel version format: $versionStr\n'
          'Expected semver (e.g. "0.53.1").',
        );
      }

      final major = int.parse(parts[0]);
      final minor = int.parse(parts[1]);

      if (major != _minMajor || minor < _minMinor) {
        throw StateError(
          'Incompatible libhegel version: $versionStr\n'
          'This hegeltest package requires libhegel >= $_minMajor.$_minMinor.0 '
          '(and < ${_minMajor + 1}.0.0).\n'
          '\n'
          'Update the native library or reinstall hegeltest from pub.dev.',
        );
      }

      _verifiedVersion = versionStr;
    } finally {
      calloc.free(outVersion);
    }
  } finally {
    hegel_context_free(ctx);
  }
}

/// Returns the version string of the loaded native `libhegel` library.
String hegelNativeVersion() {
  ensureHegelLibraryVerified();
  return _verifiedVersion!;
}

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

/// Build hook that registers the correct prebuilt native binary
/// as a [CodeAsset] for the target platform.
///
/// The Dart/Flutter SDK calls this automatically during `dart test`,
/// `dart run`, `flutter test`, and `flutter build`.
///
/// Supports overriding the binary path via `hooks.user_defines.hegeltest.libhegel_path`
/// in the consumer's `pubspec.yaml`.
///
/// Before registration, each bundled binary is SHA256-verified against the
/// `.sha256` sidecar file to detect accidental corruption or incomplete
/// downloads. This is NOT a full supply chain defense (an attacker who
/// can modify the package can also modify the hash file).
///
/// Unsupported targets (e.g. iOS, Android, macOS x64) get an empty asset list —
/// no crash, no error at build time. Runtime checks throw a clear error instead.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // Only process if SDK wants code assets.
    if (!input.config.buildCodeAssets) return;

    final rawCustomPath = input.userDefines['libhegel_path'];
    if (rawCustomPath != null) {
      if (rawCustomPath is! String || rawCustomPath.trim().isEmpty) {
        throw const FormatException(
          '[hegeltest] hooks.user_defines.hegeltest.libhegel_path '
          'must be a non-empty string.',
        );
      }

      final customUri = File(rawCustomPath).isAbsolute
          ? Uri.file(rawCustomPath)
          : (input.userDefines.path('libhegel_path') ??
                input.packageRoot.resolve(rawCustomPath));
      final customFile = File.fromUri(customUri);
      if (!customFile.existsSync()) {
        throw StateError(
          '[hegeltest] hooks.user_defines.hegeltest.libhegel_path does not exist: '
          '${customFile.path}',
        );
      }
      if (customFile.statSync().type != FileSystemEntityType.file) {
        throw StateError(
          '[hegeltest] hooks.user_defines.hegeltest.libhegel_path is not a regular file: '
          '${customFile.path}',
        );
      }

      output.dependencies.add(customUri);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'src/ffi/hegel_bindings.g.dart',
          linkMode: DynamicLoadingBundled(),
          file: customUri,
        ),
      );
      return;
    }

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;
    final arch = codeConfig.targetArchitecture;

    final dirName = '${_osName(os)}_${_archName(arch)}';
    final fileName = _libFileName(os);
    final binaryUri = input.packageRoot.resolve('native/$dirName/$fileName');
    final binaryFile = File.fromUri(binaryUri);

    // Unsupported target -> empty asset list (no build crash).
    if (!binaryFile.existsSync()) {
      stderr.writeln(
        '[hegeltest] No prebuilt binary for $os $arch. '
        'Tests using hegeltest will fail at runtime on this target unless '
        'hooks.user_defines.hegeltest.libhegel_path is configured.',
      );
      return;
    }

    // Verify binary integrity before registering.
    final hashUri = _verifyIntegrity(
      binaryFile,
      input.packageRoot,
      dirName,
      fileName,
    );

    output.dependencies.add(binaryUri);
    if (hashUri != null) {
      output.dependencies.add(hashUri);
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/ffi/hegel_bindings.g.dart',
        linkMode: DynamicLoadingBundled(),
        file: binaryUri,
      ),
    );
  });
}

/// Verifies the SHA256 hash of [binaryFile] against the `.sha256` sidecar.
///
/// Returns the [Uri] of the sidecar file if it existed, or `null` otherwise.
/// Throws [StateError] if the hash doesn't match.
Uri? _verifyIntegrity(
  File binaryFile,
  Uri packageRoot,
  String dirName,
  String fileName,
) {
  final hashUri = packageRoot.resolve('native/$dirName/$fileName.sha256');
  final hashFile = File.fromUri(hashUri);

  if (!hashFile.existsSync()) {
    stderr.writeln(
      '[hegeltest] Warning: No .sha256 file for $dirName/$fileName. '
      'Skipping integrity check.',
    );
    return null;
  }

  final rawHash = hashFile.readAsStringSync().trim();
  final expectedHash = rawHash.isEmpty
      ? ''
      : rawHash.split(RegExp(r'\s+')).first.toLowerCase();
  final bytes = binaryFile.readAsBytesSync();
  final actualHash = sha256.convert(bytes).toString().toLowerCase();

  if (actualHash != expectedHash) {
    throw StateError(
      '[hegeltest] Integrity check FAILED for $dirName/$fileName.\n'
      '  Expected: $expectedHash\n'
      '  Actual:   $actualHash\n'
      '\n'
      'The binary may have been tampered with. Reinstall hegeltest:\n'
      '  dart pub cache clean hegeltest && dart pub get',
    );
  }

  return hashUri;
}

String _osName(OS os) {
  if (os == OS.macOS) return 'macos';
  if (os == OS.linux) return 'linux';
  if (os == OS.windows) return 'windows';
  return os.toString();
}

String _archName(Architecture arch) {
  if (arch == Architecture.arm64) return 'arm64';
  if (arch == Architecture.x64) return 'x64';
  return arch.toString();
}

String _libFileName(OS os) {
  if (os == OS.windows) return 'libhegel.dll';
  if (os == OS.macOS) return 'libhegel.dylib';
  return 'libhegel.so';
}

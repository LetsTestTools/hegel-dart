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
/// Before registration, each binary is SHA256-verified against the
/// `.sha256` sidecar file to detect accidental corruption or incomplete
/// downloads. This is NOT a full supply chain defense (an attacker who
/// can modify the package can also modify the hash file).
///
/// Unsupported targets (e.g. iOS, Android) get an empty asset list —
/// no crash, no error. The runtime loader throws a clear error instead.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // Only process if SDK wants code assets
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;
    final arch = codeConfig.targetArchitecture;

    final dirName = '${_osName(os)}_${_archName(arch)}';
    final fileName = _libFileName(os);
    final binaryUri = input.packageRoot.resolve('native/$dirName/$fileName');
    final binaryFile = File.fromUri(binaryUri);

    // Unsupported target → empty asset list (no build crash).
    // Log a warning so developers understand why tests may fail.
    if (!binaryFile.existsSync()) {
      stderr.writeln(
        '[hegeltest] No prebuilt binary for $os $arch. '
        'Tests using hegeltest will fail at runtime on this target.',
      );
      return;
    }

    // Verify binary integrity before registering (supply chain defense).
    _verifyIntegrity(binaryFile, input.packageRoot, dirName, fileName);

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
/// Throws [StateError] if the hash doesn't match, preventing a potentially
/// compromised binary from being loaded. This runs at build time — before
/// the binary is ever loaded by the OS.
void _verifyIntegrity(
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
    return;
  }

  final expectedHash = hashFile.readAsStringSync().trim().toLowerCase();
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
  if (os == OS.windows) return 'hegel_c.dll';
  if (os == OS.macOS) return 'libhegel_c.dylib';
  return 'libhegel_c.so';
}

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Build hook that registers the correct prebuilt native binary
/// as a [CodeAsset] for the target platform.
///
/// The Dart/Flutter SDK calls this automatically during `dart test`,
/// `dart run`, `flutter test`, and `flutter build`.
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

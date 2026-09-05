import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../ffi/hegel_bindings.g.dart';

/// Phase of the property-test loop.
enum Phase {
  explicit(1),
  reuse(2),
  generate(4),
  target(8),
  shrink(16);

  final int value;
  const Phase(this.value);
}

/// Engine output verbosity.
enum Verbosity {
  quiet(0),
  normal(1),
  verbose(2),
  debug(3);

  final int value;
  const Verbosity(this.value);
}

/// Randomness backend.
enum Backend {
  auto_(0),
  default_(1),
  urandom(2);

  final int value;
  const Backend(this.value);
}

/// Health checks that can be suppressed.
enum HealthCheck {
  filterTooMuch(1),
  tooSlow(2),
  testCasesTooLarge(4),
  largeInitialTestCase(8);

  final int value;
  const HealthCheck(this.value);
}

/// Run mode.
enum RunMode {
  testRun(0),
  singleTestCase(1);

  final int value;
  const RunMode(this.value);
}

/// Applies settings to a [hegel_settings_t] handle.
///
/// This is used internally by [HegelRunner] to configure the engine
/// before starting a run.
void applySettings(
  LibHegel lib,
  Pointer<hegel_context_t> ctx,
  Pointer<hegel_settings_t> settings, {
  int? testCases,
  int? seed,
  bool? derandomize,
  Set<Phase>? phases,
  Verbosity? verbosity,
  Set<HealthCheck>? suppressHealthChecks,
  bool? reportMultipleFailures,
  RunMode? mode,
  Backend? backend,
  bool? database,
  String? databasePath,
  String? databaseKey,
}) {
  if (testCases != null) {
    if (testCases <= 0) {
      throw ArgumentError('testCases must be positive, got $testCases');
    }
    final res = lib.hegel_settings_set_test_cases(ctx, settings, testCases);
    _check(res, 'set_test_cases');
  }

  if (seed != null) {
    final res = lib.hegel_settings_set_seed(ctx, settings, seed, true);
    _check(res, 'set_seed');
  }

  if (derandomize != null) {
    final res = lib.hegel_settings_set_derandomize(ctx, settings, derandomize);
    _check(res, 'set_derandomize');
  }

  if (phases != null) {
    var bits = 0;
    for (final p in phases) {
      bits |= p.value;
    }
    final res = lib.hegel_settings_set_phases(ctx, settings, bits);
    _check(res, 'set_phases');
  }

  if (verbosity != null) {
    final res = lib.hegel_settings_set_verbosity(
      ctx,
      settings,
      verbosity.value,
    );
    _check(res, 'set_verbosity');
  }

  if (suppressHealthChecks != null) {
    var bits = 0;
    for (final hc in suppressHealthChecks) {
      bits |= hc.value;
    }
    final res = lib.hegel_settings_set_suppress_health_check(
      ctx,
      settings,
      bits,
    );
    _check(res, 'set_suppress_health_check');
  }

  if (reportMultipleFailures != null) {
    final res = lib.hegel_settings_set_report_multiple_failures(
      ctx,
      settings,
      reportMultipleFailures,
    );
    _check(res, 'set_report_multiple_failures');
  }

  if (mode != null) {
    final res = lib.hegel_settings_set_mode(ctx, settings, mode.value);
    _check(res, 'set_mode');
  }

  if (backend != null) {
    final res = lib.hegel_settings_set_backend(ctx, settings, backend.value);
    _check(res, 'set_backend');
  }

  if (database == false) {
    using((Arena arena) {
      final dbPtr = ''.toNativeUtf8(allocator: arena).cast<Char>();
      final res = lib.hegel_settings_set_database(ctx, settings, dbPtr);
      _check(res, 'set_database');
    });
  } else if (databasePath != null) {
    if (databasePath.isEmpty) {
      throw ArgumentError('databasePath must not be empty');
    }
    _checkNoNullBytes(databasePath, 'databasePath');
    using((Arena arena) {
      final dbPtr = databasePath.toNativeUtf8(allocator: arena).cast<Char>();
      final res = lib.hegel_settings_set_database(ctx, settings, dbPtr);
      _check(res, 'set_database');
    });
  }

  if (databaseKey != null) {
    _checkNoNullBytes(databaseKey, 'databaseKey');
    using((Arena arena) {
      final keyPtr = databaseKey.toNativeUtf8(allocator: arena).cast<Char>();
      final res = lib.hegel_settings_set_database_key(ctx, settings, keyPtr);
      _check(res, 'set_database_key');
    });
  }
}

void _check(hegel_result_t result, String operation) {
  if (result != hegel_result_t.HEGEL_OK) {
    throw StateError('Failed to $operation: ${result.value}');
  }
}

/// Validate that a string does not contain null bytes, which would
/// silently truncate it at the FFI boundary.
void _checkNoNullBytes(String value, String paramName) {
  if (value.contains('\x00')) {
    throw ArgumentError.value(
      value,
      paramName,
      'must not contain null bytes (\\x00) — they cause silent '
      'truncation at the FFI boundary',
    );
  }
}

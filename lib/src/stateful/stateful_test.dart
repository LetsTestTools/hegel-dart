import 'dart:io';

import 'package:test/test.dart';

import '../core/hegel_settings.dart';
import '../core/runner.dart';
import '../core/settings.dart';
import '../ffi/library_loader.dart';
import 'state_machine.dart';
import 'stateful_runner.dart';

/// Top-level function for stateful (model-based) property tests.
///
/// This is the stateful equivalent of [hegelTest]. Instead of a single
/// test body, you provide a factory that creates a fresh [StateMachine]
/// for each test case (and each shrink attempt).
///
/// ## Example
///
/// ```dart
/// import 'package:hegeltest/hegeltest.dart';
///
/// void main() {
///   hegelStatefulTest('stack behaves like list', () => StackMachine());
/// }
/// ```
///
/// The engine will:
/// 1. Create a fresh machine via [create]
/// 2. Execute random sequences of rules (with Swarm Testing)
/// 3. Check invariants after each rule
/// 4. On failure, shrink to the minimal reproducing sequence
void hegelStatefulTest(
  String description,
  StateMachine Function() create, {
  Timeout? timeout,
  dynamic tags,
  dynamic skip,
  Map<String, dynamic>? onPlatform,
  int? retry,
  HegelConfig? config,
  int? testCases,
  int? seed,
  bool? derandomize,
  Set<Phase>? phases,
  Verbosity? verbosity,
  Set<HealthCheck>? suppressHealthChecks,
  bool? reportMultipleFailures,
  String? reproduce,
  String? databaseKey,
  String? database,
}) {
  test(
    description,
    () async {
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);

      await runner.run(
        (tc) async {
          final machine = create();
          try {
            await machine.setUp();
            await runStateMachine(lib, tc.ctx, tc.handle, machine, tc);
          } finally {
            try {
              await machine.tearDown();
            } catch (e, st) {
              stderr.writeln('[hegeltest] tearDown threw: $e\n$st');
            }
          }
        },
        reproduceBlob: reproduce ?? config?.reproduce,
        testCases: testCases ?? config?.testCases,
        seed: seed ?? config?.seed ?? _envSeed(),
        derandomize: derandomize ?? config?.derandomize,
        phases: phases ?? config?.phases,
        verbosity: verbosity ?? config?.verbosity,
        suppressHealthChecks:
            suppressHealthChecks ?? config?.suppressHealthChecks,
        reportMultipleFailures:
            reportMultipleFailures ?? config?.reportMultipleFailures,
        databaseKey: databaseKey ?? config?.databaseKey,
        database: database ?? config?.database,
      );
    },
    timeout: timeout ?? const Timeout(Duration(minutes: 10)),
    tags: tags,
    skip: skip,
    onPlatform: onPlatform,
    retry: retry,
  );
}

int? _envSeed() {
  final raw = Platform.environment['HEGEL_SEED'];
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw);
}

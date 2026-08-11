import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../core/exceptions.dart';
import '../core/test_case.dart';
import '../ffi/hegel_bindings.g.dart';
import 'state_machine.dart';

/// Runs a [StateMachine] against the hegel engine for a single test case.
///
/// This is the core loop that:
/// 1. Registers rules/invariants with the engine
/// 2. Creates engine pools for the machine's pools
/// 3. Loops: engine selects rule → check precondition → execute → invariants
/// 4. Cleans up FFI resources
Future<void> runStateMachine(
  LibHegel lib,
  Pointer<hegel_context_t> ctx,
  Pointer<hegel_test_case_t> tc,
  StateMachine machine,
  TestCase dartTc,
) async {
  final rules = machine.rules;
  final invariants = machine.invariants;

  if (rules.isEmpty) {
    throw ArgumentError('StateMachine has no rules. '
        'Override the `rules` getter to provide at least one StateRule.');
  }

  // Convert rule/invariant names to C strings
  final ruleNames = calloc<Pointer<Char>>(rules.length);
  final invariantNames = calloc<Pointer<Char>>(invariants.length);
  final ruleNameStrs = <Pointer<Utf8>>[];
  final invariantNameStrs = <Pointer<Utf8>>[];

  try {
    for (var i = 0; i < rules.length; i++) {
      final str = rules[i].name.toNativeUtf8();
      ruleNameStrs.add(str);
      ruleNames[i] = str.cast<Char>();
    }
    for (var i = 0; i < invariants.length; i++) {
      final str = invariants[i].name.toNativeUtf8();
      invariantNameStrs.add(str);
      invariantNames[i] = str.cast<Char>();
    }

    // Register state machine with engine
    final outSmId = calloc<Int64>();
    try {
      final smResult = lib.hegel_new_state_machine(
        ctx,
        tc,
        ruleNames.cast(),
        rules.length,
        invariantNames.cast(),
        invariants.length,
        outSmId,
      );
      _checkResult(smResult, 'hegel_new_state_machine');
      final smId = outSmId.value;

      // Create engine pools for each machine pool
      for (final pool in machine.pools) {
        final outPoolId = calloc<Int64>();
        try {
          final poolResult = lib.hegel_new_pool(ctx, tc, outPoolId);
          _checkResult(poolResult, 'hegel_new_pool');
          pool.poolId = outPoolId.value;
        } finally {
          calloc.free(outPoolId);
        }
      }

      // Wire up pool callbacks
      machine.poolAddCallback = (int poolId) {
        final outVarId = calloc<Int64>();
        try {
          final result = lib.hegel_pool_add(ctx, tc, poolId, outVarId);
          _checkResult(result, 'hegel_pool_add');
          return outVarId.value;
        } finally {
          calloc.free(outVarId);
        }
      };

      machine.poolGenerateCallback = (int poolId, bool consume) {
        final outVarId = calloc<Int64>();
        try {
          final result =
              lib.hegel_pool_generate(ctx, tc, poolId, consume, outVarId);
          if (result == hegel_result_t.HEGEL_E_ASSUME) {
            return null; // pool empty
          }
          _checkResult(result, 'hegel_pool_generate');
          return outVarId.value;
        } finally {
          calloc.free(outVarId);
        }
      };

      // Main execution loop
      final outRuleIndex = calloc<Int64>();
      try {
        while (true) {
          // Ask engine for next rule
          final nextResult =
              lib.hegel_state_machine_next_rule(ctx, tc, smId, outRuleIndex);
          _checkResult(nextResult, 'hegel_state_machine_next_rule');

          final ruleIndex = outRuleIndex.value;
          if (ruleIndex == HEGEL_STATE_MACHINE_DONE) break;

          if (ruleIndex < 0 || ruleIndex >= rules.length) {
            throw StateError('Engine returned invalid rule index: $ruleIndex '
                '(${rules.length} rules registered)');
          }

          final rule = rules[ruleIndex];

          // Check precondition before executing
          if (rule.precondition != null && !rule.precondition!()) {
            // Precondition failed — signal assumption violation to engine
            throw const HegelAssumptionViolated();
          }

          // Execute the rule
          await rule.execute(dartTc);

          // Run all invariants after successful rule
          for (final inv in invariants) {
            await inv.check(dartTc);
          }
        }
      } finally {
        calloc.free(outRuleIndex);
      }
    } finally {
      calloc.free(outSmId);
    }
  } finally {
    // Free C strings
    for (final str in ruleNameStrs) {
      calloc.free(str);
    }
    for (final str in invariantNameStrs) {
      calloc.free(str);
    }
    calloc.free(ruleNames);
    calloc.free(invariantNames);
  }
}

/// Checks the result of an FFI call and throws on error.
void _checkResult(hegel_result_t result, String functionName) {
  if (result == hegel_result_t.HEGEL_OK) return;
  if (result == hegel_result_t.HEGEL_E_ASSUME) {
    throw const HegelAssumptionViolated();
  }
  if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
    throw const HegelStopTest();
  }
  stderr.writeln(
    '[hegeltest] Warning: $functionName returned unexpected code: ${result.value}',
  );
}

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../core/exceptions.dart';
import '../core/test_case.dart';
import '../ffi/hegel_bindings.g.dart';
import '../ffi/string_helpers.dart';
import 'state_machine.dart';

/// Sentinel value returned by `hegel_state_machine_next_group` and
/// `hegel_state_machine_next_rule` (`INT64_MIN`) when execution is complete.
const int hegelStateMachineDone = -9223372036854775808;

/// Runs a [StateMachine] against the hegel engine for a single test case.
///
/// This is the core loop that:
/// 1. Validates rules, invariants, and [StateMachine.stepCount]
/// 2. Registers rules and invariants with `libhegel`, then starts the machine
/// 3. Allocates native pools for the machine's [Pool] instances
/// 4. Runs initial invariants unconditionally
/// 5. Loops rounds via `hegel_state_machine_next_group` and rules via
///    `hegel_state_machine_next_rule` (reporting rejections via
///    `hegel_state_machine_rule_rejected`)
/// 6. Checks sampled/unconditional invariants and runs final invariants
/// 7. Frees all native pool and state machine handles
Future<void> runStateMachine(TestCase tc, StateMachine machine) async {
  final rules = machine.rules;
  final invariants = machine.invariants;
  final stepCount = machine.stepCount;

  if (rules.isEmpty) {
    throw ArgumentError(
      'StateMachine has no rules. '
      'Override the `rules` getter to provide at least one StateRule.',
    );
  }

  if (stepCount < 1) {
    throw ArgumentError.value(stepCount, 'machine.stepCount', 'must be >= 1');
  }

  for (final rule in rules) {
    if (rule.name.contains('\x00')) {
      throw ArgumentError.value(
        rule.name,
        'rule.name',
        'must not contain null bytes (\\x00) — they cause silent '
            'truncation at the FFI boundary',
      );
    }
    if (!rule.weight.isFinite || rule.weight <= 0) {
      throw ArgumentError.value(
        rule.weight,
        'rule.weight',
        'must be finite and > 0',
      );
    }
  }

  for (final inv in invariants) {
    if (inv.name.contains('\x00')) {
      throw ArgumentError.value(
        inv.name,
        'invariant.name',
        'must not contain null bytes (\\x00) — they cause silent '
            'truncation at the FFI boundary',
      );
    }
  }

  final ctx = tc.ctx;
  final tcHandle = tc.handle;

  final Pointer<hegel_state_machine_t> sm;
  final outSm = calloc<Pointer<hegel_state_machine_t>>();
  try {
    final smResult = hegel_new_state_machine(
      ctx,
      tcHandle,
      1,
      1,
      stepCount,
      outSm,
    );
    _checkResult(ctx, smResult, 'hegel_new_state_machine');
    sm = outSm.value;
  } finally {
    calloc.free(outSm);
  }

  try {
    using((Arena arena) {
      final groupIdPtr = arena<Int64>()..value = 0;
      for (final rule in rules) {
        final addRuleRes = hegel_state_machine_add_rule(
          ctx,
          tcHandle,
          sm,
          makeHegelString(arena, rule.name),
          rule.weight,
          groupIdPtr,
          1,
        );
        _checkResult(ctx, addRuleRes, 'hegel_state_machine_add_rule');
      }

      for (final inv in invariants) {
        final addInvRes = hegel_state_machine_add_invariant(
          ctx,
          tcHandle,
          sm,
          makeHegelString(arena, inv.name),
          inv.alwaysCheck,
        );
        _checkResult(ctx, addInvRes, 'hegel_state_machine_add_invariant');
      }

      final outConcurrency = arena<Int64>();
      final startRes = hegel_state_machine_start(
        ctx,
        tcHandle,
        sm,
        outConcurrency,
      );
      _checkResult(ctx, startRes, 'hegel_state_machine_start');
    });

    final nativePools = <Pointer<hegel_pool_t>>[];
    try {
      final outPool = calloc<Pointer<hegel_pool_t>>();
      try {
        for (var i = 0; i < machine.pools.length; i++) {
          final poolResult = hegel_new_pool(ctx, tcHandle, outPool);
          _checkResult(ctx, poolResult, 'hegel_new_pool');
          nativePools.add(outPool.value);
          machine.pools[i].poolId = i;
        }
      } finally {
        calloc.free(outPool);
      }

      machine.poolAddCallback = (int poolId) {
        final outVarId = calloc<Int64>();
        try {
          final result = hegel_pool_add(
            ctx,
            tcHandle,
            nativePools[poolId],
            outVarId,
          );
          _checkResult(ctx, result, 'hegel_pool_add');
          return outVarId.value;
        } finally {
          calloc.free(outVarId);
        }
      };

      machine.poolGenerateCallback = (int poolId, bool consume) {
        final outVarId = calloc<Int64>();
        try {
          final result = hegel_pool_generate(
            ctx,
            tcHandle,
            nativePools[poolId],
            consume,
            outVarId,
          );
          if (result == hegel_result_t.HEGEL_E_ASSUME) {
            return null;
          }
          _checkResult(ctx, result, 'hegel_pool_generate');
          return outVarId.value;
        } finally {
          calloc.free(outVarId);
        }
      };

      // Run initial invariants unconditionally before any rule.
      for (final inv in invariants) {
        await inv.check(tc);
      }

      const maxConsecutiveRejects = 200;
      var consecutiveRejects = 0;

      final outGroupId = calloc<Int64>();
      final outRoundConcurrency = calloc<Int64>();
      final outRuleIndex = calloc<Int64>();
      final outShouldCheck = calloc<Bool>();
      try {
        while (true) {
          final groupRes = hegel_state_machine_next_group(
            ctx,
            tcHandle,
            sm,
            outGroupId,
            outRoundConcurrency,
          );
          _checkResult(ctx, groupRes, 'hegel_state_machine_next_group');
          if (outGroupId.value == hegelStateMachineDone) break;

          var roundHadAcceptedRule = false;
          while (true) {
            final ruleRes = hegel_state_machine_next_rule(
              ctx,
              tcHandle,
              sm,
              0,
              outRuleIndex,
            );
            _checkResult(ctx, ruleRes, 'hegel_state_machine_next_rule');

            final ruleIndex = outRuleIndex.value;
            if (ruleIndex == hegelStateMachineDone) break;

            if (ruleIndex < 0 || ruleIndex >= rules.length) {
              throw StateError(
                'Engine returned invalid rule index: $ruleIndex '
                '(${rules.length} rules registered)',
              );
            }

            final rule = rules[ruleIndex];
            if (rule.precondition != null && !rule.precondition!()) {
              final rejRes = hegel_state_machine_rule_rejected(
                ctx,
                tcHandle,
                sm,
                0,
              );
              _checkResult(ctx, rejRes, 'hegel_state_machine_rule_rejected');
              consecutiveRejects++;
              if (consecutiveRejects >= maxConsecutiveRejects) {
                throw const HegelAssumptionViolated();
              }
              continue;
            }

            try {
              await rule.execute(tc);
              consecutiveRejects = 0;
              roundHadAcceptedRule = true;
            } on HegelAssumptionViolated {
              final rejRes = hegel_state_machine_rule_rejected(
                ctx,
                tcHandle,
                sm,
                0,
              );
              _checkResult(ctx, rejRes, 'hegel_state_machine_rule_rejected');
              consecutiveRejects++;
              if (consecutiveRejects >= maxConsecutiveRejects) {
                throw const HegelAssumptionViolated();
              }
              continue;
            }
          }

          if (roundHadAcceptedRule) {
            for (var i = 0; i < invariants.length; i++) {
              final shouldRes = hegel_state_machine_should_check_invariant(
                ctx,
                tcHandle,
                sm,
                i,
                outShouldCheck,
              );
              _checkResult(
                ctx,
                shouldRes,
                'hegel_state_machine_should_check_invariant',
              );
              if (outShouldCheck.value) {
                await invariants[i].check(tc);
              }
            }
          }
        }

        // Run final invariants unconditionally after termination.
        for (final inv in invariants) {
          await inv.check(tc);
        }
      } finally {
        calloc.free(outGroupId);
        calloc.free(outRoundConcurrency);
        calloc.free(outRuleIndex);
        calloc.free(outShouldCheck);
      }
    } finally {
      for (final poolPtr in nativePools) {
        hegel_pool_free(ctx, poolPtr);
      }
    }
  } finally {
    hegel_state_machine_free(ctx, sm);
  }
}

/// Checks the result of an FFI call and throws on error.
void _checkResult(
  Pointer<hegel_context_t> ctx,
  hegel_result_t result,
  String functionName,
) {
  if (result == hegel_result_t.HEGEL_OK) return;
  if (result == hegel_result_t.HEGEL_E_ASSUME) {
    throw const HegelAssumptionViolated();
  }
  if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
    throw const HegelStopTest();
  }
  throw hegelExceptionWithDetail(ctx, 'Failed in $functionName', result.value);
}

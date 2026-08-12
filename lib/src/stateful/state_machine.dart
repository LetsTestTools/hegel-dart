import 'dart:async';

import 'package:meta/meta.dart';

import '../core/exceptions.dart';
import '../core/test_case.dart';
import '../generators/generator.dart';

/// A rule that can be executed during stateful testing.
///
/// Each rule represents an operation on the system under test.
/// The engine uses Swarm Testing to randomly select which rules
/// to execute in each test case.
class StateRule {
  /// Human-readable name, used in counterexample output.
  final String name;

  /// Optional precondition — evaluated before the engine selects this rule.
  /// If it returns `false`, the engine skips this rule for this step.
  final bool Function()? precondition;

  /// The rule body. Receives a [TestCase] for drawing random values.
  final FutureOr<void> Function(TestCase tc) execute;

  /// Creates a state rule.
  const StateRule(this.name, {this.precondition, required this.execute});
}

/// An invariant checked after every successful rule execution.
///
/// Invariants should assert properties that must always hold,
/// regardless of which rules have been executed.
class StateInvariant {
  /// Human-readable name, used in counterexample output.
  final String name;

  /// The invariant check. Should throw (e.g. via `expect()`) on violation.
  final FutureOr<void> Function(TestCase tc) check;

  /// Creates a state invariant.
  const StateInvariant(this.name, {required this.check});
}

/// A typed pool of values that rules can add to and draw from.
///
/// Pools enable data flow between rules. For example, a `put` rule
/// can add keys to a pool, and a `get` rule can draw from it.
///
/// Mirrors Hypothesis's `Bundle` concept.
class Pool<T> {
  /// Engine-assigned pool ID (set during registration).
  int poolId = -1;

  /// Dart-side storage keyed by engine variable ID.
  final Map<int, T> values = {};

  /// Reference to the state machine this pool belongs to.
  StateMachine? machine;

  /// Returns a generator that draws a value without removing it.
  Generator<T> get reusable => _PoolGenerator<T>(this, false);

  /// Returns a generator that draws a value and removes it from the pool.
  Generator<T> get consumed => _PoolGenerator<T>(this, true);

  /// Adds a value to the pool.
  ///
  /// The value is registered with the engine and can be drawn by
  /// other rules via [reusable] or [consumed].
  void add(T value) {
    if (machine == null || poolId < 0) {
      throw StateError(
        'Pool not registered with a StateMachine. '
        'Create pools in setUp() via createPool().',
      );
    }
    final varId = machine!.poolAddCallback(poolId);
    values[varId] = value;
  }

  /// Whether the pool has any values.
  bool get isNotEmpty => values.isNotEmpty;

  /// Whether the pool is empty.
  bool get isEmpty => values.isEmpty;

  /// Number of values in the pool.
  int get length => values.length;
}

/// Internal generator that draws from a [Pool].
class _PoolGenerator<T> extends Generator<T> {
  final Pool<T> _pool;
  final bool _consume;

  _PoolGenerator(this._pool, this._consume);

  @override
  T generate(TestCase tc) {
    if (_pool.machine == null || _pool.poolId < 0) {
      throw StateError('Pool not registered with a StateMachine.');
    }
    final varId = _pool.machine!.poolGenerateCallback(_pool.poolId, _consume);
    if (varId == null) {
      // Pool was empty — signal assumption violation to skip this rule
      throw const HegelAssumptionViolated();
    }
    final value = _pool.values[varId];
    if (value == null) {
      throw StateError('Pool variable $varId not found in Dart-side storage.');
    }
    if (_consume) _pool.values.remove(varId);
    return value;
  }
}

/// Base class for stateful (model-based) property tests.
///
/// Subclass this to define rules (operations) and invariants (assertions)
/// for testing stateful systems.
///
/// ## Example
///
/// ```dart
/// class StackMachine extends StateMachine {
///   final stack = <int>[];
///   final model = <int>[];
///
///   @override
///   List<StateRule> get rules => [
///     StateRule('push', execute: (tc) {
///       final val = tc.draw(integers());
///       stack.add(val);
///       model.add(val);
///     }),
///     StateRule('pop',
///       precondition: () => stack.isNotEmpty,
///       execute: (tc) {
///         expect(stack.removeLast(), equals(model.removeLast()));
///       },
///     ),
///   ];
///
///   @override
///   List<StateInvariant> get invariants => [
///     StateInvariant('size', check: (tc) {
///       expect(stack.length, equals(model.length));
///     }),
///   ];
/// }
/// ```
abstract class StateMachine {
  /// Override to provide the list of rules (operations) for this machine.
  List<StateRule> get rules;

  /// Override to provide invariants checked after every rule.
  List<StateInvariant> get invariants => [];

  /// Called once before each test case to set up initial state.
  FutureOr<void> setUp() {}

  /// Called after each test case (including failed ones) for cleanup.
  FutureOr<void> tearDown() {}

  // --- Internal plumbing (set by the runner) ---

  /// Callback to add a value to an engine pool.
  @internal
  int Function(int poolId) poolAddCallback = (_) =>
      throw StateError('StateMachine not running');

  /// Callback to generate (draw) from an engine pool.
  /// Returns null if pool is empty (assumption violated).
  @internal
  int? Function(int poolId, bool consume) poolGenerateCallback = (_, __) =>
      throw StateError('StateMachine not running');

  /// Registered pools for this machine.
  @internal
  final List<Pool<dynamic>> pools = [];

  /// Creates and registers a [Pool] with this machine.
  ///
  /// Call this in [setUp] to create pools for value tracking.
  Pool<T> createPool<T>() {
    final pool = Pool<T>();
    pool.machine = this;
    pools.add(pool);
    return pool;
  }
}

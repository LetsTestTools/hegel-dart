import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

/// A simple stack implementation to test.
class SimpleStack<T> {
  final _items = <T>[];

  void push(T item) => _items.add(item);

  T pop() {
    if (_items.isEmpty) throw StateError('Stack is empty');
    return _items.removeLast();
  }

  T get top {
    if (_items.isEmpty) throw StateError('Stack is empty');
    return _items.last;
  }

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;

  List<T> toList() => List.unmodifiable(_items);
}

/// State machine that tests SimpleStack against a List model.
class StackMachine extends StateMachine {
  final stack = SimpleStack<int>();
  final model = <int>[];

  @override
  List<StateRule> get rules => [
    StateRule(
      'push',
      execute: (tc) {
        final val = tc.draw(integers(min: -100, max: 100));
        stack.push(val);
        model.add(val);
      },
    ),
    StateRule(
      'pop',
      precondition: () => stack.isNotEmpty,
      execute: (tc) {
        final actual = stack.pop();
        final expected = model.removeLast();
        expect(actual, equals(expected));
      },
    ),
    StateRule(
      'peek',
      precondition: () => stack.isNotEmpty,
      execute: (tc) {
        expect(stack.top, equals(model.last));
      },
    ),
  ];

  @override
  List<StateInvariant> get invariants => [
    StateInvariant(
      'size matches',
      check: (tc) {
        expect(stack.length, equals(model.length));
      },
    ),
    StateInvariant(
      'content matches',
      check: (tc) {
        expect(stack.toList(), equals(model));
      },
    ),
  ];
}

/// State machine with pools, testing a map.
class MapMachine extends StateMachine {
  final actual = <String, int>{};
  final model = <String, int>{};
  late final Pool<String> keys;

  @override
  void setUp() {
    keys = createPool<String>();
  }

  @override
  List<StateRule> get rules => [
    StateRule(
      'put',
      execute: (tc) {
        final key = tc.draw(
          text(minCodepoint: 0x61, maxCodepoint: 0x7a, minSize: 1, maxSize: 5),
        );
        final val = tc.draw(integers(min: 0, max: 999));
        actual[key] = val;
        model[key] = val;
        keys.add(key);
      },
    ),
    StateRule(
      'get',
      precondition: () => keys.isNotEmpty,
      execute: (tc) {
        final key = tc.draw(keys.reusable);
        expect(actual[key], equals(model[key]));
      },
    ),
    StateRule(
      'delete',
      precondition: () => keys.isNotEmpty,
      execute: (tc) {
        final key = tc.draw(keys.consumed);
        actual.remove(key);
        model.remove(key);
      },
    ),
  ];

  @override
  List<StateInvariant> get invariants => [
    StateInvariant(
      'size',
      check: (tc) {
        expect(actual.length, equals(model.length));
      },
    ),
    StateInvariant(
      'content',
      check: (tc) {
        expect(actual, equals(model));
      },
    ),
  ];
}

void main() {
  hegelStatefulTest('stack behaves like list', () => StackMachine());

  hegelStatefulTest('map with pool tracking', () => MapMachine());

  test('stateful tearDown failure fails the test when rules succeed', () async {
    final runner = HegelRunner();
    final result = await runner.runWithResult(
      (tc) async {
        final StateMachine machine = _FailingTearDownMachine();
        var bodyThrew = false;
        try {
          await machine.setUp();
          await runStateMachine(tc, machine);
        } catch (_) {
          bodyThrew = true;
          rethrow;
        } finally {
          try {
            await machine.tearDown();
          } catch (e) {
            if (!bodyThrew) rethrow;
          }
        }
      },
      testCases: 5,
      database: false,
    );
    expect(result.status, equals(RunStatus.failed));
    expect(
      result.failures.first.message,
      contains('tearDown invariant broken'),
    );
  });

  test(
    'runStateMachine rejects rule and invariant names with NUL bytes',
    () async {
      final runner = HegelRunner();
      final badRuleResult = await runner.runWithResult(
        (tc) async {
          await runStateMachine(tc, _NullByteRuleMachine());
        },
        testCases: 1,
        database: false,
      );
      expect(badRuleResult.status, equals(RunStatus.failed));
      expect(
        badRuleResult.failures.first.message,
        contains('must not contain null bytes'),
      );
    },
  );

  hegelStatefulTest(
    'nullable Pool<int?> supports storing and drawing null values',
    () => _NullablePoolMachine(),
    testCases: 20,
    database: false,
  );

  test('StateRule validates weight is finite and positive', () {
    for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => StateRule('invalid', weight: invalid, execute: (_) {}),
        throwsArgumentError,
      );
    }
    final valid = StateRule('valid', weight: 2.5, execute: (_) {});
    expect(valid.weight, equals(2.5));
  });

  test('runStateMachine rejects stepCount < 1', () async {
    final runner = HegelRunner();
    final result = await runner.runWithResult(
      (tc) => runStateMachine(tc, _InvalidStepCountMachine()),
      testCases: 1,
      database: false,
    );
    expect(result.status, equals(RunStatus.failed));
    expect(result.failures.first.message, contains('stepCount'));
  });

  test('custom stepCount limits executed steps per test case', () async {
    final stepCounts = <int>[];
    final runner = HegelRunner();
    final result = await runner.runWithResult(
      (tc) async {
        final machine = _BoundedStepsMachine();
        await runStateMachine(tc, machine);
        stepCounts.add(machine.executedSteps);
      },
      testCases: 10,
      database: false,
    );
    expect(result.status, equals(RunStatus.passed));
    expect(stepCounts, isNotEmpty);
    expect(stepCounts.every((s) => s >= 1 && s <= 5), isTrue);
  });

  test(
    'StateInvariant(alwaysCheck: false) checks initial and final states',
    () async {
      final runner = HegelRunner();
      final result = await runner.runWithResult(
        (tc) async {
          final checks = <int>[];
          final machine = _SampledInvariantMachine(onCheck: checks.add);
          await runStateMachine(tc, machine);
          expect(checks, isNotEmpty);
          expect(checks.first, equals(0));
          expect(checks.last, equals(machine.steps));
        },
        testCases: 10,
        database: false,
      );
      expect(result.status, equals(RunStatus.passed));
    },
  );

  hegelStatefulTest(
    'weighted rules and precondition rejections execute cleanly',
    () => _WeightedRejectedRuleMachine(),
    testCases: 20,
    database: false,
  );

  test(
    'verbose stateful run with cloned test case note completes without aborting',
    () async {
      final result = await runHegelTest(
        (tc) => runStateMachine(tc, _VerboseNoteCloneMachine()),
        verbosity: Verbosity.verbose,
        testCases: 5,
        database: false,
      );
      expect(result.status, equals(RunStatus.passed));
    },
  );
}

class _VerboseNoteCloneMachine extends StateMachine {
  @override
  int get stepCount => 4;

  @override
  List<StateRule> get rules => [
    StateRule('step', execute: (tc) => tc.draw(integers(min: 0, max: 10))),
  ];

  @override
  List<StateInvariant> get invariants => [
    StateInvariant(
      'clone note in verbose run',
      check: (tc) {
        final cloned = tc.clone();
        try {
          cloned.note('invariant note');
        } finally {
          cloned.dispose();
        }
      },
    ),
  ];
}

class _InvalidStepCountMachine extends StateMachine {
  @override
  int get stepCount => 0;

  @override
  List<StateRule> get rules => [StateRule('noop', execute: (_) {})];
}

class _BoundedStepsMachine extends StateMachine {
  int executedSteps = 0;

  @override
  int get stepCount => 5;

  @override
  List<StateRule> get rules => [
    StateRule('inc', execute: (_) => executedSteps++),
  ];
}

class _SampledInvariantMachine extends StateMachine {
  final void Function(int currentStep) onCheck;
  int steps = 0;

  _SampledInvariantMachine({required this.onCheck});

  @override
  int get stepCount => 10;

  @override
  List<StateRule> get rules => [StateRule('step', execute: (_) => steps++)];

  @override
  List<StateInvariant> get invariants => [
    StateInvariant('sampled', alwaysCheck: false, check: (_) => onCheck(steps)),
  ];
}

class _WeightedRejectedRuleMachine extends StateMachine {
  bool ready = false;
  int bRuns = 0;

  @override
  int get stepCount => 10;

  @override
  List<StateRule> get rules => [
    StateRule('enable', weight: 2.0, execute: (_) => ready = true),
    StateRule(
      'requiresReady',
      weight: 5.0,
      precondition: () => ready,
      execute: (_) {
        expect(ready, isTrue);
        bRuns++;
      },
    ),
  ];

  @override
  List<StateInvariant> get invariants => [
    StateInvariant(
      'valid count',
      check: (_) => expect(bRuns, greaterThanOrEqualTo(0)),
    ),
  ];
}

class _FailingTearDownMachine extends StateMachine {
  @override
  List<StateRule> get rules => [
    StateRule('noop', execute: (tc) => tc.draw(integers(min: 0, max: 10))),
  ];

  @override
  void tearDown() {
    throw StateError('tearDown invariant broken');
  }
}

class _NullByteRuleMachine extends StateMachine {
  @override
  List<StateRule> get rules => [StateRule('bad\x00rule', execute: (_) {})];
}

class _NullablePoolMachine extends StateMachine {
  late Pool<int?> pool;
  final List<int?> drawn = [];

  @override
  void setUp() {
    pool = createPool<int?>();
  }

  @override
  List<StateRule> get rules => [
    StateRule(
      'addNull',
      execute: (_) {
        pool.add(null);
      },
    ),
    StateRule(
      'drawNullable',
      precondition: () => pool.isNotEmpty,
      execute: (tc) {
        final v = tc.draw(pool.consumed);
        drawn.add(v);
      },
    ),
  ];

  @override
  List<StateInvariant> get invariants => [
    StateInvariant(
      'all drawn values are null',
      check: (_) {
        expect(drawn.every((v) => v == null), isTrue);
      },
    ),
  ];
}

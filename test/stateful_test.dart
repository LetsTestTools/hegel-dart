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
    final lib = loadHegelLibrary();
    final runner = HegelRunner(lib);
    final result = await runner.runWithResult(
      (tc) async {
        final StateMachine machine = _FailingTearDownMachine();
        var bodyThrew = false;
        try {
          await machine.setUp();
          await runStateMachine(lib, tc.ctx, tc.handle, machine, tc);
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
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);
      final badRuleResult = await runner.runWithResult(
        (tc) async {
          await runStateMachine(
            lib,
            tc.ctx,
            tc.handle,
            _NullByteRuleMachine(),
            tc,
          );
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

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

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;
}

/// A state machine for testing a stack's behavior against a model length count.
class StackMachine extends StateMachine {
  final stack = SimpleStack<int>();
  int model = 0;

  @override
  List<StateRule> get rules => [
    StateRule(
      'push',
      execute: (tc) {
        final val = tc.draw(integers());
        stack.push(val);
        model++;
      },
    ),
    StateRule(
      'pop',
      precondition: () => stack.isNotEmpty,
      execute: (tc) {
        stack.pop();
        model--;
      },
    ),
  ];

  @override
  List<StateInvariant> get invariants => [
    StateInvariant(
      'length invariant',
      check: (tc) {
        expect(stack.length, equals(model));
      },
    ),
  ];
}

/// A state machine using Pool to track inserted keys in a Map.
class MapPoolMachine extends StateMachine {
  final actual = <String, String>{};
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
        final key = tc.draw(text(minSize: 1, maxSize: 10));
        final val = tc.draw(text(maxSize: 10));
        actual[key] = val;
        keys.add(key);
      },
    ),
    StateRule(
      'get',
      precondition: () => keys.isNotEmpty,
      execute: (tc) {
        final key = tc.draw(keys.reusable);
        expect(actual.containsKey(key), isTrue);
      },
    ),
    StateRule(
      'remove',
      precondition: () => keys.isNotEmpty,
      execute: (tc) {
        final key = tc.draw(keys.consumed);
        actual.remove(key);
      },
    ),
  ];
}

void main() {
  hegelStatefulTest('stack length invariant', () => StackMachine());
  hegelStatefulTest('map pool tracking', () => MapPoolMachine());
}

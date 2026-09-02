# hegeltest — Property-based testing for Dart, powered by a native fuzzing engine.

[![pub package](https://img.shields.io/pub/v/hegeltest.svg)](https://pub.dev/packages/hegeltest)
[![CI](https://github.com/LetsTestTools/hegel-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/LetsTestTools/hegel-dart/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## What is property-based testing?

Instead of writing individual test cases, you describe properties that should hold for all inputs. `hegeltest` generates random inputs, finds failures, and automatically shrinks them to the minimal counterexample. This allows you to find edge cases you might never have thought to write tests for.

## Quick Start

Add `hegeltest` to your `pubspec.yaml` under `dev_dependencies`:

```yaml
dev_dependencies:
  hegeltest: ^0.5.0
  test: ^1.25.0
```

Then, write your property-based test:

```dart
import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  hegelTest('reverse is involutory', (tc) {
    // Provide a label to make counterexample output clearer on failure
    final xs = tc.draw(lists(integers()), label: 'original list');
    expect(xs.reversed.toList().reversed.toList(), equals(xs));
  });
}
```

## Available Generators

*(If you only need generators, you can use the sub-path import: `import 'package:hegeltest/generators.dart';`)*

| Category | Generators |
|----------|------------|
| Primitives | `integers()`, `doubles()`, `booleans()`, `bigIntegers()` |
| Text | `text()`, `fromRegex()`, `emails()`, `urls()`, `domains()`, `uuids()` |
| Collections | `lists()`, `sets()`, `maps()` |
| Combinators | `oneOf()`, `nullable()`, `sampled()`, `frequency()`, `tuples2/3/4()` |
| Temporal | `dates()`, `times()`, `dateTimes()` |
| Network | `ipv4Addresses()`, `ipv6Addresses()` |
| Bytes | `bytes()` |

## Composing Generators

You can build complex generators using combinators like `map()`, `flatMap()`, `where()`, and `Generator.composite()`:

```dart
final evenIntegers = integers().where((i) => i.isEven);
final stringLengths = text().map((s) => s.length);
// Or build entirely new types
final userGen = Generator.composite<User>((tc) {
  final name = tc.draw(text(minSize: 1, maxSize: 50));
  final age = tc.draw(integers(min: 0, max: 150));
  return User(name: name, age: age);
});
```

## Preconditions and Filtering

You can filter out invalid inputs using `tc.assume()`. If the condition is false, the current test case is discarded and a new one is generated:

```dart
final a = tc.draw(integers());
tc.assume(a != 0); // discard test cases where a is 0
```

## Optimization Hints

You can guide the engine's fuzzing towards specific edge cases using `tc.target()`. It records a numeric observation that the engine attempts to maximize or minimize. The `label` is required:

```dart
final items = tc.draw(lists(integers()), label: 'items');
tc.target(items.length.toDouble(), label: 'list_length');
```

## Stateful Testing

Test stateful systems by generating random sequences of operations and checking invariants after each step. Uses **Swarm Testing** to explore rule subsets and **automatic shrinking** to find minimal counterexamples.

```dart
class StackMachine extends StateMachine {
  final stack = <int>[];
  final model = <int>[];

  @override
  List<StateRule> get rules => [
    StateRule('push', execute: (tc) {
      final val = tc.draw(integers(min: -100, max: 100));
      stack.add(val);
      model.add(val);
    }),
    StateRule('pop',
      precondition: () => stack.isNotEmpty,
      execute: (tc) {
        expect(stack.removeLast(), equals(model.removeLast()));
      },
    ),
  ];

  @override
  List<StateInvariant> get invariants => [
    StateInvariant('size matches', check: (tc) {
      expect(stack.length, equals(model.length));
    }),
  ];
}

void main() {
  hegelStatefulTest('stack behaves like list', () => StackMachine());
}
```

### Pools — tracking values across rules

Use `Pool<T>` to share values between rules (like keys you've inserted into a database):

```dart
class KVStoreMachine extends StateMachine {
  final store = <String, int>{};
  late final Pool<String> keys;

  @override
  void setUp() { keys = createPool<String>(); }

  @override
  List<StateRule> get rules => [
    StateRule('put', execute: (tc) {
      final key = tc.draw(text(minSize: 1, maxSize: 5));
      final val = tc.draw(integers(min: 0, max: 999));
      store[key] = val;
      keys.add(key);                        // track the key
    }),
    StateRule('get',
      precondition: () => keys.isNotEmpty,
      execute: (tc) {
        final key = tc.draw(keys.reusable);  // draw without removing
        expect(store.containsKey(key), isTrue);
      },
    ),
    StateRule('delete',
      precondition: () => keys.isNotEmpty,
      execute: (tc) {
        final key = tc.draw(keys.consumed);  // draw and remove from pool
        store.remove(key);
      },
    ),
  ];
}
```

## Standalone Runner

If you are building custom test runners, integrating with other tools, or just want programmatic access to the fuzzing engine without `package:test` integration, you can use `runHegelTest()`:

```dart
import 'package:hegeltest/hegeltest.dart';

void main() async {
  final result = await runHegelTest((tc) {
    final a = tc.draw(integers());
    if (a < 0) throw Exception('No negatives!');
  });

  print(result.status); // RunStatus.failed
  print(result.testCasesRun);
  
  for (final failure in result.failures) {
    print(failure.message);
    print(failure.reproductionBlob);
  }
}
```

## Configuration


For reusable test configurations, you can use `HegelConfig`:

```dart
final thorough = HegelConfig(testCases: 100000);
hegelTest('check', (tc) { ... }, config: thorough);
```

You can save and load previously discovered interesting inputs across runs by specifying a `database` directory path and a unique `databaseKey` for the test. Note: database persistence depends on engine support and may require explicit path configuration.

For CI reproducibility, you can set the `HEGEL_SEED` environment variable. When set, all `hegelTest` calls will use this deterministic seed unless explicitly overridden.

### Advanced Configuration

You can fine-tune the engine's behavior using advanced settings:
* `phases`: Control which phases to run — `Phase.explicit`, `Phase.reuse`, `Phase.generate`, `Phase.target`, `Phase.shrink`.
* `verbosity`: Set output detail — `Verbosity.quiet`, `Verbosity.normal`, `Verbosity.verbose`, `Verbosity.debug`.
* `backend`: Choose the randomness source — `Backend.auto_`, `Backend.default_`, `Backend.urandom`.
* `suppressHealthChecks`: Disable specific engine health checks like `HealthCheck.tooSlow`, `HealthCheck.filterTooMuch`, `HealthCheck.returnsSlowly`, `HealthCheck.largeBaseExample`.
* `derandomize`: Avoid randomizing generation if possible.
* `reportMultipleFailures`: Report all failures instead of stopping at the first.

## Per-Iteration Isolation

If your test mutates state, make sure to isolate iterations properly using `setUpEach` and `tearDownEach` instead of the standard `package:test` setup functions. `package:test`'s `setUp` runs once per property, **not** per iteration.

```dart
hegelTest('stateful test', (tc) { ... },
  setUpEach: () => resetState(),
  tearDownEach: () => cleanupState(),
);
```

## Reproducing Failures

When a test fails, `hegeltest` provides a reproducible blob. You can use it to deterministically replay the exact failing scenario:

```dart
hegelTest('flaky test', (tc) { ... }, 
  reproduce: 'ABcdef123...', 
);
```

## Flutter

For Flutter apps, use [`hegeltest_flutter`](https://pub.dev/packages/hegeltest_flutter):

```yaml
dev_dependencies:
  hegeltest_flutter: ^0.2.0
```

```dart
import 'package:hegeltest_flutter/hegeltest_flutter.dart';

void main() {
  hegelFlutterTest('addition is commutative', (tc) {
    final a = tc.draw(integers());
    final b = tc.draw(integers());
    expect(a + b, equals(b + a));
  });

  hegelFlutterStatefulTest('stack works', () => StackMachine());
}
```

## Platform Support

| Platform | Architecture | Status |
|---|---|---|
| macOS | Apple Silicon (arm64) | ✅ Bundled |
| macOS | Intel (x64) | 🔜 Coming |
| Linux | x64 | ✅ Bundled |
| Linux | arm64 | ✅ Bundled |
| Windows | x64 | ✅ Bundled |
| Windows | arm64 | ✅ Bundled |

All bundled binaries are verified via ABI version check at load time.

Set `HEGEL_LIBHEGEL_PATH` to use a custom-built binary on unsupported platforms.

## Version Policy

| Branch | Dart SDK | Status |
|---|---|---|
| `hegeltest ^0.5.0` | `>=3.10.0` | **Active** — all new features |
| `hegeltest ^0.4.0` | `>=3.4.0` | **Maintenance** — security fixes only |

## CI/CD Notes

hegeltest uses Dart's [Build Hooks](https://dart.dev/tools/hooks) to register native binaries. The build hook runs automatically during `dart test` and `flutter test` — no extra CI configuration needed. No network access is required (binaries are bundled in the package).

## License

This package is licensed under the MIT license.

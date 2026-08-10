# hegeltest — Property-based testing for Dart, powered by a native fuzzing engine.

[![pub package](https://img.shields.io/pub/v/hegeltest.svg)](https://pub.dev/packages/hegeltest)
[![CI](https://github.com/LetsTestTools/hegel-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/LetsTestTools/hegel-dart/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

## What is property-based testing?

Instead of writing individual test cases, you describe properties that should hold for all inputs. `hegeltest` generates random inputs, finds failures, and automatically shrinks them to the minimal counterexample. This allows you to find edge cases you might never have thought to write tests for.

## Quick Start

Add `hegeltest` to your `pubspec.yaml` under `dev_dependencies`:

```yaml
dev_dependencies:
  hegeltest: ^0.1.0
  test: ^1.25.0
```

Then, write your property-based test:

```dart
import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  hegelTest('reverse is involutory', (tc) {
    final xs = tc.draw(lists(integers()));
    expect(xs.reversed.toList().reversed.toList(), equals(xs));
  });
}
```

## Available Generators

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

## Configuration

For reusable test configurations, you can use `HegelConfig`:

```dart
final thorough = HegelConfig(testCases: 100000);
hegelTest('check', (tc) { ... }, config: thorough);
```

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

## Flutter Users

The `text()` generator name conflicts with Flutter's `Text` widget. When writing tests for Flutter, you should either hide `text` from `hegeltest` or use a library prefix:

```dart
import 'package:hegeltest/hegeltest.dart' hide text;
// or
import 'package:hegeltest/hegeltest.dart' as hegel;
```

## Platform Support

| Platform | Status |
|---|---|
| macOS (Apple Silicon) | ✅ Bundled |
| macOS (Intel) | 🔜 Coming |
| Linux (x64) | 🔜 Coming |
| Linux (arm64) | 🔜 Coming |
| Windows (x64) | 🔜 Coming |

> **Note:** v0.1.0 ships with macOS arm64 only. Additional platforms will be added in upcoming releases. Set `HEGEL_LIBHEGEL_PATH` to use a locally-built binary on other platforms.

## License

This package is licensed under the BSD-3-Clause license.

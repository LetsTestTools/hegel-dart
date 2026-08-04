# hegeltest

[![pub package](https://img.shields.io/pub/v/hegeltest.svg)](https://pub.dev/packages/hegeltest)

Property-based testing for Dart, powered by [Hegel](https://hegel.dev)'s native engine.

Automatically finds edge cases by generating random inputs, then **shrinks** failures to the **smallest possible counterexample**.

## Quick Start

```dart
import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

void main() {
  hegelTest('reverse is involutory', (tc) {
    final xs = tc.draw(lists(integers()));
    expect(xs.reversed.toList().reversed.toList(), equals(xs));
  });

  hegelTest('addition is commutative', (tc) {
    final a = tc.draw(integers());
    final b = tc.draw(integers());
    expect(a + b, equals(b + a));
  });
}
```

## Features

- **Automatic shrinking** — When a test fails, Hegel automatically reduces the failing input to the smallest possible counterexample
- **Rich generators** — integers, doubles, strings, lists, sets, maps, dates, UUIDs, emails, URLs, regex patterns, IP addresses, and more
- **Composable** — Build complex generators with `map`, `where`, `flatMap`, and `Generator.composite`
- **Async support** — Test bodies can be `async`
- **Deterministic replay** — Failed tests produce a reproduce blob for deterministic replay
- **Multi-bug detection** — Find multiple distinct bugs in a single test run
- **Powered by libhegel** — The same battle-tested Hypothesis-derived engine used by hegel-rust and hegel-typescript

## Generators

### Primitives

```dart
integers(min: 0, max: 100)       // int in [0, 100]
doubles(min: 0.0, max: 1.0)      // double in [0.0, 1.0]
booleans(p: 0.7)                 // true with 70% probability
bigIntegers(min: BigInt.zero, max: BigInt.from(1) << 256)
```

### Text

```dart
text(minSize: 1, maxSize: 50)    // Unicode strings
fromRegex(r'^[a-z]+@[a-z]+\.com$') // Regex-matched strings
emails()                          // RFC 5321 email addresses
urls()                            // RFC 3986 HTTP/HTTPS URLs
domains()                         // RFC 1035 domain names
uuids(version: 4)                 // UUIDs
```

### Collections

```dart
lists(integers(), minSize: 1, maxSize: 10)
sets(integers())
maps(text(), integers())
```

### Combinators

```dart
oneOf([integers(), doubles().map((d) => d.toInt())])
sampled(['red', 'green', 'blue'])
nullable(integers())
tuples2(integers(), text())       // Dart 3 records: (int, String)
frequency([(3, integers()), (1, text().map(int.parse))])
```

### Temporal & Network

```dart
dateTimes(min: DateTime(2020), max: DateTime(2030))
ipv4Addresses()
ipv6Addresses()
```

## Composing Generators

```dart
final userGen = Generator.composite<User>((tc) {
  final name = tc.draw(text(minSize: 1, maxSize: 50));
  final age = tc.draw(integers(min: 0, max: 150));
  final email = tc.draw(emails());
  return User(name: name, age: age, email: email);
});
```

## Async Tests

```dart
hegelTest('async operations', (tc) async {
  final input = tc.draw(text());
  final result = await processAsync(input);
  expect(result, isNotNull);
});
```

## Configuration

```dart
hegelTest(
  'custom settings',
  (tc) { /* ... */ },
  testCases: 500,           // Run 500 test cases (default: 100)
  seed: 42,                 // Deterministic seed
  verbosity: Verbosity.verbose,
  suppressHealthChecks: {HealthCheck.tooSlow},
);
```

## Setup

### Prerequisites

You need the `libhegel` native library. Build from source:

```bash
git clone https://github.com/hegeldev/hegel-rust
cd hegel-rust
cargo build --release -p hegeltest-c
export HEGEL_LIBHEGEL_PATH=$(pwd)/target/release/libhegel_c.dylib  # macOS
# export HEGEL_LIBHEGEL_PATH=$(pwd)/target/release/libhegel_c.so   # Linux
```

### Install

```yaml
dev_dependencies:
  hegeltest: ^0.1.0
```

## License

MIT — see [LICENSE](LICENSE).

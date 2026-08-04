/// Property-based testing for Dart, powered by Hegel's native engine.
///
/// ```dart
/// import 'package:hegeltest/hegeltest.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   hegelTest('reverse is involutory', (tc) {
///     final xs = tc.draw(lists(integers()));
///     expect(xs.reversed.toList().reversed.toList(), equals(xs));
///   });
/// }
/// ```
library hegeltest;

export 'src/core/exceptions.dart'
    show HegelException, HegelStopTest, HegelAssumptionViolated, HegelTestFailure;
export 'src/core/result.dart' show RunStatus, RunResult, Failure;
export 'src/core/runner.dart' show hegelTest;
export 'src/core/settings.dart'
    show Phase, Verbosity, Backend, HealthCheck, RunMode;
export 'src/core/test_case.dart' show TestCase;
export 'src/generators/bytes.dart' show bytes;
export 'src/generators/collections.dart' show lists, sets, maps;
export 'src/generators/combinators.dart'
    show sampled, oneOf, nullable, tuples2, tuples3, tuples4, frequency;
export 'src/generators/generator.dart' show Generator;
export 'src/generators/network.dart' show ipv4Addresses, ipv6Addresses;
export 'src/generators/primitives.dart'
    show integers, doubles, booleans, bigIntegers;
export 'src/generators/temporal.dart' show dates, times, dateTimes;
export 'src/generators/text.dart'
    show text, fromRegex, emails, urls, domains, uuids;

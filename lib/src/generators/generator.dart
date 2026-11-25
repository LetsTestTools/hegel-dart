import 'dart:io';

import 'package:meta/meta.dart';

import '../core/exceptions.dart';
import '../core/test_case.dart';
import '../ffi/span_labels.dart';

abstract class Generator<T> {
  const Generator();

  /// Cached string representation of this generator's runtime type.
  /// Used by TestCase.draw() to avoid per-draw reflection.
  String get typeName => runtimeType.toString();

  /// Stable 64-bit span label identifying this generator's shape for the shrinker.
  @internal
  int get spanLabel => SpanLabels.fromName('hegeltest.custom.$typeName');

  T generate(TestCase tc);

  Generator<U> map<U>(U Function(T value) mapper) {
    return MappedGenerator<T, U>(this, mapper);
  }

  Generator<T> where(
    bool Function(T value) predicate, {
    int maxAttempts = 100,
  }) {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be > 0');
    }
    return FilteredGenerator<T>(this, predicate, maxAttempts: maxAttempts);
  }

  Generator<U> flatMap<U>(Generator<U> Function(T value) mapper) {
    return FlatMappedGenerator<T, U>(this, mapper);
  }

  static Generator<T> composite<T>(T Function(TestCase tc) generateFn) {
    return CompositeGenerator<T>(generateFn);
  }
}

class MappedGenerator<T, U> extends Generator<U> {
  final Generator<T> _generator;
  final U Function(T value) _mapper;

  const MappedGenerator(this._generator, this._mapper);

  @override
  int get spanLabel => SpanLabels.combine3(
    SpanLabels.mapped,
    _generator.spanLabel,
    SpanLabels.fromName(U.toString()),
  );

  @override
  U generate(TestCase tc) {
    return _mapper(_generator.generate(tc));
  }
}

class FilteredGenerator<T> extends Generator<T> {
  final Generator<T> _generator;
  final bool Function(T value) _predicate;
  final int _maxAttempts;
  late final int _spanLabel = SpanLabels.combine2(
    SpanLabels.filter,
    _generator.spanLabel,
  );

  FilteredGenerator(this._generator, this._predicate, {int maxAttempts = 100})
    : _maxAttempts = maxAttempts {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be > 0');
    }
  }

  @override
  int get spanLabel => _spanLabel;

  @override
  T generate(TestCase tc) {
    // Try up to a reasonable number of times before giving up.
    // HegelStopTest (budget exhaustion) is NOT caught — it must
    // propagate to the runner so the engine correctly distinguishes
    // "budget exhausted" from "invalid assumption".
    //
    // Each attempt is wrapped in a span so that rejected draws
    // don't shift the fuzzer tape during shrinking. Rejected
    // spans are discarded, keeping tape positions stable.
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      tc.startSpan(_spanLabel);
      bool accepted = false;
      bool threw = false;
      try {
        final value = _generator.generate(tc);
        if (_predicate(value)) {
          accepted = true;
          return value;
        }
      } catch (e) {
        threw = true;
        rethrow;
      } finally {
        tc.safeStopSpan(discard: !accepted, hadError: threw);
      }
    }
    // Exhausted filter attempts — warn and discard this test case.
    // ignore: avoid_print
    stderr.writeln(
      '[hegeltest] Warning: FilteredGenerator rejected $_maxAttempts consecutive '
      'values. Is your predicate too strict? Discarding test case.',
    );
    throw const HegelAssumptionViolated();
  }
}

class FlatMappedGenerator<T, U> extends Generator<U> {
  final Generator<T> _generator;
  final Generator<U> Function(T value) _mapper;

  const FlatMappedGenerator(this._generator, this._mapper);

  @override
  int get spanLabel => SpanLabels.combine3(
    SpanLabels.flatMap,
    _generator.spanLabel,
    SpanLabels.fromName(U.toString()),
  );

  @override
  U generate(TestCase tc) {
    tc.startSpan(spanLabel);
    bool success = false;
    try {
      final value = _generator.generate(tc);
      final result = _mapper(value).generate(tc);
      success = true;
      return result;
    } finally {
      tc.safeStopSpan(hadError: !success);
    }
  }
}

class CompositeGenerator<T> extends Generator<T> {
  final T Function(TestCase tc) _generateFn;

  const CompositeGenerator(this._generateFn);

  @override
  int get spanLabel => SpanLabels.combine2(
    SpanLabels.composite,
    SpanLabels.fromName(T.toString()),
  );

  @override
  T generate(TestCase tc) {
    tc.startSpan(spanLabel);
    bool success = false;
    try {
      final result = _generateFn(tc);
      success = true;
      return result;
    } finally {
      tc.safeStopSpan(hadError: !success);
    }
  }
}

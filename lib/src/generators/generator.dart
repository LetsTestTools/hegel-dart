import '../core/exceptions.dart';
import '../core/test_case.dart';

abstract class Generator<T> {
  const Generator();

  T generate(TestCase tc);

  Generator<U> map<U>(U Function(T value) mapper) {
    return MappedGenerator<T, U>(this, mapper);
  }

  Generator<T> where(bool Function(T value) predicate) {
    return FilteredGenerator<T>(this, predicate);
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
  U generate(TestCase tc) {
    return _mapper(_generator.generate(tc));
  }
}

class FilteredGenerator<T> extends Generator<T> {
  final Generator<T> _generator;
  final bool Function(T value) _predicate;

  const FilteredGenerator(this._generator, this._predicate);

  @override
  T generate(TestCase tc) {
    // Try up to a reasonable number of times before giving up.
    // HegelStopTest (budget exhaustion) is NOT caught — it must
    // propagate to the runner so the engine correctly distinguishes
    // "budget exhausted" from "invalid assumption".
    for (var attempt = 0; attempt < 100; attempt++) {
      final value = _generator.generate(tc);
      if (_predicate(value)) {
        return value;
      }
    }
    // Exhausted filter attempts — discard this test case.
    throw const HegelAssumptionViolated();
  }
}

class FlatMappedGenerator<T, U> extends Generator<U> {
  final Generator<T> _generator;
  final Generator<U> Function(T value) _mapper;

  const FlatMappedGenerator(this._generator, this._mapper);

  @override
  U generate(TestCase tc) {
    final value = _generator.generate(tc);
    return _mapper(value).generate(tc);
  }
}

class CompositeGenerator<T> extends Generator<T> {
  final T Function(TestCase tc) _generateFn;

  const CompositeGenerator(this._generateFn);

  @override
  T generate(TestCase tc) {
    return _generateFn(tc);
  }
}

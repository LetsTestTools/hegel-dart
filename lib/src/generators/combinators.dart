import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class SampledGenerator<T> extends Generator<T> {
  final List<T> values;

  SampledGenerator(this.values) {
    if (values.isEmpty) {
      throw ArgumentError('SampledGenerator requires a non-empty list of values.');
    }
  }

  @override
  T generate(TestCase tc) {
    return using((Arena arena) {
      final outIndex = arena<ffi.Int64>();
      final result = tc.lib.hegel_generate_integer(
        tc.ctx,
        tc.handle,
        0,
        values.length - 1,
        outIndex,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate sampled index: ${result.value}');
      }

      return values[outIndex.value];
    });
  }
}

/// Picks a value randomly from a fixed list of values.
///
/// ```dart
/// tc.draw(sampled(['a', 'b', 'c']))
/// ```
Generator<T> sampled<T>(List<T> values) => SampledGenerator(values);

class OneOfGenerator<T> extends Generator<T> {
  final List<Generator<T>> gens;

  OneOfGenerator(this.gens) {
    if (gens.isEmpty) {
      throw ArgumentError('OneOfGenerator requires a non-empty list of generators.');
    }
  }

  @override
  T generate(TestCase tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_ONE_OF.value);
      bool success = false;
      try {
        final outIndex = arena<ffi.Int64>();
        final result = tc.lib.hegel_generate_integer(
          tc.ctx,
          tc.handle,
          0,
          gens.length - 1,
          outIndex,
        );

        if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
          throw const HegelStopTest();
        }
        if (result != hegel_result_t.HEGEL_OK) {
          throw HegelException('Failed to generate oneOf index: ${result.value}');
        }

        final value = gens[outIndex.value].generate(tc);
        success = true;
        return value;
      } finally {
        tc.safeStopSpan(hadError: !success);
      }
    });
  }
}

/// Picks one of the provided generators uniformly at random.
///
/// ```dart
/// tc.draw(oneOf([integers(), doubles()]))
/// ```
Generator<T> oneOf<T>(List<Generator<T>> gens) => OneOfGenerator(gens);

class NullableGenerator<T> extends Generator<T?> {
  final Generator<T> gen;
  final double nullProbability;

  NullableGenerator(this.gen, this.nullProbability) {
    if (nullProbability < 0.0 || nullProbability > 1.0) {
      throw ArgumentError('nullable: nullProbability ($nullProbability) must be in [0.0, 1.0]');
    }
  }

  @override
  T? generate(TestCase tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_OPTIONAL.value);
      bool success = false;
      try {
        final outBool = arena<ffi.Bool>();
        final result = tc.lib.hegel_generate_boolean(
          tc.ctx,
          tc.handle,
          nullProbability,
          false,
          false,
          outBool,
        );

        if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
          throw const HegelStopTest();
        }
        if (result != hegel_result_t.HEGEL_OK) {
          throw HegelException('Failed to generate boolean for nullable: ${result.value}');
        }

        T? value;
        if (outBool.value) {
          value = null;
        } else {
          value = gen.generate(tc);
        }
        success = true;
        return value;
      } finally {
        tc.safeStopSpan(hadError: !success);
      }
    });
  }
}

/// Wraps a generator to occasionally produce null.
///
/// ```dart
/// tc.draw(nullable(integers()))
/// ```
Generator<T?> nullable<T>(Generator<T> gen, {double nullProbability = 0.5}) => NullableGenerator(gen, nullProbability);

/// Generates 2-tuples (pairs) of independent values.
///
/// ```dart
/// tc.draw(tuples2(integers(), booleans()))
/// ```
Generator<(A, B)> tuples2<A, B>(Generator<A> a, Generator<B> b) {
  return Generator.composite((tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_TUPLE.value);
      bool success = false;
      try {
        final result = (a.generate(tc), b.generate(tc));
        success = true;
        return result;
      } finally {
        tc.safeStopSpan(hadError: !success);
      }
    });
  });
}

/// Generates 3-tuples of independent values.
Generator<(A, B, C)> tuples3<A, B, C>(Generator<A> a, Generator<B> b, Generator<C> c) {
  return Generator.composite((tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_TUPLE.value);
      bool success = false;
      try {
        final result = (a.generate(tc), b.generate(tc), c.generate(tc));
        success = true;
        return result;
      } finally {
        tc.safeStopSpan(hadError: !success);
      }
    });
  });
}

/// Generates 4-tuples of independent values.
Generator<(A, B, C, D)> tuples4<A, B, C, D>(Generator<A> a, Generator<B> b, Generator<C> c, Generator<D> d) {
  return Generator.composite((tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_TUPLE.value);
      bool success = false;
      try {
        final result = (a.generate(tc), b.generate(tc), c.generate(tc), d.generate(tc));
        success = true;
        return result;
      } finally {
        tc.safeStopSpan(hadError: !success);
      }
    });
  });
}

class FrequencyGenerator<T> extends Generator<T> {
  final List<(int, Generator<T>)> weighted;
  final int totalWeight;

  FrequencyGenerator(this.weighted)
      : totalWeight = weighted.fold(0, (sum, item) => sum + item.$1) {
    if (weighted.isEmpty) {
      throw ArgumentError('FrequencyGenerator requires a non-empty list of weighted generators.');
    }
    for (final item in weighted) {
      if (item.$1 < 0) {
        throw ArgumentError('FrequencyGenerator weights must be non-negative, got ${item.$1}.');
      }
    }
    if (totalWeight <= 0) {
      throw ArgumentError('FrequencyGenerator requires at least one generator with weight > 0.');
    }
  }

  @override
  T generate(TestCase tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_ONE_OF.value);
      bool success = false;
      try {
        final outIndex = arena<ffi.Int64>();
        final result = tc.lib.hegel_generate_integer(
          tc.ctx,
          tc.handle,
          1,
          totalWeight,
          outIndex,
        );

        if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
          throw const HegelStopTest();
        }
        if (result != hegel_result_t.HEGEL_OK) {
          throw HegelException('Failed to generate frequency index: ${result.value}');
        }

        int target = outIndex.value;
        for (final item in weighted) {
          target -= item.$1;
          if (target <= 0) {
            final value = item.$2.generate(tc);
            success = true;
            return value;
          }
        }
        
        // Fallback in case of rounding/logic issues, though shouldn't happen.
        final value = weighted.last.$2.generate(tc);
        success = true;
        return value;
      } finally {
        tc.safeStopSpan(hadError: !success);
      }
    });
  }
}

/// Selects a generator based on provided probability weights.
///
/// ```dart
/// tc.draw(frequency([(1, integers()), (9, doubles())]))
/// ```
Generator<T> frequency<T>(List<(int, Generator<T>)> weighted) => FrequencyGenerator(weighted);

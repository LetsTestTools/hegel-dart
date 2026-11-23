import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';
import '../ffi/span_labels.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class ListGenerator<T> extends Generator<List<T>> {
  final Generator<T> elements;
  final int minSize;
  final int maxSize;

  ListGenerator(this.elements, this.minSize, this.maxSize) {
    if (minSize < 0) {
      throw ArgumentError('lists: minSize ($minSize) must be >= 0');
    }
    if (minSize > maxSize) {
      throw ArgumentError(
        'lists: minSize ($minSize) must be <= maxSize ($maxSize)',
      );
    }
  }

  @override
  List<T> generate(TestCase tc) {
    tc.startSpan(SpanLabels.list);
    bool success = false;

    try {
      final ctx = tc.ctx;
      final handle = tc.handle;
      final outCollection = tc.reuseBuffer<ffi.Pointer<hegel_collection_t>>(
        'listColPtr',
        () => calloc<ffi.Pointer<hegel_collection_t>>(),
      );
      final res = hegel_new_collection(
        ctx,
        handle,
        minSize,
        maxSize,
        outCollection,
      );
      if (res == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (res != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          ctx,
          'Failed to create list collection',
          res.value,
        );
      }

      final collection = outCollection.value;
      try {
        final list = <T>[];
        final outMore = tc.reuseBuffer<ffi.Bool>(
          'listMore',
          () => calloc<ffi.Bool>(),
        );

        while (true) {
          final moreRes = hegel_collection_more(
            ctx,
            handle,
            collection,
            outMore,
          );
          if (moreRes == hegel_result_t.HEGEL_E_STOP_TEST) {
            throw const HegelStopTest();
          }
          if (moreRes != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              ctx,
              'Failed to generate collection more',
              moreRes.value,
            );
          }
          if (!outMore.value) break;

          tc.startSpan(SpanLabels.listElement);
          bool elementAdded = false;
          try {
            list.add(elements.generate(tc));
            elementAdded = true;
          } finally {
            tc.safeStopSpan(discard: !elementAdded, hadError: !elementAdded);
          }
        }
        success = true;
        return list;
      } finally {
        hegel_collection_free(ctx, collection);
      }
    } finally {
      tc.safeStopSpan(hadError: !success);
    }
  }
}

class SetGenerator<T> extends Generator<Set<T>> {
  final Generator<T> elements;
  final int minSize;
  final int maxSize;

  SetGenerator(this.elements, this.minSize, this.maxSize) {
    if (minSize < 0) {
      throw ArgumentError('sets: minSize ($minSize) must be >= 0');
    }
    if (minSize > maxSize) {
      throw ArgumentError(
        'sets: minSize ($minSize) must be <= maxSize ($maxSize)',
      );
    }
  }

  @override
  Set<T> generate(TestCase tc) {
    tc.startSpan(SpanLabels.set);
    bool success = false;

    try {
      final ctx = tc.ctx;
      final handle = tc.handle;
      final outCollection = tc.reuseBuffer<ffi.Pointer<hegel_collection_t>>(
        'setColPtr',
        () => calloc<ffi.Pointer<hegel_collection_t>>(),
      );
      final res = hegel_new_collection(
        ctx,
        handle,
        minSize,
        maxSize,
        outCollection,
      );
      if (res == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (res != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          ctx,
          'Failed to create set collection',
          res.value,
        );
      }

      final collection = outCollection.value;
      try {
        final set = <T>{};
        final outMore = tc.reuseBuffer<ffi.Bool>(
          'setMore',
          () => calloc<ffi.Bool>(),
        );
        var consecutiveRejects = 0;

        while (true) {
          final moreRes = hegel_collection_more(
            ctx,
            handle,
            collection,
            outMore,
          );
          if (moreRes == hegel_result_t.HEGEL_E_STOP_TEST) {
            throw const HegelStopTest();
          }
          if (moreRes != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              ctx,
              'Failed to generate collection more',
              moreRes.value,
            );
          }
          if (!outMore.value) break;

          tc.startSpan(SpanLabels.setElement);
          bool elementAdded = false;
          bool threw = true;
          try {
            final e = elements.generate(tc);
            threw = false;
            if (set.contains(e)) {
              threw = true;
              _rejectCollectionElement(
                ctx,
                handle,
                collection,
                'Failed to reject set duplicate',
              );
              threw = false;
              consecutiveRejects++;
              if (consecutiveRejects >= 1000) {
                stderr.writeln(
                  '[hegeltest] Warning: SetGenerator rejected 1000 consecutive duplicates. Is the element domain too small for minSize? Discarding test case.',
                );
                threw = true;
                throw const HegelAssumptionViolated();
              }
            } else {
              set.add(e);
              elementAdded = true;
              consecutiveRejects = 0;
            }
          } finally {
            tc.safeStopSpan(discard: !elementAdded, hadError: threw);
          }
        }
        success = true;
        return set;
      } finally {
        hegel_collection_free(ctx, collection);
      }
    } finally {
      tc.safeStopSpan(hadError: !success);
    }
  }
}

class MapGenerator<K, V> extends Generator<Map<K, V>> {
  final Generator<K> keys;
  final Generator<V> values;
  final int minSize;
  final int maxSize;

  MapGenerator(this.keys, this.values, this.minSize, this.maxSize) {
    if (minSize < 0) {
      throw ArgumentError('maps: minSize ($minSize) must be >= 0');
    }
    if (minSize > maxSize) {
      throw ArgumentError(
        'maps: minSize ($minSize) must be <= maxSize ($maxSize)',
      );
    }
  }

  @override
  Map<K, V> generate(TestCase tc) {
    tc.startSpan(SpanLabels.map);
    bool success = false;

    try {
      final ctx = tc.ctx;
      final handle = tc.handle;
      final outCollection = tc.reuseBuffer<ffi.Pointer<hegel_collection_t>>(
        'mapColPtr',
        () => calloc<ffi.Pointer<hegel_collection_t>>(),
      );
      final res = hegel_new_collection(
        ctx,
        handle,
        minSize,
        maxSize,
        outCollection,
      );
      if (res == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (res != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          ctx,
          'Failed to create map collection',
          res.value,
        );
      }

      final collection = outCollection.value;
      try {
        final map = <K, V>{};
        final outMore = tc.reuseBuffer<ffi.Bool>(
          'mapMore',
          () => calloc<ffi.Bool>(),
        );
        var consecutiveRejects = 0;

        while (true) {
          final moreRes = hegel_collection_more(
            ctx,
            handle,
            collection,
            outMore,
          );
          if (moreRes == hegel_result_t.HEGEL_E_STOP_TEST) {
            throw const HegelStopTest();
          }
          if (moreRes != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              ctx,
              'Failed to generate collection more',
              moreRes.value,
            );
          }
          if (!outMore.value) break;

          tc.startSpan(SpanLabels.mapEntry);
          bool elementAdded = false;
          bool threw = true;
          try {
            final k = keys.generate(tc);
            if (map.containsKey(k)) {
              _rejectCollectionElement(
                ctx,
                handle,
                collection,
                'Failed to reject map duplicate key',
              );
              threw = false;
              consecutiveRejects++;
              if (consecutiveRejects >= 1000) {
                stderr.writeln(
                  '[hegeltest] Warning: MapGenerator rejected 1000 consecutive duplicates. Is the element domain too small for minSize? Discarding test case.',
                );
                threw = true;
                throw const HegelAssumptionViolated();
              }
            } else {
              final v = values.generate(tc);
              map[k] = v;
              elementAdded = true;
              threw = false;
              consecutiveRejects = 0;
            }
          } finally {
            tc.safeStopSpan(discard: !elementAdded, hadError: threw);
          }
        }
        success = true;
        return map;
      } finally {
        hegel_collection_free(ctx, collection);
      }
    } finally {
      tc.safeStopSpan(hadError: !success);
    }
  }
}

/// Generates lists of elements from the provided generator.
///
/// Defaults to a maximum size of 2^63 - 1.
///
/// ```dart
/// tc.draw(lists(integers(), maxSize: 10))
/// ```
Generator<List<T>> lists<T>(
  Generator<T> elements, {
  int minSize = 0,
  int maxSize = 9223372036854775807,
}) {
  return ListGenerator(elements, minSize, maxSize);
}

/// Generates sets of unique elements from the provided generator.
///
/// Will reject up to 1000 consecutive duplicates before throwing.
///
/// ```dart
/// tc.draw(sets(integers(), maxSize: 5))
/// ```
Generator<Set<T>> sets<T>(
  Generator<T> elements, {
  int minSize = 0,
  int maxSize = 9223372036854775807,
}) {
  return SetGenerator(elements, minSize, maxSize);
}

/// Generates maps with unique keys and corresponding values.
///
/// Will reject up to 1000 consecutive key duplicates before throwing.
///
/// ```dart
/// tc.draw(maps(text(), integers(), maxSize: 5))
/// ```
Generator<Map<K, V>> maps<K, V>(
  Generator<K> keys,
  Generator<V> values, {
  int minSize = 0,
  int maxSize = 9223372036854775807,
}) {
  return MapGenerator(keys, values, minSize, maxSize);
}

void _rejectCollectionElement(
  ffi.Pointer<hegel_context_t> ctx,
  ffi.Pointer<hegel_test_case_t> handle,
  ffi.Pointer<hegel_collection_t> collection,
  String operation,
) {
  final rejRes = hegel_collection_reject(ctx, handle, collection, ffi.nullptr);
  if (rejRes == hegel_result_t.HEGEL_E_STOP_TEST) {
    throw const HegelStopTest();
  }
  if (rejRes == hegel_result_t.HEGEL_E_ASSUME) {
    throw const HegelAssumptionViolated();
  }
  if (rejRes != hegel_result_t.HEGEL_OK) {
    throw hegelExceptionWithDetail(ctx, operation, rejRes.value);
  }
}

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class ListGenerator<T> extends Generator<List<T>> {
  final Generator<T> elements;
  final int minSize;
  final int maxSize;

  ListGenerator(this.elements, this.minSize, this.maxSize) {
    if (minSize < 0) throw ArgumentError('lists: minSize ($minSize) must be >= 0');
    if (minSize > maxSize) throw ArgumentError('lists: minSize ($minSize) must be <= maxSize ($maxSize)');
  }

  @override
  List<T> generate(TestCase tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_LIST.value);
      bool success = false;

      try {
        final outCollectionId = arena<ffi.Int64>();
        final res = tc.lib.hegel_new_collection(tc.ctx, tc.handle, minSize, maxSize, outCollectionId);
        if (res != hegel_result_t.HEGEL_OK) throw HegelException('Failed to create list collection');
        
        final collectionId = outCollectionId.value;
        final list = <T>[];
        final outMore = arena<ffi.Bool>();
        
        while (true) {
          final moreRes = tc.lib.hegel_collection_more(tc.ctx, tc.handle, collectionId, outMore);
          if (moreRes == hegel_result_t.HEGEL_E_STOP_TEST) throw const HegelStopTest();
          if (moreRes != hegel_result_t.HEGEL_OK) throw HegelException('Failed to generate collection more');
          if (!outMore.value) break;

          tc.startSpan(hegel_label_t.HEGEL_LABEL_LIST_ELEMENT.value);
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
        tc.safeStopSpan(hadError: !success);
      }
    });
  }
}

class SetGenerator<T> extends Generator<Set<T>> {
  final Generator<T> elements;
  final int minSize;
  final int maxSize;

  SetGenerator(this.elements, this.minSize, this.maxSize) {
    if (minSize < 0) throw ArgumentError('sets: minSize ($minSize) must be >= 0');
    if (minSize > maxSize) throw ArgumentError('sets: minSize ($minSize) must be <= maxSize ($maxSize)');
  }

  @override
  Set<T> generate(TestCase tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_SET.value);
      bool success = false;

      try {
        final outCollectionId = arena<ffi.Int64>();
        final res = tc.lib.hegel_new_collection(tc.ctx, tc.handle, minSize, maxSize, outCollectionId);
        if (res != hegel_result_t.HEGEL_OK) throw HegelException('Failed to create set collection');
        
        final collectionId = outCollectionId.value;
        final set = <T>{};
        final outMore = arena<ffi.Bool>();
        var consecutiveRejects = 0;
        
        while (true) {
          final moreRes = tc.lib.hegel_collection_more(tc.ctx, tc.handle, collectionId, outMore);
          if (moreRes == hegel_result_t.HEGEL_E_STOP_TEST) throw const HegelStopTest();
          if (moreRes != hegel_result_t.HEGEL_OK) throw HegelException('Failed to generate collection more');
          if (!outMore.value) break;

          tc.startSpan(hegel_label_t.HEGEL_LABEL_SET_ELEMENT.value);
          bool elementAdded = false;
          bool threw = true;
          try {
            final e = elements.generate(tc);
            threw = false;
            if (set.contains(e)) {
              tc.lib.hegel_collection_reject(tc.ctx, tc.handle, collectionId, ffi.nullptr);
              consecutiveRejects++;
              if (consecutiveRejects >= 1000) {
                stderr.writeln('[hegeltest] Warning: SetGenerator rejected 1000 consecutive duplicates. Is the element domain too small for minSize? Discarding test case.');
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
        tc.safeStopSpan(hadError: !success);
      }
    });
  }
}

class MapGenerator<K, V> extends Generator<Map<K, V>> {
  final Generator<K> keys;
  final Generator<V> values;
  final int minSize;
  final int maxSize;

  MapGenerator(this.keys, this.values, this.minSize, this.maxSize) {
    if (minSize < 0) throw ArgumentError('maps: minSize ($minSize) must be >= 0');
    if (minSize > maxSize) throw ArgumentError('maps: minSize ($minSize) must be <= maxSize ($maxSize)');
  }

  @override
  Map<K, V> generate(TestCase tc) {
    return using((Arena arena) {
      tc.startSpan(hegel_label_t.HEGEL_LABEL_MAP.value);
      bool success = false;

      try {
        final outCollectionId = arena<ffi.Int64>();
        final res = tc.lib.hegel_new_collection(tc.ctx, tc.handle, minSize, maxSize, outCollectionId);
        if (res != hegel_result_t.HEGEL_OK) throw HegelException('Failed to create map collection');
        
        final collectionId = outCollectionId.value;
        final map = <K, V>{};
        final outMore = arena<ffi.Bool>();
        var consecutiveRejects = 0;
        
        while (true) {
          final moreRes = tc.lib.hegel_collection_more(tc.ctx, tc.handle, collectionId, outMore);
          if (moreRes == hegel_result_t.HEGEL_E_STOP_TEST) throw const HegelStopTest();
          if (moreRes != hegel_result_t.HEGEL_OK) throw HegelException('Failed to generate collection more');
          if (!outMore.value) break;

          tc.startSpan(hegel_label_t.HEGEL_LABEL_MAP_ENTRY.value);
          bool elementAdded = false;
          bool threw = true;
          try {
            final k = keys.generate(tc);
            if (map.containsKey(k)) {
              tc.lib.hegel_collection_reject(tc.ctx, tc.handle, collectionId, ffi.nullptr);
              threw = false;
              consecutiveRejects++;
              if (consecutiveRejects >= 1000) {
                stderr.writeln('[hegeltest] Warning: MapGenerator rejected 1000 consecutive duplicates. Is the element domain too small for minSize? Discarding test case.');
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
        tc.safeStopSpan(hadError: !success);
      }
    });
  }
}

Generator<List<T>> lists<T>(Generator<T> elements, {int minSize = 0, int maxSize = 9223372036854775807}) {
  return ListGenerator(elements, minSize, maxSize);
}

Generator<Set<T>> sets<T>(Generator<T> elements, {int minSize = 0, int maxSize = 9223372036854775807}) {
  return SetGenerator(elements, minSize, maxSize);
}

Generator<Map<K, V>> maps<K, V>(Generator<K> keys, Generator<V> values, {int minSize = 0, int maxSize = 9223372036854775807}) {
  return MapGenerator(keys, values, minSize, maxSize);
}

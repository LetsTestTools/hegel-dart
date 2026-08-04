import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class ListGenerator<T> extends Generator<List<T>> {
  final Generator<T> elements;
  final int minSize;
  final int maxSize;

  const ListGenerator(this.elements, this.minSize, this.maxSize);

  @override
  List<T> generate(TestCase tc) {
    return using((Arena arena) {
      tc.lib.hegel_start_span(tc.ctx, tc.handle, hegel_label_t.HEGEL_LABEL_LIST.value);

      try {
        final outCollectionId = arena<ffi.Int64>();
        final res = tc.lib.hegel_new_collection(tc.ctx, tc.handle, minSize, maxSize, outCollectionId);
        if (res != hegel_result_t.HEGEL_OK) throw HegelException('Failed to create list collection');
        
        final collectionId = outCollectionId.value;
        final list = <T>[];
        final outMore = arena<ffi.Bool>();
        
        while (true) {
          final moreRes = tc.lib.hegel_collection_more(tc.ctx, tc.handle, collectionId, outMore);
          if (moreRes != hegel_result_t.HEGEL_OK) throw HegelException('Failed to generate collection more');
          if (!outMore.value) break;

          tc.lib.hegel_start_span(tc.ctx, tc.handle, hegel_label_t.HEGEL_LABEL_LIST_ELEMENT.value);
          try {
            list.add(elements.generate(tc));
          } finally {
            tc.lib.hegel_stop_span(tc.ctx, tc.handle, false);
          }
        }
        return list;
      } finally {
        tc.lib.hegel_stop_span(tc.ctx, tc.handle, false);
      }
    });
  }
}

class SetGenerator<T> extends Generator<Set<T>> {
  final Generator<T> elements;
  final int minSize;
  final int maxSize;

  const SetGenerator(this.elements, this.minSize, this.maxSize);

  @override
  Set<T> generate(TestCase tc) {
    return using((Arena arena) {
      tc.lib.hegel_start_span(tc.ctx, tc.handle, hegel_label_t.HEGEL_LABEL_SET.value);

      try {
        final outCollectionId = arena<ffi.Int64>();
        final res = tc.lib.hegel_new_collection(tc.ctx, tc.handle, minSize, maxSize, outCollectionId);
        if (res != hegel_result_t.HEGEL_OK) throw HegelException('Failed to create set collection');
        
        final collectionId = outCollectionId.value;
        final set = <T>{};
        final outMore = arena<ffi.Bool>();
        
        while (true) {
          final moreRes = tc.lib.hegel_collection_more(tc.ctx, tc.handle, collectionId, outMore);
          if (moreRes != hegel_result_t.HEGEL_OK) throw HegelException('Failed to generate collection more');
          if (!outMore.value) break;

          tc.lib.hegel_start_span(tc.ctx, tc.handle, hegel_label_t.HEGEL_LABEL_SET_ELEMENT.value);
          bool elementAdded = false;
          try {
            final e = elements.generate(tc);
            if (set.contains(e)) {
              tc.lib.hegel_collection_reject(tc.ctx, tc.handle, collectionId, ffi.nullptr);
            } else {
              set.add(e);
              elementAdded = true;
            }
          } finally {
            tc.lib.hegel_stop_span(tc.ctx, tc.handle, !elementAdded);
          }
        }
        return set;
      } finally {
        tc.lib.hegel_stop_span(tc.ctx, tc.handle, false);
      }
    });
  }
}

class MapGenerator<K, V> extends Generator<Map<K, V>> {
  final Generator<K> keys;
  final Generator<V> values;
  final int minSize;
  final int maxSize;

  const MapGenerator(this.keys, this.values, this.minSize, this.maxSize);

  @override
  Map<K, V> generate(TestCase tc) {
    return using((Arena arena) {
      tc.lib.hegel_start_span(tc.ctx, tc.handle, hegel_label_t.HEGEL_LABEL_MAP.value);

      try {
        final outCollectionId = arena<ffi.Int64>();
        final res = tc.lib.hegel_new_collection(tc.ctx, tc.handle, minSize, maxSize, outCollectionId);
        if (res != hegel_result_t.HEGEL_OK) throw HegelException('Failed to create map collection');
        
        final collectionId = outCollectionId.value;
        final map = <K, V>{};
        final outMore = arena<ffi.Bool>();
        
        while (true) {
          final moreRes = tc.lib.hegel_collection_more(tc.ctx, tc.handle, collectionId, outMore);
          if (moreRes != hegel_result_t.HEGEL_OK) throw HegelException('Failed to generate collection more');
          if (!outMore.value) break;

          tc.lib.hegel_start_span(tc.ctx, tc.handle, hegel_label_t.HEGEL_LABEL_MAP_ENTRY.value);
          bool elementAdded = false;
          try {
            final k = keys.generate(tc);
            if (map.containsKey(k)) {
              tc.lib.hegel_collection_reject(tc.ctx, tc.handle, collectionId, ffi.nullptr);
            } else {
              final v = values.generate(tc);
              map[k] = v;
              elementAdded = true;
            }
          } finally {
            tc.lib.hegel_stop_span(tc.ctx, tc.handle, !elementAdded);
          }
        }
        return map;
      } finally {
        tc.lib.hegel_stop_span(tc.ctx, tc.handle, false);
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

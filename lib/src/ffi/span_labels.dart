import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'hegel_bindings.g.dart';
import 'string_helpers.dart';

/// Cached 64-bit span labels registered via `hegel_label_from_name` and
/// combined via `hegel_label_combine`.
final class SpanLabels {
  SpanLabels._();

  static const int _maxCacheSize = 4096;

  static final Map<String, int> _nameCache = {};
  static final Map<(int, int), int> _combine2Cache = {};
  static final Map<(int, int, int), int> _combine3Cache = {};
  static final Map<_LabelListKey, int> _combineListCache = {};
  static final Set<Object> _resolving = Set<Object>.identity();
  static bool _sawCycleInTraversal = false;

  /// Computes a span label for [node] while breaking cyclic generator graphs.
  ///
  /// Returns `(label, shouldCache)`: if [node] is already being resolved,
  /// returns `(cycle, false)` instead of re-entering. Otherwise runs [compute];
  /// `shouldCache` is `true` for acyclic traversals and for the root of a
  /// cyclic traversal (so intermediate nodes are not polluted by a parent's
  /// cycle break).
  static (int label, bool shouldCache) resolveGuard(
    Object node,
    int Function() compute,
  ) {
    if (!_resolving.add(node)) {
      _sawCycleInTraversal = true;
      return (cycle, false);
    }
    final isRoot = _resolving.length == 1;
    if (isRoot) {
      _sawCycleInTraversal = false;
    }
    try {
      final label = compute();
      final shouldCache = !_sawCycleInTraversal || isRoot;
      return (label, shouldCache);
    } finally {
      _resolving.remove(node);
      if (isRoot) {
        _sawCycleInTraversal = false;
      }
    }
  }

  /// Returns a deterministic 64-bit span label for [name] via `libhegel`.
  static int fromName(String name) {
    final cached = _nameCache[name];
    if (cached != null) return cached;

    final label = using((Arena arena) {
      final outLabel = arena<Uint64>();
      final res = hegel_label_from_name(
        nullptr,
        makeHegelString(arena, name),
        outLabel,
      );
      if (res != hegel_result_t.HEGEL_OK) {
        throw StateError(
          'hegel_label_from_name("$name") failed (${res.value})',
        );
      }
      return outLabel.value;
    });

    if (_nameCache.length < _maxCacheSize) {
      _nameCache[name] = label;
    }
    return label;
  }

  /// Combines two 64-bit span labels in order via `hegel_label_combine`.
  static int combine2(int a, int b) {
    final key = (a, b);
    final cached = _combine2Cache[key];
    if (cached != null) return cached;

    final combined = _combineNative(2, (ptr) {
      ptr[0] = a;
      ptr[1] = b;
    });
    if (_combine2Cache.length < _maxCacheSize) {
      _combine2Cache[key] = combined;
    }
    return combined;
  }

  /// Combines three 64-bit span labels in order via `hegel_label_combine`.
  static int combine3(int a, int b, int c) {
    final key = (a, b, c);
    final cached = _combine3Cache[key];
    if (cached != null) return cached;

    final combined = _combineNative(3, (ptr) {
      ptr[0] = a;
      ptr[1] = b;
      ptr[2] = c;
    });
    if (_combine3Cache.length < _maxCacheSize) {
      _combine3Cache[key] = combined;
    }
    return combined;
  }

  /// Combines an ordered list of 64-bit span labels via `hegel_label_combine`.
  static int combine(List<int> labels) {
    if (labels.length == 2) return combine2(labels[0], labels[1]);
    if (labels.length == 3) return combine3(labels[0], labels[1], labels[2]);

    final lookupKey = _LabelListKey(labels);
    final cached = _combineListCache[lookupKey];
    if (cached != null) return cached;

    final combined = _combineNative(
      labels.length,
      labels.isEmpty
          ? null
          : (ptr) {
              for (var i = 0; i < labels.length; i++) {
                ptr[i] = labels[i];
              }
            },
    );
    if (_combineListCache.length < _maxCacheSize) {
      _combineListCache[_LabelListKey(List<int>.of(labels, growable: false))] =
          combined;
    }
    return combined;
  }

  static int _combineNative(int len, void Function(Pointer<Uint64> ptr)? fill) {
    return using((Arena arena) {
      final ptr = len == 0 ? nullptr.cast<Uint64>() : arena<Uint64>(len);
      if (len > 0 && fill != null) {
        fill(ptr);
      }
      final outLabel = arena<Uint64>();
      final res = hegel_label_combine(nullptr, ptr, len, outLabel);
      if (res != hegel_result_t.HEGEL_OK) {
        throw StateError('hegel_label_combine(len=$len) failed (${res.value})');
      }
      return outLabel.value;
    });
  }

  // Lazy base labels (initialized on first access).
  static final int list = fromName('hegeltest.list');
  static final int listElement = fromName('hegeltest.list_element');
  static final int set = fromName('hegeltest.set');
  static final int setElement = fromName('hegeltest.set_element');
  static final int map = fromName('hegeltest.map');
  static final int mapEntry = fromName('hegeltest.map_entry');
  static final int oneOf = fromName('hegeltest.one_of');
  static final int optional = fromName('hegeltest.optional');
  static final int tuple = fromName('hegeltest.tuple');
  static final int filter = fromName('hegeltest.filter');
  static final int flatMap = fromName('hegeltest.flat_map');
  static final int composite = fromName('hegeltest.composite');

  static final int integer = fromName('hegeltest.integer');
  static final int double_ = fromName('hegeltest.double');
  static final int boolean = fromName('hegeltest.boolean');
  static final int bigInt = fromName('hegeltest.big_int');
  static final int bytes = fromName('hegeltest.bytes');
  static final int text = fromName('hegeltest.text');
  static final int regex = fromName('hegeltest.regex');
  static final int email = fromName('hegeltest.email');
  static final int url = fromName('hegeltest.url');
  static final int domain = fromName('hegeltest.domain');
  static final int uuid = fromName('hegeltest.uuid');
  static final int date = fromName('hegeltest.date');
  static final int time = fromName('hegeltest.time');
  static final int dateTime = fromName('hegeltest.date_time');
  static final int duration = fromName('hegeltest.duration');
  static final int ipv4 = fromName('hegeltest.ipv4');
  static final int ipv6 = fromName('hegeltest.ipv6');
  static final int sampled = fromName('hegeltest.sampled');
  static final int sampledWeighted = fromName('hegeltest.sampled_weighted');
  static final int frequency = fromName('hegeltest.frequency');
  static final int mapped = fromName('hegeltest.mapped');
  static final int pool = fromName('hegeltest.pool');
  static final int cycle = fromName('hegeltest.cycle');
}

final class _LabelListKey {
  final List<int> labels;
  final int _hashCode;

  _LabelListKey(this.labels) : _hashCode = Object.hashAll(labels);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _LabelListKey || other.labels.length != labels.length) {
      return false;
    }
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] != other.labels[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => _hashCode;
}

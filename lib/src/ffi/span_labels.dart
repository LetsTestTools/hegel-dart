import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'hegel_bindings.g.dart';
import 'string_helpers.dart';

/// Cached 64-bit span labels registered via `hegel_label_from_name`.
final class SpanLabels {
  SpanLabels._();

  static bool _initialized = false;
  static late final int _list;
  static late final int _listElement;
  static late final int _set;
  static late final int _setElement;
  static late final int _map;
  static late final int _mapEntry;
  static late final int _oneOf;
  static late final int _optional;
  static late final int _tuple;
  static late final int _filter;
  static late final int _flatMap;
  static late final int _composite;

  static int get list {
    _ensureInitialized();
    return _list;
  }

  static int get listElement {
    _ensureInitialized();
    return _listElement;
  }

  static int get set {
    _ensureInitialized();
    return _set;
  }

  static int get setElement {
    _ensureInitialized();
    return _setElement;
  }

  static int get map {
    _ensureInitialized();
    return _map;
  }

  static int get mapEntry {
    _ensureInitialized();
    return _mapEntry;
  }

  static int get oneOf {
    _ensureInitialized();
    return _oneOf;
  }

  static int get optional {
    _ensureInitialized();
    return _optional;
  }

  static int get tuple {
    _ensureInitialized();
    return _tuple;
  }

  static int get filter {
    _ensureInitialized();
    return _filter;
  }

  static int get flatMap {
    _ensureInitialized();
    return _flatMap;
  }

  static int get composite {
    _ensureInitialized();
    return _composite;
  }

  static void _ensureInitialized() {
    if (_initialized) return;

    final ctx = hegel_context_new();
    if (ctx == nullptr) {
      throw StateError('Failed to allocate libhegel context for span labels.');
    }

    try {
      using((Arena arena) {
        final outLabel = arena<Uint64>();
        int resolve(String name) {
          final res = hegel_label_from_name(
            ctx,
            makeHegelString(arena, name),
            outLabel,
          );
          if (res != hegel_result_t.HEGEL_OK) {
            throw StateError(
              'hegel_label_from_name("$name") failed (${res.value})',
            );
          }
          return outLabel.value;
        }

        _list = resolve('hegeltest.list');
        _listElement = resolve('hegeltest.list_element');
        _set = resolve('hegeltest.set');
        _setElement = resolve('hegeltest.set_element');
        _map = resolve('hegeltest.map');
        _mapEntry = resolve('hegeltest.map_entry');
        _oneOf = resolve('hegeltest.one_of');
        _optional = resolve('hegeltest.optional');
        _tuple = resolve('hegeltest.tuple');
        _filter = resolve('hegeltest.filter');
        _flatMap = resolve('hegeltest.flat_map');
        _composite = resolve('hegeltest.composite');
      });
      _initialized = true;
    } finally {
      hegel_context_free(ctx);
    }
  }
}

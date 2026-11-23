import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'hegel_bindings.g.dart';

/// Allocates a [hegel_string_t] backed by UTF-8 bytes in [arena].
///
/// The backing memory stays valid for the lifetime of [arena].
Pointer<hegel_string_t> allocHegelString(Arena arena, String value) {
  final strPtr = arena<hegel_string_t>();
  if (value.isEmpty) {
    strPtr.ref.data = nullptr;
    strPtr.ref.len = 0;
    return strPtr;
  }

  final bytes = utf8.encode(value);
  final buf = arena<Uint8>(bytes.length);
  buf.asTypedList(bytes.length).setAll(0, bytes);
  strPtr.ref.data = buf.cast<Char>();
  strPtr.ref.len = bytes.length;
  return strPtr;
}

/// Builds a [hegel_string_t] value backed by UTF-8 bytes in [arena].
hegel_string_t makeHegelString(Arena arena, String value) =>
    allocHegelString(arena, value).ref;

/// Returns an empty [hegel_string_t] (`{NULL, 0}`) allocated via [arena].
hegel_string_t emptyHegelString(Arena arena) {
  final strPtr = arena<hegel_string_t>();
  strPtr.ref.data = nullptr;
  strPtr.ref.len = 0;
  return strPtr.ref;
}

/// Decodes a [hegel_string_t] into a Dart [String].
String readHegelString(hegel_string_t s) {
  if (s.data == nullptr || s.len == 0) return '';
  final bytes = s.data.cast<Uint8>().asTypedList(s.len);
  return utf8.decode(bytes, allowMalformed: true);
}

/// Decodes a nullable pointer to [hegel_string_t], returning `null` if absent.
String? readHegelStringPtr(Pointer<hegel_string_t> ptr) {
  if (ptr == nullptr) return null;
  return readHegelString(ptr.ref);
}

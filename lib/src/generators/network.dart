import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:io';
import 'dart:typed_data';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class Ipv4Generator extends Generator<InternetAddress> {
  const Ipv4Generator();

  @override
  InternetAddress generate(TestCase tc) {
    return using((Arena arena) {
      final outBytes = arena<ffi.Uint8>(4);
      final result = tc.lib.hegel_generate_ipv4(tc.ctx, tc.handle, outBytes);

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate IPv4: ${result.value}');
      }

      final list = Uint8List.fromList(outBytes.asTypedList(4));
      return InternetAddress.fromRawAddress(
        list,
        type: InternetAddressType.IPv4,
      );
    });
  }
}

/// Generates IPv4 InternetAddress values.
///
/// ```dart
/// tc.draw(ipv4Addresses())
/// ```
Generator<InternetAddress> ipv4Addresses() => const Ipv4Generator();

class Ipv6Generator extends Generator<InternetAddress> {
  const Ipv6Generator();

  @override
  InternetAddress generate(TestCase tc) {
    return using((Arena arena) {
      final outBytes = arena<ffi.Uint8>(16);
      final result = tc.lib.hegel_generate_ipv6(tc.ctx, tc.handle, outBytes);

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate IPv6: ${result.value}');
      }

      final list = Uint8List.fromList(outBytes.asTypedList(16));
      return InternetAddress.fromRawAddress(
        list,
        type: InternetAddressType.IPv6,
      );
    });
  }
}

/// Generates IPv6 InternetAddress values.
///
/// ```dart
/// tc.draw(ipv6Addresses())
/// ```
Generator<InternetAddress> ipv6Addresses() => const Ipv6Generator();

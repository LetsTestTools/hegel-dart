import 'dart:io';

import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

void main() {
  group('network', () {
    group('ipv4Addresses', () {
      hegelTest('generates valid IPv4 addresses', (tc) {
        final ip = tc.draw(ipv4Addresses());
        expect(ip.type, equals(InternetAddressType.IPv4));

        final addressString = ip.address;
        final parts = addressString.split('.');
        expect(parts.length, equals(4));

        for (final part in parts) {
          final octet = int.parse(part);
          expect(octet, inInclusiveRange(0, 255));
        }
      });
    });

    group('ipv6Addresses', () {
      hegelTest('generates valid IPv6 addresses', (tc) {
        final ip = tc.draw(ipv6Addresses());
        expect(ip.type, equals(InternetAddressType.IPv6));

        final addressString = ip.address;
        expect(addressString, contains(':'));
      });
    });
  });
}

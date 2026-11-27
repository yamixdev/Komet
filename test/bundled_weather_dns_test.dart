import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komet/core/plugins/bundled_weather_dns.dart';

void main() {
  final publicAddress = InternetAddress('93.184.216.34');
  final vpnAddress = InternetAddress('198.18.0.42');

  test(
    'weather recovers a public address from a synthetic DNS answer',
    () async {
      final addresses = await BundledWeatherDns.lookup(
        'wttr.in',
        systemLookup: (_) async => [vpnAddress],
        publicLookup: () async => [publicAddress],
      );

      expect(addresses, [publicAddress]);
    },
  );

  test(
    'weather uses system DNS when it already returns a public address',
    () async {
      final addresses = await BundledWeatherDns.lookup(
        'wttr.in',
        systemLookup: (_) async => [publicAddress],
        publicLookup: () async => throw StateError('Unexpected fallback'),
      );

      expect(addresses, [publicAddress]);
    },
  );

  test(
    'other hosts and local addresses cannot use the weather fallback',
    () async {
      for (final (host, address) in [
        ('synthetic.example.invalid', vpnAddress),
        ('wttr.in', InternetAddress.loopbackIPv4),
      ]) {
        final addresses = await BundledWeatherDns.lookup(
          host,
          systemLookup: (_) async => [address],
          publicLookup: () async => throw StateError('Unexpected fallback'),
        );
        expect(addresses, [address]);
      }
    },
  );

  test('a private answer from the fallback is rejected', () async {
    await expectLater(
      BundledWeatherDns.lookup(
        'wttr.in',
        systemLookup: (_) async => [vpnAddress],
        publicLookup: () async => [InternetAddress.loopbackIPv4],
      ),
      throwsFormatException,
    );
  });
}

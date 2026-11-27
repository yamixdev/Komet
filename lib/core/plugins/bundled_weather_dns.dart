import 'dart:convert';
import 'dart:io';

import 'plugin_network_policy.dart';

abstract final class BundledWeatherDns {
  static const host = 'wttr.in';
  static const _timeout = Duration(seconds: 5);

  static Future<List<InternetAddress>> lookup(
    String hostname, {
    Future<List<InternetAddress>> Function(String)? systemLookup,
    Future<List<InternetAddress>> Function()? publicLookup,
  }) async {
    final addresses = await (systemLookup ?? InternetAddress.lookup)(hostname);
    if (hostname != host ||
        addresses.isEmpty ||
        !addresses.every(_isVpnAddress)) {
      return addresses;
    }

    final resolved = await (publicLookup ?? _resolvePublic)();
    PluginNetworkPolicy.validateAddresses(resolved);
    return resolved;
  }

  static bool _isVpnAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    return bytes.length == 4 &&
        bytes[0] == 198 &&
        (bytes[1] == 18 || bytes[1] == 19);
  }

  static Future<List<InternetAddress>> _resolvePublic() async {
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..findProxy = (_) => 'DIRECT';
    try {
      return await _queryPublicDns(client).timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<InternetAddress>> _queryPublicDns(
    HttpClient client,
  ) async {
    final uri = Uri.https('1.1.1.1', '/dns-query', {'name': host, 'type': 'A'});
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Weather DNS lookup failed', uri: uri);
    }

    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 16 * 1024) {
        throw const FormatException('Weather DNS response is too large');
      }
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map || data['Status'] != 0 || data['Answer'] is! List) {
      throw const FormatException('Invalid weather DNS response');
    }

    final addresses = <InternetAddress>[];
    for (final record in (data['Answer'] as List).whereType<Map>()) {
      if (record['type'] != 1 || record['data'] is! String) continue;
      final address = InternetAddress.tryParse(record['data'] as String);
      if (address != null && address.type == InternetAddressType.IPv4) {
        addresses.add(address);
      }
    }
    return addresses;
  }
}

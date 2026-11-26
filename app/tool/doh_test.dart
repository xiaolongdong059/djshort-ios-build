import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final crlf = String.fromCharCodes(const <int>[13, 10]);
  final sock = await Socket.connect(InternetAddress('223.5.5.5'), 443,
      timeout: const Duration(seconds: 6));
  final tls = await SecureSocket.secure(sock, host: 'dns.alidns.com');
  tls.write('GET /resolve?name=log5-applog-lf.fqnovel.com&type=A HTTP/1.1' +
      crlf + 'Host: dns.alidns.com' + crlf +
      'Accept: application/dns-json' + crlf +
      'Connection: close' + crlf + crlf);
  final b = <int>[];
  await for (final c in tls.timeout(const Duration(seconds: 8))) { b.addAll(c); }
  final t = utf8.decode(b, allowMalformed: true);
  final i = t.indexOf(crlf + crlf);
  final body = t.substring(i + 4);
  final js = jsonDecode(body) as Map;
  final ips = (js['Answer'] as List)
      .where((e) => e['type'] == 1)
      .map((e) => e['data'])
      .toList();
  print('A records: $ips');
}

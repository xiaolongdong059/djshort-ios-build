// 验证「IPv4 直连 + SNI 仍是域名」这套机制在 Dart 里成立
import 'dart:io';

Future<void> main() async {
  final ip = InternetAddress.tryParse('101.73.99.101')!;
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  c.connectionFactory = (uri, ph, pp) async {
    final s = await Socket.connect(ip, 443, timeout: const Duration(seconds: 6));
    print('connected ${ip.address} sni=${uri.host}');
    return ConnectionTask.fromSocket(Future<Socket>.value(s), () => s.destroy());
  };
  try {
    final req = await c.getUrl(Uri.parse('https://log5-applog-lf.fqnovel.com/'));
    final resp = await req.close();
    print('status=${resp.statusCode}');
    await resp.drain<void>();
  } catch (e) {
    print('ERR ${e.runtimeType}: $e');
  } finally {
    c.close(force: true);
  }
}

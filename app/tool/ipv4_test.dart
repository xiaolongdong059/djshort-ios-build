import 'package:heihei/core/hg_reg.dart';
Future<void> main() async {
  for (final h in ['log5-applog-lf.fqnovel.com', 'applog.fqnovel.com']) {
    final l = await HgReg.resolveIpv4(h);
    print('$h -> ${l.map((a) => a.address).toList()}');
    print('   lastError=${HgReg.lastError}');
  }
}

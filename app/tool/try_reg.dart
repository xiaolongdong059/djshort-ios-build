// 本地复现：直接跑 App 里那份 HgReg.register()，把失败原因打出来
import 'package:heihei/core/hg_reg.dart';

Future<void> main() async {
  final sw = Stopwatch()..start();
  final d = await HgReg.register();
  print('elapsed=${sw.elapsedMilliseconds}ms result=${d == null ? "NULL" : d.toJson()}');
}

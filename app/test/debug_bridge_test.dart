import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haitun_app/core/debug_bridge.dart';

/// 验证「HTTP 指令 → 注入指针 → 触发真实 onTap」这条链路。
///
/// 这是 2026-11-02 给 Windows 侧做 iPhone UI 自动化时的地基：
/// 手机上没法用 WDA（启动要 testmanagerd，Windows 没有），所以改成
/// App 自己开端口收指令。这条链路断了，整个自动化就没法用。
///
/// 注意必须用 `tester.runAsync`：`testWidgets` 默认是 fake async，
/// 真实 socket 的 IO 在里面永远不会完成，`await req.close()` 会直接挂死。
void main() {
  const port = 19091;

  Future<String> call(String path) async {
    // 不能用 HttpClient：`TestWidgetsFlutterBinding` 会把全局
    // `HttpOverrides` 换成 mock，任何请求都直接返回 400、不发网络。
    // 裸 socket 不受这层影响，服务端本来就是真的 HttpServer。
    final sock = await Socket.connect('127.0.0.1', port);
    sock.write('GET $path HTTP/1.1\r\n'
        'Host: 127.0.0.1\r\n'
        'Connection: close\r\n\r\n');
    final buf = <int>[];
    await sock.listen(buf.addAll).asFuture<void>();
    final text = utf8.decode(buf, allowMalformed: true);
    final i = text.indexOf('\r\n\r\n');
    return i >= 0 ? text.substring(i + 4) : text;
  }

  testWidgets('tap 指令能触发按钮 onPressed', (tester) async {
    var taps = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 80,
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('HIT'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.runAsync(() => DebugBridge.start(port: port));

    // 屏幕 800x600（测试默认），按钮居中 → 逻辑坐标 (400, 300)
    final state = await tester.runAsync(() => call('/state'));
    expect(state, contains('ok'));
    expect(state, contains('enabled=true'));

    final out = await tester.runAsync(
        () => call('/tap?unit=dp&x=400&y=300'));
    expect(out, contains('tap 400'));

    await tester.pumpAndSettle();
    expect(taps, 1, reason: '一次 tap 应该正好触发一次点击');

    // 点到空白处不应误触
    await tester.runAsync(() => call('/tap?unit=dp&x=20&y=20'));
    await tester.pumpAndSettle();
    expect(taps, 1, reason: '空白区域点击不该触发按钮');

    await tester.runAsync(() => DebugBridge.stop());
  });

  testWidgets('/text 写入输入框、/widgets 读出文字、/click_text 按文字点击',
      (tester) async {
    const p2 = 19092;
    Future<String> call2(String path) async {
      final sock = await Socket.connect('127.0.0.1', p2);
      sock.write('GET $path HTTP/1.1\r\nHost: 127.0.0.1\r\n'
          'Connection: close\r\n\r\n');
      final buf = <int>[];
      await sock.listen(buf.addAll).asFuture<void>();
      final text = utf8.decode(buf, allowMalformed: true);
      final i = text.indexOf('\r\n\r\n');
      return i >= 0 ? text.substring(i + 4) : text;
    }

    final ctrl = TextEditingController();
    var clicked = 0;
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(controller: ctrl),
            const SizedBox(height: 40),
            TextButton(
              onPressed: () => clicked++,
              child: const Text('确定按钮'),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.runAsync(() => DebugBridge.start(port: p2));

    // 没聚焦时写文字应被拒
    final noFocus = await tester.runAsync(() => call2('/text?s=abc'));
    expect(noFocus, contains('no focused input'));

    // 先点输入框聚焦，再写
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final ok = await tester.runAsync(
        () => call2('/text?s=${Uri.encodeComponent('测试文本 hello')}'));
    expect(ok, contains('text ok'));
    await tester.pumpAndSettle();
    expect(ctrl.text, '测试文本 hello');

    // /widgets 要能读到按钮文字
    final tree = await tester.runAsync(() => call2('/widgets'));
    expect(tree, contains('确定按钮'));

    // 按文字点击
    final hit = await tester.runAsync(
        () => call2('/click_text?s=${Uri.encodeComponent('确定按钮')}'));
    expect(hit, contains('click'));
    await tester.pumpAndSettle();
    expect(clicked, 1);

    await tester.runAsync(() => DebugBridge.stop());
  });
}

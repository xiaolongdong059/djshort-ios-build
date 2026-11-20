import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';

import 'api.dart';

/// 全局分享入口。
///
/// 两个硬约束：
/// 1. **文案里绝不出现河豚的域名** —— 这是 1:1 复刻，不是把对方的站搬过来；
/// 2. 分享失败（模拟器没装分享面板、系统太老）不能干瞪眼，
///    一律降级成「复制到剪贴板 + toast」，用户至少能手动粘出去。
class ShareHelper {
  const ShareHelper._();

  static const String appName = '痞帅兔';

  /// 下载落地页（CL5，2026-11-16）。
  ///
  /// 为什么不是直接分享片源链接：片源带 token / 时效，别人点了也播不了。
  /// 落地页是**固定地址**，服务端 `/dl` 按 `data/download.json` 的 mtime 缓存，
  /// 换蓝奏云链接只改那一个文件 —— 已经发出去的分享自动跟着变，不用发版。
  static String get downloadPage => '${Api.baseUrl}/dl';

  /// 分享一部片。`remark` 是「2026/完结」这类短标签，有就拼进去当补充信息。
  static Future<void> shareVod(
    BuildContext context, {
    required String name,
    String remark = '',
    String intro = '',
  }) async {
    final buf = StringBuffer('《$name》');
    if (remark.trim().isNotEmpty) buf.write(' $remark');
    buf.write('\n正在$appName 追这部，一起来看～');
    // 简介只取第一句，避免分享面板里一坨文字
    final one = intro.split(RegExp(r'[。！？\n]')).first.trim();
    if (one.isNotEmpty) {
      buf.write('\n${one.length > 60 ? '${one.substring(0, 60)}…' : one}');
    }
    // 必须带链接：原来只发纯文案，收到的人不知道去哪（龙哥 2026-11-16 反馈）。
    buf.write('\n$downloadPage');
    await _share(context, buf.toString(), subject: '《$name》-$appName');
  }

  /// 分享 App 本身（我的页「分享好友」）。
  static Future<void> shareApp(BuildContext context) async {
    await _share(
      context,
      '推荐一个看片 App：$appName —— 免费、无广告、支持弹幕和离线缓存。\n$downloadPage',
      subject: appName,
    );
  }

  static Future<void> _share(
    BuildContext context,
    String text, {
    String? subject,
  }) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    } catch (_) {
      // 兜底：复制 + 提示。Android 上分享面板缺失极少见，但模拟器上会遇到。
      try {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('分享文案已复制，粘贴给好友即可'),
              duration: Duration(milliseconds: 1800),
            ),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('分享失败'),
              duration: Duration(milliseconds: 1600),
            ),
          );
        }
      }
    }
  }
}

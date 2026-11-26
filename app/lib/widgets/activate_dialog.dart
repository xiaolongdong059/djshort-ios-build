import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/license.dart';
import '../theme/app_theme.dart';

/// 激活弹窗（2026-11-26）。
///
/// 触发条件只有一个：`License.canPlay(epIndex) == false`，也就是每部剧的
/// 第 6 集起、且本机还没激活。列表 / 详情 / 翻页都不拦 —— 用户可以先
/// 随便逛，想接着看才需要码。
///
/// 返回 true = 这一次激活成功（调用方可以继续加载这一集）。
Future<bool> showActivateDialog(
  BuildContext context, {
  String reason = '',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _ActivateDialog(reason: reason),
  );
  return ok == true;
}

class _ActivateDialog extends StatefulWidget {
  const _ActivateDialog({this.reason = ''});
  final String reason;

  @override
  State<_ActivateDialog> createState() => _ActivateDialogState();
}

class _ActivateDialogState extends State<_ActivateDialog> {
  final TextEditingController _ctl = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await License.activate(_ctl.text);
    if (!mounted) return;
    if (e == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _err = e;
    });
  }

  void _copyDevice() {
    final d = License.deviceCode;
    if (d.isEmpty) return;
    Clipboard.setData(ClipboardData(text: d));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('设备码已复制，发给客服换激活码'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dev = License.deviceCode;
    return Dialog(
      backgroundColor: const Color(0xFF1C1B1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.lock_outline, size: 20, color: Color(0xFFFFB020)),
              SizedBox(width: 8),
              Text('需要激活',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ]),
            const SizedBox(height: 10),
            Text(
              widget.reason.isNotEmpty
                  ? widget.reason
                  : '前 5 集免费试看，第 6 集起需要激活码。\n激活后本机永久可用，不需要登录账号。',
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: Color(0xFFB9B4AC)),
            ),
            const SizedBox(height: 14),
            // 设备码
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF252321),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Text('设备码',
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFF8C877F))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dev.isEmpty ? '读取中…' : dev,
                      style: const TextStyle(
                        fontSize: 15,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFD08A),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _copyDevice,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('复制', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctl,
              autofocus: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-－ ]')),
                LengthLimitingTextInputFormatter(24),
              ],
              style: const TextStyle(
                fontSize: 16,
                letterSpacing: 1.5,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'XXXX-XXXX-XXXX-XXXX',
                hintStyle: const TextStyle(
                    color: Color(0xFF605B54), letterSpacing: 1.5),
                filled: true,
                fillColor: const Color(0xFF252321),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFFF6B5E))),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('稍后',
                        style: TextStyle(color: Color(0xFF8C877F))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 42,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB020),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('激活',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

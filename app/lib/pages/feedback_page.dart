import 'package:flutter/material.dart';

import '../core/api.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/skin_background.dart';

/// 意见反馈（我的页四宫格「意见反馈」进入）。
///
/// 走 `POST /api/j/feedback` → `data/feedback.json`。
/// 和评论不同，反馈是**私密的**：不发昵称、不回列表，提交完只清空 + 提示。
/// 联系方式选填（愿意留就留，方便回访）。
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 输入框空/满要切按钮态，直接监听 controller 比 onChanged 少一层 setState 逻辑
    _text.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _text.removeListener(_onChanged);
    _text.dispose();
    _contact.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Api.post('/api/j/feedback', {
        'text': text,
        'contact': _contact.text.trim(),
        'version': '1.0.0',
      });
      if (!mounted) return;
      setState(() => _sending = false);
      _text.clear();
      _contact.clear();
      _focus.unfocus();
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('反馈已收到，感谢你的建议！'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('提交失败：$e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _text.text.trim().isNotEmpty && !_sending;
    return SkinBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const PageHeader(title: '意见反馈'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Text(
                      '遇到卡顿、播放失败、内容缺集，或者想要什么功能，都写在这里。'
                      '描述得越具体（哪部片、点了什么、看到什么），越容易定位。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: AppTheme.textSub,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _FieldCard(
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        maxLines: 6,
                        minLines: 5,
                        maxLength: 500,
                        cursorColor: AppTheme.accent,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: AppTheme.textMain,
                        ),
                        decoration: InputDecoration(
                          hintText: '说点什么吧…',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSub,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          counterStyle: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSub,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FieldCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      child: TextField(
                        controller: _contact,
                        maxLines: 1,
                        maxLength: 64,
                        cursorColor: AppTheme.accent,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMain,
                        ),
                        decoration: InputDecoration(
                          hintText: '联系方式（选填，QQ / 邮箱 / TG）',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSub,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          counterText: '',
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 44,
                      child: FilledButton(
                        onPressed: canSend ? _submit : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          // 同 error_view：chipOn 是红字前景语义，与 accent 同色，
                          // 用作按钮前景会让「发送」二字隐形。
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.chipOff,
                          disabledForegroundColor: AppTheme.textSub,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '提交反馈',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _FieldCard({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder, width: 0.5),
      ),
      child: child,
    );
  }
}

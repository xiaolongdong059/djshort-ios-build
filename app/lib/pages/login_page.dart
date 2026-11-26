import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_session.dart';

/// 登录 / 注册页（用站点账号）。
///
/// 设计取舍：
/// · **账号唯一真源在网站**：App 不建第二套用户表，登录/注册都转给
///   站点账号（用户原话「网站用户 = 后台用户」）。
/// · **注册只收 QQ 邮箱**（2026-11-02 用户定的）：输入框里只填 QQ 号，
///   后缀固定 `@qq.com`，少一次输错。
/// · **不发邮箱验证码**：省掉邮件通道，改用 IP + 设备双维度限流
///   （服务端做：同 IP 5 次/时·10 次/天，同设备 3 次/天）。
/// · **可跳过**：工信部禁止「以登录为前提限制基本功能」，所以首次启动
///   进来时右上角必须有「跳过」，字号不能藏。
/// · 登录成功后返回上一页；失败文案直接显示服务端原文（含「已绑定其他设备」
///   这类需要用户照做的信息，不能吞成「登录失败」）。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.firstRun = false, this.onDone});

  /// 首次启动引导进来：显示「跳过」，且页面停留期间会触发首屏预取。
  final bool firstRun;

  /// 作为**首屏**使用时（首页在它下面并行加载），结束后不能 pop
  /// —— 根路由 pop 会退出 App。有回调就调回调，没有就走 pop（从「我的」进来那种）。
  final VoidCallback? onDone;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _acc = TextEditingController();
  final _pwd = TextEditingController();
  final _pwd2 = TextEditingController();
  bool _busy = false;
  bool _register = false;
  String _err = '';
  bool _obscure = true;

  @override
  void dispose() {
    _acc.dispose();
    _pwd.dispose();
    _pwd2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final a = _acc.text.trim();
    final p = _pwd.text;
    if (_register) {
      if (!RegExp(r'^[0-9A-Za-z._%+-]+@[0-9A-Za-z.-]+\.[A-Za-z]{2,}$')
          .hasMatch(a)) {
        setState(() => _err = '请输入有效邮箱，例如 name@example.com');
        return;
      }
      if (p.length < 6 || p.length > 64) {
        setState(() => _err = '密码须为 6–64 位');
        return;
      }
      if (_pwd2.text != p) {
        setState(() => _err = '两次输入的密码不一致');
        return;
      }
    } else if (a.isEmpty || p.isEmpty) {
      setState(() => _err = '请输入账号和密码');
      return;
    }

    setState(() {
      _busy = true;
      _err = '';
    });
    final err = _register
        ? await AppSession.register(a, p)
        : await AppSession.login(a, p);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = err;
    });
    if (err.isEmpty) _finish(true);
  }

  void _skip() => _finish(false);

  /// 收尾：有 [onDone]（首屏模式）就交给它切换，否则 pop 回上一页。
  ///
  /// 「已引导」标记在这里写 —— 登录成功、点跳过、甚至直接杀进程都算引导过，
  /// 不能下次再弹一遍（影视 App 最招人烦的就是重复弹登录窗）。
  void _finish(bool ok) {
    final cb = widget.onDone;
    if (cb != null) {
      unawaited(SharedPreferences.getInstance()
          .then((p) => p.setBool('onboarded_v1', true))
          .catchError((Object _) => false));
      cb();
      return;
    }
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF1A1A1A),
          automaticallyImplyLeading: false,
          title: const Text('登录 / 注册',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          actions: [
            if (widget.firstRun)
              TextButton(
                onPressed: _busy ? null : _skip,
                child: const Text('跳过',
                    style: TextStyle(
                        fontSize: 15, color: Color(0xFF666666))),
              ),
            const SizedBox(width: 6),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
          children: [
            Text(_register ? '注册新账号' : '用站点账号登录',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                _register
                    ? '用常用邮箱注册，注册后即可在 App 和网站通用。'
                    : '网站与 App 共用同一个账号，会员权益自动同步。',
                style: const TextStyle(
                    fontSize: 12.5, color: Color(0xFF888888))),
            const SizedBox(height: 18),

            // 登录 / 注册 分段控件
            Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _seg('登录', !_register),
                  _seg('注册', _register),
                ],
              ),
            ),
            const SizedBox(height: 18),

            if (_register)
              _field(
                controller: _acc,
                hint: '邮箱（如 name@example.com）',
                icon: Icons.alternate_email,
                keyboard: TextInputType.emailAddress,
              )
            else
              _field(
                controller: _acc,
                // 只填 QQ 号也行：后端 `_norm_account` 会自动补 @qq.com。
                // 2026-11-02 实测，用户只填 QQ 号（如 `123456789`）会得到「密码错误」，
                // 其实是账号匹配不上，所以提示里必须把两种写法都写出来。
                hint: '完整邮箱，或只填 QQ 号',
                icon: Icons.person_outline,
                keyboard: TextInputType.emailAddress,
              ),
            const SizedBox(height: 12),
            _field(
              controller: _pwd,
              hint: _register ? '密码（6–64 位）' : '密码',
              icon: Icons.lock_outline,
              obscure: _obscure,
              suffix: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: const Color(0xFF9A9A9A)),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            if (_register) ...[
              const SizedBox(height: 12),
              _field(
                controller: _pwd2,
                hint: '再输一次密码',
                icon: Icons.lock_outline,
                obscure: _obscure,
              ),
            ],
            if (_err.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_err,
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFFE05B4B))),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_register ? '注册并登录' : '登录',
                        style: const TextStyle(fontSize: 15)),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2026-11-16：付费墙关着时不再写「可试看 5 分钟」——
                  // 现在所有人都能看完整版，写旧文案等于把免费用户劝退。
                  // 2026-11-23（龙哥 #191）：先把登录限制全停掉，统一优化完
                  // 再开账号限制 —— 登录页不描述任何「看全集要登录」的口径。
                  const Text(
                      '现在不登录也能完整观看；登录只用于收藏与观看历史同步',
                      style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
                  const SizedBox(height: 4),
                  Text(
                      AppSession.paywall
                          ? '会员：完整观看，可离线下载'
                          : '登录只用于收藏、观看历史跨设备同步',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF666666))),
                  const SizedBox(height: 4),
                  const Text('一个账号只能绑定一台设备，换机请联系管理员解绑',
                      style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
                _register
                    ? '已有账号？点上方「登录」'
                    : '忘记密码、续费会员请联系客服',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF9A9A9A))),
          ],
        ),
      ),
    );
  }

  Widget _seg(String label, bool on) {
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : () => setState(() {
          _register = label == '注册';
          _err = '';
        }),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: on
                ? const [
                    BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 4,
                        offset: Offset(0, 1))
                  ]
                : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? const Color(0xFF1A1A1A) : const Color(0xFF888888))),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9A9A9A)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9A9A9A)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF7F7F8),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

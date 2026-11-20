import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// 登录态 + 设备标识。
///
/// ## 设备绑定（2026-11-01 用户要求）
///
/// 「一个账号只能绑定一台设备」——用来防共享账号。落地方式：
/// · 首次启动生成 `deviceId`（16 字节随机 hex），存本地，永不变；
/// · 登录时连同账号一起发给后端，后端做「账号 ↔ deviceId」一对一绑定；
/// · 之后每个请求都带 `X-Device-Id`，后端可核对（换设备直接 401）；
/// · 冲突时后端回明确文案（含旧设备尾号），App 原样弹出，不做自动换绑
///   —— 自动抢占等于把限制做成摆设（A 踢 B、B 再踢 A，白嫖）。
class AppSession {
  static const _kToken = 'session.appToken';
  static const _kDevice = 'session.deviceId';
  static const _kAccount = 'session.account';
  static const _kPlan = 'session.plan';
  static const _kMember = 'session.member';
  static const _kExpires = 'session.expiresAt';

  static String deviceId = '';
  static String account = '';
  static String plan = 'free';
  static String expiresAt = '';
  static bool member = false;

  /// 服务端当前是否开着**付费墙**（2026-11-16 新增）。
  ///
  /// 龙哥拍板「先免费」：服务端 `PAYWALL=0` 时所有人可看完整版，
  /// `/api/j/user/me`、`/api/j/user/login` 返回的 `trialSeconds` 是 **0**。
  /// 客户端据此判断「非会员也不该被限制从头播 / 不许续播」。
  ///
  /// 默认 **false**：游客根本没有 `/user/me` 调用，只能靠默认值。
  /// 默认成 true 会让未登录用户一进来就被当试看用户（连续播都回 0），
  /// 与「先让用户免费用」直接冲突。将来恢复收费时服务端下发 >0 会覆盖它。
  static bool paywall = false;

  /// 我的页那一行副标题。付费墙关着 = 免费，开着 = 老口径的试看提示。
  static String get tierLine =>
      paywall ? '普通用户 · 可试看 5 分钟' : '免费使用 · 全片可用';

  static bool get loggedIn => Api.appToken.isNotEmpty;

  static final ValueNotifier<int> rev = ValueNotifier<int>(0);

  /// 登录态被服务端判定失效时 +1（token 过期 / 被别的设备顶掉 / 服务端重启丢记录）。
  ///
  /// 为什么要这个信号（2026-11-04）：原来 [refresh] 拿到 `user: null` 就直接
  /// `logout(local: true)` 静默清态，界面上什么都不说。用户刚登录完、会员权益
  /// 却突然没了，只会以为是 App 坏了 —— 实际是他手里的 token 已经在服务端失效。
  /// 现在先发信号让 UI 弹「登录已过期」，再清态。
  static final ValueNotifier<int> expired = ValueNotifier<int>(0);

  static void _bump() => rev.value++;

  /// 从服务端响应里读付费墙状态（见 [paywall]）。
  ///
  /// 以 `trialSeconds` 为准：0 = 服务端已放开（`PAYWALL=0`），>0 = 还在试看制。
  /// 缺字段时**不动**当前值，避免老服务端把状态打回默认。
  static void _readPaywall(Map<String, dynamic> m) {
    final v = m['trialSeconds'];
    if (v is num) {
      paywall = v > 0;
      return;
    }
    final b = m['paywall'];
    if (b is bool) paywall = b;
  }

  static String _randHex(int bytes) {
    final r = Random.secure();
    final b = List<int>.generate(bytes, (_) => r.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  /// App 启动时调用一次：恢复 token / deviceId（没有就生成）。
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    var dev = p.getString(_kDevice) ?? '';
    if (dev.isEmpty) {
      dev = _randHex(8);
      await p.setString(_kDevice, dev);
    }
    deviceId = dev;
    Api.deviceId = dev;
    Api.appToken = p.getString(_kToken) ?? '';
    account = p.getString(_kAccount) ?? '';
    plan = p.getString(_kPlan) ?? 'free';
    member = p.getBool(_kMember) ?? false;
    expiresAt = p.getString(_kExpires) ?? '';
    _bump();
    if (Api.appToken.isNotEmpty) {
      // 静默复核一次：网站上续费/到期，App 侧要跟着变（后端 10 分钟回源一次）
      unawaited(refresh());
    }
  }

  /// 用网站账号密码登录。成功返回空串，失败返回给用户看的文案。
  static Future<String> login(String acc, String pwd) async {
    try {
      final data = await Api.post('/api/j/user/login', {
        'account': acc,
        'password': pwd,
        'deviceId': deviceId,
      });
      return await _applyAuth(data, acc);
    } catch (e) {
      return Api.friendly(e);
    }
  }

  /// 注册（2026-11-02）：**只收 QQ 邮箱，密码 6~64 位，不发邮箱验证码**。
  ///
  /// 账号唯一真源在 xltxa.cn，后端转发过去建号，成功后直接回 token ——
  /// 不用让用户注册完再登一次。
  ///
  /// 防刷在服务端（同 IP 5 次/时·10 次/天，同设备 3 次/天），这里只做
  /// 格式预检，省一次跨境往返。
  static Future<String> register(String email, String pwd) async {
    try {
      final data = await Api.post('/api/j/user/register', {
        'email': email,
        'password': pwd,
        'deviceId': deviceId,
      });
      return await _applyAuth(data, email);
    } catch (e) {
      return Api.friendly(e);
    }
  }

  /// 登录/注册成功后落地：存 token + 账号快照。
  static Future<String> _applyAuth(Object? data, String fallbackAcc) async {
    final m = data as Map<String, dynamic>;
    Api.appToken = (m['token'] ?? '').toString();
    final u = (m['user'] as Map?)?.cast<String, dynamic>() ?? {};
    account = (u['account'] ?? fallbackAcc).toString();
    plan = (u['plan'] ?? 'free').toString();
    member = u['member'] == true;
    expiresAt = (u['expiresAt'] ?? '').toString();
    _readPaywall(m);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, Api.appToken);
    await p.setString(_kAccount, account);
    await p.setString(_kPlan, plan);
    await p.setBool(_kMember, member);
    await p.setString(_kExpires, expiresAt);
    _bump();
    return '';
  }

  /// 重置到「首次安装」状态：账号、会员快照、所有本地偏好一把清掉。
  ///
  /// 为什么要有（2026-11-04 用户要求）：设置页原来的「清理缓存」只删临时目录，
  /// 登录态、播放历史、预取片段都还在。用户清了缓存以为干净了，实际
  /// 游客期的 5 分钟片段仍在被复用，于是「清了缓存、也登录了，会员还是不生效」。
  ///
  /// 这里清的是 SharedPreferences 全量（含 token / 账号 / 会员 / 历史 / 偏好），
  /// 调用方还需要另外清文件目录（封面临时目录、prefetch），见 settings_page。
  ///
  /// 收藏**不在这里清** —— 那是用户资产，不是缓存。
  static Future<void> wipeAll() async {
    Api.appToken = '';
    account = '';
    plan = 'free';
    member = false;
    expiresAt = '';
    final p = await SharedPreferences.getInstance();
    await p.clear();
    expired.value = 0;
    _bump();
  }

  /// 拉一次 `/api/j/user/me`（会员状态以后端回源结果为准）
  static Future<void> refresh() async {
    try {
      final data = await Api.get('/api/j/user/me');
      final m = (data as Map?)?.cast<String, dynamic>() ?? {};
      final u = (m['user'] as Map?)?.cast<String, dynamic>();
      if (u == null) {
        // 先发「过期」信号（UI 弹提示），再清本地态 —— 顺序不能反：
        // 清态会触发 `rev` 重建，UI 若先看到「已退出登录」就不会再提示原因。
        expired.value++;
        await logout(local: true);
        return;
      }
      account = (u['account'] ?? account).toString();
      plan = (u['plan'] ?? plan).toString();
      member = u['member'] == true;
      expiresAt = (u['expiresAt'] ?? '').toString();
      _readPaywall(m);
      final p = await SharedPreferences.getInstance();
      await p.setString(_kAccount, account);
      await p.setString(_kPlan, plan);
      await p.setBool(_kMember, member);
      await p.setString(_kExpires, expiresAt);
      _bump();
    } catch (_) {
      // 后端连不上：保留本地状态，别把用户踢出去
    }
  }

  /// 退出登录。
  ///
  /// **顺序很关键**（2026-11-01 用户反馈「退出登录点不了」）：
  /// 原实现先 `await` 撤销接口再清本地 —— 隧道一断就要干等 30 秒超时，
  /// 期间弹窗已关但界面仍是账号名，用户以为按钮坏了，会反复点。
  ///
  /// 现在：**先本地清态 + 立刻刷新 UI**，撤销后端 token 降级成
  /// fire-and-forget（带旧 token，5 秒超时，失败无所谓 ——
  /// 本地已经退出，token 也不在 App 里了）。
  static Future<void> logout({bool local = false}) async {
    final oldToken = Api.appToken;
    Api.appToken = '';
    account = '';
    plan = 'free';
    member = false;
    expiresAt = '';
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kAccount);
    await p.remove(_kPlan);
    await p.remove(_kMember);
    await p.remove(_kExpires);
    _bump();

    if (!local && oldToken.isNotEmpty) {
      // 不 await：退出必须立刻生效，撤销只是尽力而为
      unawaited(() async {
        try {
          await Api.post('/api/j/user/logout', {},
              token: oldToken, timeoutSec: 5);
        } catch (_) {}
      }());
    }
  }

  static String get planLabel {
    switch (plan) {
      case 'lifetime':
        return '永久会员';
      case 'year':
        return '年费会员';
      case 'month':
        return '月度会员';
      case 'trial':
        return '体验会员';
      default:
        return member ? '会员' : '普通用户';
    }
  }
}

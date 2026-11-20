import 'package:flutter/widgets.dart';

/// 全局路由观察者 —— 只关心 **页面级路由**（`PageRoute`）的进出，
/// 浮层（`showModalBottomSheet` / `showDialog` 都是 `PopupRoute`）不算。
///
/// 为什么需要它（`ROADMAP.md` #32）：
/// 详情页底部「猜你喜欢」点另一部片，走的是 `Navigator.push` ——
/// 旧的详情页并没有被销毁，它仍在栈里，内嵌的 media_kit native `Player`
/// 也还在声卡上跑。实测 `dumpsys audio` 能看到两条 `usage=USAGE_MEDIA`
/// 同时 `state:started`（piid:1839 旧片 + piid:1847 新片），
/// 就是用户反馈的「切换影片后有不属于当前影片的声音」。
///
/// 有了这个观察者，被盖住的页面能在 `didPushNext()` 里把播放器停掉。
///
/// 注意泛型必须是 `PageRoute`：`RouteObserver` 内部会对 `route is R` 做过滤，
/// 取 `PageRoute` 之后，发弹幕浮层 / 简介浮层这类 `PopupRoute` 压上来时
/// **不会**触发暂停 —— 否则一打开「发个弹幕吧~」画面就停了。
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

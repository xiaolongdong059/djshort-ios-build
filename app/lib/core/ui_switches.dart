// 播放器界面的显隐开关（2026-11-25）。
//
// 为什么单独放一个文件：这两个开关同时被 `widgets/video_player_view.dart`
//（全屏播放器）和 `pages/feed_page.dart`（首页信息区）用，放在任一方都会让
// 另一边多一条跨层 import。
//
// 龙哥的原话：「去掉弹幕、及右侧的收藏、评论、点赞、分享图标」。
// 实现方式：**只关渲染，代码一行没删** —— 改回 `true` 就完整恢复。
library;

/// 右侧社交簇（收藏 / 评论 / 点赞 / 分享）。
/// 关掉范围：竖屏全屏右列 + 横屏底栏那一排。
const bool kShowPlayerSocialRail = false;

/// 弹幕相关 UI：飘字层 / 「弹」开关 / 发弹幕输入 / 弹幕设置入口 /
/// 首页「弹｜发弹幕」胶囊。
const bool kShowPlayerDanmuUi = false;

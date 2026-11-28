// 通道选择逻辑的测试（2026-11-27，B 阶段）。
//
// 为什么单测这一块：通道顺序决定「先走哪条」，选错了会白等超时。
// 这段是纯逻辑，不依赖网络和 Flutter，所以能在 PC 上跑，比"真机看日志"可靠。

import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/data/hg/hg_channel.dart';

void main() {
  group('冷却语义', () {
    test('失败一次即冷却（对齐「空响应=确定性拒绝」的历史观测）', () {
      final c = HgChannel(name: 'v5', cool: const Duration(minutes: 5));
      expect(c.cooling, false);
      c.markFail();
      expect(c.cooling, true);
      expect(c.failCount, 1);
    });

    test('成功一次立刻解除冷却并清零失败计数', () {
      final c = HgChannel(name: 'v5', cool: const Duration(minutes: 5));
      c.markFail();
      c.markFail();
      expect(c.cooling, true);
      c.markOk();
      expect(c.cooling, false);
      expect(c.failCount, 0);
      expect(c.okCount, 1);
      expect(c.lastOkAt, isNotNull);
    });
  });

  group('排序', () {
    test('全健康时保持注册顺序（v5 在最前）', () {
      final v5 = HgChannel(name: 'v5');
      final tab = HgChannel(name: 'tab');
      final legacy = HgChannel(name: 'legacy');
      final out = HgChannelPicker.order([v5, tab, legacy]);
      expect(out.map((e) => e.name).toList(), ['v5', 'tab', 'legacy']);
    });

    test('冷却中的排到最后（但不被丢弃）', () {
      final v5 = HgChannel(name: 'v5', cool: const Duration(minutes: 5));
      final tab = HgChannel(name: 'tab');
      v5.markFail();
      final out = HgChannelPicker.order([v5, tab]);
      expect(out.map((e) => e.name).toList(), ['tab', 'v5']);
      expect(out.length, 2); // 冷却不等于删除
    });

    test('最近成功的排第一（真机语义：刚才能用的路大概率还能用）', () {
      final v5 = HgChannel(name: 'v5', cool: const Duration(minutes: 5));
      final tab = HgChannel(name: 'tab');
      v5.markFail(); // v5 冷却
      tab.markOk(); // tab 成功过
      final out = HgChannelPicker.order([v5, tab]);
      expect(out.first.name, 'tab');
      expect(out.last.name, 'v5');
    });
  });

  group('firstUsable', () {
    test('有可用通道时返回第一条', () {
      final v5 = HgChannel(name: 'v5');
      expect(HgChannelPicker.firstUsable([v5])?.name, 'v5');
    });

    test('全在冷却时返回 null（调用方应立刻失败，不许硬试）', () {
      final v5 = HgChannel(name: 'v5', cool: const Duration(minutes: 5));
      final tab = HgChannel(name: 'tab', cool: const Duration(minutes: 5));
      v5.markFail();
      tab.markFail();
      expect(HgChannelPicker.firstUsable([v5, tab]), isNull);
    });

    test('空列表返回 null', () {
      expect(HgChannelPicker.firstUsable(const []), isNull);
    });
  });
}

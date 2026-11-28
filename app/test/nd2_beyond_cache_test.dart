import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/app/session/playback_session.dart';

/// `#82` ND-2 判据锁：`PlaybackSession.isBeyondCache`。
///
/// 这条判据的职责只有一个 —— 在**报错流永不静默**的前提下，仍然能认出
/// 「播放真的恢复了」。所以每个用例都要回答同一个问题：
///   同样的 `pos - errAt`，旧判据（只有 `quiet` 一条路）判成什么，
///   新判据（加物理上限）判成什么。
///
/// 物理量：`cache-secs` = 缓冲上限，断流后本地缓存最多再推这么多秒。
/// 越过它的内容只可能来自网络。数值取河豚三档 60 / 120 / 300。
void main() {
  Duration s(int sec, [int ms = 0]) =>
      Duration(seconds: sec, milliseconds: ms);

  group('cacheSecsOf：档位归一', () {
    test('三档原样返回', () {
      expect(PlaybackSession.cacheSecsOf(60), 60);
      expect(PlaybackSession.cacheSecsOf(120), 120);
      expect(PlaybackSession.cacheSecsOf(300), 300);
    });

    test('<=0 回落默认 60（对应 _applyPlayerOptions 的同一回落）', () {
      expect(PlaybackSession.cacheSecsOf(0), 60);
      expect(PlaybackSession.cacheSecsOf(-1), 60);
    });
  });

  group('isBeyondCache：真值表', () {
    // 行 1：刚报错被冻住 —— 前进 0，任何档都不越界
    test('行1 pos==errAt：不越界（60 档）', () {
      expect(PlaybackSession.isBeyondCache(s(10), s(10), 60), isFalse);
    });

    // 行 2 / 行 6：仍在物理上限内 ⇒ 保守，不越界（这一行是整个改动的安全边界）
    test('行2 前进 30s < 60 档：不越界（可能只是烧缓存）', () {
      expect(PlaybackSession.isBeyondCache(s(130), s(100), 60), isFalse);
    });

    test('行6 前进 200s < 300 档：不越界（高档缓冲下不抢跑）', () {
      expect(PlaybackSession.isBeyondCache(s(300), s(100), 300), isFalse);
    });

    // 行 5：`_n1_t6` 现场 —— 遮罩已上屏，position 仍推进 113s
    test('行5 前进 113s > 60 档：越界 ⇒ 必为真恢复', () {
      expect(PlaybackSession.isBeyondCache(s(113), s(0), 60), isTrue);
    });

    test('行5b 前进 866s（run3.log:2880 实测 errAt=2:23 → pos=16:49）', () {
      expect(PlaybackSession.isBeyondCache(s(16 * 60 + 49), s(2 * 60 + 23), 60),
          isTrue);
    });

    test('行5c 同一起点换 120 / 300 档：仍越界（113s 跨过 120？否）', () {
      // 113 < 120 ⇒ 120 档不越界；这正说明判据随档位缩放
      expect(PlaybackSession.isBeyondCache(s(113), s(0), 120), isFalse);
      expect(PlaybackSession.isBeyondCache(s(113), s(0), 300), isFalse);
      // 而 121s 在 120 档下越界
      expect(PlaybackSession.isBeyondCache(s(121), s(0), 120), isTrue);
    });
  });

  group('isBeyondCache：边界（严格大于，不是大于等于）', () {
    test('恰好等于上限 ⇒ 不越界', () {
      expect(PlaybackSession.isBeyondCache(s(60), s(0), 60), isFalse);
      expect(PlaybackSession.isBeyondCache(s(300), s(0), 300), isFalse);
    });

    test('上限 +1ms ⇒ 越界', () {
      expect(PlaybackSession.isBeyondCache(s(60, 1), s(0), 60), isTrue);
    });

    test('position 回退（重连后归零）⇒ 负数，不越界', () {
      // 实测 13:22:15.514 recover firstframe pos=0:00:00.000000 errAt=0:00:04.298500
      expect(PlaybackSession.isBeyondCache(s(0), s(4, 298), 60), isFalse);
    });
  });

  group('新旧判据对照（同一组数据）', () {
    /// 旧判据复刻：只有 quiet 一条路，且要求前进 > 1s。
    /// 这里用 `quiet=false` 模拟「ND-1 报错风暴持续刷新 _errAtWall」的真实场景。
    bool oldRule(Duration pos, Duration errAt,
            {required bool quiet, required bool buffering}) =>
        quiet && !buffering && pos > errAt + const Duration(seconds: 1);

    test('_n1_t6 现场：旧判据 false / 新判据 true', () {
      final pos = s(113), errAt = s(0);
      expect(oldRule(pos, errAt, quiet: false, buffering: false), isFalse,
          reason: '报错风暴把 quiet 打在 false ⇒ 旧判据永久失能，这就是 113s 挂死');
      expect(PlaybackSession.isBeyondCache(pos, errAt, 60), isTrue,
          reason: '越过 60s 物理上限 ⇒ 新判据放行');
    });

    test('烧缓存现场：新旧一致判 false（安全边界没被削）', () {
      final pos = s(30), errAt = s(0);
      expect(oldRule(pos, errAt, quiet: false, buffering: false), isFalse);
      expect(PlaybackSession.isBeyondCache(pos, errAt, 60), isFalse);
    });

    test('网络真恢复 + 静默满足：新旧都 true（老出口没被破坏）', () {
      final pos = s(30), errAt = s(0);
      expect(oldRule(pos, errAt, quiet: true, buffering: false), isTrue);
      // 新代码里这条仍走 `position-forward` 分支，`beyondCache` 只是并集的一项
      expect(PlaybackSession.isBeyondCache(pos, errAt, 60), isFalse);
    });
  });

  group('结构性上界：整体断网永远够不到判据（b1-c 实测反推）', () {
    // 物理账（两处同一常量）：
    //   `:478` 把 `bufferSecs` 落成 mpv 的 `cache-secs`（缓冲的物理上限）；
    //   `:707` 拿**同一个** `bufferSecs` 当判据阈值。
    // ⇒ 整体断网时 demuxer 只能把缓存烧完，position 前进量 ≤ cache-secs，
    //   而判据要求**严格大于** cache-secs ⇒ 整网断下结构性不可达。
    //   唯一能跨过的形态是「在途余量」：缓存已满但仍在收字节 ⇒ 网络部分通。
    // 这一组不是文字表述，是把 b1-c 的失败原因钉成回归项 —— 谁哪天把阈值
    // 写成 `>=` 或换了别的常量，这里立刻红。
    for (final tier in [60, 120, 300]) {
      test('$tier 档：烧满缓存（前进 == 上限）⇒ 不越界', () {
        expect(PlaybackSession.isBeyondCache(s(tier), s(0), tier), isFalse);
      });
    }

    test('唯一能跨过的形态：在途余量（上限已满仍在收字节）', () {
      // 前进 65s / 60 档：多出的 5s 只可能来自「网络还在给字节」= 部分通路。
      // b1-c 想用 wifi 开关造这个状态，实测造不出来（见 VERIFICATION §4b.3）。
      expect(PlaybackSession.isBeyondCache(s(65), s(0), 60), isTrue);
    });

    test('实测标定值：b1 断网 5s 前进 5.04s ⇒ 远在上界之内', () {
      // 逐字取自 r1b_b1_5s.log:13:34:36.961
      //   pos=0:02:08.663222 errAt=0:02:03.623222
      final pos = s(128, 663), errAt = s(123, 623);
      expect(pos - errAt, const Duration(seconds: 5, milliseconds: 40));
      expect(PlaybackSession.isBeyondCache(pos, errAt, 60), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 遮蔽回归锁（ND-2 三轮真机回归后补）
  //
  // 上一版把两条出口挂在**同一个** `_errAtPos` 上，而它在 `_onStreamError`
  // 里每条 error 都刷新（ND-1 风暴 ~10Hz）。后果：
  //   · 风暴态下 `pos - anchor ≡ 0.1s` ⇒ beyondCache **恒 false**（死代码）；
  //   · 静默态下 forward 的阈值 `+1s` 比 60s 门槛早 59 秒开火 ⇒ 抢走裁决。
  // 两条合起来 = `position-beyond-cache` 在任何可达状态下都轮不到。
  // 这一组用一个「两个基准不同」的输入把这个洞钉死：**基准一换，结论就翻**。
  // ══════════════════════════════════════════════════════════════════════════
  group('judgeByPosition：基准分家（遮蔽回归锁）', () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);

    /// 风暴态：墙钟刚被刷新过 100ms（< 5s 静默窗）⇒ quiet 恒 false。
    PositionRecovery storm({
      required Duration pos,
      required Duration lastErrPos,
      required Duration firstErrPos,
      bool buffering = false,
      int bufferSecs = 60,
    }) =>
        PlaybackSession.judgeByPosition(
          pos: pos,
          lastErrPos: lastErrPos,
          firstErrPos: firstErrPos,
          errAtWall: t0.add(const Duration(milliseconds: 100)),
          now: t0.add(const Duration(milliseconds: 200)),
          buffering: buffering,
          bufferSecs: bufferSecs,
          quietWin: const Duration(seconds: 5),
        );

    /// 静默态：最后一条 error 已过去 6s（≥ 5s 静默窗）。
    PositionRecovery quietAfter({
      required Duration pos,
      required Duration lastErrPos,
      required Duration firstErrPos,
      bool buffering = false,
      int bufferSecs = 60,
    }) =>
        PlaybackSession.judgeByPosition(
          pos: pos,
          lastErrPos: lastErrPos,
          firstErrPos: firstErrPos,
          errAtWall: t0,
          now: t0.add(const Duration(seconds: 6)),
          buffering: buffering,
          bufferSecs: bufferSecs,
          quietWin: const Duration(seconds: 5),
        );

    test('核心：风暴态 + 累计越界 ⇒ beyondCache（旧实现此处恒 none）', () {
      // 现场形态：错误从 0:00 起持续重报，position 已推到 1:53（`_n1_t6` 值）。
      // 风暴把 lastErrPos 一路刷新到 1:52.9 ⇒ 旧代码 `pos - lastErrPos = 0.1s`。
      const pos = Duration(minutes: 1, seconds: 53);
      const lastErrPos = Duration(minutes: 1, seconds: 52, milliseconds: 900);
      const firstErrPos = Duration.zero;

      expect(
        PlaybackSession.judgeByPosition(
          pos: pos,
          lastErrPos: lastErrPos,
          // 旧实现只有 `_errAtPos` 一个变量 ⇒ 两条判据共用它。
          // 把它同时喂给 firstErrPos，就是「基准被风暴推着跑」的精确复刻。
          firstErrPos: lastErrPos,
          errAtWall: t0, // quiet=false
          now: t0.add(const Duration(milliseconds: 100)),
          buffering: false,
          bufferSecs: 60,
          quietWin: const Duration(seconds: 5),
        ),
        PositionRecovery.none,
        reason: '基准跟着风暴跑 ⇒ 累计量归零 ⇒ 遮蔽。这一行就是旧行为',
      );

      expect(storm(pos: pos, lastErrPos: lastErrPos, firstErrPos: firstErrPos),
          PositionRecovery.beyondCache,
          reason: '换成 firstErrPos ⇒ 113s > 60s ⇒ 新出口接管');
    });

    test('安全边界：风暴态但仍在物理上限内 ⇒ none（不许抢跑）', () {
      expect(
        storm(
          pos: const Duration(seconds: 30),
          lastErrPos: const Duration(seconds: 29, milliseconds: 900),
          firstErrPos: Duration.zero,
        ),
        PositionRecovery.none,
        reason: '30s < 60s 档 ⇒ 可能只是烧缓存，遮罩必须留着',
      );
    });

    test('三档缩放：同一个 113s 前进量在 120/300 档下都不放行', () {
      const pos = Duration(minutes: 1, seconds: 53);
      const lastErrPos = Duration(minutes: 1, seconds: 52, milliseconds: 900);
      for (final tier in [120, 300]) {
        expect(
          storm(
              pos: pos,
              lastErrPos: lastErrPos,
              firstErrPos: Duration.zero,
              bufferSecs: tier),
          PositionRecovery.none,
          reason: '$tier 档：113 < $tier',
        );
      }
      expect(
        storm(
            pos: pos,
            lastErrPos: lastErrPos,
            firstErrPos: Duration.zero,
            bufferSecs: 60),
        PositionRecovery.beyondCache,
      );
    });

    test('静默态 + 未越界 ⇒ forward（老出口原样保留）', () {
      expect(
        quietAfter(
          pos: const Duration(seconds: 30),
          lastErrPos: Duration.zero,
          firstErrPos: Duration.zero,
        ),
        PositionRecovery.forward,
      );
    });

    test('静默态 + buffering ⇒ none（两项否决一个都没删）', () {
      expect(
        quietAfter(
          pos: const Duration(seconds: 30),
          lastErrPos: Duration.zero,
          firstErrPos: Duration.zero,
          buffering: true,
        ),
        PositionRecovery.none,
      );
    });

    test('静默态 + 只前进 1s 以内 ⇒ none（`#91` 的 1s 门槛没被削）', () {
      expect(
        quietAfter(
          pos: const Duration(seconds: 10, milliseconds: 900),
          lastErrPos: const Duration(seconds: 10),
          firstErrPos: const Duration(seconds: 10),
        ),
        PositionRecovery.none,
      );
    });

    test('越界与 forward 同时成立 ⇒ beyondCache 优先（why 串要能区分）', () {
      // `_n1_t6` 之后的真实形态：网络部分回来，静默也满足了，但累计早已过界。
      // 两条都成立时必须报 beyondCache —— 否则 trace 里看不出是谁救的。
      expect(
        quietAfter(
          pos: const Duration(minutes: 2, seconds: 40),
          lastErrPos: const Duration(minutes: 2, seconds: 39),
          firstErrPos: Duration.zero,
        ),
        PositionRecovery.beyondCache,
      );
    });

    test('errAtWall 为 null（无错误态）⇒ quiet 视为成立', () {
      expect(
        PlaybackSession.judgeByPosition(
          pos: const Duration(seconds: 30),
          lastErrPos: Duration.zero,
          firstErrPos: Duration.zero,
          errAtWall: null,
          now: t0,
          buffering: false,
          bufferSecs: 60,
          quietWin: const Duration(seconds: 5),
        ),
        PositionRecovery.forward,
      );
    });

    test('whyOf：三条裁决的 why 串与 trace 字面量一致', () {
      expect(PlaybackSession.whyOf(PositionRecovery.beyondCache),
          'position-beyond-cache');
      expect(PlaybackSession.whyOf(PositionRecovery.forward), 'position-forward');
      expect(PlaybackSession.whyOf(PositionRecovery.none), 'none');
    });
  });
}

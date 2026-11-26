// 图片解码（本机模式，2026-11-25）：HEIC/HEIF → JPEG，失败给占位图。
//
// ## 为什么必须转
//
// 片库 6275 部里 **5982 部（95.3%）的封面是 `.heic`**（实测见
// docs/PLAN-OFFLINE-EXEC.md §3.3）。Flutter 自带解码器不认 HEIF：
//   · 改扩展名 `.heic → .jpg` → 源站 403（URL 带 x-signature）
//   · 加 `&x-oss-process=image/format,jpg` 之类 → 参数被忽略，仍回 HEIC 字节
// 所以只能在客户端解。
//
// ## 用什么解
//
// `heif_converter`（MIT）→ 内部就是 `BitmapFactory.decodeFile` +
// `Bitmap.compress(JPEG)`。平台侧要求 **Android API 28+**（HEIF 解码器），
// 本机测试机 24069RA21C 是 API 36，满足。
//
// 解不出来一律返回 `null`，调用方给占位图 —— 不许抛，不许 5xx（硬约束 7）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:heif_converter/heif_converter.dart';
import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithIV;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';

import 'trace.dart';

class ImgCodec {
  ImgCodec._();

  /// 把 [srcPath] 的图（HEIC/JPG/PNG 都行）转成 JPEG 字节。失败返回 null。
  ///
  /// `heif_converter` 只吃**文件路径**，所以调用方要先把字节落盘。
  static Future<Uint8List?> toJpeg(String srcPath) async {
    // 黄果封面（2026-11-26）：URL 叫 `.jpg`，下载回来是 AES-128-CBC 密文
    // （Content-Type: binary/octet-stream）。这种字节过 heif_converter 必然
    // 失败，所以在转码之前先试一次解密。
    // 判定条件很严：**解出来必须以 JPEG/PNG 头开始**才认，避免把正常图片
    // 误当密文（正常 JPEG 的前几字节不是 16 字节对齐的密文，解出来是垃圾）。
    final plain = await _tryDecryptHg(srcPath);
    if (plain != null) return plain;

    final out = '$srcPath.jpg';
    try {
      final r = await HeifConverter.convert(srcPath, output: out, format: 'jpg');
      if (r == null || r.isEmpty) {
        trace('img.decode.null', _tail(srcPath));
        return null;
      }
      final f = File(r);
      if (!f.existsSync()) {
        trace('img.decode.nofile', _tail(srcPath));
        return null;
      }
      final bytes = await f.readAsBytes();
      if (r != out) {
        // 插件自己挑的落点（理论上不会走到，output 已显式给全路径）
        try {
          await f.delete();
        } catch (_) {}
      }
      if (bytes.isEmpty) {
        trace('img.decode.empty', _tail(srcPath));
        return null;
      }
      return bytes;
    } catch (e) {
      // 平台通道没注册（flutter test / 老系统没有 HEIF 解码器）也走这里
      trace('img.decode.err', '${_tail(srcPath)} $e');
      return null;
    }
  }

  /// 黄果封面密钥（站点固定，不是每图一个）。
  /// 来源：waitforcopilot/huangguoTV 的 CoverCipher.kt，与本项目实测一致
  /// （openssl 解出的前 8 字节 = ff d8 ff e0 00 10 4a 46，标准 JFIF）。
  static const String _hgKey = 'f5d965df75336270';
  static const String _hgIv = '97b60394abc2fbe1';

  /// 试解黄果的 CBC 密文。不是密文（或解不出图片）返回 null。
  static Future<Uint8List?> _tryDecryptHg(String srcPath) async {
    try {
      final raw = await File(srcPath).readAsBytes();
      // CBC 密文必须是 16 的整数倍；太小也不可能是图
      if (raw.length < 32 || raw.length % 16 != 0) return null;
      // 已经是真图片就不碰
      final head = _sniffKind(raw);
      if (head == 'jpeg' || head == 'png' || head == 'webp' || head == 'heic') {
        return null;
      }

      final cipher = CBCBlockCipher(AESEngine())
        ..init(
          false,
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(_hgKey))),
            Uint8List.fromList(utf8.encode(_hgIv)),
          ),
        );
      final out = Uint8List(raw.length);
      for (var off = 0; off < raw.length; off += 16) {
        cipher.processBlock(raw, off, out, off);
      }

      // 解出来必须是图片才认
      final kind = _sniffKind(out);
      if (kind != 'jpeg' && kind != 'png') {
        trace('img.aes.miss', _tail(srcPath));
        return null;
      }

      // PKCS7 padding 尾巴按 EOI/IEND 截掉
      var end = out.length;
      if (kind == 'jpeg') {
        for (var i = out.length - 2; i > 2; i--) {
          if (out[i] == 0xFF && out[i + 1] == 0xD9) {
            end = i + 2;
            break;
          }
        }
      }
      trace('img.aes.ok', '$kind ${raw.length}->$end ${_tail(srcPath)}');
      return Uint8List.sublistView(out, 0, end);
    } catch (e) {
      trace('img.aes.err', '$e');
      return null;
    }
  }

  /// 按 magic bytes 判类型。与 local_hls_server 的嗅探同一套判据。
  static String _sniffKind(List<int> b) {
    if (b.length < 12) return 'unknown';
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpeg';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'png';
    }
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'webp';
    }
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      final brand = String.fromCharCodes(b.sublist(8, 12));
      return brand.startsWith('avi') ? 'avif' : 'heic';
    }
    return 'unknown';
  }

  static String _tail(String p) =>
      p.length > 48 ? p.substring(p.length - 48) : p;

  static Uint8List? _placeholder;

  /// 占位图：12×16 深灰 PNG（竖版比例，和海报位一致，不会把布局撑歪）。
  ///
  /// 为什么不用 1×1 白色 JPEG：白色拉伸后就是一块白 —— 验收口径里
  /// 「白块」正是要数的那种。深灰一眼能看出是「缺图」而不是「加载中」。
  static Uint8List get placeholder => _placeholder ??= _makePng(12, 16, 0x33);

  /// 手写 PNG：单色，无依赖（`ZLibEncoder` 在 dart:io 里）。
  ///
  /// 只在进程内生成一次，长度约 90 字节。
  static Uint8List _makePng(int w, int h, int gray) {
    final raw = BytesBuilder();
    final row = <int>[0, ...List<int>.generate(w * 3, (i) => gray)];
    for (var y = 0; y < h; y++) {
      raw.add(row);
    }
    final idat = ZLibEncoder(level: 9).convert(raw.takeBytes());

    final png = BytesBuilder();
    png.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    void chunk(String type, List<int> data) {
      final body = BytesBuilder()
        ..add(ascii.encode(type))
        ..add(data);
      final bytes = body.takeBytes();
      png.add(_be32(data.length));
      png.add(bytes);
      png.add(_be32(_crc32(bytes)));
    }

    final ihdr = <int>[
      ..._be32(w),
      ..._be32(h),
      8, // bit depth
      2, // color type: truecolor RGB
      0, 0, 0,
    ];
    chunk('IHDR', ihdr);
    chunk('IDAT', idat);
    chunk('IEND', const <int>[]);
    return png.takeBytes();
  }

  static List<int> _be32(int v) => <int>[
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  }, growable: false);

  static int _crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

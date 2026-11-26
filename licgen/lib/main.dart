import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 激活码生成器（2026-11-26）
///
/// 与 HeiHei短剧 内的校验逻辑逐字节一致：
///   设备码 = base32( SHA256(id|pkg) 前 6B ) → 10 字符
///   激活码 = base32( devFp(4B) + days(2B 大端) + mac(4B) ) → 16 字符
///   mac    = HMAC-SHA256(secret, devFp+days) 前 4B
///
/// **这个 App 里含密钥**：只自己签名安装，不要分发、不要上架。
void main() => runApp(const LicGenApp());

const List<int> _key = <int>[
  0x4B, 0xF1, 0x4C, 0x3B, 0xD5, 0x9E, 0x22, 0xC0,
  0xDA, 0xA3, 0xE7, 0x09, 0x8A, 0xAD, 0xD0, 0xF3,
  0x06, 0xB6, 0x6C, 0xC3, 0x9D, 0x5F, 0xBF, 0x5E,
  0x7C, 0x37, 0xBE, 0x03, 0xF7, 0x63, 0xFA, 0x9E,
];
const String _alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String b32encode(List<int> b) {
  final sb = StringBuffer();
  var buf = 0;
  var bits = 0;
  for (final x in b) {
    buf = (buf << 8) | (x & 0xFF);
    bits += 8;
    while (bits >= 5) {
      sb.write(_alpha[(buf >> (bits - 5)) & 0x1F]);
      bits -= 5;
    }
  }
  if (bits > 0) sb.write(_alpha[(buf << (5 - bits)) & 0x1F]);
  return sb.toString();
}

List<int> b32decode(String s) {
  var buf = 0;
  var bits = 0;
  final out = <int>[];
  for (final c in s.toUpperCase().split('')) {
    final v = _alpha.indexOf(c);
    if (v < 0) continue;
    buf = (buf << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.add((buf >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
  }
  return out;
}

String cleanDevice(String s) =>
    s.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');

/// 生成 16 位激活码（带连字符）。设备码不对会抛 [FormatException]。
String makeCode(String device, int days) {
  final d = cleanDevice(device);
  if (d.length < 10) {
    throw const FormatException('设备码应为 10 位（A-Z、2-7）');
  }
  final raw = b32decode(d.substring(0, 10));
  if (raw.length < 4) {
    throw const FormatException('设备码解不出来，检查有没有抄错');
  }
  if (days < 0 || days > 65535) {
    throw const FormatException('天数要 0~65535（0 = 永久）');
  }
  final body = <int>[...raw.sublist(0, 4), (days >> 8) & 0xFF, days & 0xFF];
  final mac = Hmac(sha256, Uint8List.fromList(_key))
      .convert(Uint8List.fromList(body))
      .bytes
      .sublist(0, 4);
  final all = <int>[...body, ...mac];
  final s = b32encode(all);
  return '${s.substring(0, 4)}-${s.substring(4, 8)}-'
      '${s.substring(8, 12)}-${s.substring(12, 16)}';
}

class LicGenApp extends StatelessWidget {
  const LicGenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '激活码生成器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF161514),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB020),
          surface: Color(0xFF201E1C),
        ),
        useMaterial3: true,
      ),
      home: const GenPage(),
    );
  }
}

class GenPage extends StatefulWidget {
  const GenPage({super.key});

  @override
  State<GenPage> createState() => _GenPageState();
}

class _GenPageState extends State<GenPage> {
  final TextEditingController _dev = TextEditingController();
  final TextEditingController _days = TextEditingController(text: '0');
  String _out = '—';
  String _err = '';

  @override
  void dispose() {
    _dev.dispose();
    _days.dispose();
    super.dispose();
  }

  void _gen() {
    setState(() {
      _err = '';
      try {
        _out = makeCode(_dev.text, int.tryParse(_days.text.trim()) ?? 0);
        Clipboard.setData(ClipboardData(text: _out));
        _err = '已生成并复制';
      } on FormatException catch (e) {
        _out = '—';
        _err = e.message;
      } catch (e) {
        _out = '—';
        _err = '$e';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const dim = Color(0xFF9A948B);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161514),
        elevation: 0,
        centerTitle: false,
        title: const Text('激活码生成器',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text('仅供本人使用',
                  style: TextStyle(
                      fontSize: 11, color: Color(0x997E7973))),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const Text('填用户 App 里显示的设备码（10 位），生成 16 位激活码。',
              style: TextStyle(fontSize: 12.5, color: dim, height: 1.6)),
          const SizedBox(height: 22),
          const Text('设备码', style: TextStyle(fontSize: 12.5, color: dim)),
          const SizedBox(height: 6),
          TextField(
            controller: _dev,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
              LengthLimitingTextInputFormatter(14),
            ],
            style: const TextStyle(fontSize: 17, letterSpacing: 2),
            decoration: _dec('XXXXXXXXXX'),
          ),
          const SizedBox(height: 18),
          const Text('有效期天数（0 = 永久）',
              style: TextStyle(fontSize: 12.5, color: dim)),
          const SizedBox(height: 6),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            style: const TextStyle(fontSize: 17, letterSpacing: 2),
            decoration: _dec('0'),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _gen,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB020),
                      foregroundColor: const Color(0xFF201A10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('生成并复制',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () {
                      if (_out == '—') return;
                      Clipboard.setData(ClipboardData(text: _out));
                      setState(() => _err = '已复制');
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3A3530)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('复制'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF201E1C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2A26)),
            ),
            child: Text(
              _out,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: Color(0xFFFFD08A),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(_err,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: _err.startsWith('已')
                    ? const Color(0xFF7DD3A4)
                    : const Color(0xFFFF6B5E),
              )),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1B19),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '提示\n'
              '· 激活码与设备绑定，一码一机\n'
              '· 天数 0 = 永久有效\n'
              '· 此 App 内含密钥，只留给自己，别转发或上架',
              style: TextStyle(
                  fontSize: 12, height: 1.7, color: Color(0xFF7E7973)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF605B54), letterSpacing: 2),
        filled: true,
        fillColor: const Color(0xFF201E1C),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF302C28)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFB020)),
        ),
      );
}

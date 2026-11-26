/// 采集数据的文本清洗工具。
///
/// 采集站的简介/标题常带 `&nbsp;` 之类 HTML 残留，甚至**多层转义**
/// （`&amp;quot;` → 解一层得 `&quot;` → 再解一层得 `"`）。
/// 只按 `&xxx;` 一刀切成空格会把引号、破折号也吃掉，所以这里先按常见命名实体
/// **映射成真字符**，再反复解到稳定，最后去标签、压平空白。
library;

const Map<String, String> _named = {
  'nbsp': ' ',
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'middot': '·',
  'bull': '·',
};

/// 清洗简介类长文本：解实体、去 HTML 标签、压平空白。
String cleanBrief(String s) {
  var t = s;
  for (var i = 0; i < 4; i++) {
    final before = t;
    // 命名实体 → 真字符（大小写不敏感）
    t = t.replaceAllMapped(
      RegExp(r'&([a-zA-Z]+);'),
      (m) => _named[m.group(1)!.toLowerCase()] ?? m.group(1)!.toLowerCase(),
    );
    // 数字实体：&#39; / &#x27;
    t = t.replaceAllMapped(
      RegExp(r'&#(x?)([0-9a-fA-F]+);'),
      (m) {
        final code = int.tryParse(
          m.group(2)!,
          radix: m.group(1)!.isEmpty ? 10 : 16,
        );
        return code == null ? '' : String.fromCharCode(code);
      },
    );
    if (t == before) break;
  }
  return t
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

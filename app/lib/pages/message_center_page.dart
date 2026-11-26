import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_config.dart';
import '../theme/app_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/page_header.dart';
import '../widgets/skin_background.dart';

/// 消息中心（我的页 💬 与「更多 → 消息中心」都进这里）。
///
/// 数据来自后端 `/api/j/app/config` 的 `notice` 数组：
/// ```json
/// {"tgUrl": "", "siteUrl": "", "notice": [{"title": "...", "body": "...", "at": 1710000000000}]}
/// ```
/// 后端没配公告时就是空态 —— **不在客户端写死任何文案或域名**，
/// 上线前把自己的公告塞进 `data/app_config.json` 即可。
class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({super.key});

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // force: 这一页就是「看最新公告」的地方，用户点进来必须拿新的
      await AppConfig.ensureLoaded(force: true);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = Api.friendly(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SkinBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              PageHeader(
                title: '消息中心',
                actions: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: '刷新',
                      onPressed: _loading ? null : _load,
                      iconSize: 20,
                      color: AppTheme.textMain,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ],
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && AppConfig.notices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && AppConfig.notices.isEmpty) {
      return ErrorView(
        title: '消息拉取失败',
        message: _error!,
        icon: Icons.notifications_off_outlined,
        onRetry: _load,
        compact: true,
      );
    }
    if (AppConfig.notices.isEmpty) {
      return const EmptyView(
        text: '暂无消息',
        hint: '有新公告会出现在这里',
        icon: Icons.notifications_none,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: AppConfig.notices.length,
      itemBuilder: (context, i) => _NoticeTile(notice: AppConfig.notices[i]),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  final AppNotice notice;
  const _NoticeTile({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  notice.title,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
              if (notice.timeText.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  notice.timeText,
                  style: TextStyle(fontSize: 10, color: AppTheme.textSub),
                ),
              ],
            ],
          ),
          if (notice.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              notice.body,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.65,
                color: AppTheme.textSub,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

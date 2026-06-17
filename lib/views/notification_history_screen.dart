import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../models/notification_record.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends State<NotificationHistoryScreen> {

  @override
  void initState() {
    super.initState();
    // 화면 진입 시 전체 읽음 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final history = context.watch<NotificationProvider>().history;

    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 내역')
      , centerTitle: true
      , backgroundColor: primary
      , foregroundColor: Colors.white
      , elevation: 0
      , actions: [
          if (history.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context
                , builder: (ctx) => AlertDialog(
                    title: const Text('알림 내역 삭제')
                  , content: const Text('모든 알림 내역을 삭제할까요?')
                  , actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false)
                      , child: const Text('취소')
                      )
                    , FilledButton(
                        onPressed: () => Navigator.pop(ctx, true)
                      , child: const Text('삭제')
                      )
                    ]
                  )
                );
                if (ok == true && mounted) {
                  context.read<NotificationProvider>().clearHistory();
                }
              }
            , child: const Text('전체 삭제', style: TextStyle(color: Colors.white))
            )
        ]
      )
    , body: history.isEmpty
          ? _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8)
            , itemCount: history.length
            , separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16)
            , itemBuilder: (_, i) => _NotifTile(record: history[i])
            )
    );
  }
}

// ── _NotifTile ────────────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.record});

  final NotificationRecord record;

  @override
  Widget build(BuildContext context) {
    final now       = DateTime.now();
    final isPast    = record.scheduledAt.isBefore(now);
    final primary   = Theme.of(context).colorScheme.primary;
    final timeLabel = _timeLabel(record.scheduledAt, now);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
    , leading: CircleAvatar(
        radius: 20
      , backgroundColor:
            (isPast ? Colors.grey : primary).withOpacity(0.12)
      , child: Icon(
          isPast
              ? Icons.notifications_rounded
              : Icons.notifications_active_rounded
        , size: 20
        , color: isPast ? Colors.grey.shade500 : primary
        )
      )
    , title: Text(
        record.title
      , style: TextStyle(
          fontSize: 13
        , fontWeight: record.isRead ? FontWeight.w400 : FontWeight.w700
        , color: isPast ? Colors.black87 : primary
        )
      )
    , subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start
      , children: [
          const SizedBox(height: 2)
        , Text(
            record.body
          , style: TextStyle(fontSize: 12, color: Colors.grey.shade600)
          )
        , const SizedBox(height: 4)
        , Row(
            children: [
              Icon(
                isPast ? Icons.check_circle_outline : Icons.schedule_rounded
              , size: 12
              , color: Colors.grey.shade400
              )
            , const SizedBox(width: 3)
            , Text(
                isPast ? '발송됨 · $timeLabel' : '예정 · $timeLabel'
              , style: TextStyle(fontSize: 11, color: Colors.grey.shade400)
              )
            ]
          )
        ]
      )
    );
  }

  String _timeLabel(DateTime dt, DateTime now) {
    final diff = now.difference(dt);
    if (diff.isNegative) {
      // 미래
      final d = dt.difference(now);
      if (d.inDays > 0)    return '${d.inDays}일 후';
      if (d.inHours > 0)   return '${d.inHours}시간 후';
      return '곧';
    }
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours   < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }
}

// ── _EmptyState ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min
      , children: [
          Icon(Icons.notifications_off_outlined
            , size: 56, color: Colors.grey.shade300)
        , const SizedBox(height: 16)
        , Text(
            '알림 내역이 없어요'
          , style: TextStyle(
              fontSize: 15
            , color: Colors.grey.shade500
            )
          )
        , const SizedBox(height: 6)
        , Text(
            '즐겨찾기 브랜드 할인 하루 전에 알림을 드려요.'
          , style: TextStyle(fontSize: 12, color: Colors.grey.shade400)
          , textAlign: TextAlign.center
          )
        ]
      )
    );
  }
}

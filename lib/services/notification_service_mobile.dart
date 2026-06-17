import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/discount_history.dart';
import '../models/notification_record.dart';
import '../providers/notification_provider.dart';

// ── 모바일 전용 알림 구현 ─────────────────────────────────────────────────────

final _plugin       = FlutterLocalNotificationsPlugin();
bool  _initialized  = false;

Future<void> notificationInit() async {
  if (_initialized) return;
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings     = DarwinInitializationSettings(
    requestAlertPermission: false
  , requestBadgePermission: false
  , requestSoundPermission: false
  );

  await _plugin.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings)
  );
  _initialized = true;
}

Future<bool> notificationRequestPermission() async {
  final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android != null) {
    return await android.requestNotificationsPermission() ?? false;
  }
  final ios = _plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>();
  if (ios != null) {
    return await ios.requestPermissions(
      alert: true, badge: true, sound: true
    ) ?? false;
  }
  return true;
}

Future<void> notificationSchedule(
  String brandName
, List<DiscountHistory> upcomingDiscounts
, NotificationProvider? notifProvider
) async {
  if (!_initialized) await notificationInit();

  for (final d in upcomingDiscounts) {
    final notifTime = _dayBefore(d.startDate);
    if (notifTime == null) continue;

    final id      = _notifId(d.brandId, d.startDate);
    final rateStr = '${(d.discountRate * 100).toStringAsFixed(0)}%';
    final label   = d.label != null ? ' (${d.label})' : '';
    final title   = '🛍 $brandName 할인 내일 시작!';
    final body    = '$rateStr 할인$label이 내일부터 시작해요.';

    await _plugin.zonedSchedule(
      id
    , title
    , body
    , notifTime
    , NotificationDetails(
        android: AndroidNotificationDetails(
          'ping_discount'
        , '할인 알림'
        , channelDescription: '즐겨찾기 브랜드 할인 시작 전날 알림'
        , importance: Importance.high
        , priority: Priority.high
        , icon: '@mipmap/ic_launcher'
        )
      , iOS: const DarwinNotificationDetails(
          presentAlert: true
        , presentBadge: true
        , presentSound: true
        )
      )
    , androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle
    );

    // 이력 저장
    notifProvider?.addRecord(NotificationRecord(
      id:          '${d.brandId}-${d.startDate.toIso8601String().substring(0, 10)}',
      brandId:     d.brandId
    , brandName:   brandName
    , title:       title
    , body:        body
    , scheduledAt: notifTime.toLocal()
    , createdAt:   DateTime.now()
    ));
  }
}

Future<void> notificationCancel(
  String brandId
, List<DiscountHistory> discounts
) async {
  for (final d in discounts) {
    await _plugin.cancel(_notifId(brandId, d.startDate));
  }
}

Future<void> notificationCancelAll() async {
  await _plugin.cancelAll();
}

// ── 유틸 ──────────────────────────────────────────────────────────────────────

tz.TZDateTime? _dayBefore(DateTime startDate) {
  final seoul    = tz.getLocation('Asia/Seoul');
  final notifDay = startDate.subtract(const Duration(days: 1));
  final notifDt  = tz.TZDateTime(
    seoul
  , notifDay.year, notifDay.month, notifDay.day
  , 9
  );
  final now = tz.TZDateTime.now(seoul);
  if (notifDt.isBefore(now)) return null;
  return notifDt;
}

int _notifId(String brandId, DateTime startDate) {
  final key = '$brandId-${startDate.toIso8601String().substring(0, 10)}';
  return key.hashCode.abs() % 2000000000;
}

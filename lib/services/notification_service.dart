import 'package:flutter/foundation.dart';
import '../models/discount_history.dart';
import '../providers/notification_provider.dart';

// 웹에서는 flutter_local_notifications 미지원 → 조건부 import
import 'notification_service_mobile.dart'
    if (dart.library.html) 'notification_service_stub.dart';

// ── NotificationService ───────────────────────────────────────────────────────
// 웹(Chrome)에서는 모든 메서드가 no-op으로 동작

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  NotificationProvider? _notifProvider;

  void setProvider(NotificationProvider provider) {
    _notifProvider = provider;
  }

  Future<void> init() async {
    if (kIsWeb) return;
    await notificationInit();
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    return notificationRequestPermission();
  }

  Future<void> scheduleDiscountNotifications(
    String brandName
  , List<DiscountHistory> upcomingDiscounts
  ) async {
    if (kIsWeb) return;
    await notificationSchedule(brandName, upcomingDiscounts, _notifProvider);
  }

  Future<void> cancelBrandNotifications(
    String brandId
  , List<DiscountHistory> discounts
  ) async {
    if (kIsWeb) return;
    await notificationCancel(brandId, discounts);
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await notificationCancelAll();
  }
}

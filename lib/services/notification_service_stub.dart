// 웹 플랫폼용 stub — flutter_local_notifications는 웹 미지원
import '../models/discount_history.dart';
import '../providers/notification_provider.dart';

Future<void> notificationInit() async {}
Future<bool> notificationRequestPermission() async => false;
Future<void> notificationSchedule(String brandName, List<DiscountHistory> _, NotificationProvider? __) async {}
Future<void> notificationCancel(String brandId, List<DiscountHistory> _) async {}
Future<void> notificationCancelAll() async {}

import 'package:flutter/foundation.dart';
import 'notification_provider.dart';

class FavoriteProvider extends ChangeNotifier {
  FavoriteProvider({required NotificationProvider notificationProvider})
      : _notifProvider = notificationProvider;

  final NotificationProvider _notifProvider;
  final Set<String> _favoriteIds = {};

  /// 현재 즐겨찾기된 브랜드 ID 집합 (읽기 전용)
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  /// 특정 브랜드가 즐겨찾기 상태인지 확인
  bool isFavorite(String brandId) => _favoriteIds.contains(brandId);

  /// 즐겨찾기 토글 — 없으면 추가(알림 기본 on), 있으면 제거(알림 off)
  Future<void> toggleFavorite(String brandId) async {
    if (_favoriteIds.contains(brandId)) {
      _favoriteIds.remove(brandId);
      // 즐겨찾기 해제 시 알림도 끔
      await _notifProvider.setEnabled(brandId, false);
    } else {
      _favoriteIds.add(brandId);
      // 즐겨찾기 추가 시 알림 기본 on
      await _notifProvider.setEnabled(brandId, true);
    }
    notifyListeners();
  }

  /// 즐겨찾기 전체 초기화
  void clearAll() {
    _favoriteIds.clear();
    notifyListeners();
  }
}

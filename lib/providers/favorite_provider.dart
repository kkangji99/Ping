import 'package:flutter/foundation.dart';

class FavoriteProvider extends ChangeNotifier {
  final Set<String> _favoriteIds = {};

  /// 현재 즐겨찾기된 브랜드 ID 집합 (읽기 전용)
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  /// 특정 브랜드가 즐겨찾기 상태인지 확인
  bool isFavorite(String brandId) => _favoriteIds.contains(brandId);

  /// 즐겨찾기 토글 — 없으면 추가, 있으면 제거
  void toggleFavorite(String brandId) {
    if (_favoriteIds.contains(brandId)) {
      _favoriteIds.remove(brandId);
    } else {
      _favoriteIds.add(brandId);
    }
    notifyListeners();
  }

  /// 즐겨찾기 전체 초기화
  void clearAll() {
    _favoriteIds.clear();
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';
import '../models/brand.dart';
import '../models/discount_history.dart';
import '../services/supabase_service.dart';
import '../utils/discount_predictor.dart';

enum DiscountLoadState { idle, loading, loaded, error }

class DiscountProvider extends ChangeNotifier {
  DiscountProvider({required SupabaseService service}) : _service = service;

  final SupabaseService _service;

  // ── State ──────────────────────────────────────────────────────────────────

  List<Brand> _brands = [];
  List<DiscountHistory> _realHistory = [];
  List<DiscountHistory> _aiPredictions = [];
  DiscountLoadState _state = DiscountLoadState.idle;
  String? _errorMessage;
  Set<String> _loadedFavoriteIds = {};

  // 경쟁 조건 방지
  int _loadGeneration = 0;

  // ── 캐시 ──────────────────────────────────────────────────────────────────
  Map<String, String>?  _brandNameMapCache;
  Map<String, String?>? _brandUrlMapCache;
  List<DiscountHistory>? _allHistoryCache;

  void _invalidateBrandCaches() {
    _brandNameMapCache = null;
    _brandUrlMapCache  = null;
  }

  void _invalidateHistoryCache() {
    _allHistoryCache = null;
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  List<Brand> get brands => List.unmodifiable(_brands);
  DiscountLoadState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DiscountLoadState.loading;

  /// 실제 할인 + 예측 통합 목록 (캐시됨)
  List<DiscountHistory> get allHistory =>
      _allHistoryCache ??= [..._realHistory, ..._aiPredictions];

  /// brandId → brandName 룩업 맵 (캐시됨)
  Map<String, String> get brandNameMap =>
      _brandNameMapCache ??= {for (final b in _brands) b.id: b.name};

  /// brandId → crawlUrl 룩업 맵 (캐시됨)
  Map<String, String?> get brandUrlMap =>
      _brandUrlMapCache ??= {for (final b in _brands) b.id: b.crawlUrl};

  /// 특정 브랜드가 실제 이력 기준으로 지금 할인 중인지 여부.
  /// 즐겨찾기 브랜드(이력 로드됨) → bool 반환.
  /// 비즐겨찾기(이력 미로드) → null (호출자가 brand.isDiscounting 폴백).
  bool? isActivelyDiscounting(String brandId) {
    if (!_loadedFavoriteIds.contains(brandId)) return null;
    final today = todayString();
    String ds(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    return _realHistory.any((h) =>
        h.brandId == brandId &&
        ds(h.startDate).compareTo(today) <= 0 &&
        ds(h.endDate).compareTo(today) >= 0
    );
  }

  /// 특정 브랜드의 가장 이른 예측 할인 (홈 배지용)
  DiscountHistory? firstPredictionFor(String brandId) {
    DiscountHistory? result;
    for (final h in _aiPredictions) {
      if (h.brandId != brandId) continue;
      if (result == null || h.startDate.isBefore(result.startDate)) result = h;
    }
    return result;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  void onFavoritesChanged(Set<String> favoriteIds) {
    if (setEquals(_loadedFavoriteIds, favoriteIds)) return;
    _loadedFavoriteIds = Set.from(favoriteIds);
    _load(favoriteIds);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _load(Set<String> favoriteIds) async {
    final generation = ++_loadGeneration;

    _state = DiscountLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_brands.isEmpty) {
        final fetchedBrands = await _service.fetchBrands();
        if (generation != _loadGeneration) return;
        _brands = fetchedBrands;
        _invalidateBrandCaches();
      }

      if (favoriteIds.isEmpty) {
        if (generation != _loadGeneration) return;
        _realHistory = [];
        _aiPredictions = [];
        _invalidateHistoryCache();
        _state = DiscountLoadState.loaded;
        notifyListeners();
        return;
      }

      final realHistory = await _service.fetchRealHistoryForBrands(
        favoriteIds.toList()
      );
      if (generation != _loadGeneration) return;

      // 브랜드별 이력 그룹화 → 로컬 예측 생성
      final historyByBrand = <String, List<DiscountHistory>>{};
      for (final h in realHistory) {
        historyByBrand.putIfAbsent(h.brandId, () => []).add(h);
      }
      final today = todayString();
      final predictions = <DiscountHistory>[];
      for (final brandId in favoriteIds) {
        predictions.addAll(
          generateLocalPredictions(brandId, historyByBrand[brandId] ?? [], today)
        );
      }

      _realHistory   = realHistory;
      _aiPredictions = predictions;
      _invalidateHistoryCache();
      _state = DiscountLoadState.loaded;

    } catch (e, st) {
      if (generation != _loadGeneration) return;
      debugPrint('[DiscountProvider] _load failed: $e\n$st');
      _errorMessage = e.toString();
      _state = DiscountLoadState.error;
    }

    if (generation == _loadGeneration) notifyListeners();
  }
}

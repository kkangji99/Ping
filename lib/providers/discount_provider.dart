import 'package:flutter/foundation.dart';
import '../models/brand.dart';
import '../models/discount_history.dart';
import '../services/supabase_service.dart';

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

  // 경쟁 조건 방지: favorites가 빠르게 변경될 때 이전 로드 결과를 무시
  int _loadGeneration = 0;

  // brandNameMap 캐시: _brands 변경 시 null 로 초기화
  Map<String, String>? _brandNameMapCache;

  // allHistory 캐시: 데이터 변경 시 null 로 초기화
  List<DiscountHistory>? _allHistoryCache;

  // ── Getters ────────────────────────────────────────────────────────────────

  List<Brand> get brands => List.unmodifiable(_brands);
  DiscountLoadState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DiscountLoadState.loading;

  /// 실제 할인 + AI 예측 통합 목록 (캐시됨)
  List<DiscountHistory> get allHistory =>
      _allHistoryCache ??= [..._realHistory, ..._aiPredictions];

  /// brandId → brandName 룩업 맵 (캐시됨)
  Map<String, String> get brandNameMap =>
      _brandNameMapCache ??= {for (final b in _brands) b.id: b.name};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// FavoriteProvider 변경 시 ProxyProvider가 호출
  void onFavoritesChanged(Set<String> favoriteIds) {
    if (setEquals(_loadedFavoriteIds, favoriteIds)) return;
    _loadedFavoriteIds = Set.from(favoriteIds);
    _load(favoriteIds);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _load(Set<String> favoriteIds) async {
    // 현재 세대 번호를 캡처 — 비동기 완료 후 세대가 바뀌면 결과를 버림
    final generation = ++_loadGeneration;

    _state = DiscountLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // 브랜드 목록이 비어있으면 먼저 로드
      if (_brands.isEmpty) {
        final fetchedBrands = await _service.fetchBrands();
        if (generation != _loadGeneration) return; // stale
        _brands = fetchedBrands;
        _brandNameMapCache = null; // 캐시 무효화
      }

      if (favoriteIds.isEmpty) {
        if (generation != _loadGeneration) return;
        _realHistory = [];
        _aiPredictions = [];
        _allHistoryCache = null;
        _state = DiscountLoadState.loaded;
        notifyListeners();
        return;
      }

      // 실제 할인 이력 조회
      final realHistory = await _service.fetchRealHistoryForBrands(
        favoriteIds.toList()
      );
      if (generation != _loadGeneration) return; // stale

      // AI 예측: 브랜드별 병렬 호출
      final aiResults = await Future.wait(
        favoriteIds.map((id) => _service.predictNextDiscount(id))
      );
      if (generation != _loadGeneration) return; // stale

      _realHistory    = realHistory;
      _aiPredictions  = aiResults.whereType<DiscountHistory>().toList();
      _allHistoryCache = null; // 캐시 무효화
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

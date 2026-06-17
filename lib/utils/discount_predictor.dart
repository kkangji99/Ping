import '../models/discount_history.dart';

// ── 시즌 규칙 ─────────────────────────────────────────────────────────────────

const _seasonalSales = [
  (month: 0,  rate: 0.30, duration: 14)  // 1월 겨울 세일
, (month: 2,  rate: 0.15, duration: 10)  // 3월 봄 세일
, (month: 5,  rate: 0.30, duration: 14)  // 6월 여름 대세일
, (month: 6,  rate: 0.25, duration: 14)  // 7월 여름 세일
, (month: 8,  rate: 0.20, duration: 10)  // 9월 가을 세일
, (month: 10, rate: 0.40, duration: 7 )  // 11월 블랙프라이데이
, (month: 11, rate: 0.25, duration: 14)  // 12월 연말 세일
];

String _ds(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

String _addDays(String dateStr, int days) =>
    _ds(DateTime.parse(dateStr).add(Duration(days: days)));

/// 과거 이력 기반 규칙으로 향후 3개월 예측 생성
List<DiscountHistory> generateLocalPredictions(
  String brandId
, List<DiscountHistory> realHistory
, String todayStr
) {
  // 이력이 없으면 예측 불가
  if (realHistory.isEmpty) return [];

  final now     = DateTime.now();
  final results = <DiscountHistory>[];

  // 실제 이력과 날짜 겹침 여부 (겹치면 예측 불필요)
  bool overlapsReal(String sd, String ed) => realHistory.any((h) {
    final hStart = _ds(h.startDate);
    final hEnd   = _ds(h.endDate);
    // [sd,ed] ∩ [hStart,hEnd] ≠ ∅
    return ed.compareTo(hStart) >= 0 && sd.compareTo(hEnd) <= 0;
  });

  // ── Phase 1: 월별 패턴 (2회 이상 반복된 달) ──────────────────────────────
  final monthStats = <int, ({int count, double totalRate})>{};
  for (final h in realHistory) {
    final m = h.startDate.month - 1; // 0-indexed
    final s = monthStats[m];
    monthStats[m] = (
      count:     (s?.count ?? 0) + 1
    , totalRate: (s?.totalRate ?? 0.0) + h.discountRate
    );
  }

  bool foundPattern = false;
  for (int offset = 1; offset <= 3; offset++) {
    final future = DateTime(now.year, now.month + offset, 1);
    final month0 = future.month - 1; // 0-indexed
    final stats  = monthStats[month0];
    if (stats == null || stats.count < 2) continue;

    final avgRate = stats.totalRate / stats.count;
    final y  = future.year;
    final m  = future.month;
    final sd = '$y-${m.toString().padLeft(2,'0')}-01';
    final ed = _ds(DateTime(y, m + 1, 0));
    if (sd.compareTo(todayStr) > 0 && !overlapsReal(sd, ed)) {
      results.add(DiscountHistory(
        id:           'pred_${brandId}_$sd'
      , brandId:      brandId
      , startDate:    DateTime.parse(sd)
      , endDate:      DateTime.parse(ed)
      , discountRate: double.parse(avgRate.toStringAsFixed(2))
      , isAiPredicted: true
      ));
      foundPattern = true;
    }
  }

  // ── Phase 2: 시즌 규칙 폴백 ──────────────────────────────────────────────
  if (!foundPattern) {
    for (final season in _seasonalSales) {
      for (int offset = 1; offset <= 3; offset++) {
        final future = DateTime(now.year, now.month + offset, 1);
        if (future.month - 1 == season.month) {
          final y  = future.year;
          final m  = future.month;
          final sd = '$y-${m.toString().padLeft(2,'0')}-01';
          final ed = _addDays(sd, season.duration);
          if (sd.compareTo(todayStr) > 0 && !overlapsReal(sd, ed)) {
            results.add(DiscountHistory(
              id:           'seasonal_${brandId}_$sd'
            , brandId:      brandId
            , startDate:    DateTime.parse(sd)
            , endDate:      DateTime.parse(ed)
            , discountRate: season.rate
            , isAiPredicted: true
            ));
          }
        }
      }
    }
  }

  results.sort((a, b) => a.startDate.compareTo(b.startDate));
  return results.take(2).toList();
}

String todayString() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
}

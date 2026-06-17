import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/brand.dart';
import '../models/discount_history.dart';
import '../services/supabase_service.dart';
import '../providers/favorite_provider.dart';

import '../utils/discount_predictor.dart';

class BrandDetailScreen extends StatefulWidget {
  const BrandDetailScreen({super.key, required this.brand});

  final Brand brand;

  @override
  State<BrandDetailScreen> createState() => _BrandDetailScreenState();
}

class _BrandDetailScreenState extends State<BrandDetailScreen> {
  late Future<List<DiscountHistory>> _future;

  @override
  void initState() {
    super.initState();
    _future = context
        .read<SupabaseService>()
        .fetchDiscountsForBrand(widget.brand.id);
  }

  Future<void> _refresh() {
    setState(() {
      _future = context
          .read<SupabaseService>()
          .fetchDiscountsForBrand(widget.brand.id);
    });
    return _future;
  }

  @override
  Widget build(BuildContext context) {
    final primary    = Theme.of(context).colorScheme.primary;
    final isFavorite = context.select<FavoriteProvider, bool>(
        (p) => p.isFavorite(widget.brand.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.brand.name)
      , centerTitle: true
      , backgroundColor: Theme.of(context).colorScheme.primary
      , foregroundColor: Colors.white
      , elevation: 0
      , actions: [
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded
            , color: Colors.white
            )
          , onPressed: () =>
                context.read<FavoriteProvider>().toggleFavorite(widget.brand.id)
          )
        ]
      )
    , body: FutureBuilder<List<DiscountHistory>>(
        future: _future
      , builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min
              , children: [
                  Icon(Icons.error_outline, color: Colors.grey.shade400, size: 48)
                , const SizedBox(height: 12)
                , Text(
                    '데이터를 불러오지 못했어요'
                  , style: TextStyle(color: Colors.grey.shade600)
                  )
                , const SizedBox(height: 12)
                , FilledButton.tonal(
                    onPressed: _refresh
                  , child: const Text('다시 시도')
                  )
                ]
              )
            );
          }

          final all      = snap.data ?? [];
          final todayStr = todayString();

          String ds(DateTime d) =>
              '${d.year}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';

          // 지금 할인 중: 실제, start <= today <= end
          final active = all.where((h) =>
              !h.isAiPredicted &&
              ds(h.startDate).compareTo(todayStr) <= 0 &&
              ds(h.endDate).compareTo(todayStr) >= 0
          ).toList();

          // 과거 + 현재 실제 이력 합산 → 패턴 분석 재료
          final allReal = all.where((h) => !h.isAiPredicted).toList();

          // 예측: DB에 있으면 그걸 쓰고, 없으면 로컬 계산
          final dbPredictions = all.where((h) => h.isAiPredicted).toList()
            ..sort((a, b) => a.startDate.compareTo(b.startDate));
          final predictions = dbPredictions.isNotEmpty
              ? dbPredictions
              : generateLocalPredictions(widget.brand.id, allReal, todayStr);

          // 과거 이력: 실제, end < today, 그리고 active 목록과 ID가 겹치지 않는 것만
          final activeIds = active.map((h) => h.id).toSet();
          final pastReal  = all.where((h) =>
              !h.isAiPredicted &&
              !activeIds.contains(h.id) &&
              ds(h.endDate).compareTo(todayStr) < 0
          ).toList();

          return RefreshIndicator(
            onRefresh: _refresh
          , child: CustomScrollView(
              slivers: [
                // ── 브랜드 헤더 ──────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _BrandHeader(
                    brand: widget.brand
                  , primary: primary
                  , isActive: active.isNotEmpty
                  )
                )

              , // ── 현재 할인 중 ─────────────────────────────────────────────
                if (active.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.local_offer_rounded
                  , label: '지금 할인 중'
                  , color: Colors.redAccent
                  )
                , SliverList.builder(
                    itemCount: active.length
                  , itemBuilder: (_, i) => _DiscountCard(
                        history: active[i]
                      , color: Colors.redAccent
                      , showType: false
                      )
                  )
                ]

              , // ── 예측 기간 ─────────────────────────────────────────────────
                _SectionHeader(
                  icon: Icons.event_note_rounded
                , label: '예측 할인 기간'
                , color: primary
                )
              , if (predictions.isNotEmpty)
                  SliverList.builder(
                    itemCount: predictions.length
                  , itemBuilder: (_, i) => _DiscountCard(
                        history: predictions[i]
                      , color: primary
                      , showType: false
                      )
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                    , child: Text(
                        '예측 데이터가 없어요.'
                      , style: TextStyle(fontSize: 12, color: Colors.grey.shade500)
                      )
                    )
                  )

              , // ── 과거 할인 이력 ─────────────────────────────────────────────
                if (pastReal.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.history_rounded
                  , label: '과거 할인 이력'
                  , color: Colors.grey.shade600
                  )
                , SliverList.builder(
                    itemCount: pastReal.length
                  , itemBuilder: (_, i) => _DiscountCard(
                        history: pastReal[i]
                      , color: Colors.grey.shade500
                      , showType: false
                      )
                  )
                ]

              , // ── 데이터 없음 ─────────────────────────────────────────────
                if (active.isEmpty && predictions.isEmpty && pastReal.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min
                      , children: [
                          Icon(Icons.event_busy_rounded
                            , size: 56
                            , color: Colors.grey.shade300
                            )
                        , const SizedBox(height: 16)
                        , Text(
                            '할인 정보가 없어요'
                          , style: TextStyle(
                              color: Colors.grey.shade500
                            , fontSize: 15
                            )
                          )
                        , const SizedBox(height: 6)
                        , Text(
                            '크롤링 후 자동으로 업데이트됩니다.'
                          , style: TextStyle(
                              color: Colors.grey.shade400
                            , fontSize: 12
                            )
                          )
                        ]
                      )
                    )
                  )

              , const SliverToBoxAdapter(child: SizedBox(height: 32))
              ]
            )
          );
        }
      )
    );
  }
}

// ── _BrandHeader ──────────────────────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.brand
  , required this.primary
  , required this.isActive
  });

  final Brand  brand;
  final Color  primary;
  final bool   isActive;

  Future<void> _openSite() async {
    final raw = brand.crawlUrl;
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = brand.crawlUrl != null && brand.crawlUrl!.isNotEmpty;

    return Container(
      color: primary.withOpacity(0.04)
    , padding: const EdgeInsets.fromLTRB(20, 20, 20, 16)
    , child: Column(
        crossAxisAlignment: CrossAxisAlignment.start
      , children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32
              , backgroundColor: primary.withOpacity(0.12)
              , child: brand.logoUrl != null
                    ? ClipOval(
                        child: Image.network(
                          brand.logoUrl!
                        , width: 64, height: 64
                        , fit: BoxFit.cover
                        , errorBuilder: (_, __, ___) => _initial(primary)
                        )
                      )
                    : _initial(primary)
              )
            , const SizedBox(width: 16)
            , Column(
                crossAxisAlignment: CrossAxisAlignment.start
              , children: [
                  Text(
                    brand.name
                  , style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)
                  )
                , const SizedBox(height: 4)
                , if (isActive)
                    _Badge(label: '현재 할인 중', color: Colors.redAccent)
                  else
                    _Badge(label: '할인 없음', color: Colors.grey.shade400)
                ]
              )
            ]
          )
        , const SizedBox(height: 14)
        , SizedBox(
            width: double.infinity
          , child: OutlinedButton.icon(
              onPressed: hasUrl ? _openSite : null
            , icon: const Icon(Icons.open_in_new_rounded, size: 16)
            , label: const Text('사이트 방문하기')
            , style: OutlinedButton.styleFrom(
                foregroundColor: primary
              , side: BorderSide(color: primary.withOpacity(0.4))
              , shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)
                )
              )
            )
          )
        ]
      )
    );
  }

  Widget _initial(Color color) => Text(
    brand.name.isNotEmpty ? brand.name[0].toUpperCase() : '?'
  , style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
    , decoration: BoxDecoration(
        color: color.withOpacity(0.12)
      , borderRadius: BorderRadius.circular(6)
      )
    , child: Text(
        label
      , style: TextStyle(
          fontSize: 11
        , fontWeight: FontWeight.w700
        , color: color
        )
      )
    );
  }
}

// ── _SectionHeader ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon
  , required this.label
  , required this.color
  });

  final IconData icon;
  final String   label;
  final Color    color;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6)
      , child: Row(
          children: [
            Icon(icon, size: 16, color: color)
          , const SizedBox(width: 6)
          , Text(
              label
            , style: TextStyle(
                fontSize: 13
              , fontWeight: FontWeight.w700
              , color: color
              )
            )
          ]
        )
      )
    );
  }
}

// ── _DiscountCard ─────────────────────────────────────────────────────────────

class _DiscountCard extends StatelessWidget {
  const _DiscountCard({
    required this.history
  , required this.color
  , required this.showType
  });

  final DiscountHistory history;
  final Color           color;
  final bool            showType;

  String _fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final rateStr = '${(history.discountRate * 100).toStringAsFixed(0)}% 할인';
    final period  = '${_fmt(history.startDate)} ~ ${_fmt(history.endDate)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
    , child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
      , decoration: BoxDecoration(
          color: color.withOpacity(0.06)
        , borderRadius: BorderRadius.circular(12)
        , border: Border.all(color: color.withOpacity(0.18))
        )
      , child: Row(
          children: [
            Container(
              width: 4
            , height: 44
            , decoration: BoxDecoration(
                color: color
              , borderRadius: BorderRadius.circular(4)
              )
            )
          , const SizedBox(width: 14)
          , Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start
              , children: [
                  Text(
                    rateStr
                  , style: TextStyle(
                      fontSize: 15
                    , fontWeight: FontWeight.w700
                    , color: color
                    )
                  )
                , const SizedBox(height: 3)
                , Text(
                    period
                  , style: TextStyle(
                      fontSize: 12
                    , color: Colors.grey.shade600
                    )
                  )
                ]
              )
            )
          ]
        )
      )
    );
  }
}

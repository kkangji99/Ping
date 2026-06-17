import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/brand.dart';
import '../models/discount_history.dart';
import '../providers/favorite_provider.dart';
import '../providers/discount_provider.dart';
import 'brand_detail_screen.dart';

// ── CalendarEvent (내부 ViewModel) ───────────────────────────────────────────

class _CalendarEvent {
  final String brandId;
  final String brandName;
  final double discountRate;
  final bool   isAiPredicted;

  const _CalendarEvent({
    required this.brandId
  , required this.brandName
  , required this.discountRate
  , required this.isAiPredicted
  });
}

// ── CalendarScreen ────────────────────────────────────────────────────────────

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime  _focusedDay  = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  bool _showAiPrediction = true;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // ── Event Map 캐시 ────────────────────────────────────────────────────────
  Map<DateTime, List<_CalendarEvent>>? _cachedEventMap;
  List<DiscountHistory>? _lastHistory;
  Map<String, String>?   _lastBrandNames;
  bool? _lastShowAi;

  static final _headerFmt = DateFormat('M월 d일 (E)', 'ko_KR');

  static const _aiColor   = Color(0xFF7C4DFF);
  static const _realColor = Colors.redAccent;

  // ── Event Map ──────────────────────────────────────────────────────────────

  Map<DateTime, List<_CalendarEvent>> _getEventMap({
    required List<DiscountHistory> history
  , required Map<String, String>  brandNames
  , required bool showAi
  }) {
    // 입력이 동일하면 캐시 반환 (identity 비교)
    if (_cachedEventMap != null &&
        identical(_lastHistory, history) &&
        identical(_lastBrandNames, brandNames) &&
        _lastShowAi == showAi) {
      return _cachedEventMap!;
    }

    final Map<DateTime, List<_CalendarEvent>> map = {};
    for (final h in history) {
      if (h.isAiPredicted && !showAi) continue;
      final name = brandNames[h.brandId] ?? h.brandId;
      DateTime cursor = _toUtcDate(h.startDate);
      final end       = _toUtcDate(h.endDate);
      while (!cursor.isAfter(end)) {
        map.putIfAbsent(cursor, () => []).add(
          _CalendarEvent(
            brandId:      h.brandId
          , brandName:    name
          , discountRate: h.discountRate
          , isAiPredicted: h.isAiPredicted
          )
        );
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    _cachedEventMap = map;
    _lastHistory    = history;
    _lastBrandNames = brandNames;
    _lastShowAi     = showAi;
    return map;
  }

  DateTime _toUtcDate(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

  List<_CalendarEvent> _eventsForDay(
    DateTime day
  , Map<DateTime, List<_CalendarEvent>> map
  ) => map[_toUtcDate(day)] ?? [];

  // ── 셀 빌더 ───────────────────────────────────────────────────────────────
  // markerBuilder overlay 방식 대신, 셀 전체를 Column으로 직접 그립니다.
  // → 날짜 원(circle)과 인디케이터(bar)가 Column으로 쌓여 절대 겹치지 않음.

  Widget _buildCell(
    BuildContext context
  , DateTime day
  , Map<DateTime, List<_CalendarEvent>> eventMap
  , Color primary
  , { bool isToday    = false
    , bool isSelected = false
    , bool isOutside  = false
    }
  ) {
    final events  = _eventsForDay(day, eventMap);
    final hasReal = events.any((e) => !e.isAiPredicted);
    final hasAi   = _showAiPrediction && events.any((e) => e.isAiPredicted);
    final isWeekend = day.weekday == DateTime.saturday
                   || day.weekday == DateTime.sunday;

    // 텍스트 색
    Color textColor;
    if      (isSelected) textColor = Colors.white;
    else if (isOutside)  textColor = Colors.grey.shade300;
    else if (isWeekend)  textColor = _realColor;
    else                 textColor = Colors.black87;

    // 원 장식
    BoxDecoration? deco;
    if      (isSelected) deco = BoxDecoration(color: primary, shape: BoxShape.circle);
    else if (isToday)    deco = BoxDecoration(color: primary.withOpacity(0.25), shape: BoxShape.circle);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center
    , children: [
        // 날짜 원
        Container(
          width: 34, height: 34
        , decoration: deco
        , alignment: Alignment.center
        , child: Text(
            '${day.day}'
          , style: TextStyle(
              fontSize: 13
            , fontWeight: (isSelected || isToday) ? FontWeight.w700 : FontWeight.w400
            , color: textColor
            )
          )
        )

      , const SizedBox(height: 3)

      // 인디케이터 영역 (고정 5px — 이벤트 없는 날도 공간 확보해 정렬 통일)
      , SizedBox(
          height: 5
        , child: Row(
            mainAxisSize: MainAxisSize.min
          , children: [
              if (hasReal) _bar(_realColor)
            , if (hasReal && hasAi) const SizedBox(width: 2)
            , if (hasAi)  _bar(_aiColor)
            ]
          )
        )
      ]
    );
  }

  // 얇은 pill 형태 인디케이터 (원보다 세련된 느낌)
  Widget _bar(Color color) => Container(
    width: 14, height: 4
  , decoration: BoxDecoration(
      color: color
    , borderRadius: BorderRadius.circular(2)
    )
  );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary        = Theme.of(context).colorScheme.primary;
    final favoriteIds    = context.watch<FavoriteProvider>().favoriteIds;
    final discountProv   = context.watch<DiscountProvider>();
    final brandNames     = discountProv.brandNameMap;
    final eventMap       = _getEventMap(
      history:    discountProv.allHistory
    , brandNames: brandNames
    , showAi:     _showAiPrediction
    );
    final selectedEvents = _selectedDay != null
        ? _eventsForDay(_selectedDay!, eventMap)
        : <_CalendarEvent>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('할인 캘린더')
      , centerTitle: true
      , backgroundColor: primary
      , foregroundColor: Colors.white
      , elevation: 0
      , actions: [
          TextButton(
            onPressed: () => setState(() {
              final today = DateTime.now();
              _focusedDay  = today;
              _selectedDay = today;
            })
          , child: const Text(
              'Today'
            , style: TextStyle(
                color: Colors.white
              , fontWeight: FontWeight.w700
              , fontSize: 13
              )
            )
          )
        ]
      )
    , body: Column(
        children: [

          // ── 예측 기간 토글 ────────────────────────────────────────────────
          _AiToggleBar(
            value: _showAiPrediction
          , onChanged: (v) => setState(() => _showAiPrediction = v)
          )
        , const Divider(height: 1)

        // ── 로딩 / 에러 배너 ──────────────────────────────────────────────────
        , if (discountProv.isLoading)
            LinearProgressIndicator(
              color: primary
            , backgroundColor: primary.withOpacity(0.1)
            )
        , if (discountProv.state == DiscountLoadState.error)
            _ErrorBanner(message: discountProv.errorMessage ?? '오류 발생')

        // ── 캘린더 ────────────────────────────────────────────────────────────
        , TableCalendar<_CalendarEvent>(
            locale: 'ko_KR'
          , firstDay: DateTime(2025, 1, 1)
          , lastDay: DateTime(2027, 12, 31)
          , focusedDay: _focusedDay
          , calendarFormat: _calendarFormat
          , onFormatChanged: (fmt) => setState(() => _calendarFormat = fmt)
          , selectedDayPredicate: (day) => isSameDay(_selectedDay, day)
          , eventLoader: (day) => _eventsForDay(day, eventMap)
          , onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay  = focused;
              });
            }
          , onPageChanged: (focused) => setState(() => _focusedDay = focused)

          // rowHeight = circle(34) + gap(3) + bar(5) + 상하여백 = 56이면 여유 있음
          , rowHeight: 56
          , daysOfWeekHeight: 30

          , headerStyle: HeaderStyle(
              formatButtonDecoration: BoxDecoration(
                border: Border.all(color: primary.withOpacity(0.3))
              , borderRadius: BorderRadius.circular(8)
              )
            , formatButtonTextStyle: TextStyle(fontSize: 12, color: primary)
            , titleTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)
            , leftChevronMargin:  EdgeInsets.zero
            , rightChevronMargin: EdgeInsets.zero
            )

          , calendarStyle: const CalendarStyle(
              // 모든 기본 장식·마커 비활성 — 커스텀 빌더가 전담
              markersMaxCount: 0
            , outsideDaysVisible: false  // 인접 월 날짜 숨김 (깔끔)
            )

          , calendarBuilders: CalendarBuilders<_CalendarEvent>(
              // 마커 오버레이 완전 비활성
              markerBuilder: (_, __, ___) => const SizedBox.shrink()

              // 모든 셀 타입을 동일한 Column 레이아웃으로 그림
            , defaultBuilder:  (ctx, day, _) =>
                  _buildCell(ctx, day, eventMap, primary)
            , todayBuilder:    (ctx, day, _) =>
                  _buildCell(ctx, day, eventMap, primary, isToday: true)
            , selectedBuilder: (ctx, day, _) =>
                  _buildCell(ctx, day, eventMap, primary, isSelected: true)
            , disabledBuilder: (ctx, day, _) =>
                  _buildCell(ctx, day, eventMap, primary, isOutside: true)
            )
          )

        , const SizedBox(height: 4)
        , const Divider(height: 1, thickness: 1)
        , _LegendBar(showAi: _showAiPrediction)
        , const Divider(height: 1, thickness: 1)

        // ── 선택 날 이벤트 목록 ────────────────────────────────────────────────
        , Expanded(
            child: _EventList(
              events: selectedEvents
            , selectedDay: _selectedDay
            , favoriteIds: favoriteIds
            , isLoading: discountProv.isLoading
            , headerFmt: _headerFmt
            , brandMap: { for (final b in discountProv.brands) b.id: b }
            )
          )
        ]
      )
    );
  }
}

// ── _AiToggleBar ──────────────────────────────────────────────────────────────

class _AiToggleBar extends StatelessWidget {
  const _AiToggleBar({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  static const _aiColor = Color(0xFF7C4DFF);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
    , child: Row(
        children: [
          Container(
            width: 14, height: 4
          , margin: const EdgeInsets.only(right: 8)
          , decoration: BoxDecoration(
              color: _aiColor
            , borderRadius: BorderRadius.circular(2)
            )
          )
        , const Text('예측 기간 보기', style: TextStyle(fontSize: 13))
        , const Spacer()
        , Switch.adaptive(
            value: value
          , onChanged: onChanged
          , activeColor: _aiColor
          )
        ]
      )
    );
  }
}

// ── _LegendBar ────────────────────────────────────────────────────────────────

class _LegendBar extends StatelessWidget {
  const _LegendBar({required this.showAi});
  final bool showAi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7)
    , child: Row(
        children: [
          _item(color: Colors.redAccent,        label: '실제 할인')
        , const SizedBox(width: 16)
        , if (showAi)
            _item(color: const Color(0xFF7C4DFF), label: '예측')
        ]
      )
    );
  }

  Widget _item({required Color color, required String label}) => Row(
    mainAxisSize: MainAxisSize.min
  , children: [
      Container(
        width: 14, height: 4
      , decoration: BoxDecoration(
          color: color
        , borderRadius: BorderRadius.circular(2)
        )
      )
    , const SizedBox(width: 6)
    , Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey))
    ]
  );
}

// ── _ErrorBanner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity
    , color: Colors.red.shade50
    , padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
    , child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16)
        , const SizedBox(width: 8)
        , Expanded(
            child: Text(
              message
            , style: const TextStyle(color: Colors.redAccent, fontSize: 12)
            , overflow: TextOverflow.ellipsis
            )
          )
        ]
      )
    );
  }
}

// ── _EventList ────────────────────────────────────────────────────────────────

class _EventList extends StatelessWidget {
  const _EventList({
    required this.events
  , required this.selectedDay
  , required this.favoriteIds
  , required this.isLoading
  , required this.headerFmt
  , required this.brandMap
  });

  final List<_CalendarEvent> events;
  final DateTime?      selectedDay;
  final Set<String>    favoriteIds;
  final bool           isLoading;
  final DateFormat     headerFmt;
  final Map<String, Brand> brandMap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (favoriteIds.isEmpty) {
      return _emptyState(
        context
      , icon: Icons.favorite_border_rounded
      , message: '홈에서 브랜드를 즐겨찾기(♥)하면\n할인 일정이 표시됩니다.'
      );
    }
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (selectedDay == null) {
      return _emptyState(
        context
      , icon: Icons.touch_app_outlined
      , message: '날짜를 선택하면 할인 정보를 볼 수 있어요.'
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start
    , children: [
        // ── 날짜 헤더 ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4)
        , child: Row(
            children: [
              Text(
                headerFmt.format(selectedDay!)
              , style: TextStyle(
                    fontSize: 13
                  , fontWeight: FontWeight.w700
                  , color: primary
                  )
              )
            , const SizedBox(width: 8)
            , if (events.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
                , decoration: BoxDecoration(
                    color: primary.withOpacity(0.1)
                  , borderRadius: BorderRadius.circular(10)
                  )
                , child: Text(
                    '${events.length}건'
                  , style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary)
                  )
                )
            ]
          )
        )
      , const Divider(height: 1, indent: 16, endIndent: 16)

      , if (events.isEmpty)
          Expanded(
            child: _emptyState(
              context
            , icon: Icons.event_available_outlined
            , message: '이 날은 할인 일정이 없어요.'
            )
          )
      else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12)
            , itemCount: events.length
            , separatorBuilder: (_, __) => const SizedBox(height: 6)
            , itemBuilder: (context, index) {
                final event = events[index];
                final brand = brandMap[event.brandId];
                return _EventCard(event: event, brand: brand);
              }
            )
          )
      ]
    );
  }

  Widget _emptyState(
    BuildContext context, {
    required IconData icon
  , required String message
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min
      , children: [
          Icon(icon, size: 40, color: Colors.grey.shade300)
        , const SizedBox(height: 12)
        , Text(
            message
          , textAlign: TextAlign.center
          , style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.6)
          )
        ]
      )
    );
  }
}

// ── _EventCard ────────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.brand});
  final _CalendarEvent event;
  final Brand?         brand;

  static const _aiColor = Color(0xFF7C4DFF);

  @override
  Widget build(BuildContext context) {
    final isAi  = event.isAiPredicted;
    final color = isAi ? _aiColor : Colors.redAccent;
    final pct   = (event.discountRate * 100).toStringAsFixed(0);

    return InkWell(
      onTap: brand == null ? null : () {
        Navigator.push(
          context
        , MaterialPageRoute(builder: (_) => BrandDetailScreen(brand: brand!))
        );
      }
    , borderRadius: BorderRadius.circular(12)
    , child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
      , decoration: BoxDecoration(
          color: color.withOpacity(0.05)
        , borderRadius: BorderRadius.circular(12)
        , border: Border.all(color: color.withOpacity(0.15))
        )
      , child: Row(
          children: [
            Container(
              width: 36, height: 36
            , decoration: BoxDecoration(
                color: color.withOpacity(0.12)
              , shape: BoxShape.circle
              )
            , child: Icon(
                  isAi ? Icons.event_note_rounded : Icons.local_offer_rounded
                , color: color
                , size: 18
                )
            )
          , const SizedBox(width: 12)
          , Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start
              , children: [
                  Text(
                    event.brandName
                  , style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)
                  )
                , const SizedBox(height: 2)
                , Text(
                    isAi ? '할인 예측' : '현재 할인 중'
                  , style: TextStyle(fontSize: 11, color: color)
                  )
                ]
              )
            )
          , Row(
              mainAxisSize: MainAxisSize.min
            , children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                , decoration: BoxDecoration(
                    color: color
                  , borderRadius: BorderRadius.circular(8)
                  )
                , child: Text(
                    '$pct% OFF'
                  , style: const TextStyle(
                      color: Colors.white
                    , fontWeight: FontWeight.w800
                    , fontSize: 12
                    )
                  )
                )
              , if (brand != null) ...[
                  const SizedBox(width: 6)
                , Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade400)
                ]
              ]
            )
          ]
        )
      )
    );
  }
}

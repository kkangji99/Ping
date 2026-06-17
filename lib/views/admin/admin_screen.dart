import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/brand_with_categories.dart';
import '../../models/category.dart';
import '../../services/supabase_service.dart';
import '../../utils/brand_search.dart';

// ─────────────────────────────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<BrandWithCategories> _brands     = [];
  List<Category>            _categories = [];
  bool    _loading = true;
  String? _error;

  // 검색
  final _brandSearchCtrl    = TextEditingController();
  final _categorySearchCtrl = TextEditingController();
  String _brandQuery    = '';
  String _categoryQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _brandSearchCtrl.dispose();
    _categorySearchCtrl.dispose();
    super.dispose();
  }

  SupabaseService get _svc => context.read<SupabaseService>();

  List<BrandWithCategories> get _filteredBrands => _brandQuery.isEmpty
      ? _brands
      : _brands.where((b) => matchesBrandSearch(b.name, _brandQuery)).toList();

  List<Category> get _filteredCategories => _categoryQuery.isEmpty
      ? _categories
      : _categories.where((c) => matchesBrandSearch(c.name, _categoryQuery)).toList();

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _svc.fetchBrandsWithCategories()
      , _svc.fetchCategories()
      ]);
      if (!mounted) return;
      setState(() {
        _brands     = results[0] as List<BrandWithCategories>;
        _categories = results[1] as List<Category>;
        _loading    = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── 브랜드 CRUD ─────────────────────────────────────────────────────────────

  Future<void> _addBrand() async {
    final result = await showDialog<_BrandFormResult>(
      context: context
    , builder: (_) => _BrandFormDialog(allCategories: _categories)
    );
    if (result == null) return;

    final brand = await _svc.createBrand(
      name:          result.name
    , isDiscounting: result.isDiscounting
    , crawlUrl:      result.crawlUrl
    );

    if (result.pickedImageBytes != null) {
      try {
        final url = await _svc.uploadBrandLogo(
          brand.id, result.pickedImageBytes!, result.pickedImageExtension ?? 'jpg'
        );
        await _svc.updateBrandLogoUrl(brand.id, url);
      } catch (e) {
        _showSnackError('이미지 업로드 실패: $e');
      }
    }

    for (final catId in result.categoryIds) {
      await _svc.assignBrandToCategory(brand.id, catId);
    }
    await _refresh();
    _showSnackSuccess('"${result.name}" 브랜드가 추가됐어요.');
  }

  Future<void> _editBrand(BrandWithCategories bwc) async {
    final result = await showDialog<_BrandFormResult>(
      context: context
    , builder: (_) => _BrandFormDialog(
          initialName:          bwc.name
        , initialDiscounting:   bwc.isDiscounting
        , initialCategoryIds:   bwc.categories.map((c) => c.id).toSet()
        , initialCrawlUrl:      bwc.crawlUrl
        , initialLogoUrl:       bwc.logoUrl
        , allCategories:        _categories
        )
    );
    if (result == null) return;

    await _svc.updateBrand(
      bwc.id, name: result.name, isDiscounting: result.isDiscounting, crawlUrl: result.crawlUrl
    );

    if (result.pickedImageBytes != null) {
      try {
        final url = await _svc.uploadBrandLogo(
          bwc.id, result.pickedImageBytes!, result.pickedImageExtension ?? 'jpg'
        );
        await _svc.updateBrandLogoUrl(bwc.id, url);
      } catch (e) {
        _showSnackError('이미지 업로드 실패: $e');
      }
    }

    final prev = bwc.categories.map((c) => c.id).toSet();
    final next = result.categoryIds;
    for (final id in next.difference(prev)) await _svc.assignBrandToCategory(bwc.id, id);
    for (final id in prev.difference(next)) await _svc.removeBrandFromCategory(bwc.id, id);

    await _refresh();
    _showSnackSuccess('"${result.name}" 정보가 수정됐어요.');
  }

  Future<void> _deleteBrand(BrandWithCategories bwc) async {
    final ok = await _showConfirm('브랜드 삭제', '"${bwc.name}"을(를) 완전히 삭제할까요?');
    if (!ok) return;
    await _svc.deleteBrand(bwc.id);
    await _refresh();
    _showSnackSuccess('"${bwc.name}"이(가) 삭제됐어요.');
  }

  Future<void> _removeCategoryFromBrand(BrandWithCategories bwc, Category cat) async {
    await _svc.removeBrandFromCategory(bwc.id, cat.id);
    await _refresh();
  }

  // ── 카테고리 CRUD ────────────────────────────────────────────────────────────

  Future<void> _addCategory() async {
    final name = await _showTextDialog(title: '카테고리 추가', hint: '카테고리 이름');
    if (name == null || name.isEmpty) return;
    await _svc.createCategory(name);
    await _refresh();
    _showSnackSuccess('"$name" 카테고리가 추가됐어요.');
  }

  Future<void> _editCategory(Category cat) async {
    final name = await _showTextDialog(
      title: '카테고리 수정', hint: '카테고리 이름', initial: cat.name
    );
    if (name == null || name.isEmpty) return;
    await _svc.updateCategory(cat.id, name);
    await _refresh();
    _showSnackSuccess('카테고리 이름이 "$name"으로 수정됐어요.');
  }

  Future<void> _deleteCategory(Category cat) async {
    final ok = await _showConfirm(
      '카테고리 삭제'
    , '"${cat.name}" 카테고리를 삭제할까요?\n(브랜드와의 연결도 함께 삭제됩니다)'
    );
    if (!ok) return;
    await _svc.deleteCategory(cat.id);
    await _refresh();
    _showSnackSuccess('"${cat.name}"이(가) 삭제됐어요.');
  }

  // ── 유틸 ──────────────────────────────────────────────────────────────────────

  void _showSnackSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg)
    , backgroundColor: Colors.green.shade600
    , behavior: SnackBarBehavior.floating
    , duration: const Duration(seconds: 2)
    ));
  }

  void _showSnackError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg)
    , backgroundColor: Colors.redAccent
    , behavior: SnackBarBehavior.floating
    ));
  }

  Future<String?> _showTextDialog({
    required String title, required String hint, String initial = ''
  }) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context
    , builder: (ctx) => AlertDialog(
        title: Text(title)
      , content: TextField(
          controller: ctrl
        , decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder())
        , autofocus: true
        , onSubmitted: (v) => Navigator.pop(ctx, v.trim())
        )
      , actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소'))
        , FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim())
          , child: const Text('저장')
          )
        ]
      )
    );
  }

  Future<bool> _showConfirm(String title, String content) async {
    final result = await showDialog<bool>(
      context: context
    , builder: (ctx) => AlertDialog(
        title: Text(title)
      , content: Text(content)
      , actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소'))
        , FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent)
          , onPressed: () => Navigator.pop(ctx, true)
          , child: const Text('삭제')
          )
        ]
      )
    );
    return result ?? false;
  }

  Future<void> _signOut() async {
    await _svc.signOut();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 패널')
      , backgroundColor: primary
      , foregroundColor: Colors.white
      , elevation: 0
      , actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded)
          , tooltip: '새로고침'
          , onPressed: _loading ? null : _refresh
          )
        , TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.white, size: 18)
          , label: const Text('로그아웃', style: TextStyle(color: Colors.white, fontSize: 13))
          , onPressed: _signOut
          )
        ]
      , bottom: TabBar(
          controller: _tabController
        , labelColor: Colors.white
        , unselectedLabelColor: Colors.white70
        , indicatorColor: Colors.white
        , indicatorWeight: 3
        , tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min
              , children: [
                  const Icon(Icons.store_outlined, size: 18)
                , const SizedBox(width: 6)
                , Text('브랜드${_loading ? '' : ' (${_brands.length})'}')
                ]
              )
            )
          , Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min
              , children: [
                  const Icon(Icons.label_outlined, size: 18)
                , const SizedBox(width: 6)
                , Text('카테고리${_loading ? '' : ' (${_categories.length})'}')
                ]
              )
            )
          ]
        )
      )
    , floatingActionButton: _loading ? null : AnimatedBuilder(
        animation: _tabController
      , builder: (_, __) => FloatingActionButton.extended(
            onPressed: _tabController.index == 0 ? _addBrand : _addCategory
          , icon: const Icon(Icons.add)
          , label: Text(_tabController.index == 0 ? '브랜드 추가' : '카테고리 추가')
          )
      )
    , body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _refresh)
              : TabBarView(
                  controller: _tabController
                , children: [_buildBrandsTab(), _buildCategoriesTab()]
                )
    );
  }

  // ── 브랜드 탭 ──────────────────────────────────────────────────────────────

  Widget _buildBrandsTab() {
    final filtered   = _filteredBrands;
    final onSaleCount = _brands.where((b) => b.isDiscounting).length;

    return Column(
      children: [
        // 통계 요약
        _StatBar(items: [
          (label: '전체', value: '${_brands.length}')
        , (label: '할인 중', value: '$onSaleCount')
        , (label: '카테고리 없음', value: '${_brands.where((b) => b.categories.isEmpty).length}')
        , (label: '이미지 없음', value: '${_brands.where((b) => b.logoUrl == null).length}')
        ])

      , // 검색바
        _AdminSearchBar(
          controller: _brandSearchCtrl
        , hint: '브랜드 검색'
        , onChanged: (v) => setState(() => _brandQuery = v)
        )

      , if (_brandQuery.isNotEmpty)
          _SearchResultBanner(
            query: _brandQuery, count: filtered.length, total: _brands.length
          )

      , Expanded(
          child: filtered.isEmpty
              ? _EmptySearchState(query: _brandQuery)
              : RefreshIndicator(
                  onRefresh: _refresh
                , child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96)
                  , itemCount: filtered.length
                  , itemBuilder: (_, i) => _buildBrandCard(filtered[i])
                  )
                )
        )
      ]
    );
  }

  Widget _buildBrandCard(BrandWithCategories bwc) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5)
    , clipBehavior: Clip.antiAlias
    , elevation: 1
    , child: ExpansionTile(
        leading: _BrandLogoAvatar(name: bwc.name, logoUrl: bwc.logoUrl, radius: 22)
      , title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start
              , children: [
                  Text(
                    bwc.name
                  , style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)
                  )
                , const SizedBox(height: 2)
                , Row(
                    children: [
                      if (bwc.isDiscounting)
                        _MiniChip(label: '할인 중', color: Colors.redAccent)
                      , if (bwc.crawlUrl != null && bwc.crawlUrl!.isNotEmpty) ...[
                          if (bwc.isDiscounting) const SizedBox(width: 4)
                        , _MiniChip(label: '크롤링', color: Colors.blue.shade300)
                        ]
                      , if (bwc.categories.isEmpty) ...[
                          const SizedBox(width: 4)
                        , _MiniChip(label: '카테고리 없음', color: Colors.orange)
                        ]
                      ]
                    )
                  ]
                )
              )
            , _iconBtn(Icons.edit_outlined,  '편집', () => _editBrand(bwc))
            , _iconBtn(Icons.delete_outline, '삭제', () => _deleteBrand(bwc), color: Colors.redAccent)
          ]
        )
      , subtitle: bwc.categories.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4)
              , child: Wrap(
                  spacing: 4, runSpacing: 2
                , children: bwc.categories.map((c) => Chip(
                      label: Text(c.name, style: const TextStyle(fontSize: 10))
                    , visualDensity: VisualDensity.compact
                    , padding: EdgeInsets.zero
                    , materialTapTargetSize: MaterialTapTargetSize.shrinkWrap
                    )).toList()
                )
              )
      , initiallyExpanded: false
      , childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 12)
      , children: [
          if (bwc.logoUrl != null)
            ListTile(
              dense: true
            , contentPadding: const EdgeInsets.only(left: 40)
            , leading: const Icon(Icons.image_outlined, size: 16, color: Colors.grey)
            , title: Text(
                bwc.logoUrl!
              , style: const TextStyle(fontSize: 11, color: Colors.blueGrey)
              , overflow: TextOverflow.ellipsis
              )
            )
        , if (bwc.crawlUrl != null)
            ListTile(
              dense: true
            , contentPadding: const EdgeInsets.only(left: 40)
            , leading: const Icon(Icons.link, size: 16, color: Colors.grey)
            , title: Text(
                bwc.crawlUrl!
              , style: const TextStyle(fontSize: 11, color: Colors.blueGrey)
              , overflow: TextOverflow.ellipsis
              )
            )
        , ...bwc.categories.map((cat) => ListTile(
              dense: true
            , contentPadding: const EdgeInsets.only(left: 40)
            , leading: const Icon(Icons.label_outline, size: 16)
            , title: Text(cat.name, style: const TextStyle(fontSize: 13))
            , trailing: _iconBtn(
                  Icons.link_off
                , '카테고리 연결 해제'
                , () => _removeCategoryFromBrand(bwc, cat)
                , color: Colors.orange
                )
            ))
        , _buildAddCategoryChips(bwc)
        ]
      )
    );
  }

  Widget _buildAddCategoryChips(BrandWithCategories bwc) {
    final assigned   = bwc.categories.map((c) => c.id).toSet();
    final unassigned = _categories.where((c) => !assigned.contains(c.id)).toList();
    if (unassigned.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6)
    , child: Wrap(
        spacing: 6, runSpacing: 4
      , children: [
          Text('+ 카테고리 연결:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
        , ...unassigned.map((cat) => ActionChip(
              label: Text(cat.name, style: const TextStyle(fontSize: 11))
            , avatar: const Icon(Icons.add, size: 14)
            , visualDensity: VisualDensity.compact
            , padding: EdgeInsets.zero
            , materialTapTargetSize: MaterialTapTargetSize.shrinkWrap
            , onPressed: () async {
                await _svc.assignBrandToCategory(bwc.id, cat.id);
                await _refresh();
              }
            ))
        ]
      )
    );
  }

  // ── 카테고리 탭 ─────────────────────────────────────────────────────────────

  Widget _buildCategoriesTab() {
    final filtered = _filteredCategories;

    return Column(
      children: [
        _StatBar(items: [
          (label: '전체', value: '${_categories.length}')
        , (label: '비어있음', value: '${_categories.where((c) =>
              !_brands.any((b) => b.categories.any((bc) => bc.id == c.id))).length}')
        ])

      , _AdminSearchBar(
          controller: _categorySearchCtrl
        , hint: '카테고리 검색'
        , onChanged: (v) => setState(() => _categoryQuery = v)
        )

      , if (_categoryQuery.isNotEmpty)
          _SearchResultBanner(
            query: _categoryQuery, count: filtered.length, total: _categories.length
          )

      , Expanded(
          child: filtered.isEmpty
              ? _EmptySearchState(query: _categoryQuery)
              : RefreshIndicator(
                  onRefresh: _refresh
                , child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96)
                  , itemCount: filtered.length
                  , separatorBuilder: (_, __) => const Divider(height: 1, indent: 16)
                  , itemBuilder: (_, i) {
                      final cat   = filtered[i];
                      final count = _brands.where(
                        (b) => b.categories.any((c) => c.id == cat.id)
                      ).length;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18
                        , backgroundColor: Theme.of(context).colorScheme.primaryContainer
                        , child: Text(
                              cat.name.isNotEmpty ? cat.name[0] : '?'
                            , style: TextStyle(
                                fontSize: 13
                              , fontWeight: FontWeight.bold
                              , color: Theme.of(context).colorScheme.onPrimaryContainer
                              )
                            )
                        )
                      , title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600))
                      , subtitle: Text(
                            count == 0 ? '브랜드 없음' : '브랜드 $count개'
                          , style: TextStyle(
                                fontSize: 12
                              , color: count == 0 ? Colors.orange : Colors.grey
                              )
                          )
                      , trailing: Row(
                          mainAxisSize: MainAxisSize.min
                        , children: [
                              _iconBtn(Icons.edit_outlined,  '편집', () => _editCategory(cat))
                            , _iconBtn(Icons.delete_outline, '삭제', () => _deleteCategory(cat)
                                , color: Colors.redAccent)
                          ]
                        )
                      );
                    }
                  )
                )
        )
      ]
    );
  }

  Widget _iconBtn(
    IconData icon, String tooltip, VoidCallback onPressed, {Color? color}
  ) => IconButton(
      icon: Icon(icon, size: 20, color: color)
    , tooltip: tooltip
    , onPressed: onPressed
    , visualDensity: VisualDensity.compact
    );
}

// ── 공통 UI 위젯 ──────────────────────────────────────────────────────────────

class _AdminSearchBar extends StatelessWidget {
  const _AdminSearchBar({
    required this.controller
  , required this.hint
  , required this.onChanged
  });

  final TextEditingController controller;
  final String                 hint;
  final ValueChanged<String>   onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6)
    , child: TextField(
        controller: controller
      , onChanged: onChanged
      , textAlignVertical: TextAlignVertical.center
      , decoration: InputDecoration(
          hintText: hint
        , prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.grey)
        , suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey)
                , onPressed: () { controller.clear(); onChanged(''); }
                )
              : null
        , filled: true
        , fillColor: Colors.grey.shade100
        , contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12)
        , border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none
          )
        , enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none
          )
        , focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)
          , borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.4)
              , width: 1.5
              )
          )
        )
      )
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({required this.items});

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      color: primary.withOpacity(0.04)
    , padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
    , child: Row(
        children: items.map((item) => Expanded(
          child: Column(
            children: [
              Text(item.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primary))
            , Text(item.label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))
            ]
          )
        )).toList()
      )
    );
  }
}

class _SearchResultBanner extends StatelessWidget {
  const _SearchResultBanner({
    required this.query, required this.count, required this.total
  });

  final String query;
  final int    count;
  final int    total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity
    , color: Theme.of(context).colorScheme.primary.withOpacity(0.06)
    , padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
    , child: Text(
        '"$query" 검색결과: $count / $total개'
      , style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)
      )
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min
      , children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300)
        , const SizedBox(height: 12)
        , Text('"$query"에 해당하는 항목이 없어요.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500))
        , const SizedBox(height: 6)
        , Text('한국어 또는 영어로 검색해보세요.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400))
        ]
      )
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
    , decoration: BoxDecoration(
        color: color.withOpacity(0.12)
      , borderRadius: BorderRadius.circular(4)
      )
    , child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600))
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String       message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32)
      , child: Column(
          mainAxisSize: MainAxisSize.min
        , children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400)
          , const SizedBox(height: 16)
          , Text(message, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center)
          , const SizedBox(height: 16)
          , FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도'))
          ]
        )
      )
    );
  }
}

// ── _BrandLogoAvatar ─────────────────────────────────────────────────────────

class _BrandLogoAvatar extends StatelessWidget {
  const _BrandLogoAvatar({required this.name, this.logoUrl, this.radius = 22});

  final String  name;
  final String? logoUrl;
  final double  radius;

  @override
  Widget build(BuildContext context) {
    final bg      = Theme.of(context).colorScheme.primaryContainer;
    final onBg    = Theme.of(context).colorScheme.onPrimaryContainer;
    final fontSize = radius * 0.8;

    return CircleAvatar(
      radius: radius
    , backgroundColor: bg
    , child: logoUrl != null
          ? ClipOval(
              child: Image.network(
                logoUrl!
              , width: radius * 2, height: radius * 2
              , fit: BoxFit.cover
              , errorBuilder: (_, __, ___) => Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?'
                  , style: TextStyle(color: onBg, fontWeight: FontWeight.bold, fontSize: fontSize)
                  )
              )
            )
          : Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?'
            , style: TextStyle(color: onBg, fontWeight: FontWeight.bold, fontSize: fontSize)
            )
    );
  }
}

// ── 브랜드 폼 다이얼로그 ─────────────────────────────────────────────────────

class _BrandFormResult {
  final String      name;
  final bool        isDiscounting;
  final Set<String> categoryIds;
  final String?     crawlUrl;
  final Uint8List?  pickedImageBytes;
  final String?     pickedImageExtension;

  const _BrandFormResult({
    required this.name
  , required this.isDiscounting
  , required this.categoryIds
  , this.crawlUrl
  , this.pickedImageBytes
  , this.pickedImageExtension
  });
}

class _BrandFormDialog extends StatefulWidget {
  const _BrandFormDialog({
    this.initialName
  , this.initialDiscounting = false
  , this.initialCategoryIds = const {}
  , this.initialCrawlUrl
  , this.initialLogoUrl
  , this.allCategories = const []
  });

  final String?        initialName;
  final bool           initialDiscounting;
  final Set<String>    initialCategoryIds;
  final String?        initialCrawlUrl;
  final String?        initialLogoUrl;
  final List<Category> allCategories;

  @override
  State<_BrandFormDialog> createState() => _BrandFormDialogState();
}

class _BrandFormDialogState extends State<_BrandFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _crawlUrlCtrl;
  late bool        _isDiscounting;
  late Set<String> _selectedCategoryIds;

  Uint8List? _pickedBytes;
  String?    _pickedExt;
  bool       _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl            = TextEditingController(text: widget.initialName ?? '');
    _crawlUrlCtrl        = TextEditingController(text: widget.initialCrawlUrl ?? '');
    _isDiscounting       = widget.initialDiscounting;
    _selectedCategoryIds = Set.from(widget.initialCategoryIds);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _crawlUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.first.bytes == null) return;
      setState(() {
        _pickedBytes = result.files.first.bytes;
        _pickedExt   = result.files.first.extension?.toLowerCase() ?? 'jpg';
      });
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasExistingLogo = widget.initialLogoUrl != null;
    final hasNewImage     = _pickedBytes != null;
    final isEdit          = widget.initialName != null;

    return AlertDialog(
      title: Text(isEdit ? '브랜드 수정' : '브랜드 추가')
    , content: SizedBox(
        width: 400
      , child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min
          , crossAxisAlignment: CrossAxisAlignment.start
          , children: [
              // 로고
              Center(
                child: Column(
                  children: [
                    _LogoPreview(
                      pickedBytes: _pickedBytes
                    , networkUrl: hasNewImage ? null : widget.initialLogoUrl
                    , name: widget.initialName ?? ''
                    )
                  , const SizedBox(height: 8)
                  , _pickingImage
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : OutlinedButton.icon(
                          onPressed: _pickImage
                        , icon: const Icon(Icons.image_outlined, size: 16)
                        , label: Text(hasNewImage || hasExistingLogo ? '이미지 변경' : '이미지 선택'
                            , style: const TextStyle(fontSize: 13))
                        )
                  ]
                )
              )
            , const SizedBox(height: 16)

            // 브랜드명
            , TextField(
                controller: _nameCtrl
              , decoration: const InputDecoration(
                  labelText: '브랜드 이름 *'
                , border: OutlineInputBorder()
                )
              , autofocus: !isEdit
              )
            , const SizedBox(height: 12)

            // 크롤링 URL
            , TextField(
                controller: _crawlUrlCtrl
              , decoration: const InputDecoration(
                  labelText: '크롤링 URL (선택)'
                , hintText: 'https://...'
                , prefixIcon: Icon(Icons.link)
                , border: OutlineInputBorder()
                )
              , keyboardType: TextInputType.url
              )
            , const SizedBox(height: 4)

            // 할인 여부
            , SwitchListTile(
                contentPadding: EdgeInsets.zero
              , title: const Text('현재 할인 중')
              , subtitle: const Text('크롤링 후 자동 업데이트됩니다', style: TextStyle(fontSize: 11))
              , value: _isDiscounting
              , onChanged: (v) => setState(() => _isDiscounting = v)
              )

            // 카테고리
            , if (widget.allCategories.isNotEmpty) ...[
                const Divider()
              , const Text('카테고리', style: TextStyle(fontWeight: FontWeight.w600))
              , const SizedBox(height: 8)
              , Wrap(
                  spacing: 0, runSpacing: 0
                , children: widget.allCategories.map((cat) =>
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero
                    , dense: true
                    , title: Text(cat.name, style: const TextStyle(fontSize: 14))
                    , value: _selectedCategoryIds.contains(cat.id)
                    , onChanged: (v) => setState(() {
                        if (v == true) _selectedCategoryIds.add(cat.id);
                        else           _selectedCategoryIds.remove(cat.id);
                      })
                    )
                  ).toList()
                )
              ]
            ]
          )
        )
      )
    , actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소'))
      , FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, _BrandFormResult(
              name:                 name
            , isDiscounting:        _isDiscounting
            , categoryIds:          _selectedCategoryIds
            , crawlUrl:             _crawlUrlCtrl.text.trim().isEmpty ? null : _crawlUrlCtrl.text.trim()
            , pickedImageBytes:     _pickedBytes
            , pickedImageExtension: _pickedExt
            ));
          }
        , child: const Text('저장')
        )
      ]
    );
  }
}

// ── _LogoPreview ─────────────────────────────────────────────────────────────

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({this.pickedBytes, this.networkUrl, required this.name});

  final Uint8List? pickedBytes;
  final String?    networkUrl;
  final String     name;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primaryContainer;
    final fg = Theme.of(context).colorScheme.onPrimaryContainer;

    Widget child;
    if (pickedBytes != null) {
      child = Image.memory(pickedBytes!, width: 80, height: 80, fit: BoxFit.cover);
    } else if (networkUrl != null) {
      child = Image.network(networkUrl!, width: 80, height: 80, fit: BoxFit.cover
        , errorBuilder: (_, __, ___) => _initials(fg));
    } else {
      child = _initials(fg);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12)
    , child: Container(width: 80, height: 80, color: bg, child: child)
    );
  }

  Widget _initials(Color color) => Center(
    child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?'
    , style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)
    )
  );
}

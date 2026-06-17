import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/brand.dart';
import '../models/category_with_brands.dart';
import '../providers/favorite_provider.dart';
import '../providers/discount_provider.dart';
import '../services/supabase_service.dart';
import 'admin/admin_login_screen.dart';

// ── HomeScreen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int    _selectedIndex = 0;
  String _searchQuery   = '';
  final  _searchController = TextEditingController();
  late Future<List<CategoryWithBrands>> _dataFuture;

  // ── 시크릿 관리자 진입 (타이틀 5번 탭) ─────────────────────────────────────
  int       _adminTapCount = 0;
  DateTime? _adminLastTap;

  void _onTitleTap() {
    final now = DateTime.now();
    if (_adminLastTap == null ||
        now.difference(_adminLastTap!) > const Duration(seconds: 2)) {
      _adminTapCount = 0;
    }
    _adminTapCount++;
    _adminLastTap = now;
    if (_adminTapCount >= 5) {
      _adminTapCount = 0;
      Navigator.push(
        context
      , MaterialPageRoute(builder: (_) => const AdminLoginScreen())
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _dataFuture = context.read<SupabaseService>().fetchCategoriesWithBrands();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = context.read<SupabaseService>().fetchCategoriesWithBrands();
    });
  }

  // ── 브랜드 목록 필터링 ────────────────────────────────────────────────────

  List<({Brand brand, String categoryName})> _buildBrandList(
    List<CategoryWithBrands> categories
  ) {
    final seen = <String>{};
    final all  = <({Brand brand, String categoryName})>[];

    final targetCategories = _selectedIndex == 0
        ? categories
        : [categories[_selectedIndex - 1]];

    for (final cat in targetCategories) {
      for (final b in cat.brands) {
        if (seen.add(b.id)) all.add((brand: b, categoryName: cat.name));
      }
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      return all.where((e) => e.brand.name.toLowerCase().contains(q)).toList();
    }
    return all;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 타이틀을 GestureDetector로 감싸서 5-탭 시크릿 관리자 진입
        title: GestureDetector(
          onTap: _onTitleTap
        , child: const Text('Ping')
        )
      , centerTitle: true
      , backgroundColor: Theme.of(context).colorScheme.primary
      , foregroundColor: Colors.white
      , elevation: 0
      )
    , body: FutureBuilder<List<CategoryWithBrands>>(
        future: _dataFuture
      , builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(onRetry: _refresh);
          }

          final categories  = snap.data ?? [];
          final brandList   = _buildBrandList(categories);
          final isSearching = _searchQuery.isNotEmpty;

          return RefreshIndicator(
            onRefresh: _refresh
          , child: Column(
              children: [
                _SearchBar(
                  controller: _searchController
                , onChanged: (v) => setState(() => _searchQuery = v)
                )
              , const Divider(height: 1)
              , if (!isSearching) ...[
                  _CategoryBar(
                    categories: categories
                  , selectedIndex: _selectedIndex
                  , onSelected: (i) => setState(() => _selectedIndex = i)
                  )
                , const Divider(height: 1)
                ]
              , Expanded(
                  child: _BrandListView(
                    items: brandList
                  , showCategory: isSearching || _selectedIndex == 0
                  )
                )
              ]
            )
          );
        }
      )
    );
  }
}

// ── _ErrorView ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32)
      , child: Column(
          mainAxisSize: MainAxisSize.min
        , children: [
            Icon(
              Icons.wifi_off_rounded
            , size: 56
            , color: Colors.grey.shade400
            )
          , const SizedBox(height: 16)
          , Text(
              '데이터를 불러오지 못했어요'
            , style: TextStyle(
                fontSize: 16
              , fontWeight: FontWeight.w600
              , color: Colors.grey.shade700
              )
            )
          , const SizedBox(height: 8)
          , Text(
              '네트워크 연결을 확인하고 다시 시도해주세요.'
            , style: TextStyle(fontSize: 13, color: Colors.grey.shade500)
            , textAlign: TextAlign.center
            )
          , const SizedBox(height: 24)
          , FilledButton.tonal(
              onPressed: onRetry
            , child: const Text('다시 시도')
            )
          ]
        )
      )
    );
  }
}

// ── _SearchBar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>  onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
    , child: TextField(
        controller: controller
      , onChanged: onChanged
      , textAlignVertical: TextAlignVertical.center
      , decoration: InputDecoration(
          hintText: '브랜드 검색'
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
            borderRadius: BorderRadius.circular(12)
          , borderSide: BorderSide.none
          )
        , enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)
          , borderSide: BorderSide.none
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

// ── _CategoryBar ──────────────────────────────────────────────────────────────

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories
  , required this.selectedIndex
  , required this.onSelected
  });

  final List<CategoryWithBrands> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _iconMap = <String, IconData>{
    '패션':     Icons.checkroom_outlined
  , '스포츠':   Icons.sports_soccer_outlined
  , '패스트푸드': Icons.fastfood_outlined
  , '뷰티':     Icons.face_retouching_natural_outlined
  , '카페':     Icons.local_cafe_outlined
  , '편의점':   Icons.store_outlined
  , '아웃도어': Icons.terrain_outlined
  , '라이프':   Icons.home_outlined
  , '전자':     Icons.devices_outlined
  };

  @override
  Widget build(BuildContext context) {
    final primary    = Theme.of(context).colorScheme.primary;
    final itemCount  = categories.length + 1;

    return SizedBox(
      height: 86
    , child: ListView.builder(
        scrollDirection: Axis.horizontal
      , padding: const EdgeInsets.symmetric(horizontal: 10)
      , itemCount: itemCount
      , itemBuilder: (context, index) {
          final isSelected = index == selectedIndex;
          final name = index == 0 ? '전체' : categories[index - 1].name;
          final icon = index == 0
              ? Icons.apps_rounded
              : (_iconMap[name] ?? Icons.label_outline);

          return GestureDetector(
            onTap: () => onSelected(index)
          , child: AnimatedContainer(
              duration: const Duration(milliseconds: 180)
            , curve: Curves.easeInOut
            , width: 64
            , child: Column(
                mainAxisAlignment: MainAxisAlignment.center
              , children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180)
                  , width: 46, height: 46
                  , decoration: BoxDecoration(
                      shape: BoxShape.circle
                    , color: isSelected ? primary : primary.withOpacity(0.08)
                    , boxShadow: isSelected
                          ? [BoxShadow(
                                color: primary.withOpacity(0.3)
                              , blurRadius: 8
                              , offset: const Offset(0, 3)
                              )]
                          : null
                    )
                  , child: Icon(
                      icon
                    , size: 22
                    , color: isSelected ? Colors.white : primary
                    )
                  )
                , const SizedBox(height: 5)
                , Text(
                    name
                  , style: TextStyle(
                      fontSize: 11
                    , fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400
                    , color: isSelected ? primary : Colors.black54
                    )
                  , maxLines: 1
                  , overflow: TextOverflow.ellipsis
                  , textAlign: TextAlign.center
                  )
                ]
              )
            )
          );
        }
      )
    );
  }
}

// ── _BrandListView ────────────────────────────────────────────────────────────

class _BrandListView extends StatelessWidget {
  const _BrandListView({required this.items, required this.showCategory});

  final List<({Brand brand, String categoryName})> items;
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min
        , children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300)
          , const SizedBox(height: 12)
          , Text(
              '브랜드가 없습니다.'
            , style: TextStyle(color: Colors.grey.shade500, fontSize: 14)
            )
          ]
        )
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16)
    , itemCount: items.length
    , separatorBuilder: (_, __) => const Divider(height: 1, indent: 76, endIndent: 16)
    , itemBuilder: (context, index) => _BrandTile(
        brand: items[index].brand
      , categoryName: showCategory ? items[index].categoryName : null
      )
    );
  }
}

// ── _BrandTile ────────────────────────────────────────────────────────────────

class _BrandTile extends StatelessWidget {
  const _BrandTile({required this.brand, this.categoryName});

  final Brand   brand;
  final String? categoryName;

  @override
  Widget build(BuildContext context) {
    final isFavorite = context.watch<FavoriteProvider>().isFavorite(brand.id);
    final primary    = Theme.of(context).colorScheme.primary;
    final isOnSale   = brand.isDiscounting;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200)
    , color: isOnSale
          ? Colors.redAccent.withOpacity(0.03)
          : Colors.transparent
    , child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
      , leading: _BrandLogo(name: brand.name, logoUrl: brand.logoUrl)
      , title: Text(
            brand.name
          , style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)
          )
      , subtitle: categoryName != null
            ? Text(
                categoryName!
              , style: TextStyle(fontSize: 11, color: Colors.grey.shade500)
              )
            : null
      , trailing: Row(
          mainAxisSize: MainAxisSize.min
        , children: [
            if (isOnSale)
              _DiscountBadge(label: '할인 중', color: Colors.redAccent)
            else
              _AiPredictionBadge(brandId: brand.id, primary: primary)
          , const SizedBox(width: 2)
          , IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded
              , color: isFavorite ? Colors.redAccent : Colors.grey.shade400
              , size: 22
              )
            , onPressed: () =>
                  context.read<FavoriteProvider>().toggleFavorite(brand.id)
            )
          ]
        )
      )
    );
  }
}

// ── _DiscountBadge ────────────────────────────────────────────────────────────

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.label, required this.color});

  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
    , decoration: BoxDecoration(
        color: color.withOpacity(0.1)
      , borderRadius: BorderRadius.circular(8)
      , border: Border.all(color: color.withOpacity(0.2))
      )
    , child: Text(
        label
      , style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)
      )
    );
  }
}

// ── _AiPredictionBadge ────────────────────────────────────────────────────────

class _AiPredictionBadge extends StatelessWidget {
  const _AiPredictionBadge({required this.brandId, required this.primary});

  final String brandId;
  final Color  primary;

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DiscountProvider>();
    final prediction = dp.allHistory
        .where((h) => h.brandId == brandId && h.isAiPredicted)
        .fold<dynamic>(null, (prev, h) =>
            prev == null || h.startDate.isBefore(prev.startDate) ? h : prev);

    if (prediction == null) return const SizedBox.shrink();

    final month = prediction.startDate.month;
    return _DiscountBadge(label: 'AI $month월', color: primary);
  }
}

// ── _BrandLogo ────────────────────────────────────────────────────────────────

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.name, this.logoUrl});

  final String  name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final bg   = Theme.of(context).colorScheme.primaryContainer;
    final onBg = Theme.of(context).colorScheme.onPrimaryContainer;

    return CircleAvatar(
      radius: 24
    , backgroundColor: bg
    , child: logoUrl != null
          ? ClipOval(
              child: Image.network(
                logoUrl!
              , width: 48, height: 48
              , fit: BoxFit.cover
              , frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1
                  , duration: const Duration(milliseconds: 300)
                  , child: child
                  );
                }
              , errorBuilder: (_, __, ___) => _initials(onBg)
              )
            )
          : _initials(onBg)
    );
  }

  Widget _initials(Color color) => Text(
    name.isNotEmpty ? name[0].toUpperCase() : '?'
  , style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)
  );
}

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/brand_with_categories.dart';
import '../../models/category.dart';
import '../../services/supabase_service.dart';

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
  bool   _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  SupabaseService get _svc => context.read<SupabaseService>();

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
      name: result.name
    , isDiscounting: result.isDiscounting
    , crawlUrl: result.crawlUrl
    );

    // 이미지 업로드 (브랜드 생성 후 ID를 알 수 있으므로 이 순서로)
    if (result.pickedImageBytes != null) {
      try {
        final url = await _svc.uploadBrandLogo(
          brand.id
        , result.pickedImageBytes!
        , result.pickedImageExtension ?? 'jpg'
        );
        await _svc.updateBrandLogoUrl(brand.id, url);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('이미지 업로드 실패: $e')
            , backgroundColor: Colors.redAccent
            )
          );
        }
      }
    }

    // 카테고리 연결
    for (final catId in result.categoryIds) {
      await _svc.assignBrandToCategory(brand.id, catId);
    }
    await _refresh();
  }

  Future<void> _editBrand(BrandWithCategories bwc) async {
    final result = await showDialog<_BrandFormResult>(
      context: context
    , builder: (_) => _BrandFormDialog(
          initialName: bwc.name
        , initialDiscounting: bwc.isDiscounting
        , initialCategoryIds: bwc.categories.map((c) => c.id).toSet()
        , initialCrawlUrl: bwc.crawlUrl
        , initialLogoUrl: bwc.logoUrl
        , allCategories: _categories
        )
    );
    if (result == null) return;

    await _svc.updateBrand(
      bwc.id
    , name: result.name
    , isDiscounting: result.isDiscounting
    , crawlUrl: result.crawlUrl
    );

    // 새 이미지 선택했으면 업로드
    if (result.pickedImageBytes != null) {
      try {
        final url = await _svc.uploadBrandLogo(
          bwc.id
        , result.pickedImageBytes!
        , result.pickedImageExtension ?? 'jpg'
        );
        await _svc.updateBrandLogoUrl(bwc.id, url);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('이미지 업로드 실패: $e')
            , backgroundColor: Colors.redAccent
            )
          );
        }
      }
    }

    // 카테고리 diff 적용
    final prev = bwc.categories.map((c) => c.id).toSet();
    final next = result.categoryIds;
    for (final id in next.difference(prev)) {
      await _svc.assignBrandToCategory(bwc.id, id);
    }
    for (final id in prev.difference(next)) {
      await _svc.removeBrandFromCategory(bwc.id, id);
    }
    await _refresh();
  }

  Future<void> _deleteBrand(BrandWithCategories bwc) async {
    final ok = await _showConfirm(
      '브랜드 삭제', '"${bwc.name}"을(를) 완전히 삭제할까요?'
    );
    if (!ok) return;
    await _svc.deleteBrand(bwc.id);
    await _refresh();
  }

  Future<void> _removeCategoryFromBrand(
    BrandWithCategories bwc, Category cat
  ) async {
    await _svc.removeBrandFromCategory(bwc.id, cat.id);
    await _refresh();
  }

  // ── 카테고리 CRUD ────────────────────────────────────────────────────────────

  Future<void> _addCategory() async {
    final name = await _showTextDialog(
      title: '카테고리 추가', hint: '카테고리 이름'
    );
    if (name == null || name.isEmpty) return;
    await _svc.createCategory(name);
    await _refresh();
  }

  Future<void> _editCategory(Category cat) async {
    final name = await _showTextDialog(
      title: '카테고리 수정', hint: '카테고리 이름', initial: cat.name
    );
    if (name == null || name.isEmpty) return;
    await _svc.updateCategory(cat.id, name);
    await _refresh();
  }

  Future<void> _deleteCategory(Category cat) async {
    final ok = await _showConfirm(
      '카테고리 삭제'
    , '"${cat.name}" 카테고리를 삭제할까요?\n(브랜드와의 연결도 함께 삭제됩니다)'
    );
    if (!ok) return;
    await _svc.deleteCategory(cat.id);
    await _refresh();
  }

  // ── 공통 다이얼로그 ──────────────────────────────────────────────────────────

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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false)
          , child: const Text('취소')
          )
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 패널')
      , backgroundColor: Theme.of(context).colorScheme.primary
      , foregroundColor: Colors.white
      , actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.white)
          , label: const Text('로그아웃', style: TextStyle(color: Colors.white))
          , onPressed: _signOut
          )
        ]
      , bottom: TabBar(
          controller: _tabController
        , labelColor: Colors.white
        , unselectedLabelColor: Colors.white70
        , indicatorColor: Colors.white
        , tabs: const [
            Tab(icon: Icon(Icons.store_outlined),  text: '브랜드')
          , Tab(icon: Icon(Icons.label_outlined),  text: '카테고리')
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
              ? Center(
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent))
                )
              : TabBarView(
                  controller: _tabController
                , children: [_buildBrandsTab(), _buildCategoriesTab()]
                )
    );
  }

  // ── 브랜드 탭 ──────────────────────────────────────────────────────────────

  Widget _buildBrandsTab() {
    if (_brands.isEmpty) {
      return const Center(child: Text('브랜드가 없습니다. 추가해보세요.'));
    }
    return RefreshIndicator(
      onRefresh: _refresh
    , child: ListView(
        padding: const EdgeInsets.only(bottom: 80)
      , children: _brands.map(_buildBrandCard).toList()
      )
    );
  }

  Widget _buildBrandCard(BrandWithCategories bwc) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
    , clipBehavior: Clip.antiAlias
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
                  , style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                  )
                , if (bwc.isDiscounting)
                    const Text(
                      '할인 중'
                    , style: TextStyle(color: Colors.redAccent, fontSize: 11)
                    )
                ]
              )
            )
          , _iconBtn(Icons.edit_outlined,   '편집', () => _editBrand(bwc))
          , _iconBtn(Icons.delete_outline,  '삭제', () => _deleteBrand(bwc)
              , color: Colors.redAccent)
          ]
        )
      , subtitle: bwc.categories.isEmpty
            ? const Text('카테고리 없음', style: TextStyle(fontSize: 12, color: Colors.grey))
            : Wrap(
                spacing: 4
              , children: bwc.categories
                    .map((c) => Chip(
                          label: Text(c.name, style: const TextStyle(fontSize: 11))
                        , visualDensity: VisualDensity.compact
                        , padding: EdgeInsets.zero
                        ))
                    .toList()
              )
      , initiallyExpanded: false
      , children: [
          // 현재 logo_url 표시
          if (bwc.logoUrl != null)
            Padding(
              padding: const EdgeInsets.only(left: 56, right: 16, bottom: 4)
            , child: Row(
                children: [
                  const Icon(Icons.image_outlined, size: 14, color: Colors.grey)
                , const SizedBox(width: 4)
                , Expanded(
                    child: Text(
                      bwc.logoUrl!
                    , style: const TextStyle(fontSize: 11, color: Colors.blueGrey)
                    , overflow: TextOverflow.ellipsis
                    )
                  )
                ]
              )
            )
        , // 카테고리 목록
          ...bwc.categories.map(
            (cat) => ListTile(
              contentPadding: const EdgeInsets.only(left: 56, right: 8)
            , leading: const Icon(Icons.label_outline, size: 18)
            , title: Text(cat.name)
            , trailing: _iconBtn(
                  Icons.link_off
                , '카테고리 연결 해제'
                , () => _removeCategoryFromBrand(bwc, cat)
                , color: Colors.orange
                )
            )
          )
        , // 카테고리 연결 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 4, 16, 12)
          , child: _buildAddCategoryChips(bwc)
          )
        ]
      )
    );
  }

  Widget _buildAddCategoryChips(BrandWithCategories bwc) {
    final assigned   = bwc.categories.map((c) => c.id).toSet();
    final unassigned = _categories.where((c) => !assigned.contains(c.id)).toList();
    if (unassigned.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6
    , runSpacing: 4
    , children: [
        const Text('+ 카테고리 연결:', style: TextStyle(fontSize: 12, color: Colors.grey))
      , ...unassigned.map(
          (cat) => ActionChip(
            label: Text(cat.name, style: const TextStyle(fontSize: 11))
          , avatar: const Icon(Icons.add, size: 14)
          , visualDensity: VisualDensity.compact
          , padding: EdgeInsets.zero
          , onPressed: () async {
              await _svc.assignBrandToCategory(bwc.id, cat.id);
              await _refresh();
            }
          )
        )
      ]
    );
  }

  // ── 카테고리 탭 ─────────────────────────────────────────────────────────────

  Widget _buildCategoriesTab() {
    if (_categories.isEmpty) {
      return const Center(child: Text('카테고리가 없습니다. 추가해보세요.'));
    }
    return RefreshIndicator(
      onRefresh: _refresh
    , child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 80)
      , itemCount: _categories.length
      , separatorBuilder: (_, __) => const Divider(height: 1)
      , itemBuilder: (_, i) {
          final cat   = _categories[i];
          final count = _brands.where(
            (b) => b.categories.any((c) => c.id == cat.id)
          ).length;

          return ListTile(
            leading: const Icon(Icons.label_outlined)
          , title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600))
          , subtitle: Text('브랜드 $count개')
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

// ── _BrandLogoAvatar ─────────────────────────────────────────────────────────
// 관리자 화면 브랜드 카드 + 폼 미리보기 공통 위젯

class _BrandLogoAvatar extends StatelessWidget {
  const _BrandLogoAvatar({
    required this.name
  , this.logoUrl
  , this.radius = 22
  });

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
              , width:  radius * 2
              , height: radius * 2
              , fit: BoxFit.cover
              , errorBuilder: (_, __, ___) => Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?'
                  , style: TextStyle(
                        color: onBg
                      , fontWeight: FontWeight.bold
                      , fontSize: fontSize
                      )
                  )
              )
            )
          : Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?'
            , style: TextStyle(
                  color: onBg
                , fontWeight: FontWeight.bold
                , fontSize: fontSize
                )
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
  final String?     pickedImageExtension;  // 예: 'jpg', 'png'

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

  final String?     initialName;
  final bool        initialDiscounting;
  final Set<String> initialCategoryIds;
  final String?     initialCrawlUrl;
  final String?     initialLogoUrl;       // 기존 Storage URL
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image
      , withData: true
      );
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

    return AlertDialog(
      title: Text(widget.initialName == null ? '브랜드 추가' : '브랜드 수정')
    , content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min
        , crossAxisAlignment: CrossAxisAlignment.start
        , children: [
            // ── 로고 이미지 섹션 ──────────────────────────────────────
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
                    ? const SizedBox(
                        width: 24, height: 24
                      , child: CircularProgressIndicator(strokeWidth: 2)
                      )
                    : OutlinedButton.icon(
                        onPressed: _pickImage
                      , icon: const Icon(Icons.image_outlined, size: 16)
                      , label: Text(
                            hasNewImage || hasExistingLogo ? '이미지 변경' : '이미지 선택'
                          , style: const TextStyle(fontSize: 13)
                          )
                      )
                ]
              )
            )
          , const SizedBox(height: 16)

          // ── 기본 필드 ─────────────────────────────────────────────
          , TextField(
              controller: _nameCtrl
            , decoration: const InputDecoration(
                labelText: '브랜드 이름'
              , border: OutlineInputBorder()
              )
            , autofocus: widget.initialName == null
            )
          , const SizedBox(height: 12)
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
          , SwitchListTile(
              contentPadding: EdgeInsets.zero
            , title: const Text('현재 할인 중')
            , value: _isDiscounting
            , onChanged: (v) => setState(() => _isDiscounting = v)
            )
          , if (widget.allCategories.isNotEmpty) ...[
              const Divider()
            , const Text('카테고리', style: TextStyle(fontWeight: FontWeight.w600))
            , const SizedBox(height: 8)
            , ...widget.allCategories.map(
                (cat) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero
                , dense: true
                , title: Text(cat.name)
                , value: _selectedCategoryIds.contains(cat.id)
                , onChanged: (v) => setState(() {
                    if (v == true) _selectedCategoryIds.add(cat.id);
                    else           _selectedCategoryIds.remove(cat.id);
                  })
                )
              )
            ]
          ]
        )
      )
    , actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소'))
      , FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context
            , _BrandFormResult(
                name: name
              , isDiscounting: _isDiscounting
              , categoryIds: _selectedCategoryIds
              , crawlUrl: _crawlUrlCtrl.text.trim().isEmpty
                    ? null
                    : _crawlUrlCtrl.text.trim()
              , pickedImageBytes:     _pickedBytes
              , pickedImageExtension: _pickedExt
              )
            );
          }
        , child: const Text('저장')
        )
      ]
    );
  }
}

// ── _LogoPreview ─────────────────────────────────────────────────────────────
// 다이얼로그 안 이미지 미리보기 (로컬 bytes 우선, 없으면 Network, 없으면 이니셜)

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({
    this.pickedBytes
  , this.networkUrl
  , required this.name
  });

  final Uint8List? pickedBytes;
  final String?    networkUrl;
  final String     name;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primaryContainer;
    final fg = Theme.of(context).colorScheme.onPrimaryContainer;

    Widget imageChild;
    if (pickedBytes != null) {
      imageChild = Image.memory(
        pickedBytes!, width: 80, height: 80, fit: BoxFit.cover
      );
    } else if (networkUrl != null) {
      imageChild = Image.network(
        networkUrl!
      , width: 80, height: 80, fit: BoxFit.cover
      , errorBuilder: (_, __, ___) => _initials(fg)
      );
    } else {
      imageChild = _initials(fg);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12)
    , child: Container(
        width: 80, height: 80
      , color: bg
      , child: imageChild
      )
    );
  }

  Widget _initials(Color color) => Center(
    child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?'
    , style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)
    )
  );
}

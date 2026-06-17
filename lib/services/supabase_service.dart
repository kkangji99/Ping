import 'dart:typed_data';
import 'package:flutter/foundation.dart' hide Category;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category.dart';
import '../models/brand.dart';
import '../models/category_with_brands.dart';
import '../models/brand_with_categories.dart';
import '../models/discount_history.dart';

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  // ── Auth ────────────────────────────────────────────────────────────────────

  bool get isSignedIn => _client.auth.currentUser != null;
  String? get currentUserId => _client.auth.currentUser?.id;
  String? get currentUserEmail => _client.auth.currentUser?.email;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email
    , password: password
    );
  }

  Future<void> signUp(String email, String password) async {
    await _client.auth.signUp(
      email: email
    , password: password
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ── Categories ─────────────────────────────────────────────────────────────

  Future<List<Category>> fetchCategories() async {
    final data = await _client
        .from('categories')
        .select('id, name')
        .order('name');
    return (data as List<dynamic>)
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 카테고리별 브랜드 목록 (단일 쿼리, 다대다 조인)
  Future<List<CategoryWithBrands>> fetchCategoriesWithBrands() async {
    final data = await _client
        .from('categories')
        .select('id, name, brand_categories(brands(id, name, logo_url, is_discounting))')
        .order('name');
    return (data as List<dynamic>)
        .map((e) => CategoryWithBrands.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Category> createCategory(String name) async {
    final data = await _client
        .from('categories')
        .insert({'name': name})
        .select('id, name')
        .single();
    return Category.fromJson(data as Map<String, dynamic>);
  }

  Future<void> updateCategory(String id, String name) async {
    await _client
        .from('categories')
        .update({'name': name})
        .eq('id', id);
  }

  Future<void> deleteCategory(String id) async {
    await _client
        .from('categories')
        .delete()
        .eq('id', id);
  }

  // ── Brands ──────────────────────────────────────────────────────────────────

  /// 브랜드별 카테고리 목록 (관리자용, 단일 쿼리)
  Future<List<BrandWithCategories>> fetchBrandsWithCategories() async {
    final data = await _client
        .from('brands')
        .select('id, name, logo_url, is_discounting, crawl_url, brand_categories(categories(id, name))')
        .order('name');
    return (data as List<dynamic>)
        .map((e) => BrandWithCategories.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Brand>> fetchBrands() async {
    final data = await _client
        .from('brands')
        .select('id, name, logo_url, is_discounting, crawl_url')
        .order('name');
    return (data as List<dynamic>)
        .map((e) => Brand.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Brand> createBrand({
    required String name
  , String? logoUrl
  , required bool isDiscounting
  , String? crawlUrl
  }) async {
    final data = await _client
        .from('brands')
        .insert({
          'name': name
        , 'logo_url': logoUrl
        , 'is_discounting': isDiscounting
        , 'crawl_url': crawlUrl?.isEmpty == true ? null : crawlUrl
        })
        .select('id, name, logo_url, is_discounting')
        .single();
    return Brand.fromJson(data as Map<String, dynamic>);
  }

  Future<void> updateBrand(
    String id, {
    required String name
  , required bool isDiscounting
  , String? crawlUrl
  }) async {
    await _client
        .from('brands')
        .update({
          'name': name
        , 'is_discounting': isDiscounting
        , 'crawl_url': crawlUrl?.isEmpty == true ? null : crawlUrl
        })
        .eq('id', id);
  }

  Future<void> deleteBrand(String id) async {
    await _client.from('brands').delete().eq('id', id);
  }

  // ── Storage ──────────────────────────────────────────────────────────────────

  static const _logoBucket = 'brand-logos';

  /// 브랜드 로고를 Storage에 업로드하고 public URL을 반환한다.
  /// [extension]은 'jpg' / 'png' / 'webp' 등 (점 제외).
  Future<String> uploadBrandLogo(
    String brandId
  , Uint8List bytes
  , String extension
  ) async {
    final path        = 'logos/$brandId.$extension';
    final contentType = _extToMime(extension);
    await _client.storage
        .from(_logoBucket)
        .uploadBinary(
          path
        , bytes
        , fileOptions: FileOptions(contentType: contentType, upsert: true)
        );
    return _client.storage.from(_logoBucket).getPublicUrl(path);
  }

  Future<void> updateBrandLogoUrl(String brandId, String? url) async {
    await _client
        .from('brands')
        .update({'logo_url': url})
        .eq('id', brandId);
  }

  static String _extToMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/jpeg';
    }
  }

  // ── BrandCategories ──────────────────────────────────────────────────────────

  Future<void> assignBrandToCategory(
    String brandId
  , String categoryId
  ) async {
    await _client.from('brand_categories').upsert({
      'brand_id': brandId
    , 'category_id': categoryId
    });
  }

  Future<void> removeBrandFromCategory(
    String brandId
  , String categoryId
  ) async {
    await _client
        .from('brand_categories')
        .delete()
        .eq('brand_id', brandId)
        .eq('category_id', categoryId);
  }

  // ── DiscountHistory ──────────────────────────────────────────────────────────

  Future<List<DiscountHistory>> fetchRealHistoryForBrands(
    List<String> brandIds
  ) async {
    if (brandIds.isEmpty) return [];
    final data = await _client
        .from('discount_history')
        .select('id, brand_id, start_date, end_date, discount_rate, is_ai_predicted, label')
        .inFilter('brand_id', brandIds)
        .eq('is_ai_predicted', false)
        .order('start_date');
    return (data as List<dynamic>)
        .map((e) => DiscountHistory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 특정 브랜드의 모든 할인 기간 (실제 + 예측) 조회
  Future<List<DiscountHistory>> fetchDiscountsForBrand(String brandId) async {
    final data = await _client
        .from('discount_history')
        .select('id, brand_id, start_date, end_date, discount_rate, is_ai_predicted, label')
        .eq('brand_id', brandId)
        .order('start_date', ascending: false);
    return (data as List<dynamic>)
        .map((e) => DiscountHistory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DiscountHistory?> predictNextDiscount(String brandId) async {
    try {
      final response = await _client.functions.invoke(
        'predict-discount'
      , body: {'brand_id': brandId}
      );
      if (response.data == null) return null;
      final map = Map<String, dynamic>.from(response.data as Map);
      if (map.containsKey('error')) {
        debugPrint('[SupabaseService] predictNextDiscount error for $brandId: ${map['error']}');
        return null;
      }
      return DiscountHistory(
        id: 'ai_${brandId}_${DateTime.now().millisecondsSinceEpoch}'
      , brandId: brandId
      , startDate: DateTime.parse(map['start_date'] as String)
      , endDate: DateTime.parse(map['end_date'] as String)
      , discountRate: (map['discount_rate'] as num).toDouble()
      , isAiPredicted: true
      );
    } catch (e, st) {
      debugPrint('[SupabaseService] predictNextDiscount failed for $brandId: $e\n$st');
      return null;
    }
  }
}

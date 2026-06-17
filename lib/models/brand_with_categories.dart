import 'brand.dart';
import 'category.dart';

class BrandWithCategories {
  final String id;
  final String name;
  final String? logoUrl;
  final bool isDiscounting;
  final String? crawlUrl;
  final List<Category> categories;

  const BrandWithCategories({
    required this.id
  , required this.name
  , this.logoUrl
  , required this.isDiscounting
  , this.crawlUrl
  , required this.categories
  });

  Brand get brand => Brand(id: id, name: name, logoUrl: logoUrl, isDiscounting: isDiscounting);

  /// brands.select('id, name, logo_url, is_discounting, crawl_url, brand_categories(categories(id, name))')
  factory BrandWithCategories.fromJson(Map<String, dynamic> json) {
    final rawList = json['brand_categories'] as List<dynamic>? ?? [];
    final categories = rawList
        .map((bc) {
          final c = bc['categories'];
          if (c == null) return null;
          return Category.fromJson(c as Map<String, dynamic>);
        })
        .whereType<Category>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return BrandWithCategories(
      id: json['id'] as String
    , name: json['name'] as String
    , logoUrl: json['logo_url'] as String?
    , isDiscounting: json['is_discounting'] as bool
    , crawlUrl: json['crawl_url'] as String?
    , categories: categories
    );
  }
}

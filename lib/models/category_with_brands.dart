import 'brand.dart';

class CategoryWithBrands {
  final String id;
  final String name;
  final List<Brand> brands;

  const CategoryWithBrands({
    required this.id
  , required this.name
  , required this.brands
  });

  /// PostgREST 중첩 select 결과 파싱
  /// categories.select('id, name, brand_categories(brands(...))')
  factory CategoryWithBrands.fromJson(Map<String, dynamic> json) {
    final rawList = json['brand_categories'] as List<dynamic>? ?? [];
    final brands = rawList
        .map((bc) {
          final b = bc['brands'];
          if (b == null) return null;
          return Brand.fromJson(b as Map<String, dynamic>);
        })
        .whereType<Brand>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return CategoryWithBrands(
      id: json['id'] as String
    , name: json['name'] as String
    , brands: brands
    );
  }
}

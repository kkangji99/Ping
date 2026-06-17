class Category {
  final String id;
  final String name;

  const Category({
    required this.id
  , required this.name
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String
  , name: json['name'] as String
  );

  Map<String, dynamic> toJson() => {
    'id': id
  , 'name': name
  };

  @override
  String toString() => 'Category(id: $id, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

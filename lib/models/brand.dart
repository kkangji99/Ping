class Brand {
  final String id;
  final String name;
  final String? logoUrl;
  final bool isDiscounting;

  const Brand({
    required this.id
  , required this.name
  , this.logoUrl
  , required this.isDiscounting
  });

  Brand copyWith({
    String? id
  , String? name
  , String? logoUrl
  , bool? isDiscounting
  }) => Brand(
    id: id ?? this.id
  , name: name ?? this.name
  , logoUrl: logoUrl ?? this.logoUrl
  , isDiscounting: isDiscounting ?? this.isDiscounting
  );

  factory Brand.fromJson(Map<String, dynamic> json) => Brand(
    id: json['id'] as String
  , name: json['name'] as String
  , logoUrl: json['logo_url'] as String?
  , isDiscounting: json['is_discounting'] as bool
  );

  Map<String, dynamic> toJson() => {
    'id': id
  , 'name': name
  , 'logo_url': logoUrl
  , 'is_discounting': isDiscounting
  };

  @override
  String toString() =>
      'Brand(id: $id, name: $name, isDiscounting: $isDiscounting)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Brand && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

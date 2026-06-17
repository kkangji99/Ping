class DiscountHistory {
  final String  id;
  final String  brandId;
  final DateTime startDate;
  final DateTime endDate;
  final double  discountRate; // 0.0 ~ 1.0
  final bool    isAiPredicted;
  final String? label; // 이벤트 이름 (예: '여름 세일', '멤버십 위크')

  const DiscountHistory({
    required this.id
  , required this.brandId
  , required this.startDate
  , required this.endDate
  , required this.discountRate
  , this.isAiPredicted = false
  , this.label
  });

  factory DiscountHistory.fromJson(Map<String, dynamic> json) => DiscountHistory(
    id:            json['id'] as String
  , brandId:       json['brand_id'] as String
  , startDate:     DateTime.parse(json['start_date'] as String)
  , endDate:       DateTime.parse(json['end_date'] as String)
  , discountRate:  (json['discount_rate'] as num).toDouble()
  , isAiPredicted: json['is_ai_predicted'] as bool? ?? false
  , label:         json['label'] as String?
  );

  Map<String, dynamic> toJson() => {
    'id':            id
  , 'brand_id':      brandId
  , 'start_date':    startDate.toIso8601String()
  , 'end_date':      endDate.toIso8601String()
  , 'discount_rate': discountRate
  , 'is_ai_predicted': isAiPredicted
  , 'label':         label
  };

  @override
  String toString() =>
      'DiscountHistory(brandId: $brandId, ${startDate.toLocal()} ~ ${endDate.toLocal()}'
      ', rate: ${(discountRate * 100).toStringAsFixed(0)}%'
      ', label: $label'
      ', aiPredicted: $isAiPredicted)';
}

class NotificationRecord {
  final String   id;
  final String   brandId;
  final String   brandName;
  final String   title;
  final String   body;
  final DateTime scheduledAt; // 알림이 실제로 울리는 시각
  final DateTime createdAt;   // 예약한 시각
  bool           isRead;

  NotificationRecord({
    required this.id
  , required this.brandId
  , required this.brandName
  , required this.title
  , required this.body
  , required this.scheduledAt
  , required this.createdAt
  , this.isRead = false
  });

  factory NotificationRecord.fromJson(Map<String, dynamic> j) => NotificationRecord(
    id:          j['id'] as String
  , brandId:     j['brandId'] as String
  , brandName:   j['brandName'] as String
  , title:       j['title'] as String
  , body:        j['body'] as String
  , scheduledAt: DateTime.parse(j['scheduledAt'] as String)
  , createdAt:   DateTime.parse(j['createdAt'] as String)
  , isRead:      j['isRead'] as bool? ?? false
  );

  Map<String, dynamic> toJson() => {
    'id':          id
  , 'brandId':     brandId
  , 'brandName':   brandName
  , 'title':       title
  , 'body':        body
  , 'scheduledAt': scheduledAt.toIso8601String()
  , 'createdAt':   createdAt.toIso8601String()
  , 'isRead':      isRead
  };
}

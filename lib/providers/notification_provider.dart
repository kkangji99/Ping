import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_record.dart';

// ── NotificationProvider ──────────────────────────────────────────────────────
// 브랜드별 알림 on/off 상태 + 알림 이력 관리

class NotificationProvider extends ChangeNotifier {
  static const _enablePrefix  = 'notif_';
  static const _historyKey    = 'notif_history';
  static const _historyMaxAge = Duration(days: 7);

  final Map<String, bool>    _enabled = {};
  final List<NotificationRecord> _history = [];
  bool _loaded = false;

  // ── 초기 로드 ────────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    // 브랜드별 알림 설정 복원
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_enablePrefix) && key != _historyKey) {
        _enabled[key.substring(_enablePrefix.length)] =
            prefs.getBool(key) ?? false;
      }
    }

    // 알림 이력 복원 + 7일 이상 지난 항목 제거
    final raw = prefs.getString(_historyKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      final cutoff = DateTime.now().subtract(_historyMaxAge);
      _history.addAll(
        list
          .map((e) => NotificationRecord.fromJson(e as Map<String, dynamic>))
          .where((r) => r.scheduledAt.isAfter(cutoff))
      );
      // 오래된 항목 제거 후 다시 저장
      await _saveHistory(prefs);
    }

    _loaded = true;
    notifyListeners();
  }

  // ── 브랜드 알림 설정 ──────────────────────────────────────────────────────────

  bool isEnabled(String brandId) => _enabled[brandId] ?? false;

  Future<void> setEnabled(String brandId, bool enabled) async {
    _enabled[brandId] = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_enablePrefix$brandId', enabled);
  }

  Future<void> toggle(String brandId) async {
    await setEnabled(brandId, !isEnabled(brandId));
  }

  // ── 알림 이력 ────────────────────────────────────────────────────────────────

  /// 최신순 정렬된 이력
  List<NotificationRecord> get history =>
      List.unmodifiable(_history..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt)));

  /// 읽지 않은 알림 수 (scheduledAt이 과거인 것만 카운트)
  int get unreadCount {
    final now = DateTime.now();
    return _history.where((r) => !r.isRead && r.scheduledAt.isBefore(now)).length;
  }

  Future<void> addRecord(NotificationRecord record) async {
    // 동일 id 중복 방지
    _history.removeWhere((r) => r.id == record.id);
    _history.add(record);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _saveHistory(prefs);
  }

  Future<void> markAllRead() async {
    for (final r in _history) {
      r.isRead = true;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _saveHistory(prefs);
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<void> _saveHistory(SharedPreferences prefs) async {
    await prefs.setString(
      _historyKey
    , jsonEncode(_history.map((r) => r.toJson()).toList())
    );
  }
}

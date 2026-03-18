import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:voice_ink/services/database_service.dart';

class StatsService {
  StatsService._();
  static final instance = StatsService._();

  final Map<String, String> _cache = {};

  // Keys
  static const _kWordsToday = 'words_today';
  static const _kWordsThisMonth = 'words_this_month';
  static const _kWordsTotal = 'words_total';
  static const _kCurrentStreak = 'current_streak';
  static const _kBestStreak = 'best_streak';
  static const _kLastActiveDate = 'last_active_date';
  static const _kLastActiveMonth = 'last_active_month';
  static const _kTranscriptionsToday = 'transcriptions_today';

  // --- Getters ---

  int get wordsToday => int.tryParse(_cache[_kWordsToday] ?? '') ?? 0;
  int get wordsThisMonth => int.tryParse(_cache[_kWordsThisMonth] ?? '') ?? 0;
  int get wordsTotal => int.tryParse(_cache[_kWordsTotal] ?? '') ?? 0;
  int get currentStreak => int.tryParse(_cache[_kCurrentStreak] ?? '') ?? 0;
  int get bestStreak => int.tryParse(_cache[_kBestStreak] ?? '') ?? 0;
  int get transcriptionsToday =>
      int.tryParse(_cache[_kTranscriptionsToday] ?? '') ?? 0;

  // --- Initialisation ---

  Future<void> init() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query('user_stats');
    _cache.clear();
    for (final row in rows) {
      _cache[row['key'] as String] = row['value'] as String;
    }

    // Seed defaults for any missing keys
    final defaults = <String, String>{
      _kWordsToday: '0',
      _kWordsThisMonth: '0',
      _kWordsTotal: '0',
      _kCurrentStreak: '0',
      _kBestStreak: '0',
      _kLastActiveDate: '',
      _kLastActiveMonth: '',
      _kTranscriptionsToday: '0',
    };

    for (final entry in defaults.entries) {
      if (!_cache.containsKey(entry.key)) {
        _cache[entry.key] = entry.value;
        await _setStat(entry.key, entry.value);
      }
    }

    debugPrint('[StatsService] Loaded ${_cache.length} stats');
  }

  // --- Core ---

  Future<void> recordTranscription({
    required int wordCount,
    int durationMs = 0,
  }) async {
    final todayStr = _todayString();
    final monthStr = _currentMonthString();

    // Date changed → reset daily stats & update streak
    if (!_isToday(_cache[_kLastActiveDate] ?? '')) {
      _updateStreak(_cache[_kLastActiveDate] ?? '');
      _cache[_kWordsToday] = '0';
      _cache[_kTranscriptionsToday] = '0';
    }

    // Month changed → reset monthly stats
    if (!_isCurrentMonth(_cache[_kLastActiveMonth] ?? '')) {
      _cache[_kWordsThisMonth] = '0';
    }

    // Increment counters
    _cache[_kWordsToday] = '${wordsToday + wordCount}';
    _cache[_kWordsThisMonth] = '${wordsThisMonth + wordCount}';
    _cache[_kWordsTotal] = '${wordsTotal + wordCount}';
    _cache[_kTranscriptionsToday] = '${transcriptionsToday + 1}';

    // Update best streak
    if (currentStreak > bestStreak) {
      _cache[_kBestStreak] = '$currentStreak';
    }

    // Stamp active date / month
    _cache[_kLastActiveDate] = todayStr;
    _cache[_kLastActiveMonth] = monthStr;

    // Persist everything
    await _saveAll();
  }

  Future<Map<String, dynamic>> getStatsSnapshot() async {
    return <String, dynamic>{
      'wordsToday': wordsToday,
      'wordsThisMonth': wordsThisMonth,
      'wordsTotal': wordsTotal,
      'currentStreak': currentStreak,
      'bestStreak': bestStreak,
      'transcriptionsToday': transcriptionsToday,
      'lastActiveDate': _cache[_kLastActiveDate] ?? '',
      'lastActiveMonth': _cache[_kLastActiveMonth] ?? '',
    };
  }

  // --- Streak logic ---

  void _updateStreak(String lastDateStr) {
    if (_isYesterday(lastDateStr)) {
      _cache[_kCurrentStreak] = '${currentStreak + 1}';
    } else if (lastDateStr.isEmpty) {
      _cache[_kCurrentStreak] = '1';
    } else {
      // Gap > 1 day — streak resets
      _cache[_kCurrentStreak] = '1';
    }
  }

  // --- Date helpers ---

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
  }

  String _currentMonthString() {
    final now = DateTime.now();
    return '${now.year}-${_pad(now.month)}';
  }

  bool _isToday(String dateStr) => dateStr == _todayString();

  bool _isYesterday(String dateStr) {
    if (dateStr.isEmpty) return false;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yStr = '${yesterday.year}-${_pad(yesterday.month)}-${_pad(yesterday.day)}';
    return dateStr == yStr;
  }

  bool _isCurrentMonth(String monthStr) => monthStr == _currentMonthString();

  String _pad(int n) => n.toString().padLeft(2, '0');

  // --- DB helpers ---

  Future<void> _setStat(String key, String value) async {
    final db = await DatabaseService.instance.database;
    await db.insert(
      'user_stats',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _getStat(String key) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'user_stats',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _saveAll() async {
    for (final entry in _cache.entries) {
      await _setStat(entry.key, entry.value);
    }
  }
}

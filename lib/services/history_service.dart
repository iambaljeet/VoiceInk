import 'package:voice_ink/services/database_service.dart';

/// Manages transcription history storage and retrieval.
class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  static const String _table = 'transcription_history';

  bool isEnabled = false;

  Future<void> init() async {
    // Placeholder for future setup.
  }

  Future<int> saveTranscription({
    required String rawText,
    required String cleanedText,
    required int wordCount,
    int durationMs = 0,
    String? modelUsed,
    String? language,
  }) async {
    if (!isEnabled) return -1;

    final db = await DatabaseService.instance.database;
    final id = await db.insert(_table, {
      'raw_text': rawText,
      'cleaned_text': cleanedText,
      'word_count': wordCount,
      'duration_ms': durationMs,
      'model_used': modelUsed,
      'language': language,
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> getHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await DatabaseService.instance.database;
    return db.query(
      _table,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Map<String, dynamic>>> searchHistory(String query) async {
    final db = await DatabaseService.instance.database;
    return db.query(
      _table,
      where: 'cleaned_text LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> deleteEntry(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await DatabaseService.instance.database;
    await db.delete(_table);
  }

  Future<int> totalCount() async {
    final db = await DatabaseService.instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS count FROM $_table');
    return result.first['count'] as int;
  }
}

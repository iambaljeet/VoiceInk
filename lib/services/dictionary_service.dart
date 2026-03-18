import 'dart:math';

import 'package:voice_ink/services/database_service.dart';

class DictionaryService {
  DictionaryService._();
  static final instance = DictionaryService._();

  static const _table = 'dictionary_terms';
  static const _fuzzyThreshold = 0.85;

  /// Master toggle — when false, applyReplacements is a no-op.
  bool isEnabled = false;

  List<Map<String, dynamic>> _cachedTerms = [];

  List<Map<String, dynamic>> get allTerms => List.unmodifiable(_cachedTerms);

  // Symbol shortcut patterns (case-insensitive).
  static final _symbolPatterns = [
    (RegExp(r'\bhashtag\s+(\S+)', caseSensitive: false), r'#$1'),
    (RegExp(r'\bat\s+(\S+)', caseSensitive: false), r'@$1'),
    (RegExp(r'\bdollar\s+(\S+)', caseSensitive: false), r'\$$1'),
  ];

  /// Load all terms from the database into the in-memory cache.
  Future<void> init() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(_table, orderBy: 'id ASC');
    _cachedTerms = rows.map((r) {
      return <String, dynamic>{
        'id': r['id'] as int,
        'sourceValue': r['source_value'] as String,
        'destinationValue': r['destination_value'] as String,
        'isEnabled': (r['is_enabled'] as int) == 1,
      };
    }).toList();
  }

  /// Insert a new term. Returns the auto-generated id.
  Future<int> addTerm(String source, String destination) async {
    final db = await DatabaseService.instance.database;
    final id = await db.insert(_table, {
      'source_value': source,
      'destination_value': destination,
      'is_enabled': 1,
    });
    _cachedTerms.add({
      'id': id,
      'sourceValue': source,
      'destinationValue': destination,
      'isEnabled': true,
    });
    return id;
  }

  /// Update an existing term's source and destination values.
  Future<void> updateTerm(int id, String source, String destination) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      _table,
      {'source_value': source, 'destination_value': destination},
      where: 'id = ?',
      whereArgs: [id],
    );
    final idx = _cachedTerms.indexWhere((t) => t['id'] == id);
    if (idx != -1) {
      _cachedTerms[idx] = {
        ..._cachedTerms[idx],
        'sourceValue': source,
        'destinationValue': destination,
      };
    }
  }

  /// Delete a term by id.
  Future<void> deleteTerm(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _cachedTerms.removeWhere((t) => t['id'] == id);
  }

  /// Toggle the is_enabled flag for a term.
  Future<void> toggleTerm(int id, bool enabled) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      _table,
      {'is_enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    final idx = _cachedTerms.indexWhere((t) => t['id'] == id);
    if (idx != -1) {
      _cachedTerms[idx] = {..._cachedTerms[idx], 'isEnabled': enabled};
    }
  }

  // ---------------------------------------------------------------------------
  // Text replacement
  // ---------------------------------------------------------------------------

  /// Apply dictionary replacements to [text].
  ///
  /// Returns the input unchanged when the service is disabled.
  String applyReplacements(String text) {
    if (!isEnabled) return text;

    // 1. Symbol shortcuts (applied on the full string first).
    var result = text;
    for (final (pattern, replacement) in _symbolPatterns) {
      result = result.replaceAllMapped(
        pattern,
        (m) => m[0]!.replaceAll(pattern, replacement),
      );
    }

    // Collect enabled terms once for the word-level pass.
    final enabledTerms =
        _cachedTerms.where((t) => t['isEnabled'] == true).toList();
    if (enabledTerms.isEmpty) return result;

    // 2. Word-level matching.
    final words = result.split(' ');
    final buffer = <String>[];

    for (final word in words) {
      if (word.isEmpty) {
        buffer.add(word);
        continue;
      }

      // Strip trailing punctuation so it doesn't interfere with matching.
      final punctMatch = RegExp(r'^(.*?)([^\w]*)$').firstMatch(word);
      final core = punctMatch?.group(1) ?? word;
      final trailing = punctMatch?.group(2) ?? '';

      if (core.isEmpty) {
        buffer.add(word);
        continue;
      }

      final replacement = _findReplacement(core, enabledTerms);
      buffer.add(replacement != null ? '$replacement$trailing' : word);
    }

    return buffer.join(' ');
  }

  /// Find the best replacement for [word] among [terms].
  ///
  /// Tries exact (case-insensitive) match first, then fuzzy.
  String? _findReplacement(String word, List<Map<String, dynamic>> terms) {
    final lower = word.toLowerCase();

    // Exact match (case-insensitive).
    for (final t in terms) {
      if ((t['sourceValue'] as String).toLowerCase() == lower) {
        return t['destinationValue'] as String;
      }
    }

    // Fuzzy match — pick highest similarity above threshold.
    String? bestDestination;
    var bestScore = 0.0;

    for (final t in terms) {
      final score = similarity(lower, (t['sourceValue'] as String).toLowerCase());
      if (score >= _fuzzyThreshold && score > bestScore) {
        bestScore = score;
        bestDestination = t['destinationValue'] as String;
      }
    }

    return bestDestination;
  }

  // ---------------------------------------------------------------------------
  // Levenshtein helpers
  // ---------------------------------------------------------------------------

  /// Classic DP Levenshtein distance.
  static int levenshteinDistance(String a, String b) {
    final n = a.length;
    final m = b.length;

    if (n == 0) return m;
    if (m == 0) return n;

    // Use two rows instead of a full matrix for O(min(n,m)) space.
    var prev = List<int>.generate(m + 1, (j) => j);
    var curr = List<int>.filled(m + 1, 0);

    for (var i = 1; i <= n; i++) {
      curr[0] = i;
      for (var j = 1; j <= m; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = min(
          min(curr[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    return prev[m];
  }

  /// Similarity between two strings (0.0 – 1.0).
  static double similarity(String a, String b) {
    final maxLen = max(a.length, b.length);
    if (maxLen == 0) return 1.0;
    return 1.0 - (levenshteinDistance(a, b) / maxLen);
  }
}

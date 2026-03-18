enum WritingStyle {
  verbatim(
    label: 'Verbatim',
    description: 'Raw output, no cleanup whatsoever',
  ),
  clean(
    label: 'Clean',
    description: 'Filler removal, punctuation, and capitalization',
  ),
  formal(
    label: 'Formal',
    description: 'Full sentences, proper capitalization, expanded contractions',
  ),
  chat(
    label: 'Chat',
    description: 'Lowercase, minimal punctuation, casual tone',
  );

  const WritingStyle({required this.label, required this.description});

  final String label;
  final String description;

  // ── Storage helpers ──────────────────────────────────────────────────

  String toStorageString() => name;

  static WritingStyle fromString(String value) {
    return WritingStyle.values.firstWhere(
      (style) => style.name == value,
      orElse: () => WritingStyle.clean,
    );
  }

  // ── Transform ────────────────────────────────────────────────────────

  String apply(String text) {
    return switch (this) {
      WritingStyle.verbatim => text,
      WritingStyle.clean => text,
      WritingStyle.formal => _applyFormal(text),
      WritingStyle.chat => _applyChat(text),
    };
  }

  // ── Formal ───────────────────────────────────────────────────────────

  static final _contractions = <String, String>{
    "don't": 'do not',
    "can't": 'cannot',
    "won't": 'will not',
    "I'm": 'I am',
    "it's": 'it is',
    "we're": 'we are',
    "they're": 'they are',
    "you're": 'you are',
    "isn't": 'is not',
    "aren't": 'are not',
    "wasn't": 'was not',
    "weren't": 'were not',
    "doesn't": 'does not',
    "didn't": 'did not',
    "haven't": 'have not',
    "hasn't": 'has not',
    "couldn't": 'could not',
    "wouldn't": 'would not',
    "shouldn't": 'should not',
  };

  static final _contractionPattern = RegExp(
    _contractions.keys.map(RegExp.escape).join('|'),
    caseSensitive: false,
  );

  static String _applyFormal(String text) {
    if (text.isEmpty) return text;

    // Expand contractions (preserve original casing of first character).
    var result = text.replaceAllMapped(_contractionPattern, (match) {
      final found = match.group(0)!;
      final key = _contractions.keys.firstWhere(
        (k) => k.toLowerCase() == found.toLowerCase(),
      );
      final replacement = _contractions[key]!;
      // If the original started with uppercase, capitalize the replacement.
      if (found[0] == found[0].toUpperCase()) {
        return replacement[0].toUpperCase() + replacement.substring(1);
      }
      return replacement;
    });

    // Capitalize the first letter of each sentence.
    result = result.replaceAllMapped(
      RegExp(r'(^|[.!?]\s+)(\p{Ll})', unicode: true),
      (m) => '${m.group(1)}${m.group(2)!.toUpperCase()}',
    );

    // Ensure the text ends with punctuation.
    final trimmed = result.trimRight();
    if (trimmed.isNotEmpty && !RegExp(r'[.!?]$').hasMatch(trimmed)) {
      result = '$trimmed.${result.substring(trimmed.length)}';
    }

    return result;
  }

  // ── Chat ─────────────────────────────────────────────────────────────

  static final _chatAbbreviations = <String, String>{
    'because': 'cuz',
    'going to': 'gonna',
    'want to': 'wanna',
    'got to': 'gotta',
    'kind of': 'kinda',
    'sort of': 'sorta',
  };

  static final _chatAbbrPattern = RegExp(
    _chatAbbreviations.keys.map(RegExp.escape).join('|'),
    caseSensitive: false,
  );

  static String _applyChat(String text) {
    if (text.isEmpty) return text;

    var result = text.toLowerCase();

    // Apply chat abbreviations.
    result = result.replaceAllMapped(_chatAbbrPattern, (match) {
      final key = _chatAbbreviations.keys.firstWhere(
        (k) => k.toLowerCase() == match.group(0)!.toLowerCase(),
      );
      return _chatAbbreviations[key]!;
    });

    // Remove periods at end of sentences but keep ? and !
    result = result.replaceAllMapped(
      RegExp(r'\.(\s|$)'),
      (m) => m.group(1)!,
    );

    return result;
  }
}

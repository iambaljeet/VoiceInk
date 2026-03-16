/// Post-processes transcribed text:
/// - Removes filler words (um, uh, etc.)
/// - Converts spoken punctuation to symbols
/// - Auto-capitalizes sentences
/// - Trims extra whitespace
class TextCleanupService {
  bool removeFillers = true;
  bool convertPunctuation = true;
  bool autoCapitalize = true;

  static const _fillerWords = [
    r'\bum\b',
    r'\buh\b',
    r'\buhh\b',
    r'\bumm\b',
    r'\bhmm\b',
    r'\blike\b(?=\s*,)',
    r'\byou know\b(?=\s*,)',
    r'\bso\b(?=\s*,\s)',
    r'\bI mean\b(?=\s*,)',
  ];

  static const _punctuationMap = {
    r'\bperiod\b': '.',
    r'\bfull stop\b': '.',
    r'\bcomma\b': ',',
    r'\bquestion mark\b': '?',
    r'\bexclamation mark\b': '!',
    r'\bexclamation point\b': '!',
    r'\bcolon\b': ':',
    r'\bsemicolon\b': ';',
    r'\bsemi colon\b': ';',
    r'\bnew line\b': '\n',
    r'\bnewline\b': '\n',
    r'\bnew paragraph\b': '\n\n',
    r'\bopen quote\b': '"',
    r'\bclose quote\b': '"',
    r'\bopen paren\b': '(',
    r'\bclose paren\b': ')',
    r'\bdash\b': '—',
    r'\bhyphen\b': '-',
    r'\bellipsis\b': '…',
  };

  String process(String text) {
    if (text.isEmpty) return text;

    var result = text;

    if (removeFillers) {
      result = _removeFillerWords(result);
    }

    if (convertPunctuation) {
      result = _convertPunctuation(result);
    }

    if (autoCapitalize) {
      result = _autoCapitalize(result);
    }

    // Clean up extra whitespace
    result = result.replaceAll(RegExp(r'  +'), ' ').trim();
    // Clean up space before punctuation
    result = result.replaceAll(RegExp(r'\s+([.,;:!?])'), r'$1');

    return result;
  }

  String _removeFillerWords(String text) {
    var result = text;
    for (final pattern in _fillerWords) {
      result = result.replaceAll(
        RegExp(pattern, caseSensitive: false),
        '',
      );
    }
    return result;
  }

  String _convertPunctuation(String text) {
    var result = text;
    for (final entry in _punctuationMap.entries) {
      result = result.replaceAll(
        RegExp(entry.key, caseSensitive: false),
        entry.value,
      );
    }
    return result;
  }

  String _autoCapitalize(String text) {
    if (text.isEmpty) return text;

    final buffer = StringBuffer();
    var capitalizeNext = true;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (capitalizeNext && char.trim().isNotEmpty) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
      }
      if (char == '.' || char == '!' || char == '?' || char == '\n') {
        capitalizeNext = true;
      }
    }

    return buffer.toString();
  }
}

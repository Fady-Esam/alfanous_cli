import 'uthmani_map.dart' as u;

class NlpUtils {
  // Arabic Punctuation
  static const String COMMA = '\u060C';
  static const String SEMICOLON = '\u061B';
  static const String QUESTION = '\u061F';

  // Hamza variants
  static const String HAMZA = '\u0621';
  static const String ALEF_MADDA = '\u0622';
  static const String ALEF_HAMZA_ABOVE = '\u0623';
  static const String WAW_HAMZA = '\u0624';
  static const String ALEF_HAMZA_BELOW = '\u0625';
  static const String YEH_HAMZA = '\u0626';

  // Core Letters
  static const String ALEF = '\u0627';
  static const String BEH = '\u0628';
  static const String TEH_MARBUTA = '\u0629';
  static const String TEH = '\u062A';
  static const String THEH = '\u062B';
  static const String JEEM = '\u062C';
  static const String HAH = '\u062D';
  static const String KHAH = '\u062E';
  static const String DAL = '\u062F';
  static const String THAL = '\u0630';
  static const String REH = '\u0631';
  static const String ZAIN = '\u0632';
  static const String SEEN = '\u0633';
  static const String SHEEN = '\u0634';
  static const String SAD = '\u0635';
  static const String DAD = '\u0636';
  static const String TAH = '\u0637';
  static const String ZAH = '\u0638';
  static const String AIN = '\u0639';
  static const String GHAIN = '\u063A';
  static const String TATWEEL = '\u0640';
  static const String FEH = '\u0641';
  static const String QAF = '\u0642';
  static const String KAF = '\u0643';
  static const String LAM = '\u0644';
  static const String MEEM = '\u0645';
  static const String NOON = '\u0646';
  static const String HEH = '\u0647';
  static const String WAW = '\u0648';
  static const String ALEF_MAKSURA = '\u0649';
  static const String YEH = '\u064A';

  // Extension/Above variants
  static const String MADDA_ABOVE = '\u0653';
  static const String HAMZA_ABOVE = '\u0654';
  static const String HAMZA_BELOW = '\u0655';

  // Quranic specific marks
  static const String MINI_ALEF = '\u0670';
  static const String ALEF_WASLA = '\u0671';
  static const String SMALL_HIGH_JEEM = '\u06DA';
  static const String SMALL_HIGH_LIGATURE = '\u06D6';

  // Diacritics (Harakat)
  static const String FATHATAN = '\u064B';
  static const String DAMMATAN = '\u064C';
  static const String KASRATAN = '\u064D';
  static const String FATHA = '\u064E';
  static const String DAMMA = '\u064F';
  static const String KASRA = '\u0650';
  static const String SHADDA = '\u0651';
  static const String SUKUN = '\u0652';

  // Small Letters
  static const String SMALL_ALEF = '\u0670';
  static const String SMALL_WAW = '\u06E5';
  static const String SMALL_YEH = '\u06E6';

  // Ligatures
  static const String LAM_ALEF = '\uFEFB';
  static const String LAM_ALEF_HAMZA_ABOVE = '\uFEF7';
  static const String LAM_ALEF_HAMZA_BELOW = '\uFEF9';
  static const String LAM_ALEF_MADDA_ABOVE = '\uFEF5';

  // Groupings
  static const List<String> _ALEFAT = [
    ALEF_MADDA,
    ALEF_HAMZA_ABOVE,
    ALEF_HAMZA_BELOW,
    HAMZA_ABOVE,
    HAMZA_BELOW
  ];
  static const List<String> _HAMZAT = [WAW_HAMZA, YEH_HAMZA];
  static const List<String> _LAMALEFAT = [
    LAM_ALEF,
    LAM_ALEF_HAMZA_ABOVE,
    LAM_ALEF_HAMZA_BELOW,
    LAM_ALEF_MADDA_ABOVE
  ];
  static const String _TASHKEEL_REGEX =
      '[$FATHATAN$DAMMATAN$KASRATAN$FATHA$DAMMA$KASRA$SUKUN$SHADDA]';

  /// Removes all Harakat (diacritics) and Shadda from the text.
  static String stripTashkeel(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(_TASHKEEL_REGEX), '');
  }

  /// Removes the tatweel (kashida) character from the text.
  static String stripTatweel(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(TATWEEL, '');
  }

  /// Replaces Lam-Alef ligatures with standalone Lam and Alef.
  static String normalizeLamalef(String text) {
    if (text.isEmpty) return text;
    String s = text;
    for (var letter in _LAMALEFAT) {
      s = s.replaceAll(letter, LAM + ALEF);
    }
    return s;
  }

  /// Converts all `_ALEFAT` variants to Alef and all `_HAMZAT` variants to Hamza.
  static String normalizeHamza(String text) {
    if (text.isEmpty) return text;
    String s = text;
    for (var letter in _ALEFAT) {
      s = s.replaceAll(letter, ALEF);
    }
    for (var letter in _HAMZAT) {
      s = s.replaceAll(letter, HAMZA);
    }
    return s;
  }

  /// Converts Teh Marbuta to Heh, and Alef Maksura to Yeh.
  static String normalizeSpellerrors(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(TEH_MARBUTA, HEH).replaceAll(ALEF_MAKSURA, YEH);
  }

  /// Strips small Quranic symbols (e.g., Mini Alef, Small Yeh/Waw, High Jeem)
  /// and replaces Alef Wasla with a standard Alef.
  static String normalizeUthmaniSymbols(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAll(MINI_ALEF, '')
        .replaceAll(SMALL_YEH, '')
        .replaceAll(SMALL_WAW, '')
        .replaceAll(ALEF_WASLA, ALEF)
        .replaceAll(SMALL_HIGH_LIGATURE, '')
        .replaceAll(SMALL_HIGH_JEEM, '');
  }

  static String normalizeArabicText(String text,
      {bool stripSpellErrors = false, bool stripHamza = false}) {
    if (text.trim().isEmpty) return '';

    String normalized = text;
    normalized = stripTashkeel(normalized);
    normalized = stripTatweel(normalized);
    normalized = normalizeLamalef(normalized);
    if (stripHamza) {
      normalized = normalizeHamza(normalized);
    }
    if (stripSpellErrors) {
      normalized = normalizeSpellerrors(normalized);
    }
    normalized = normalizeUthmaniSymbols(normalized);

    return normalized;
  }

  static const List<String> _ARABIC_PREFIXES = [
    '',
    'و',
    'ف',
    'ب',
    'ك',
    'ل',
    'لل',
    'ال',
    'وال',
    'فال',
    'بال',
    'كال'
  ];

  /// Generates the strict sensitive words for the fallback LIKE query.
  /// It keeps the exact user input, and ONLY adds explicit Uthmani constants.
  static List<String> getStrictFallbackWords(String rawWord) {
    if (rawWord.isEmpty) return [];
    final result = <String>{rawWord};

    final aggressiveStem =
        normalizeArabicText(rawWord, stripSpellErrors: true, stripHamza: true);

    u.standardToUthmaniMap.forEach((key, value) {
      final normKey =
          normalizeArabicText(key, stripSpellErrors: true, stripHamza: true);
      if (aggressiveStem == normKey) {
        result.add(normalizeArabicText(value));
      } else if (aggressiveStem.endsWith(normKey)) {
        final prefix =
            aggressiveStem.substring(0, aggressiveStem.length - normKey.length);
        if (_ARABIC_PREFIXES.contains(prefix)) {
          result.add(prefix + normalizeArabicText(value));
        }
      }
    });

    return result.toList();
  }

  /// Generates the broad FTS5 permutations (insensitive stem + all prefixes)
  /// because SQLite FTS5 lacks left-wildcard (*word) support.
  static List<String> getFtsPrefixExpansions(String rawWord) {
    if (rawWord.isEmpty) return [];

    // 1. FTS5 requires heavily stripped text
    final baseStem =
        normalizeArabicText(rawWord, stripSpellErrors: true, stripHamza: true);
    final result = <String>{};

    // 2. Generate all prefixed combinations of the stem
    for (final prefix in _ARABIC_PREFIXES) {
      result.add(prefix + baseStem);
    }

    return result.toList();
  }

  /// Sanitizes input by trimming leading/trailing whitespace.
  static String sanitizeForQuery(String rawInput) {
    return rawInput.trim();
  }
}

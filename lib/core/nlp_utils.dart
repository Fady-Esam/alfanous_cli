class NlpUtils {
  static String removeDiacritics(String query) {
    final RegExp diacriticsRegExp = RegExp(r'[\u064B-\u065F\u0670]');
    return query.replaceAll(diacriticsRegExp, '');
  }

  static String normalizeArabicText(String query) {
    if (query.trim().isEmpty) return '';

    String normalized = removeDiacritics(query);

    normalized = normalized.replaceAll(RegExp(r'[أإآ]'), 'ا');

    normalized = normalized.replaceAll('ى', 'ي');

    normalized = normalized.replaceAll('ة', 'ه');

    normalized = normalized.replaceAll('ؤ', 'و');

    normalized = normalized.replaceAll('ئ', 'ي');

    return normalized;
  }

  static String sanitizeForQuery(String rawInput) {
    return rawInput.trim();
  }
}

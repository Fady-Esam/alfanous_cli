import 'package:sqlite3/sqlite3.dart';
import 'nlp_utils.dart';

sealed class ExpandedGroup {
  const ExpandedGroup();
}

final class IncludeGroup extends ExpandedGroup {
  final List<String> ftsWords; // FTS words
  final List<String> fallbackWords; // Highlights + Fallback LIKE targets
  const IncludeGroup(this.ftsWords, this.fallbackWords);
}

final class ExcludeGroup extends ExpandedGroup {
  final List<String> words;
  const ExcludeGroup(this.words);
}

final class PhraseGroup extends ExpandedGroup {
  final String phrase;
  const PhraseGroup(this.phrase);
}

class ParsedQuery {
  final String matchExpression;
  final List<String> highlightTerms;
  final List<List<String>> fallbackGroups;
  final bool isEmpty;

  const ParsedQuery({
    required this.matchExpression,
    required this.highlightTerms,
    required this.fallbackGroups,
    this.isEmpty = false,
  });

  factory ParsedQuery.empty() => const ParsedQuery(
      matchExpression: '',
      highlightTerms: [],
      fallbackGroups: [],
      isEmpty: true);
}

class QueryParser {
  final Database _db;

  static const _logicalOperators = {'AND', 'OR', 'NOT'};

  static const Set<String> _stopWords = {
    'أن',
    'أو',
    'إذا',
    'إلا',
    'إلى',
    'إن',
    'الذي',
    'الذين',
    'بما',
    'به',
    'ثم',
    'ذلك',
    'شيء',
    'على',
    'عليهم',
    'عن',
    'في',
    'فيها',
    'كان',
    'كانوا',
    'كل',
    'كنتم',
    'لا',
    'لكم',
    'لم',
    'له',
    'لهم',
    'ما',
    'من',
    'هذا',
    'هم',
    'هو',
    'وإن',
    'ولا',
    'وما',
    'ومن',
    'وهو',
    'يا',
  };

  QueryParser(this._db);

  Future<ParsedQuery> parse(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return ParsedQuery.empty();

    // Standardize implicit operators for tokenization
    final spacedQuery = trimmed
        .replaceAll('+', ' + ')
        .replaceAll('|', ' | ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final rawTokens = RegExp(r'"[^"]*"|[^\s]+')
        .allMatches(spacedQuery)
        .map((m) => m.group(0)!)
        .toList();

    final fallbackGroups = <List<String>>[];
    final allHighlights = <String>{};
    final expressionParts = <String>[];

    for (int i = 0; i < rawTokens.length; i++) {
      final token = rawTokens[i];

      // Explicit Operators mapping
      if (token == '+') {
        _appendOperator(expressionParts, 'AND');
        continue;
      } else if (token == '|') {
        _appendOperator(expressionParts, 'OR');
        continue;
      }

      bool isNot = false;
      String actualToken = token;

      if (token.startsWith('-') && token.length > 1) {
        isNot = true;
        actualToken = token.substring(1);
      }

      final group = await _expandToken(actualToken);
      if (group == null) continue;

      // Extract highlights strictly from normalized inputs
      if (group is IncludeGroup) {
        final variants = group.fallbackWords
            .map((w) => w.replaceAll(RegExp(r'[\*\?]'), ''))
            .toList();
        allHighlights.addAll(variants);
        if (!isNot) fallbackGroups.add(variants);
      } else if (group is PhraseGroup) {
        final phrase =
            group.phrase.split(' ').map(NlpUtils.normalizeArabicText).join(' ');
        allHighlights.add(phrase);
        if (!isNot) fallbackGroups.add([phrase]);
      }

      final expr = _buildGroupExpression(group);
      if (expr.isNotEmpty) {
        if (isNot) {
          _appendOperator(expressionParts, 'NOT');
        } else if (expressionParts.isNotEmpty &&
            !_logicalOperators.contains(expressionParts.last)) {
          // Implicit AND if previous part was a term (FTS5 default is AND, but making it explicit ensures safety)
          _appendOperator(expressionParts, 'AND');
        }
        expressionParts.add(expr);
      }
    }

    if (expressionParts.isEmpty) return ParsedQuery.empty();

    // Syntax Safety: Clean up dangling operators from the end
    while (expressionParts.isNotEmpty &&
        _logicalOperators.contains(expressionParts.last)) {
      expressionParts.removeLast();
    }

    // Syntax Safety: Clean up dangling operators from the beginning
    while (expressionParts.isNotEmpty &&
        (expressionParts.first == 'AND' || expressionParts.first == 'OR')) {
      expressionParts.removeAt(0);
    }

    // Safety fallback
    if (expressionParts.isEmpty) return ParsedQuery.empty();

    final finalMatch = '{normalized} : (${expressionParts.join(' ').trim()})';
    //print('\n[DEBUG] Generated FTS5 MATCH Expression: $finalMatch\n');

    return ParsedQuery(
      matchExpression: finalMatch,
      highlightTerms: allHighlights.where((w) => w.isNotEmpty).toList(),
      fallbackGroups: fallbackGroups,
    );
  }

  void _appendOperator(List<String> parts, String operator) {
    if (parts.isEmpty && operator != 'NOT') return; // Cannot start with AND/OR
    if (parts.isNotEmpty && _logicalOperators.contains(parts.last)) {
      // Avoid consecutive operators by overriding the last one if it's not a NOT
      if (parts.last == 'NOT' && operator == 'NOT') return;
      parts[parts.length - 1] = operator;
    } else {
      parts.add(operator);
    }
  }

  Future<ExpandedGroup?> _expandToken(String token) async {
    // 1. Exact Phrase handling "word word"
    if (token.startsWith('"') && token.endsWith('"') && token.length > 2) {
      final inner = token.substring(1, token.length - 1).trim();
      if (inner.isEmpty) return null;
      // Normalize entire phrase
      final normalizedPhrase = inner
          .split(' ')
          .map((w) => NlpUtils.normalizeArabicText(w))
          .join(' ');
      if (normalizedPhrase.trim().isEmpty) return null;
      return PhraseGroup(normalizedPhrase);
    }

    // Identify prefixed expansion operators
    bool isSynonym = false;
    bool isAntonym = false;
    bool isDerivRoot = false;
    bool isDerivLevel1 = false;

    String stem = token;

    if (token.startsWith('~')) {
      isSynonym = true;
      stem = token.substring(1);
    } else if (token.startsWith('#')) {
      isAntonym = true;
      stem = token.substring(1);
    } else if (token.startsWith('<<')) {
      isDerivRoot = true;
      stem = token.substring(2);
    } else if (token.startsWith('<')) {
      isDerivLevel1 = true;
      stem = token.substring(1);
    }

    // Handle wildcards
    final hasStar = stem.endsWith('*');
    final cleaned = hasStar ? stem.substring(0, stem.length - 1) : stem;
    final hasLeadQ = cleaned.startsWith('?');
    stem = hasLeadQ ? cleaned.substring(1) : cleaned;

    // MANDATORY NLP PIPELINE INTEGRATION
    final norm = NlpUtils.normalizeArabicText(stem);
    if (norm.isEmpty) return null;

    if (_stopWords.contains(norm) && !hasStar) return null;

    final wordsSet = <String>{norm};

    if (isSynonym) {
      wordsSet.addAll(await _synonymExpansion(norm));
    } else if (isAntonym) {
      wordsSet.addAll(await _antonymExpansion(norm));
    } else if (isDerivRoot) {
      wordsSet.addAll(await _rootDerivationExpansion(norm));
    } else if (isDerivLevel1) {
      wordsSet.addAll(await _derivationExpansion(norm));
    }

    // THE FIX:
    // The FTS5 `aya_fts` table was populated using Python's aggressive analyzer
    // which strips EVERYTHING (no hamza, no Uthmani, no diacritics).
    // The fallback `LIKE` search uses `standard` which PRESERVES these letters!

    final ftsWords = <String>{};
    final fallbackWords = <String>{};

    for (final w in wordsSet) {
      ftsWords.addAll(NlpUtils.getFtsPrefixExpansions(w));
      fallbackWords.addAll(NlpUtils.getStrictFallbackWords(w));
    }

    final finalFTSWords = ftsWords
        .map((w) => '${hasLeadQ ? '?' : ''}$w${hasStar ? '*' : ''}')
        .toList();

    if (finalFTSWords.isEmpty) return null;
    return IncludeGroup(finalFTSWords, fallbackWords.toList());
  }

  String _buildGroupExpression(ExpandedGroup group) {
    switch (group) {
      case PhraseGroup group:
        return '"${_escapeWord(group.phrase)}"';

      case ExcludeGroup group:
        return group.words.map((w) => 'NOT "${_escapeWord(w)}"').join(' ');

      case IncludeGroup group:
        if (group.ftsWords.isEmpty) return '';
        if (group.ftsWords.length == 1) {
          final word = group.ftsWords.first;
          return (word.contains('*') || word.contains('?'))
              ? word // FTS5 native prefix, do not quote
              : '"${_escapeWord(word)}"';
        } else {
          final inner = group.ftsWords.map((w) {
            return (w.contains('*') || w.contains('?'))
                ? w
                : '"${_escapeWord(w)}"';
          }).join(' OR ');
          return '($inner)';
        }
    }
  }

  String _escapeWord(String word) => word.replaceAll('"', '""');

  Future<List<String>> _synonymExpansion(String normalizedWord) async {
    // Implement synonym hooks here via SQLite dictionaries if available
    return [normalizedWord];
  }

  Future<List<String>> _antonymExpansion(String normalizedWord) async {
    return [normalizedWord];
  }

  Future<List<String>> _derivationExpansion(String normalizedWord) async {
    return [normalizedWord];
  }

  Future<List<String>> _rootDerivationExpansion(String normalizedWord) async {
    return [normalizedWord];
  }
}

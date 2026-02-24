import 'package:sqlite3/sqlite3.dart';
import 'nlp_utils.dart';

sealed class ExpandedGroup {
  const ExpandedGroup();
}

final class IncludeGroup extends ExpandedGroup {
  final List<String> words;
  const IncludeGroup(this.words);
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
  final bool isEmpty;

  const ParsedQuery({
    required this.matchExpression,
    required this.highlightTerms,
    this.isEmpty = false,
  });

  factory ParsedQuery.empty() =>
      const ParsedQuery(matchExpression: '', highlightTerms: [], isEmpty: true);
}

class QueryParser {
  final Database _db;

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

  /// The entry point for converting a raw user query string into a highly optimized FTS MATCH segment.
  Future<ParsedQuery> parse(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return ParsedQuery.empty();

    // The `+` operator must act as a STRICT segment divider for FTS5 AND logic.
    final segments = trimmed
        .split('+')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return ParsedQuery.empty();

    final allHighlights = <String>{};
    final segmentExpressions = <String>[];

    for (final segment in segments) {
      final rawTokens = RegExp(r'[^\s"]+|"[^"]*"')
          .allMatches(segment)
          .map((m) => m.group(0)!)
          .where((t) => t.isNotEmpty)
          .toList();

      if (rawTokens.isEmpty) continue;

      final groups = <ExpandedGroup>[];
      for (final token in rawTokens) {
        final group = _expandTokenSync(token);
        if (group != null) groups.add(group);
      }

      if (groups.isEmpty) continue;

      final highlightTerms = groups
          .whereType<IncludeGroup>()
          .expand((g) => g.words)
          .map((w) => w.endsWith('*') ? w.substring(0, w.length - 1) : w)
          .where((w) => w.isNotEmpty && !w.startsWith('?'))
          .toSet();

      allHighlights.addAll(highlightTerms);

      final includeGroups = groups.whereType<IncludeGroup>().toList();
      if (includeGroups.isNotEmpty) {
        final allStops = includeGroups.every(
          (g) => g.words.every(_stopWords.contains),
        );
        if (allStops) continue;
      }

      final segmentExpr = _buildSegmentExpression(groups);
      if (segmentExpr.isNotEmpty && segmentExpr != '""') {
        segmentExpressions.add(segmentExpr);
      }
    }

    if (segmentExpressions.isEmpty) return ParsedQuery.empty();

    final joinedExpression = segmentExpressions.join(' AND ');
    final finalMatch = '{normalized} $joinedExpression';

    return ParsedQuery(
      matchExpression: finalMatch,
      highlightTerms: allHighlights.toList(),
    );
  }

  ExpandedGroup? _expandTokenSync(String token) {
    if (token.startsWith('"') && token.endsWith('"') && token.length > 2) {
      final inner = token.substring(1, token.length - 1).trim();
      if (inner.isEmpty) return null;
      final normWords = inner
          .split(RegExp(r'\s+'))
          .map(NlpUtils.normalizeArabicText)
          .where((w) => w.isNotEmpty)
          .toList();
      if (normWords.isEmpty) return null;
      return PhraseGroup(normWords.join(' '));
    }

    if (token.startsWith('-') && token.length > 1) {
      final word = NlpUtils.normalizeArabicText(token.substring(1));
      if (word.isEmpty) return null;
      return ExcludeGroup([word]);
    }

    if (token.startsWith('~') && token.length > 1) {
      final word = NlpUtils.normalizeArabicText(token.substring(1));
      if (word.isEmpty) return null;
      final expanded = _synonymExpansion(word);
      return IncludeGroup({word, ...expanded}.toList());
    }

    if (token.startsWith('#') && token.length > 1) {
      final word = NlpUtils.normalizeArabicText(token.substring(1));
      if (word.isEmpty) return null;
      final expanded = _antonymExpansion(word);
      return IncludeGroup({word, ...expanded}.toList());
    }

    if (token.startsWith('<<') && token.length > 2) {
      final word = NlpUtils.normalizeArabicText(token.substring(2));
      if (word.isEmpty) return null;
      final expanded = _rootDerivationExpansion(word);
      return IncludeGroup({word, ...expanded}.toList());
    }

    if (token.startsWith('<') && token.length > 1) {
      final word = NlpUtils.normalizeArabicText(token.substring(1));
      if (word.isEmpty) return null;
      final expanded = _derivationExpansion(word);
      return IncludeGroup({word, ...expanded}.toList());
    }

    final hasStar = token.endsWith('*');
    final cleaned = hasStar ? token.substring(0, token.length - 1) : token;
    final hasLeadQ = cleaned.startsWith('?');
    final stem = hasLeadQ ? cleaned.substring(1) : cleaned;

    final norm = NlpUtils.normalizeArabicText(stem);
    if (norm.isEmpty) return null;

    final result = '${hasLeadQ ? '?' : ''}$norm${hasStar ? '*' : ''}';
    return IncludeGroup([result]);
  }

  String _buildSegmentExpression(List<ExpandedGroup> groups) {
    final positives = <String>[];
    final negatives = <String>[];

    for (final group in groups) {
      switch (group) {
        case PhraseGroup group:
          final escaped = _escapeWord(group.phrase);
          positives.add('"$escaped"');
          break;

        case ExcludeGroup group:
          for (final word in group.words) {
            negatives.add('NOT "${_escapeWord(word)}"');
          }
          break;

        case IncludeGroup group:
          if (group.words.isEmpty) break;
          if (group.words.length == 1) {
            final word = group.words.first;
            if (word.contains('*') || word.contains('?')) {
              positives.add(word);
            } else {
              positives.add('"${_escapeWord(word)}"');
            }
          } else {
            final inner = group.words.map((w) {
              if (w.contains('*') || w.contains('?')) {
                return w;
              }
              return '"${_escapeWord(w)}"';
            }).join(' OR ');
            positives.add('($inner)');
          }
          break;
      }
    }

    if (positives.isEmpty && negatives.isNotEmpty) {
      return '""';
    }

    final body = [...positives, ...negatives].join(' ');
    if (positives.length + negatives.length > 1) {
      return '($body)';
    }
    return body;
  }

  String _escapeWord(String word) => word.replaceAll('"', '""');

  List<String> _synonymExpansion(String normalizedWord) {
    try {
      final results = <String>{};

      PreparedStatement? stmt1;
      PreparedStatement? stmt2;
      try {
        stmt1 = _db.prepare('SELECT synonym FROM synonym WHERE word = ?');
        for (final row in stmt1.select([normalizedWord])) {
          final norm =
              NlpUtils.normalizeArabicText(row['synonym'] as String? ?? '');
          if (norm.isNotEmpty) results.add(norm);
        }
      } catch (_) {
      } finally {
        stmt1?.dispose();
      }

      try {
        stmt2 = _db.prepare('SELECT word FROM synonym WHERE synonym = ?');
        for (final row in stmt2.select([normalizedWord])) {
          final norm =
              NlpUtils.normalizeArabicText(row['word'] as String? ?? '');
          if (norm.isNotEmpty) results.add(norm);
        }
      } catch (_) {
      } finally {
        stmt2?.dispose();
      }

      return results.toList();
    } catch (_) {
      return [];
    }
  }

  List<String> _antonymExpansion(String normalizedWord) {
    try {
      final results = <String>{};

      PreparedStatement? stmt1;
      PreparedStatement? stmt2;
      try {
        stmt1 = _db.prepare('SELECT antonym FROM antonym WHERE word = ?');
        for (final row in stmt1.select([normalizedWord])) {
          final norm =
              NlpUtils.normalizeArabicText(row['antonym'] as String? ?? '');
          if (norm.isNotEmpty) results.add(norm);
        }
      } catch (_) {
      } finally {
        stmt1?.dispose();
      }

      try {
        stmt2 = _db.prepare('SELECT word FROM antonym WHERE antonym = ?');
        for (final row in stmt2.select([normalizedWord])) {
          final norm =
              NlpUtils.normalizeArabicText(row['word'] as String? ?? '');
          if (norm.isNotEmpty) results.add(norm);
        }
      } catch (_) {
      } finally {
        stmt2?.dispose();
      }

      return results.toList();
    } catch (_) {
      return [];
    }
  }

  List<String> _derivationExpansion(String normalizedWord) {
    try {
      PreparedStatement? stmt;
      try {
        stmt = _db.prepare(
            'SELECT lemma FROM derivation WHERE word_form = ? LIMIT 1');
        final lemmaRows = stmt.select([normalizedWord]);
        if (lemmaRows.isNotEmpty) {
          final lemma = lemmaRows.first['lemma'] as String? ?? '';
          if (lemma.isNotEmpty) {
            stmt.dispose();
            return _wordsByLemma(lemma);
          }
        }
      } catch (_) {
      } finally {
        stmt?.dispose();
      }

      try {
        stmt = _db
            .prepare('SELECT root FROM derivation WHERE word_form = ? LIMIT 1');
        final rootRows = stmt.select([normalizedWord]);
        if (rootRows.isNotEmpty) {
          final root = rootRows.first['root'] as String? ?? '';
          if (root.isNotEmpty) {
            stmt.dispose();
            return _wordsByRoot(root);
          }
        }
      } catch (_) {
      } finally {
        stmt?.dispose();
      }

      return [];
    } catch (_) {
      return [];
    }
  }

  List<String> _rootDerivationExpansion(String normalizedWord) {
    try {
      PreparedStatement? stmt;
      try {
        stmt = _db
            .prepare('SELECT root FROM derivation WHERE word_form = ? LIMIT 1');
        final rootRows = stmt.select([normalizedWord]);
        if (rootRows.isNotEmpty) {
          final root = rootRows.first['root'] as String? ?? '';
          if (root.isNotEmpty) {
            stmt.dispose();
            return _wordsByRoot(root);
          }
        }
      } catch (_) {
      } finally {
        stmt?.dispose();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  List<String> _wordsByLemma(String lemma) {
    PreparedStatement? stmt;
    try {
      stmt = _db
          .prepare('SELECT DISTINCT word_form FROM derivation WHERE lemma = ?');
      final rows = stmt.select([lemma]);
      return rows
          .map((r) =>
              NlpUtils.normalizeArabicText(r['word_form'] as String? ?? ''))
          .where((w) => w.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    } finally {
      stmt?.dispose();
    }
  }

  List<String> _wordsByRoot(String root) {
    PreparedStatement? stmt;
    try {
      stmt = _db
          .prepare('SELECT DISTINCT word_form FROM derivation WHERE root = ?');
      final rows = stmt.select([root]);
      return rows
          .map((r) =>
              NlpUtils.normalizeArabicText(r['word_form'] as String? ?? ''))
          .where((w) => w.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    } finally {
      stmt?.dispose();
    }
  }
}

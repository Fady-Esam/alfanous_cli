import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'exceptions.dart';
import 'models.dart';
import 'query_parser.dart';

enum SortMode { score, mushaf, tanzil, subject, ayaLength }

class SearchResultItem {
  final AyahModel aya;
  final List<String> highlightTerms;
  const SearchResultItem({required this.aya, required this.highlightTerms});
}

class SearchEngine {
  late final Database _db;
  late final QueryParser _parser;

  SearchEngine(String dbPath) {
    _validateDbPath(dbPath);
    try {
      _db = sqlite3.open(dbPath);
      _parser = QueryParser(_db);
    } catch (e) {
      throw DatabaseInitializationException(
          'Failed to open the database at path: $dbPath. Inner Error: $e');
    }
  }

  void _validateDbPath(String dbPath) {
    if (dbPath == ':memory:') return;

    if (!File(dbPath).existsSync()) {
      throw DatabaseNotFoundException(
        'The specified quran.db file does not exist or lacks read permissions.',
        dbPath,
      );
    }
  }

  Future<int> getTotalSearchCount(String query) async {
    final parsed = await _parser.parse(query);
    if (parsed.isEmpty) return 0;

    PreparedStatement? stmt;
    try {
      stmt = _db.prepare(
          'SELECT COUNT(*) AS count FROM aya_fts WHERE aya_fts MATCH ?');
      final result = stmt.select([parsed.matchExpression]);
      if (result.isNotEmpty) {
        return result.first['count'] as int? ?? 0;
      }
      return 0;
    } on SqliteException catch (e) {
      if (_isFtsQueryError(e)) {
        return _fallbackCount(parsed.highlightTerms);
      }
      return 0;
    } finally {
      stmt?.dispose();
    }
  }

  int _fallbackCount(List<String> highlightTerms) {
    final fallbackWord = highlightTerms.isNotEmpty ? highlightTerms.first : '';
    if (fallbackWord.isEmpty) return 0;

    PreparedStatement? stmt;
    try {
      stmt = _db
          .prepare('SELECT COUNT(*) AS count FROM aya WHERE standard LIKE ?');
      final result = stmt.select(['%$fallbackWord%']);
      if (result.isNotEmpty) {
        return result.first['count'] as int? ?? 0;
      }
    } catch (_) {
    } finally {
      stmt?.dispose();
    }
    return 0;
  }

  Future<List<SearchResultItem>> searchAyat(
    String query, {
    int limit = 50,
    int offset = 0,
    SortMode sort = SortMode.score,
  }) async {
    final parsed = await _parser.parse(query);
    if (parsed.isEmpty) return const [];

    final orderBy = _orderByClause(sort);

    PreparedStatement? stmt;
    try {
      stmt = _db.prepare('''
        SELECT 
          a.sura_id, a.aya_id, a.standard AS text, a.sura_name
        FROM aya a
        JOIN aya_fts f ON a.gid = f.rowid
        WHERE aya_fts MATCH ?
        $orderBy
        LIMIT ? OFFSET ?
      ''');

      final resultSet = stmt.select([parsed.matchExpression, limit, offset]);
      final items = <SearchResultItem>[];

      for (final row in resultSet) {
        final rowMap = <String, dynamic>{};
        for (var key in row.keys) {
          rowMap[key] = row[key];
        }
        items.add(SearchResultItem(
          aya: AyahModel.fromMap(rowMap),
          highlightTerms: parsed.highlightTerms,
        ));
      }

      return items;
    } on SqliteException catch (e) {
      if (_isFtsQueryError(e)) {
        return _fallbackSearch(parsed.highlightTerms, limit, offset);
      }
      throw QueryExecutionException('Failed to execute FTS5 search.', e);
    } finally {
      stmt?.dispose();
    }
  }

  List<SearchResultItem> _fallbackSearch(
      List<String> highlightTerms, int limit, int offset) {
    final fallbackWord = highlightTerms.isNotEmpty ? highlightTerms.first : '';
    if (fallbackWord.isEmpty) return [];

    PreparedStatement? stmt;
    try {
      stmt = _db.prepare('''
        SELECT 
          sura_id, aya_id, standard AS text, sura_name
        FROM aya
        WHERE standard LIKE ?
        LIMIT ? OFFSET ?
      ''');
      final resultSet = stmt.select(['%$fallbackWord%', limit, offset]);
      final items = <SearchResultItem>[];

      for (final row in resultSet) {
        final rowMap = <String, dynamic>{};
        for (var key in row.keys) {
          rowMap[key] = row[key];
        }
        items.add(SearchResultItem(
          aya: AyahModel.fromMap(rowMap),
          highlightTerms: highlightTerms,
        ));
      }

      return items;
    } catch (_) {
      return [];
    } finally {
      stmt?.dispose();
    }
  }

  String _orderByClause(SortMode sort) {
    switch (sort) {
      case SortMode.score:
        return 'ORDER BY f.rank';
      case SortMode.mushaf:
        return 'ORDER BY a.gid ASC';
      case SortMode.tanzil:
        return 'ORDER BY a.sura_id ASC, a.aya_id ASC';
      case SortMode.subject:
        return 'ORDER BY a.chapter ASC, a.topic ASC, a.subtopic ASC';
      case SortMode.ayaLength:
        return 'ORDER BY a.aya_letters_nb ASC, a.aya_words_nb ASC';
    }
  }

  bool _isFtsQueryError(SqliteException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('fts5') ||
        msg.contains('syntax error') ||
        msg.contains('malformed');
  }

  void dispose() {
    try {
      _db.dispose();
    } catch (_) {}
  }
}

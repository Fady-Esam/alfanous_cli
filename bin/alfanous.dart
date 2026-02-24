import 'dart:io';
import 'package:args/args.dart';
import 'package:alfanous_core/alfanous_core.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show this help output');

  parser.addCommand('search')
    ..addOption('query',
        abbr: 'q', help: 'The search query string (e.g., "رحمة")')
    ..addOption('limit',
        abbr: 'l', defaultsTo: '10', help: 'Number of results to return')
    ..addOption('db',
        abbr: 'd', defaultsTo: 'quran.db', help: 'Path to sqlite database');

  try {
    final argResults = parser.parse(arguments);

    if (argResults['help'] as bool) {
      _printUsage(parser);
      return;
    }

    if (argResults.command == null || argResults.command!.name != 'search') {
      stdout.writeln(
          '\x1B[31mError: You must provide a command, e.g., "search".\x1B[0m');
      _printUsage(parser);
      exit(64);
    }

    final searchCmd = argResults.command!;
    final query = searchCmd['query'] ?? argResults['query'];
    final finalQuery = query as String?;

    if (finalQuery == null || finalQuery.trim().isEmpty) {
      stdout.writeln(
          '\x1B[31mError: Missing search query. Use --query or -q to specify.\x1B[0m');
      _printUsage(parser);
      exit(64);
    }

    final limitStr = searchCmd['limit'] ?? argResults['limit'];
    final limit = int.tryParse(limitStr.toString()) ?? 10;

    final dbPath = searchCmd['db'] ?? argResults['db'] as String;

    _executeSearch(dbPath, finalQuery, limit);
  } on FormatException catch (e) {
    stdout.writeln('\x1B[31mError parsing arguments: ${e.message}\x1B[0m');
    exit(64);
  } catch (e) {
    stdout.writeln('\x1B[31mAn unexpected CLI error occurred: $e\x1B[0m');
    exit(1);
  }
}

void _executeSearch(String dbPath, String rawQuery, int limit) async {
  SearchEngine? engine;
  try {
    engine = SearchEngine(dbPath);

    stdout.writeln('\n\x1B[36m[Alfanous Core CLI]\x1B[0m Requesting Search...');
    stdout.writeln(' Raw Input: "$rawQuery"');
    stdout.writeln(' Limit    : $limit');
    stdout.writeln(' --------------------------------------------------');

    final results = await engine.searchAyat(rawQuery, limit: limit);

    if (results.isEmpty) {
      stdout.writeln(' \x1B[33mNo results found.\x1B[0m\n');
    } else {
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        stdout.writeln(
            '\x1B[32m${i + 1}\x1B[0m. سورة ${r.aya.suraName} [آية ${r.aya.ayaId}]');
        stdout.writeln('   ${r.aya.text}\n');
      }
    }
  } on DatabaseNotFoundException catch (e) {
    _printError('Database Not Found', e.message,
        suggestion: 'Path Checked: ${e.attemptedPath}');
    exit(66);
  } on QueryExecutionException catch (e) {
    _printError('Query Execution Failed', e.message,
        suggestion: 'Inner error: ${e.originalError}');
    exit(70);
  } on DatabaseInitializationException catch (e) {
    _printError('Engine Initialization Failed', e.message);
    exit(70);
  } on AlfanousException catch (e) {
    _printError('Engine Error', e.message);
    exit(1);
  } catch (e, stack) {
    _printError('Fatal Error', 'An unhandled system error occurred.',
        suggestion: '$e\n$stack');
    exit(1);
  } finally {
    engine?.dispose();
  }
}

void _printError(String title, String message, {String? suggestion}) {
  stdout.writeln(
      '\n\x1B[31m======================================================\x1B[0m');
  stdout.writeln(' \x1B[31m❌ $title\x1B[0m');
  stdout.writeln(' $message');
  if (suggestion != null) {
    stdout.writeln(' \x1B[33m> $suggestion\x1B[0m');
  }
  stdout.writeln(
      '\x1B[31m======================================================\x1B[0m\n');
}

void _printUsage(ArgParser parser) {
  stdout.writeln('\nAlfanous - Thin CLI Binding for AlfanousEngine');
  stdout.writeln(
      'Usage: dart run bin/alfanous.dart search --query "<query>" [options]\n');
  stdout.writeln(parser.usage);
}

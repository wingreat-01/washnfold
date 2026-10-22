import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/draw_result.dart';
import '../models/lotto_game.dart';

class PcsoResultsException implements Exception {
  PcsoResultsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Results source strategy:
/// 1) If LOTTO_RESULTS_API_BASE_URL is configured, use the user's backend.
/// 2) On web, use the CORS-enabled historical snapshot (coverage is limited).
/// 3) On native platforms, query the official PCSO ASP.NET search form, then
///    fall back to the historical snapshot if PCSO is unavailable.
///
/// The historical snapshot is independently compiled and is NOT an official
/// PCSO API. Always verify numbers against PCSO before relying on them.
class PcsoResultsService {
  PcsoResultsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _configuredApiBase = String.fromEnvironment(
    'LOTTO_RESULTS_API_BASE_URL',
    defaultValue: '',
  );
  static final Uri pageUri =
      Uri.parse('https://www.pcso.gov.ph/SearchLottoResult.aspx');
  static final Uri _historicalUri = Uri.parse(
    'https://remo65588-boop.github.io/lottolens-ph-public-data/api/v1/results.json',
  );
  static const _timeout = Duration(seconds: 25);
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  List<DrawResult>? _historicalMemoryCache;

  Future<List<DrawResult>> fetchRecent(LottoGame game, {int days = 10}) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(Duration(days: days));
    return fetchRange(game, startDate: start, endDate: end);
  }

  /// Fetches a selected date range (inclusive), newest first.
  Future<List<DrawResult>> fetchRange(
    LottoGame game, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (start.isAfter(end)) {
      throw PcsoResultsException('The start date must be on or before the end date.');
    }
    if (end.difference(start).inDays > 3650) {
      throw PcsoResultsException('Please search a maximum of 10 years at a time.');
    }

    if (_configuredApiBase.trim().isNotEmpty) {
      return _fetchFromConfiguredApi(game, start, end);
    }

    if (!kIsWeb) {
      try {
        return await _fetchPcsoRange(game, start, end);
      } catch (e) {
        debugPrint('Direct PCSO request failed; trying historical snapshot: $e');
        try {
          return await _fetchHistoricalRange(game, start, end);
        } on PcsoResultsException catch (fallbackError) {
          throw PcsoResultsException(
            'PCSO could not be reached and the historical fallback failed. '
            'PCSO error: $e. Historical data: ${fallbackError.message}',
          );
        }
      }
    }

    return _fetchHistoricalRange(game, start, end);
  }

  Future<List<DrawResult>> _fetchFromConfiguredApi(
    LottoGame game, DateTime start, DateTime end) async {
    final base = Uri.parse(_configuredApiBase.endsWith('/')
        ? _configuredApiBase.substring(0, _configuredApiBase.length - 1)
        : _configuredApiBase);
    final uri = base.resolve('/api/results').replace(queryParameters: {
      'game': _gameKey(game),
      'from': _isoDate(start),
      'to': _isoDate(end),
    });
    final response = await _client.get(uri, headers: {'Accept': 'application/json'})
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw PcsoResultsException('Results backend returned HTTP ${response.statusCode}.');
    }
    return _parseApiPayload(response.body, game, start, end);
  }

  Future<List<DrawResult>> _fetchHistoricalRange(
    LottoGame game, DateTime start, DateTime end) async {
    try {
      _historicalMemoryCache ??= await _downloadHistoricalDataset();
      final results = _historicalMemoryCache!
          .where((r) => r.game == game &&
              !_dateOnly(r.drawDate).isBefore(start) &&
              !_dateOnly(r.drawDate).isAfter(end))
          .toList()
        ..sort((a, b) => b.drawDate.compareTo(a.drawDate));
      if (results.isEmpty) {
        throw PcsoResultsException(
          'No matching historical records were found. The public snapshot covers '
          'January 2, 2022 through July 20, 2026; newer results need the backend or PCSO.',
        );
      }
      return results;
    } on PcsoResultsException {
      rethrow;
    } on TimeoutException {
      throw PcsoResultsException('The historical results source timed out. Try again.');
    } catch (e, st) {
      debugPrint('Historical results fetch failed: $e\n$st');
      throw PcsoResultsException('Could not load the historical dataset (${e.runtimeType}).');
    }
  }

  Future<List<DrawResult>> _downloadHistoricalDataset() async {
    final response = await _client.get(_historicalUri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'LottoPatternPH/1.0',
    }).timeout(_timeout);
    if (response.statusCode != 200) {
      throw PcsoResultsException('Historical data source returned HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    final rows = _findRows(decoded);
    if (rows.isEmpty) {
      throw PcsoResultsException('The historical dataset format was not recognized.');
    }
    final parsed = <DrawResult>[];
    for (final row in rows) {
      final item = _parseDatasetRow(row);
      if (item != null) parsed.add(item);
    }
    if (parsed.isEmpty) {
      throw PcsoResultsException('No valid six-number draw records were found in the dataset.');
    }
    return parsed;
  }

  List<Map<String, dynamic>> _findRows(dynamic decoded) {
    if (decoded is List) {
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (decoded is Map) {
      for (final key in ['results', 'data', 'records', 'draws', 'items']) {
        final value = decoded[key];
        if (value is List) {
          return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    }
    return [];
  }

  DrawResult? _parseDatasetRow(Map<String, dynamic> row) {
    dynamic getValue(List<String> keys) {
      for (final key in keys) {
        if (row.containsKey(key) && row[key] != null) return row[key];
      }
      final normalized = <String, dynamic>{
        for (final entry in row.entries)
          entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''): entry.value,
      };
      for (final key in keys) {
        final value = normalized[key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')];
        if (value != null) return value;
      }
      return null;
    }

    final gameText = '${getValue(['game', 'gameId', 'game_id', 'gameKey', 'game_key', 'gameName', 'game_name', 'lottoGame', 'lotto_game']) ?? ''}'
        .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final game = _gameFromText(gameText);
    final dateValue = getValue(['drawDate', 'draw_date', 'date', 'datePht', 'date_pht', 'drawDatePht', 'draw_date_pht']);
    final numbersValue = getValue([
      'numbers', 'winningNumbers', 'winning_numbers', 'combination',
      'winningCombination', 'winning_combination', 'result', 'winningNumbersText', 'winning_numbers_text', 'numbersDrawn', 'numbers_drawn'
    ]);
    if (game == null || dateValue == null || numbersValue == null) return null;
    final date = _parseDate('$dateValue');
    final numbers = _parseNumbers(numbersValue);
    if (date == null || numbers.length != 6 ||
        numbers.any((n) => !game.isValidNumber(n)) || numbers.toSet().length != 6) {
      return null;
    }
    numbers.sort();
    return DrawResult(
      game: game,
      numbers: numbers,
      drawDate: date,
      jackpot: getValue(['jackpot', 'jackpotPrize', 'jackpot_prize'])?.toString(),
      winners: int.tryParse('${getValue(['winners', 'jackpotWinners', 'jackpot_winners']) ?? ''}'),
    );
  }

  List<int> _parseNumbers(dynamic value) {
    if (value is List) {
      return value.map((v) => int.tryParse('$v')).whereType<int>().toList();
    }
    final text = '$value';
    return RegExp(r'\d+').allMatches(text)
        .map((m) => int.tryParse(m.group(0)!))
        .whereType<int>().toList();
  }

  LottoGame? _gameFromText(String text) {
    if (text.contains('642')) return LottoGame.lotto642;
    if (text.contains('645')) return LottoGame.lotto645;
    if (text.contains('649')) return LottoGame.lotto649;
    if (text.contains('655')) return LottoGame.lotto655;
    if (text.contains('658')) return LottoGame.lotto658;
    return null;
  }

  Future<List<DrawResult>> _fetchPcsoRange(
    LottoGame game, DateTime start, DateTime end) async {
    final getResponse = await _client.get(pageUri, headers: _headers()).timeout(_timeout);
    if (getResponse.statusCode != 200) {
      throw PcsoResultsException('PCSO page returned ${getResponse.statusCode}.');
    }
    final cookie = _cookieFrom(getResponse.headers['set-cookie']);
    final doc = html_parser.parse(getResponse.body);
    final form = doc.querySelector('form');
    if (form == null) throw PcsoResultsException('PCSO page layout changed.');

    final body = <String, String>{};
    for (final input in form.querySelectorAll('input')) {
      final name = input.attributes['name'];
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (name == null || type == 'submit' || type == 'button') continue;
      body[name] = input.attributes['value'] ?? '';
    }
    for (final select in form.querySelectorAll('select')) {
      final name = select.attributes['name'];
      if (name == null) continue;
      final selected = select.querySelector('option[selected]') ?? select.querySelector('option');
      body[name] = selected?.attributes['value'] ?? '';
    }

    void setSelect(String suffix, List<String> candidates) {
      final select = form.querySelectorAll('select').firstWhere(
        (s) => (s.attributes['name'] ?? '').endsWith(suffix),
        orElse: () => throw PcsoResultsException('PCSO date/game controls changed.'),
      );
      final value = _matchOption(select, candidates);
      if (value == null) throw PcsoResultsException('PCSO does not offer the selected date.');
      body[select.attributes['name']!] = value;
    }

    void setDate(String prefix, DateTime date) {
      setSelect('ddl${prefix}Month', [_months[date.month - 1], '${date.month}']);
      setSelect('ddl${prefix}Date', ['${date.day}', date.day.toString().padLeft(2, '0')]);
      setSelect('ddl${prefix}Year', ['${date.year}']);
    }
    setDate('Start', start);
    setDate('End', end);

    final gameSelect = form.querySelectorAll('select').firstWhere(
      (s) => (s.attributes['name'] ?? '').endsWith('ddlSelectGame'),
      orElse: () => throw PcsoResultsException('PCSO game selector changed.'),
    );
    final token = RegExp(r'6/\d+').firstMatch(game.displayName)!.group(0)!;
    Element? gameOption;
    for (final option in gameSelect.querySelectorAll('option')) {
      if (RegExp('(^|[^0-9])${RegExp.escape(token)}([^0-9]|\$)').hasMatch(option.text)) {
        gameOption = option;
        break;
      }
    }
    if (gameOption == null) throw PcsoResultsException('${game.displayName} was not found on PCSO.');
    body[gameSelect.attributes['name']!] = gameOption.attributes['value'] ?? '';

    final submit = form.querySelectorAll('input').firstWhere(
      (i) => (i.attributes['name'] ?? '').endsWith('btnSearch'),
      orElse: () => throw PcsoResultsException('PCSO search button changed.'),
    );
    body[submit.attributes['name']!] = submit.attributes['value'] ?? 'Search';

    final postResponse = await _client.post(pageUri,
      headers: _headers(cookie: cookie), body: body).timeout(_timeout);
    if (postResponse.statusCode != 200) {
      throw PcsoResultsException('PCSO search returned ${postResponse.statusCode}.');
    }
    return _parsePcsoResults(postResponse.body, game);
  }

  List<DrawResult> _parsePcsoResults(String htmlBody, LottoGame game) {
    final doc = html_parser.parse(htmlBody);
    final dateRe = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})');
    final comboRe = RegExp(r'^\s*\d{1,2}(\s*-\s*\d{1,2}){5}\s*$');
    final results = <DrawResult>[];
    for (final row in doc.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td').map((c) => c.text.trim()).toList();
      if (cells.length < 3) continue;
      final combo = cells.firstWhere(comboRe.hasMatch, orElse: () => '');
      final dateText = cells.firstWhere(dateRe.hasMatch, orElse: () => '');
      if (combo.isEmpty || dateText.isEmpty) continue;
      final numbers = combo.split('-').map((s) => int.parse(s.trim())).toList();
      if (numbers.any((n) => !game.isValidNumber(n)) || numbers.toSet().length != 6) continue;
      numbers.sort();
      final match = dateRe.firstMatch(dateText)!;
      final date = DateTime(int.parse(match.group(3)!), int.parse(match.group(1)!), int.parse(match.group(2)!));
      final idx = cells.indexOf(dateText);
      results.add(DrawResult(
        game: game,
        numbers: numbers,
        drawDate: date,
        jackpot: idx + 1 < cells.length && cells[idx + 1].isNotEmpty ? cells[idx + 1] : null,
        winners: idx + 2 < cells.length ? int.tryParse(cells[idx + 2]) : null,
      ));
    }
    results.sort((a, b) => b.drawDate.compareTo(a.drawDate));
    return results;
  }

  List<DrawResult> _parseApiPayload(
      String body, LottoGame game, DateTime start, DateTime end) {
    final decoded = jsonDecode(body);
    final rows = _findRows(decoded);
    final output = <DrawResult>[];
    for (final row in rows) {
      final result = _parseDatasetRow(row);
      if (result != null && result.game == game &&
          !_dateOnly(result.drawDate).isBefore(start) &&
          !_dateOnly(result.drawDate).isAfter(end)) {
        output.add(result);
      }
    }
    output.sort((a, b) => b.drawDate.compareTo(a.drawDate));
    return output;
  }

  static String _gameKey(LottoGame game) => switch (game) {
    LottoGame.lotto642 => 'lotto-642',
    LottoGame.lotto645 => 'mega-lotto-645',
    LottoGame.lotto649 => 'super-lotto-649',
    LottoGame.lotto655 => 'grand-lotto-655',
    LottoGame.lotto658 => 'ultra-lotto-658',
  };

  static DateTime? _parseDate(String value) {
    final iso = DateTime.tryParse(value);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(value);
    if (us != null) return DateTime(int.parse(us.group(3)!), int.parse(us.group(1)!), int.parse(us.group(2)!));
    return null;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String? _matchOption(Element select, List<String> candidates) {
    for (final option in select.querySelectorAll('option')) {
      final text = option.text.trim().toLowerCase();
      final value = (option.attributes['value'] ?? '').trim().toLowerCase();
      for (final candidate in candidates) {
        if (text == candidate.toLowerCase() || value == candidate.toLowerCase()) {
          return option.attributes['value'] ?? option.text.trim();
        }
      }
    }
    return null;
  }

  static Map<String, String> _headers({String? cookie}) => {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) LottoPatternPH/1.0',
    'Accept': 'text/html,application/xhtml+xml',
    if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
  };

  static String? _cookieFrom(String? setCookie) {
    if (setCookie == null || setCookie.isEmpty) return null;
    return setCookie.split(RegExp(r',(?=\s*[^;,=\s]+=)'))
        .map((c) => c.split(';').first.trim()).join('; ');
  }

  void dispose() => _client.close();
}

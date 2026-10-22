import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/draw_result.dart';
import '../models/lotto_game.dart';
import '../services/pattern_analyzer.dart';
import '../services/pcso_results_service.dart';

/// Live PCSO results for the selected game, with the patterns found in the
/// latest draw and in the previous draw day.
class LatestResultsScreen extends StatefulWidget {
  const LatestResultsScreen({super.key, this.initialGame = LottoGame.lotto642});

  final LottoGame initialGame;

  @override
  State<LatestResultsScreen> createState() => _LatestResultsScreenState();
}

class _LatestResultsScreenState extends State<LatestResultsScreen> {
  static const _accent = Color(0xFF6254DF);
  static const _refreshEvery = Duration(minutes: 2);

  final _service = PcsoResultsService();
  final _analyzer = const PatternAnalyzer();
  final Map<LottoGame, List<DrawResult>> _cache = {};

  late LottoGame _game = widget.initialGame;
  Timer? _timer;
  bool _loading = false;
  String? _error;
  DateTime? _updatedAt;
  DateTime _historyFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _historyTo = DateTime.now();
  List<DrawResult>? _historyResults;
  String? _historyError;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
    // "Live": re-check PCSO every couple of minutes while this tab is open.
    _timer = Timer.periodic(_refreshEvery, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_loading) return;
    final game = _game;
    if (!silent || !_cache.containsKey(game)) setState(() => _loading = true);
    try {
      final results = await _service.fetchRecent(game);
      if (!mounted) return;
      setState(() {
        _cache[game] = results;
        if (game == _game) {
          _error = null;
          _updatedAt = DateTime.now();
        }
      });
    } on PcsoResultsException catch (e) {
      // Keep showing the last good data on a failed background refresh.
      if (mounted && game == _game && !(silent && _cache.containsKey(game))) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickHistoryDate({required bool from}) async {
    final initial = from ? _historyFrom : _historyTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1995, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: from ? 'Choose start date' : 'Choose end date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _historyFrom = picked;
      } else {
        _historyTo = picked;
      }
      _historyResults = null;
      _historyError = null;
    });
  }

  Future<void> _searchHistory() async {
    if (_historyFrom.isAfter(_historyTo)) {
      setState(() => _historyError = 'Start date must be on or before end date.');
      return;
    }
    setState(() {
      _historyLoading = true;
      _historyError = null;
      _historyResults = null;
    });
    try {
      final results = await _service.fetchRange(_game, startDate: _historyFrom, endDate: _historyTo);
      if (!mounted) return;
      setState(() {
        _historyResults = results;
        if (results.isEmpty) _historyError = 'No results were found for this game and date range.';
      });
    } on PcsoResultsException catch (e) {
      if (mounted) setState(() => _historyError = e.message);
    } catch (e) {
      if (mounted) setState(() => _historyError = 'Could not search historical results. Please try again.');
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  void _selectGame(LottoGame game) {
    if (game == _game) return;
    setState(() {
      _game = game;
      _error = null;
      _historyResults = null;
      _historyError = null;
      _updatedAt = _cache.containsKey(game) ? _updatedAt : null;
    });
    _load();
  }

  Future<void> _openOfficial() async {
    final ok = await launchUrl(PcsoResultsService.pageUri,
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open PCSO results.')),
      );
    }
  }

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _dateLabel(DateTime d) =>
      '${_wd[d.weekday - 1]}, ${_mo[d.month - 1]} ${d.day}, ${d.year}';

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final draws = _cache[_game] ?? const <DrawResult>[];
    final visibleHistory = _historyResults;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Latest Lotto Results'),
        actions: [
          IconButton(
            tooltip: 'Open official PCSO page',
            onPressed: _openOfficial,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    children: [
                      const _LiveDot(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _updatedAt == null
                              ? 'Connecting to PCSO…'
                              : 'Live · updated ${_two(_updatedAt!.hour)}:${_two(_updatedAt!.minute)} · pull to refresh',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      if (_loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in LottoGame.values)
                        ChoiceChip(
                          label: Text(g.displayName),
                          selected: g == _game,
                          onSelected: (_) => _selectGame(g),
                          selectedColor: const Color(0xFFECE9FF),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Search historical results', style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('Choose a game above, then select the draw date range.', style: TextStyle(color: muted, fontSize: 12)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: OutlinedButton.icon(
                                onPressed: _historyLoading ? null : () => _pickHistoryDate(from: true),
                                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                label: Text('From ${_two(_historyFrom.day)}/${_two(_historyFrom.month)}/${_historyFrom.year}'),
                              )),
                              const SizedBox(width: 8),
                              Expanded(child: OutlinedButton.icon(
                                onPressed: _historyLoading ? null : () => _pickHistoryDate(from: false),
                                icon: const Icon(Icons.event_rounded, size: 18),
                                label: Text('To ${_two(_historyTo.day)}/${_two(_historyTo.month)}/${_historyTo.year}'),
                              )),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _historyLoading ? null : _searchHistory,
                              icon: _historyLoading
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.search_rounded),
                              label: Text(_historyLoading ? 'Searching…' : 'Search selected dates'),
                            ),
                          ),
                          if (_historyError != null) ...[
                            const SizedBox(height: 10),
                            Text(_historyError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (visibleHistory != null) ...[
                    Text('HISTORICAL SEARCH · ${visibleHistory.length} RESULT${visibleHistory.length == 1 ? '' : 'S'}',
                      style: const TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < visibleHistory.length; i++) ...[
                      _drawCard(i == 0 ? 'Historical draw' : 'Historical draw ${i + 1}', visibleHistory[i]),
                      if (i < visibleHistory.length - 1) const SizedBox(height: 12),
                    ],
                  ] else if (_error != null && draws.isEmpty)
                    _ErrorCard(message: _error!, onRetry: _load, onOpen: _openOfficial)
                  else if (visibleHistory == null && draws.isEmpty && _loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (visibleHistory == null && draws.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'No ${_game.displayName} draws in the last 10 days.',
                          style: TextStyle(color: muted),
                        ),
                      ),
                    )
                  else if (visibleHistory == null && draws.isNotEmpty) ...[
                    _drawCard('Latest draw', draws.first),
                    if (draws.length > 1) ...[
                      const SizedBox(height: 14),
                      _drawCard(_previousLabel(draws), draws[1]),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFEFF7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Recent native-app results are requested from PCSO. Historical searches may use a third-party archived dataset if PCSO is unavailable; its snapshot ends July 20, 2026 and is not an official live feed. Always confirm winning numbers on the official PCSO website. Patterns are for reference only and do not predict future results.',
                      style: TextStyle(color: Color(0xFF6E6B86), fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _previousLabel(List<DrawResult> draws) {
    final latest = draws.first.drawDate;
    final prev = draws[1].drawDate;
    return latest.difference(prev).inDays == 1 ? 'Previous day' : 'Previous draw';
  }

  Widget _drawCard(String title, DrawResult draw) {
    final report = _analyzer.analyze(draw.numbers);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    String pairText(List<({int first, int second})> pairs) =>
        pairs.map((p) => '${_two(p.first)}–${_two(p.second)}').join(', ');

    final chips = <String>[
      if (report.plusTwo.isNotEmpty) 'Plus 2: ${pairText(report.plusTwo)}',
      if (report.twins.isNotEmpty) 'Twin: ${report.twins.map(_two).join(', ')}',
      if (report.reversed.isNotEmpty) 'Reversed: ${pairText(report.reversed)}',
      for (final e in report.plusSteps.entries)
        if (e.value.isNotEmpty) 'Plus ${e.key}: ${pairText(e.value)}',
      if (report.hasConsecutive) 'Consecutive run of ${report.longestRun}',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title.toUpperCase(),
                    style: const TextStyle(
                        color: _accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                const Spacer(),
                Text(_dateLabel(draw.drawDate), style: TextStyle(color: muted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in draw.numbers)
                  _Ball(number: _two(n), highlighted: report.involved.contains(n)),
              ],
            ),
            const SizedBox(height: 14),
            if (chips.isEmpty)
              Text('No patterns in this draw', style: TextStyle(color: muted, fontSize: 12))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECE9FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(c,
                          style: const TextStyle(
                              color: _accent, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            if (draw.jackpot != null) ...[
              const SizedBox(height: 12),
              Text(
                'Jackpot ₱${draw.jackpot}'
                '${draw.winners == null ? '' : ' · ${draw.winners} winner${draw.winners == 1 ? '' : 's'}'}',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Ball extends StatelessWidget {
  const _Ball({required this.number, required this.highlighted});

  final String number;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: highlighted ? const Color(0xFF6254DF) : const Color(0xFFE6E5EE),
      ),
      child: Text(
        number,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: highlighted ? Colors.white : const Color(0xFF3B3957),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry, required this.onOpen});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: onRetry, child: const Text('Try again')),
                OutlinedButton(onPressed: onOpen, child: const Text('Open PCSO page')),
              ]),
            ],
          ),
        ),
      );
}

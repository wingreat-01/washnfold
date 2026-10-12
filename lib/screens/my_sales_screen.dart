import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sales_today.dart';
import '../services/supabase_service.dart';
import '../utils/app_errors.dart';
import '../theme/app_theme.dart';

/// Attendant tab: what I collected today, the shop's total today, and a cash
/// check (counted drawer vs what the app recorded). Today only, decided in
/// the database, so this screen can't be used to look at older days.
class MySalesScreen extends StatefulWidget {
  /// True while this tab is the one on screen; it refreshes on becoming active.
  final bool active;
  const MySalesScreen({super.key, this.active = false});

  @override
  State<MySalesScreen> createState() => _MySalesScreenState();
}

class _MySalesScreenState extends State<MySalesScreen> {

  final _money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final _floatCtrl = TextEditingController();
  final _countedCtrl = TextEditingController();

  SalesToday? _sales;
  bool _loading = true;
  String? _error;
  DateTime? _updatedAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.active) _load(silent: true);
    });
  }

  @override
  void didUpdateWidget(covariant MySalesScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load(silent: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _floatCtrl.dispose();
    _countedCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final sales = await SupabaseService.instance.fetchSalesToday();
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _error = null;
        _loading = false;
        _updatedAt = DateTime.now();
      });
    } catch (e) {
      logDebug('load sales today failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_sales == null) {
          _error = friendlyError(e,
              fallback: "Couldn't load today's sales. Pull down to retry.");
        }
      });
    }
  }

  double? _parse(String text) {
    final t = text.replaceAll(',', '').replaceAll('₱', '').trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    return (v == null || v < 0 || v > 100000000) ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _sales == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final sales = _sales;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
              child: Text('My sales today',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800, color: context.palette.strong)),
            ),
            IconButton.filledTonal(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ]),
          Text(
            _updatedAt == null
                ? ''
                : 'Updated ${DateFormat('h:mm:ss a').format(_updatedAt!)}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.palette.muted),
          ),
          const SizedBox(height: 12),
          if (_error != null && sales == null) Text(_error!),
          if (sales != null) ...[
            _mineCard(sales),
            const SizedBox(height: 12),
            _shopLine(sales),
            const SizedBox(height: 16),
            _cashCheck(sales),
          ],
        ],
      ),
    );
  }

  Widget _mineCard(SalesToday s) {
    const labels = {
      'cash': 'Cash',
      'gcash': 'GCash',
      'maya': 'Maya',
      'card': 'Card',
    };
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('I collected', style: TextStyle(color: context.palette.muted)),
            const SizedBox(height: 4),
            Text(_money.format(s.mineTotal),
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: context.palette.strong)),
            Text('${s.minePayments} payment${s.minePayments == 1 ? '' : 's'}',
                style: TextStyle(color: context.palette.muted)),
            const Divider(height: 24),
            for (final key in labels.keys)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(labels[key]!)),
                  Text(_money.format(s.mineByMethod[key] ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _shopLine(SalesToday s) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.storefront_outlined, color: context.palette.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shop total today',
                    style: TextStyle(color: context.palette.muted)),
                Text(_money.format(s.shopTotal),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: context.palette.strong)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cashCheck(SalesToday s) {
    final float = _parse(_floatCtrl.text) ?? 0;
    final counted = _parse(_countedCtrl.text);
    final expected = float + s.mineCash;
    String? result;
    Color? color;
    if (counted != null) {
      final diff = double.parse((counted - expected).toStringAsFixed(2));
      if (diff == 0) {
        result = 'Balanced — the drawer matches the app.';
        color = Colors.green.shade700;
      } else if (diff > 0) {
        result = 'Over by ${_money.format(diff)}';
        color = Colors.orange.shade800;
      } else {
        result = 'Short by ${_money.format(-diff)}';
        color = Colors.red.shade700;
      }
    }
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cash check',
                style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.strong)),
            const SizedBox(height: 4),
            Text(
              'Counts only the cash I collected today. Nothing here is saved.',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _floatCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Starting cash in drawer (optional)',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _countedCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Cash counted now',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Expected in drawer')),
              Text(_money.format(expected),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            if (result != null) ...[
              const SizedBox(height: 8),
              Text(result,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w800)),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../providers/order_provider.dart';
import '../theme/app_theme.dart';
import '../providers/currency_settings.dart';

/// Owner-only sales/order-value report. Uses the shop-scoped orders already
/// loaded by OrderProvider and filters them by the order creation date.
class SalesReportsScreen extends StatefulWidget {
  const SalesReportsScreen({super.key});

  @override
  State<SalesReportsScreen> createState() => _SalesReportsScreenState();
}

class _SalesReportsScreenState extends State<SalesReportsScreen> {

  String _period = 'Daily';
  DateTime _selectedDay = DateTime.now();
  DateTime _start = DateTime.now().subtract(const Duration(days: 6));
  DateTime _end = DateTime.now();
  NumberFormat get _money => context.read<CurrencySettings>().format(decimals: 2);
  final _date = DateFormat('MMM d, yyyy');

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: isStart ? 'Select start date' : 'Select end date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (_period == 'Daily') {
        _selectedDay = picked;
      } else if (_period == 'Weekly') {
        final day = _day(picked);
        _start = day.subtract(Duration(days: day.weekday - DateTime.monday));
        _end = _start.add(const Duration(days: 6));
      } else if (isStart) {
        _start = _day(picked);
        if (_start.isAfter(_end)) _end = _start;
      } else {
        _end = _day(picked);
        if (_end.isBefore(_start)) _start = _end;
      }
    });
  }

  DateTime get _rangeStart {
    final now = DateTime.now();
    if (_period == 'Daily') return _day(_selectedDay);
    if (_period == 'Weekly') {
      final today = _day(now);
      return today.subtract(Duration(days: today.weekday - DateTime.monday));
    }
    return _day(_start);
  }

  DateTime get _rangeEndExclusive {
    if (_period == 'Daily') return _rangeStart.add(const Duration(days: 1));
    if (_period == 'Weekly') return _rangeStart.add(const Duration(days: 7));
    return _day(_end).add(const Duration(days: 1));
  }

  String get _rangeLabel {
    if (_period == 'Daily') return _date.format(_rangeStart);
    if (_period == 'Weekly') {
      final last = _rangeEndExclusive.subtract(const Duration(days: 1));
      return '${_date.format(_rangeStart)} – ${_date.format(last)}';
    }
    return '${_date.format(_rangeStart)} – ${_date.format(_rangeEndExclusive.subtract(const Duration(days: 1)))}';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<CurrencySettings>(); // rebuild when the currency changes
    final provider = context.watch<OrderProvider>();
    final orders = provider.orders.where((o) {
      return !o.createdAt.isBefore(_rangeStart) &&
          o.createdAt.isBefore(_rangeEndExclusive);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final totalSales = orders.fold<double>(0, (sum, o) => sum + o.total);
    final paid = orders.where((o) => o.paymentStatus == PaymentStatus.paid)
        .fold<double>(0, (sum, o) => sum + o.total);
    final outstanding = orders.where((o) => o.paymentStatus == PaymentStatus.unpaid)
        .fold<double>(0, (sum, o) => sum + o.total);
    final serviceTotals = <String, double>{};
    final serviceCounts = <String, int>{};
    for (final order in orders) {
      for (final item in order.items) {
        final name = item.serviceName.trim().isEmpty ? 'Other services' : item.serviceName;
        serviceTotals[name] = (serviceTotals[name] ?? 0) + item.subtotal;
        serviceCounts[name] = (serviceCounts[name] ?? 0) + 1;
      }
    }
    final sortedServices = serviceTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: () async {
        // OrderProvider maintains a realtime subscription; pull-to-refresh
        // redraws the report using its latest available data.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sales reports', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: context.palette.strong)),
              const SizedBox(height: 4),
              Text('Review sales and order value over time.', style: TextStyle(color: context.palette.muted)),
            ])),
            IconButton.filledTonal(onPressed: () => setState(() {}), tooltip: 'Refresh report', icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Daily', label: Text('Daily'), icon: Icon(Icons.today_outlined)),
              ButtonSegment(value: 'Weekly', label: Text('Weekly'), icon: Icon(Icons.date_range_outlined)),
              ButtonSegment(value: 'Custom', label: Text('Custom'), icon: Icon(Icons.calendar_month_outlined)),
            ],
            selected: {_period},
            onSelectionChanged: (values) => setState(() {
              _period = values.first;
              if (_period == 'Weekly') {
                final today = _day(DateTime.now());
                _start = today.subtract(Duration(days: today.weekday - DateTime.monday));
                _end = _start.add(const Duration(days: 6));
              }
            }),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 12),
          Card(elevation: 0, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: _period == 'Daily'
                ? ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.event_outlined, color: context.palette.accent), title: Text('Report date'), subtitle: Text(_rangeLabel), trailing: Icon(Icons.edit_calendar_outlined), onTap: () => _pickDate(isStart: true))
                : _period == 'Weekly'
                    ? ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.date_range_outlined, color: context.palette.accent), title: Text('Select a week'), subtitle: Text(_rangeLabel), trailing: Icon(Icons.edit_calendar_outlined), onTap: () => _pickDate(isStart: true))
                    : Row(children: [
                        Expanded(child: _datePickerTile('Start date', _start, () => _pickDate(isStart: true))),
                        const SizedBox(width: 8),
                        Expanded(child: _datePickerTile('End date', _end, () => _pickDate(isStart: false))),
                      ]),
          )),
          const SizedBox(height: 16),
          if (provider.loading && provider.orders.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else ...[
            Text(_rangeLabel, style: TextStyle(color: context.palette.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                _metric('Order value', _money.format(totalSales), Icons.payments_outlined, context.palette.tintGreen, const Color(0xFF16845B), width),
                _metric('Orders created', '${orders.length}', Icons.receipt_long_outlined, context.palette.tintBlue, context.palette.accent, width),
                _metric('Paid order value', _money.format(paid), Icons.check_circle_outline, context.palette.tintPurple, const Color(0xFF805AD5), width),
                _metric('Outstanding', _money.format(outstanding), Icons.pending_actions_outlined, context.palette.tintAmber, const Color(0xFFD97706), width),
              ]);
            }),
            const SizedBox(height: 24),
            _sectionTitle('Sales by service'),
            const SizedBox(height: 10),
            Card(elevation: 0, child: Padding(
              padding: const EdgeInsets.all(16),
              child: sortedServices.isEmpty
                  ? Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: Text('No service sales for this period.', style: TextStyle(color: context.palette.muted))))
                  : Column(children: [
                      for (var i = 0; i < sortedServices.length; i++) ...[
                        if (i > 0) const Divider(height: 22),
                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(sortedServices[i].key, style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.strong)),
                            Text('${serviceCounts[sortedServices[i].key] ?? 0} line items', style: TextStyle(fontSize: 12, color: context.palette.muted)),
                          ])),
                          Text(_money.format(sortedServices[i].value), style: TextStyle(fontWeight: FontWeight.w800, color: context.palette.strong)),
                        ]),
                      ],
                    ]),
            )),
            const SizedBox(height: 24),
            _sectionTitle('Orders in this period'),
            const SizedBox(height: 10),
            if (orders.isEmpty)
              Card(elevation: 0, child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No orders found for these dates.', style: TextStyle(color: context.palette.muted)))))
            else
              ...orders.map((order) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: order.paymentStatus == PaymentStatus.paid ? context.palette.tintGreen : context.palette.tintAmber, child: Icon(order.paymentStatus == PaymentStatus.paid ? Icons.check_rounded : Icons.schedule_rounded, color: order.paymentStatus == PaymentStatus.paid ? const Color(0xFF16845B) : const Color(0xFFD97706))),
                  title: Text(order.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.strong)),
                  subtitle: Text('${order.publicReference} • ${DateFormat('MMM d, h:mm a').format(order.createdAt.toLocal())}\n${order.paymentStatus == PaymentStatus.paid ? 'Paid' : 'Unpaid'} · ${order.status.label}', style: TextStyle(color: context.palette.muted, height: 1.5)),
                  isThreeLine: true,
                  trailing: Text(_money.format(order.total), style: TextStyle(fontWeight: FontWeight.w800, color: context.palette.strong)),
                ),
              )),
            const SizedBox(height: 12),
            Text('Order value is based on order creation date. Paid and outstanding figures reflect each order’s current payment status, not payment date.', style: TextStyle(color: context.palette.muted, fontSize: 12, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _datePickerTile(String label, DateTime value, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: context.palette.border), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: context.palette.muted)),
        const SizedBox(height: 5),
        Row(children: [Expanded(child: Text(_date.format(value), style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.strong))), Icon(Icons.calendar_month_outlined, size: 18, color: context.palette.accent)]),
      ]),
    ),
  );

  Widget _metric(String label, String value, IconData icon, Color tint, Color accent, double width) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 132),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.palette.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 38, height: 38, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: accent, size: 21)),
      const SizedBox(height: 14),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: context.palette.strong))),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 12, color: context.palette.muted, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _sectionTitle(String title) => Row(children: [
    Container(width: 4, height: 21, decoration: BoxDecoration(color: context.palette.teal, borderRadius: BorderRadius.circular(4))),
    const SizedBox(width: 10),
    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.palette.strong)),
  ]);
}

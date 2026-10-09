import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/dashboard_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DashboardProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    if (dashboard.loading && dashboard.todayRevenue == 0) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: dashboard.refresh,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final compact = constraints.maxWidth < 360;
        final cardWidth = wide ? (constraints.maxWidth - 64) / 4 : (constraints.maxWidth - 44) / 2;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(wide ? 28 : (compact ? 12 : 16)),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Shop overview', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4, color: const Color(0xFF123047))),
                const SizedBox(height: 5),
                Text('Here’s how your laundry business is doing.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF718096))),
              ])),
              IconButton.filledTonal(
                tooltip: 'Refresh overview',
                onPressed: dashboard.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                dashboard.lastUpdatedAt == null
                    ? 'Waiting for latest data…'
                    : 'Updated ${DateFormat('h:mm:ss a').format(dashboard.lastUpdatedAt!.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8795A7),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (dashboard.errorMessage != null) ...[
              Card(
                color: const Color(0xFFFFF3F0),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'Dashboard data could not be loaded',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF912018)),
                        )),
                      ]),
                      const SizedBox(height: 8),
                      const Text(
                        'Check your Supabase connection, orders/order_items schema, shop access policies, and the debug console for the underlying error.',
                        style: TextStyle(color: Color(0xFF7A271A)),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        dashboard.errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A271A)),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: dashboard.refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try again'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Wrap(spacing: 12, runSpacing: 12, children: [
              _MetricCard(label: "Today's revenue", value: currency.format(dashboard.todayRevenue), icon: Icons.payments_outlined, tint: const Color(0xFFE5F4EC), accent: const Color(0xFF16845B), width: cardWidth),
              _MetricCard(label: 'This week', value: currency.format(dashboard.weekRevenue), icon: Icons.date_range_rounded, tint: const Color(0xFFE8F1FC), accent: const Color(0xFF2677C9), width: cardWidth),
              _MetricCard(label: 'This month', value: currency.format(dashboard.monthRevenue), icon: Icons.calendar_month_rounded, tint: const Color(0xFFF1EAFE), accent: const Color(0xFF805AD5), width: cardWidth),
              _MetricCard(label: 'Active orders', value: '${dashboard.activeOrderCount}', icon: Icons.local_laundry_service_rounded, tint: const Color(0xFFFFF1DA), accent: const Color(0xFFD97706), width: cardWidth),
            ]),
            const SizedBox(height: 28),
            Row(children: [
              Container(width: 4, height: 22, decoration: BoxDecoration(color: const Color(0xFF16A6A1), borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(child: Text('Top services this month', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.35, color: const Color(0xFF123047)))),
            ]),
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(18),
              child: dashboard.topServices.isEmpty
                  ? const _EmptyServices()
                  : Column(children: dashboard.topServices.entries.take(5).toList().asMap().entries.map((entry) {
                      final index = entry.key;
                      final service = entry.value;
                      final maxValue = dashboard.topServices.values.fold<int>(1, (a, b) => a > b ? a : b);
                      return Padding(
                        padding: EdgeInsets.only(bottom: index == dashboard.topServices.length - 1 ? 0 : 18),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(service.key, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF25364A)))),
                            Text('${service.value} orders', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF123047))),
                          ]),
                          const SizedBox(height: 8),
                          ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: service.value / maxValue, minHeight: 7, backgroundColor: const Color(0xFFEDF2F7), color: const Color(0xFF16A6A1))),
                        ]),
                      );
                    }).toList(),
              ),
            )),
            const SizedBox(height: 12),
            Text('Revenue updates when an order changes, with a 30-second backup refresh.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF8795A7))),
          ],
        );
      }),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final Color accent;
  final double width;

  const _MetricCard({required this.label, required this.value, required this.icon, required this.tint, required this.accent, required this.width});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 142),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE5EBF2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: accent, size: 22)),
      const SizedBox(height: 16),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF123047)))),
      const SizedBox(height: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF718096), fontWeight: FontWeight.w600)),
    ]),
  );
}

class _EmptyServices extends StatelessWidget {
  const _EmptyServices();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 22),
    child: Column(children: [
      Icon(Icons.local_laundry_service_outlined, size: 38, color: Color(0xFF9AA9BA)),
      SizedBox(height: 10),
      Text('No service activity yet', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF25364A))),
      SizedBox(height: 4),
      Text('Your most popular services will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF718096))),
    ]),
  );
}

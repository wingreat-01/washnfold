import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/dashboard_provider.dart';
import '../theme/app_theme.dart';
import '../providers/currency_settings.dart';

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
    final currency = context.watch<CurrencySettings>().format(decimals: 0);

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
                Text('Shop overview', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4, color: context.palette.strong)),
                const SizedBox(height: 5),
                Text('Here’s how your laundry business is doing.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.palette.muted)),
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
                  color: context.palette.subtle,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (dashboard.errorMessage != null) ...[
              Card(
                color: context.palette.errorBg,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.error_outline_rounded, color: context.palette.errorIcon),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'Dashboard data could not be loaded',
                          style: TextStyle(fontWeight: FontWeight.w800, color: context.palette.errorTitle),
                        )),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Check your Supabase connection, orders/order_items schema, shop access policies, and the debug console for the underlying error.',
                        style: TextStyle(color: context.palette.errorText),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        dashboard.errorMessage!,
                        style: TextStyle(fontSize: 12, color: context.palette.errorText),
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
              _MetricCard(label: "Today's revenue", value: currency.format(dashboard.todayRevenue), icon: Icons.payments_outlined, tint: context.palette.tintGreen, accent: const Color(0xFF16845B), width: cardWidth),
              _MetricCard(label: 'This week', value: currency.format(dashboard.weekRevenue), icon: Icons.date_range_rounded, tint: context.palette.tintBlue, accent: context.palette.accent, width: cardWidth),
              _MetricCard(label: 'This month', value: currency.format(dashboard.monthRevenue), icon: Icons.calendar_month_rounded, tint: context.palette.tintPurple, accent: const Color(0xFF805AD5), width: cardWidth),
              _MetricCard(label: 'Active orders', value: '${dashboard.activeOrderCount}', icon: Icons.local_laundry_service_rounded, tint: context.palette.tintAmber, accent: const Color(0xFFD97706), width: cardWidth),
            ]),
            const SizedBox(height: 28),
            Row(children: [
              Container(width: 4, height: 22, decoration: BoxDecoration(color: context.palette.teal, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(child: Text('Top services this month', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.35, color: context.palette.strong))),
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
                            Expanded(child: Text(service.key, style: TextStyle(fontWeight: FontWeight.w600, color: context.palette.body))),
                            Text('${service.value} orders', style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.strong)),
                          ]),
                          const SizedBox(height: 8),
                          ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: service.value / maxValue, minHeight: 7, backgroundColor: context.palette.border, color: context.palette.teal)),
                        ]),
                      );
                    }).toList(),
              ),
            )),
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
    decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: context.palette.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: accent, size: 22)),
      const SizedBox(height: 16),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: context.palette.strong))),
      const SizedBox(height: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.muted, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _EmptyServices extends StatelessWidget {
  const _EmptyServices();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(children: [
      Icon(Icons.local_laundry_service_outlined, size: 38, color: context.palette.subtle),
      const SizedBox(height: 10),
      Text('No service activity yet', style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.body)),
      const SizedBox(height: 4),
      Text('Your most popular services will appear here.', textAlign: TextAlign.center, style: TextStyle(color: context.palette.muted)),
    ]),
  );
}

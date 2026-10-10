import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/order.dart';
import '../models/washer.dart';
import '../providers/dryer_provider.dart';
import '../providers/order_provider.dart';
import '../providers/tile_layout_settings.dart';
import '../providers/washer_provider.dart';
import '../widgets/dryer_picker.dart';
import '../widgets/machine_alert_host.dart';
import '../widgets/machine_timer.dart';
import '../widgets/tile_columns_menu.dart';
import '../utils/app_errors.dart';

const _availableColor = Color(0xFF2F9E5B);
const _inUseColor = Color(0xFFD32F2F); // red = busy
const _maintenanceColor = Color(0xFFD9822B);

Color _colorFor(WasherStatus s) {
  switch (s) {
    case WasherStatus.available:
      return _availableColor;
    case WasherStatus.inUse:
      return _inUseColor;
    case WasherStatus.maintenance:
      return _maintenanceColor;
  }
}

IconData _iconFor(WasherStatus s) {
  switch (s) {
    case WasherStatus.available:
      return Icons.check_circle_outline;
    case WasherStatus.inUse:
      return Icons.autorenew;
    case WasherStatus.maintenance:
      return Icons.build_outlined;
  }
}

String _shortId(String id) =>
    '#${id.replaceAll('-', '').substring(0, 6).toUpperCase()}';

/// Washer floor view: every machine as a card colored by status, with the
/// customer/order shown on busy ones. Cashiers assign, release, and
/// configure machines from here. Updates live via WasherProvider's stream.
class WasherScreen extends StatefulWidget {
  const WasherScreen({super.key});

  @override
  State<WasherScreen> createState() => _WasherScreenState();
}

class _WasherScreenState extends State<WasherScreen> {
  WasherStatus? _filter; // null = all
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Re-render every 30s so "running for X min" stays current.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openForm({Washer? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<WasherProvider>(),
        child: _WasherForm(existing: existing),
      ),
    );
  }

  /// Correct the timer for the load in a washer (e.g. heavy load, extra
  /// rinse, or it finished early).
  Future<void> _editTimer(Washer washer) async {
    final end = washer.expectedEnd;
    if (end == null) return;
    final provider = context.read<WasherProvider>();
    final newEnd = await showMachineTimerEditor(context,
        machineName: washer.name, endsAt: end);
    if (newEnd == null) return;
    // "Mark finished" / 0 minutes: staff just did this themselves, so
    // don't pop a banner or chime about it.
    if (newEnd.difference(DateTime.now()) < const Duration(seconds: 5)) {
      silenceNextMachineAlert(washer.id);
    }
    try {
      await provider.setEndsAt(washer.id, newEnd);
    } catch (e) {
      _snack(friendlyError(e, fallback: 'Could not update the timer.'));
    }
  }

  Future<void> _assign(Washer washer) async {
    final washers = context.read<WasherProvider>();
    final orders = context.read<OrderProvider>();

    final assigned = washers.assignedOrderIds;
    final eligible = orders.orders
        .where((o) =>
            (o.status == OrderStatus.received ||
                o.status == OrderStatus.washing) &&
            !assigned.contains(o.id))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final picked = await showModalBottomSheet<Order>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _OrderPicker(washer: washer, orders: eligible),
    );
    if (picked == null) return;

    try {
      await washers.assignOrder(washer.id, picked.id);
      // Loading a machine means the order is now being washed.
      if (picked.status == OrderStatus.received) {
        await orders.advanceStatus(picked.id, OrderStatus.washing);
      }
      _snack('${picked.customerName} → ${washer.name}');
      // No payment dialog here: this order was waiting in the queue, so it
      // is paid after all services are finished (Ready → Picked up).
    } catch (e) {
      logDebug('assign failed: $e');
      _snack(friendlyError(e, fallback: 'Could not assign. Please try again.'));
    }
  }

  /// Frees the washer. For a wash-only order there is nothing left to do
  /// (no drying or folding), so the order also moves to Ready. For any other
  /// order (the undo icon next to "Assign to dryer") it only frees the
  /// washer and the order stays where it is in the queue.
  Future<void> _release(Washer washer, Order? order) async {
    final washers = context.read<WasherProvider>();
    final orders = context.read<OrderProvider>();
    final customer = order?.customerName;
    final finishesOrder = order != null &&
        order.isWashOnly &&
        (order.status == OrderStatus.received ||
            order.status == OrderStatus.washing);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Release ${washer.name}?'),
        content: Text(
          finishesOrder
              ? "${customer ?? 'This load'}'s wash is finished. The washer is "
                  'marked Available and the order moves to Ready.'
              : '${customer ?? 'This load'} will be taken out and the washer '
                  'marked Available. The order stays in the queue.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Release')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await washers.release(washer.id);
      if (finishesOrder) {
        await orders.advanceStatus(order!.id, OrderStatus.ready);
        _snack('${customer ?? 'Order'} is ready for pickup');
      }
    } catch (e) {
      _snack(friendlyError(e, fallback: 'Could not release. Please try again.'));
    }
  }

  /// "Assign to dryer" on a busy washer: choose a dryer in a modal, move the load there,
  /// free the washer, and set the order to Drying.
  Future<void> _dry(Washer washer, Order order) async {
    final washers = context.read<WasherProvider>();
    final dryers = context.read<DryerProvider>();
    final orders = context.read<OrderProvider>();

    final picked = await showDryerPicker(
      context,
      order: order,
      dryers: dryers.dryers,
      ordersById: {for (final o in orders.orders) o.id: o},
    );
    if (picked == null) return;

    try {
      // Guarded: throws if someone else took that dryer a moment ago.
      await dryers.assignOrder(picked.id, order.id);
    } catch (e) {
      logDebug('assign dryer failed: $e');
      _snack(friendlyError(e, fallback: 'Could not assign the dryer. Please try again.'));
      return;
    }

    try {
      await washers.release(washer.id);
      await orders.advanceStatus(order.id, OrderStatus.drying);
      _snack('${order.customerName} → ${picked.name}');
    } catch (e) {
      logDebug('dry hand-off failed: $e');
      // Don't leave the load in two machines: undo the dryer assignment.
      try {
        await dryers.release(picked.id);
      } catch (_) {}
      _snack(friendlyError(e, fallback: 'Could not move the load to the dryer.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WasherProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final orderById = {for (final o in orderProvider.orders) o.id: o};

    if (provider.loading && provider.washers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final visible = provider.washers
        .where((w) => _filter == null || w.status == _filter)
        .toList();

    final layout = context.watch<TileLayoutSettings>();
    final phone = isPhoneWidth(context);
    final cols = phone ? layout.washerColumns : 2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add washer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All (${provider.washers.length})',
                    color: Theme.of(context).colorScheme.primary,
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final s in WasherStatus.values)
                    _FilterChip(
                      label: '${s.label} (${provider.countByStatus(s)})',
                      color: _colorFor(s),
                      selected: _filter == s,
                      onTap: () => setState(
                          () => _filter = _filter == s ? null : s),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: provider.washers.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No washers yet.\nTap "Add washer" to set up your first machine.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : visible.isEmpty
                    ? Center(
                        child: Text(
                            'No washers are ${_filter!.label.toLowerCase()} right now.'))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        gridDelegate: phone
                            ? SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisExtent:
                                    cols == 2 ? 204 : (cols == 3 ? 152 : 140),
                                crossAxisSpacing: cols == 2 ? 12 : 8,
                                mainAxisSpacing: cols == 2 ? 12 : 8,
                              )
                            : const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 240,
                                mainAxisExtent: 204,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final w = visible[i];
                          final order = w.currentOrderId == null
                              ? null
                              : orderById[w.currentOrderId];
                          return _WasherCard(
                            washer: w,
                            order: order,
                            onAssign: () => _assign(w),
                            onRelease: () => _release(w, order),
                            onDry: order == null ? null : () => _dry(w, order),
                            onConfigure: () => _openForm(existing: w),
                            onEditTimer: () => _editTimer(w),
                            columns: cols,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: color.withOpacity(0.18),
        side: BorderSide(color: selected ? color : Colors.black12),
        labelStyle: TextStyle(
          color: selected ? color : null,
          fontWeight: FontWeight.w600,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _WasherCard extends StatelessWidget {
  final Washer washer;
  final Order? order;
  final VoidCallback onAssign;
  final VoidCallback onRelease;
  final VoidCallback? onDry;
  final VoidCallback onConfigure;
  final VoidCallback onEditTimer;

  /// Tiles per row on the screen (2 = full card, 3-4 = compact tile).
  final int columns;

  const _WasherCard({
    required this.washer,
    required this.order,
    required this.onAssign,
    required this.onRelease,
    required this.onDry,
    required this.onConfigure,
    required this.onEditTimer,
    this.columns = 2,
  });

  /// Small tile used when 3 or 4 tiles are shown per row.
  Widget _buildCompact(BuildContext context) {
    final color = _colorFor(washer.status);
    final theme = Theme.of(context);
    final tiny = columns >= 4;
    final pad = tiny ? 6.0 : 8.0;
    final fs = tiny ? 11.0 : 12.0;

    Widget btn(String label, VoidCallback? onPressed, {required int kind}) {
      final shape =
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
      const padding = EdgeInsets.symmetric(horizontal: 4);
      const size = Size(0, 32);
      final text = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label,
            maxLines: 1,
            style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700)),
      );
      switch (kind) {
        case 0:
          return FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: color.withOpacity(0.15),
              foregroundColor: color,
              padding: padding,
              minimumSize: size,
              shape: shape,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onPressed,
            child: text,
          );
        case 1:
          return FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: padding,
              minimumSize: size,
              shape: shape,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onPressed,
            child: text,
          );
        default:
          return OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color),
              padding: padding,
              minimumSize: size,
              shape: shape,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onPressed,
            child: text,
          );
      }
    }

    Widget body;
    Widget? action;

    switch (washer.status) {
      case WasherStatus.available:
        body = Text('Ready',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: fs + 1));
        action = btn(tiny ? 'Assign' : 'Assign order', onAssign, kind: 0);
        break;
      case WasherStatus.inUse:
        final hasOrder = washer.currentOrderId != null;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order?.customerName ?? (hasOrder ? 'Order not found' : 'Unknown'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800, fontSize: tiny ? 12.5 : 13.5),
            ),
            if (!tiny && hasOrder)
              Text(
                _shortId(washer.currentOrderId!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Colors.black54,
                ),
              ),
            const SizedBox(height: 4),
            if (washer.expectedEnd != null)
              MachineTimer(
                endsAt: washer.expectedEnd!,
                startedAt: washer.startedAt,
                color: color,
                onEdit: onEditTimer,
                compact: true,
              ),
          ],
        );
        final washOnly = order == null || order!.isWashOnly;
        action = washOnly
            ? btn('Release', onRelease, kind: 2)
            : Row(
                children: [
                  Expanded(
                    child: btn(tiny ? 'Dryer' : 'To dryer', onDry, kind: 1),
                  ),
                  SizedBox(
                    width: 30,
                    height: 32,
                    child: IconButton(
                      tooltip: 'Take out (assigned by mistake)',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 30, height: 32),
                      iconSize: 18,
                      color: color,
                      icon: const Icon(Icons.undo),
                      onPressed: onRelease,
                    ),
                  ),
                ],
              );
        break;
      case WasherStatus.maintenance:
        body = Text(
          washer.notes?.isNotEmpty == true ? washer.notes! : 'Out of service',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: fs),
        );
        action = null;
        break;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: Color.alphaBlend(color.withOpacity(0.06), Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: InkWell(
        onTap: onConfigure,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      washer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: tiny ? 12.5 : 14),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_iconFor(washer.status),
                      size: tiny ? 14 : 16, color: color),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(child: body),
              if (action != null)
                SizedBox(width: double.infinity, child: action),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (columns >= 3) return _buildCompact(context);
    final color = _colorFor(washer.status);
    final theme = Theme.of(context);
    final cap = washer.capacityKg;

    Widget body;
    Widget? action;

    switch (washer.status) {
      case WasherStatus.available:
        body = Text('Ready for a load',
            style: theme.textTheme.bodyMedium?.copyWith(color: color));
        action = FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: color.withOpacity(0.15),
            foregroundColor: color,
          ),
          onPressed: onAssign,
          child: const Text('Assign order'),
        );
        break;
      case WasherStatus.inUse:
        final hasOrder = washer.currentOrderId != null;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    order?.customerName ??
                        (hasOrder ? 'Order not found' : 'Unknown'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (hasOrder) ...[
                  const SizedBox(width: 8),
                  Text(
                    _shortId(washer.currentOrderId!),
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
            if (order != null && order!.items.isNotEmpty)
              Text(
                order!.items.map((e) => e.serviceName).join(' + '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            if (washer.expectedEnd != null) ...[
              const SizedBox(height: 4),
              MachineTimer(
                endsAt: washer.expectedEnd!,
                startedAt: washer.startedAt,
                color: color,
                onEdit: onEditTimer,
              ),
            ],
          ],
        );
        // Wash-only customers take their laundry straight out of the washer,
        // so they get Release. Everything else (wash+dry, wash+dry+fold,
        // full service) follows the queue: Assign to dryer.
        final washOnly = order == null || order!.isWashOnly;
        action = washOnly
            ? OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                ),
                onPressed: onRelease,
                child: const Text('Release'),
              )
            : Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onDry,
                      child: const Text('Assign to dryer'),
                    ),
                  ),
                  // Small escape hatch for a load assigned by mistake.
                  IconButton(
                    tooltip: 'Take out (assigned by mistake)',
                    icon: const Icon(Icons.undo, size: 20),
                    color: color,
                    onPressed: onRelease,
                  ),
                ],
              );
        break;
      case WasherStatus.maintenance:
        body = Text(
          washer.notes?.isNotEmpty == true
              ? washer.notes!
              : 'Out of service',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        );
        action = null;
        break;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: Color.alphaBlend(color.withOpacity(0.06), Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: InkWell(
        onTap: onConfigure,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.local_laundry_service,
                        color: color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          washer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (cap != null)
                          Text(
                            '${cap == cap.roundToDouble() ? cap.toInt() : cap} kg',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_iconFor(washer.status), size: 14, color: color),
                        const SizedBox(width: 4),
                        Text(
                          washer.status.label,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(child: body),
              if (action != null)
                SizedBox(width: double.infinity, child: action),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing orders that can be put into [washer].
class _OrderPicker extends StatelessWidget {
  final Washer washer;
  final List<Order> orders;

  const _OrderPicker({required this.washer, required this.orders});

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Assign to ${washer.name}',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No orders waiting for a washer.\nNew and washing orders that '
                  "aren't in a machine yet show up here.",
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final o = orders[i];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    child: ListTile(
                      onTap: () => Navigator.pop(context, o),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(o.customerName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (o.isRush) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.bolt,
                                size: 16, color: Color(0xFFE0A020)),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '${_shortId(o.id)} • ${o.status.label}\n'
                        '${o.items.map((e) => e.serviceName).join(', ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Add / configure a washer: name, capacity, notes, and (when it isn't
/// mid-load) Available ↔ Maintenance. Delete is blocked while in use.
class _WasherForm extends StatefulWidget {
  final Washer? existing;
  const _WasherForm({this.existing});

  @override
  State<_WasherForm> createState() => _WasherFormState();
}

class _WasherFormState extends State<_WasherForm> {
  late final TextEditingController _name;
  late final TextEditingController _capacity;
  late final TextEditingController _notes;
  late final TextEditingController _cycle;
  late WasherStatus _status;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;
  bool get _inUse => widget.existing?.status == WasherStatus.inUse;

  @override
  void initState() {
    super.initState();
    final w = widget.existing;
    _name = TextEditingController(text: w?.name ?? '');
    final cap = w?.capacityKg;
    _capacity = TextEditingController(
      text: cap == null
          ? ''
          : (cap == cap.roundToDouble() ? '${cap.toInt()}' : '$cap'),
    );
    _notes = TextEditingController(text: w?.notes ?? '');
    _cycle = TextEditingController(
        text: '${w?.cycleMinutes ?? AppConfig.washerCycleMinutes}');
    _status = w?.status ?? WasherStatus.available;
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _notes.dispose();
    _cycle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the washer a name, e.g. "Washer 1".');
      return;
    }
    final capText = _capacity.text.trim();
    double? cap;
    if (capText.isNotEmpty) {
      cap = double.tryParse(capText);
      if (cap == null || cap <= 0) {
        setState(() => _error = 'Capacity must be a number above 0.');
        return;
      }
    }
    final cycle = int.tryParse(_cycle.text.trim());
    if (cycle == null || cycle < 1 || cycle > 600) {
      setState(() => _error = 'Cycle time must be 1 to 600 minutes.');
      return;
    }
    final notes = _notes.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    final provider = context.read<WasherProvider>();
    final nav = Navigator.of(context);
    try {
      if (_isEdit) {
        await provider.updateWasher(
          widget.existing!.id,
          name: name,
          capacityKg: cap,
          notes: notes.isEmpty ? null : notes,
          cycleMinutes: cycle,
          status: _inUse ? null : _status,
        );
      } else {
        await provider.addWasher(
          name: name,
          capacityKg: cap,
          notes: notes.isEmpty ? null : notes,
          cycleMinutes: cycle,
        );
      }
      nav.pop();
    } catch (e) {
      logDebug('save washer failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e, fallback: 'Could not save. Please try again.');
        });
      }
    }
  }

  Future<void> _delete() async {
    final provider = context.read<WasherProvider>();
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete washer?'),
        content: Text('"${widget.existing!.name}" will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await provider.deleteWasher(widget.existing!.id);
      nav.pop();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, fallback: 'Could not delete. Please try again.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEdit ? 'Configure washer' : 'Add washer',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Washer 1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacity,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Capacity (kg) — optional',
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cycle,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cycle time',
                suffixText: 'min',
                helperText: 'How long one load runs. The timer counts down '
                    'from this; you can adjust it per load on the card.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes — optional',
                hintText: 'e.g. drain pump being replaced',
              ),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 16),
              if (_inUse)
                Text(
                  'This washer is in use. Release it from the card before '
                  'changing its status or deleting it.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                SegmentedButton<WasherStatus>(
                  segments: const [
                    ButtonSegment(
                        value: WasherStatus.available,
                        label: Text('Available'),
                        icon: Icon(Icons.check_circle_outline)),
                    ButtonSegment(
                        value: WasherStatus.maintenance,
                        label: Text('Maintenance'),
                        icon: Icon(Icons.build_outlined)),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) =>
                      setState(() => _status = s.first),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Save changes' : 'Add washer'),
              ),
            ),
            if (_isEdit && !_inUse)
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete washer'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}

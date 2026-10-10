import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dryer.dart';
import '../models/order.dart';
import '../models/washer.dart';
import '../providers/dryer_provider.dart';
import '../providers/order_provider.dart';
import '../providers/waitlist.dart';
import '../providers/washer_provider.dart';
import '../widgets/amount_due_dialog.dart';
import '../widgets/order_card.dart';
import '../widgets/order_qr_dialog.dart';
import '../widgets/washer_picker.dart';
import '../utils/app_errors.dart';

/// The live queue. On wide screens (web/tablet) this shows every pipeline
/// stage side by side, kanban-style, since that's where an owner watching
/// the whole shop benefits most. On phones it collapses to one stage at a
/// time behind a segmented control, since an attendant is usually only
/// working one stage.
class OrderQueueScreen extends StatefulWidget {
  const OrderQueueScreen({super.key});

  @override
  State<OrderQueueScreen> createState() => _OrderQueueScreenState();
}

class _OrderQueueScreenState extends State<OrderQueueScreen> {
  OrderStatus _selectedMobileStatus = OrderStatus.received;
  final ScrollController _chipScroll = ScrollController();

  @override
  void dispose() {
    _chipScroll.dispose();
    super.dispose();
  }

  static const _pipeline = [
    OrderStatus.received,
    OrderStatus.washing,
    OrderStatus.drying,
    OrderStatus.foldingPressing,
    OrderStatus.ready,
  ];

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        if (orderProvider.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return isWide
            ? _buildKanban(context, orderProvider)
            : _buildMobileList(context, orderProvider);
      },
    );
  }

  Widget _buildKanban(BuildContext context, OrderProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _pipeline
            .map((status) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFD), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE7EDF4))),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _StatusColumn(status: status, provider: provider),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildMobileList(BuildContext context, OrderProvider provider) {
    final orders = provider.ordersByStatus(_selectedMobileStatus);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          // Swipe (touch) or click-drag / scrollbar (mouse) sideways to
          // reach every stage chip. Mouse drag is enabled explicitly
          // because Flutter web ignores it by default.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: Scrollbar(
              controller: _chipScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _chipScroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: _pipeline.map((status) {
                    final selected = status == _selectedMobileStatus;
                    final count = provider.ordersByStatus(status).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${status.label} ($count)'),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _selectedMobileStatus = status),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFE8F1FC), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.checkroom_rounded, size: 30, color: Color(0xFF2677C9))),
                      const SizedBox(height: 14),
                      Text('All clear in ${_selectedMobileStatus.label}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF123047))),
                      const SizedBox(height: 5),
                      const Text('New orders will show up here.', style: TextStyle(color: Color(0xFF718096))),
                    ]),
                  ))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    return _buildOrderCard(context, provider, order);
                  },
                ),
        ),
      ],
    );
  }
}

class _StatusColumn extends StatelessWidget {
  final OrderStatus status;
  final OrderProvider provider;

  const _StatusColumn({required this.status, required this.provider});

  @override
  Widget build(BuildContext context) {
    final orders = provider.ordersByStatus(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(
            '${status.label} (${orders.length})',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF123047)),
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? const SizedBox.shrink()
              : ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    return _buildOrderCard(context, provider, order);
                  },
                ),
        ),
      ],
    );
  }
}

/// Builds an OrderCard with machine info wired in: the washer / dryer name
/// the order is currently in (shown in its status pill), or an "Assign
/// washer" button for received / washing orders that aren't in a machine yet.
Widget _buildOrderCard(
    BuildContext context, OrderProvider provider, Order order) {
  final washerProvider = context.watch<WasherProvider>();
  final washers = washerProvider.washers;
  Washer? washer;
  for (final w in washers) {
    if (w.currentOrderId == order.id) {
      washer = w;
      break;
    }
  }
  final dryers = context.watch<DryerProvider>().dryers;
  Dryer? dryer;
  for (final d in dryers) {
    if (d.currentOrderId == order.id) {
      dryer = d;
      break;
    }
  }
  final canAssign = washer == null &&
      (order.status == OrderStatus.received ||
          order.status == OrderStatus.washing);

  // Received but not in a machine yet: show its place in line and, when
  // every washer is busy, a rough wait.
  String? waitingText;
  if (washer == null && order.status == OrderStatus.received) {
    final line =
        computeWaitlist(provider.orders, washerProvider.assignedOrderIds);
    final i = line.indexWhere((o) => o.id == order.id);
    if (i >= 0) {
      var text = 'Waiting · #${i + 1} in line';
      final est = washerProvider.estimatedWait(position: i + 1);
      if (est != null && est > Duration.zero) {
        text += ' · ~${formatWait(est)}';
      }
      waitingText = text;
    }
  }

  return OrderCard(
    order: order,
    waitingText: waitingText,
    machineEndsAt: order.status == OrderStatus.washing
        ? washer?.expectedEnd
        : order.status == OrderStatus.drying
            ? dryer?.expectedEnd
            : null,
    washerName: washer?.name,
    dryerName: dryer?.name,
    onAssignWasher:
        canAssign ? () => assignOrderToWasher(context, order) : null,
    onTap: () => showDialog(
      context: context,
      builder: (_) => OrderQrDialog(order: order),
    ),
    onPay: () => showAmountDueDialog(context, order, provider),
    onAdvance: order.status.next == null
        ? null
        : () => _advanceOrder(context, provider, order),
  );
}

/// Moves an order to its next stage. The final step (Ready → Picked up)
/// checks payment first: an unpaid order opens the amount-due dialog, and
/// if the cashier still chooses "Pay later" they must confirm the release.
Future<void> _advanceOrder(
    BuildContext context, OrderProvider provider, Order order) async {
  final next = order.status.next;
  if (next == null) return;

  if (next == OrderStatus.pickedUp &&
      order.paymentStatus == PaymentStatus.unpaid &&
      order.total > 0) {
    final paid = await showAmountDueDialog(context, order, provider);
    if (!paid) {
      if (!context.mounted) return;
      final releaseAnyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Release unpaid order?'),
          content: Text(
            '${order.customerName} has not paid yet. The order will be '
            'marked Picked up with the balance still unpaid.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Release anyway')),
          ],
        ),
      );
      if (releaseAnyway != true) return;
    }
  }

  try {
    await provider.advanceStatus(order.id, next);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Could not update the order. Please try again.'))));
    }
  }
}

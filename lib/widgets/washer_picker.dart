import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../models/washer.dart';
import '../providers/order_provider.dart';
import '../providers/waitlist.dart';
import '../providers/washer_provider.dart';
import 'amount_due_dialog.dart';
import '../utils/app_errors.dart';

/// True while the washer picker sheet is on screen. The "washer just freed
/// up" prompt stays quiet then, because the picker already updates live.
bool washerPickerOpen = false;

/// Orders the cashier already collected payment for from the picker sheet
/// (while waiting for a washer), so the payment dialog isn't shown again
/// when the order is finally loaded — the order list refreshes a moment
/// after payment, so it can briefly still read unpaid.
final Set<String> _paidUpfront = {};

/// Orders just marked "Keep in queue" on this device. The real flag lives
/// on the order (orders.pay_later, shared by every staff/owner device); this
/// set only covers the moment before the realtime refresh brings it back.
final Set<String> _keptNow = {};

/// True if payment for [order] should wait until all services are finished
/// (the cashier chose "Keep in queue" while every washer was busy). The
/// payment then comes up at Ready → Picked up in the Queue tab, or from the
/// Pay button there.
bool paymentDeferred(OrderProvider orders, Order order) {
  if (_keptNow.contains(order.id)) return true;
  if (order.payLater) return true;
  final live = orders.orders.where((o) => o.id == order.id);
  return live.isNotEmpty && live.first.payLater;
}

/// Lets the cashier pick an available washer for [order], then assigns it
/// (and moves the order to Washing if it was still Received). Used right
/// after an order is created, but works from anywhere an Order is in hand.
///
/// When every washer is busy the sheet shows the order's place in line and
/// an estimated wait; the order simply stays Received (shown as Waiting in
/// the queue) until a washer frees up.
Future<void> assignOrderToWasher(
  BuildContext context,
  Order order, {
  bool collectPayment = false,
}) async {
  final washers = context.read<WasherProvider>();
  final orders = context.read<OrderProvider>();

  washerPickerOpen = true;
  final Washer? picked;
  try {
    picked = await showModalBottomSheet<Washer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // The sheet lives under the root navigator, so hand it the providers.
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: washers),
          ChangeNotifierProvider.value(value: orders),
        ],
        child: _WasherPickerSheet(order: order),
      ),
    );
  } finally {
    washerPickerOpen = false;
  }
  if (picked == null) {
    // Closed the sheet with every washer busy = "Keep in queue".
    final anyFree =
        washers.washers.any((w) => w.status == WasherStatus.available);
    if (!anyFree && order.paymentStatus == PaymentStatus.unpaid) {
      _keptNow.add(order.id);
      try {
        await orders.setPayLater(order.id, true);
      } catch (e) {
        logDebug('could not save pay-later flag: $e');
      }
    }
    return;
  }
  if (!context.mounted) return;

  await loadOrderIntoWasher(context, order, picked,
      collectPayment: collectPayment);
}

/// Puts [order] into [washer], moves it to Washing if it was still Received.
///
/// The payment dialog only follows when [collectPayment] is true, which is
/// the case right after an order is created at the counter. An order loaded
/// later from the queue (it was waiting, or kept in queue) is paid after all
/// services are finished instead (Ready → Picked up, or the Pay button).
/// Shared by the picker and the "washer just freed up" prompt.
Future<void> loadOrderIntoWasher(
  BuildContext context,
  Order order,
  Washer washer, {
  bool collectPayment = false,
}) async {
  final washers = context.read<WasherProvider>();
  final orders = context.read<OrderProvider>();
  final messenger = ScaffoldMessenger.of(context);

  // One order must never end up in two machines.
  if (washers.assignedOrderIds.contains(order.id)) {
    messenger.showSnackBar(SnackBar(
        content: Text('${order.customerName} is already in a washer.')));
    return;
  }

  try {
    await washers.assignOrder(washer.id, order.id);
    if (order.status == OrderStatus.received) {
      await orders.advanceStatus(order.id, OrderStatus.washing);
    }
    messenger.showSnackBar(SnackBar(
        content: Text('${order.customerName} → ${washer.name}')));
    // Washer is loaded — now collect payment (skipped if already paid, or
    // if the cashier had chosen "Keep in queue" for this order).
    if (context.mounted &&
        collectPayment &&
        !paymentDeferred(orders, order) &&
        !_paidUpfront.contains(order.id)) {
      final fresh = orders.orders
          .firstWhere((o) => o.id == order.id, orElse: () => order);
      await showAmountDueDialog(context, fresh, orders);
    }
  } catch (e) {
    logDebug('assign to washer failed: $e');
    messenger.showSnackBar(SnackBar(
      content: Text(
          friendlyError(e, fallback: 'Could not assign a washer. Please try again.')),
    ));
  }
}

class _WasherPickerSheet extends StatelessWidget {
  final Order order;
  const _WasherPickerSheet({required this.order});

  @override
  Widget build(BuildContext context) {
    // Watching keeps the list live if another cashier grabs a machine
    // while this sheet is open.
    final washerProvider = context.watch<WasherProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final all = washerProvider.washers;
    final free =
        all.where((w) => w.status == WasherStatus.available).toList();

    // Where this order sits in line, and roughly how long until a washer
    // is free for it.
    final line = computeWaitlist(
        orderProvider.orders, washerProvider.assignedOrderIds);
    var position = line.indexWhere((o) => o.id == order.id) + 1;
    if (position == 0) position = line.length + 1;
    final wait = washerProvider.estimatedWait(position: position);
    final nextWasher = washerProvider.nextWasherToFree;
    final maxH = MediaQuery.of(context).size.height * 0.7;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Assign ${order.customerName} to a washer',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '${free.length} of ${all.length} available',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (free.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: all.isEmpty
                  ? const Center(
                      child: Text(
                        'No washers set up yet.\nAdd one in the Washers tab.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _AllBusyInfo(
                      order: orderProvider.orders.firstWhere(
                          (o) => o.id == order.id,
                          orElse: () => order),
                      orders: orderProvider,
                      position: position,
                      wait: wait,
                      nextWasherName: position == 1 ? nextWasher?.name : null,
                    ),
            )
          else
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisExtent: 96,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: free.length,
                itemBuilder: (context, i) {
                  final w = free[i];
                  const green = Color(0xFF2F9E5B);
                  final cap = w.capacityKg;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, w),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: green.withOpacity(0.5)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.local_laundry_service,
                              color: green),
                          const SizedBox(height: 4),
                          Text(w.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          if (cap != null)
                            Text(
                              '${cap == cap.roundToDouble() ? cap.toInt() : cap} kg',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
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

/// Shown in the picker when no washer is available: the order stays in the
/// queue as "Waiting", with its place in line and a rough wait.
class _AllBusyInfo extends StatefulWidget {
  final Order order;
  final OrderProvider orders;
  final int position;
  final Duration? wait;
  final String? nextWasherName;

  const _AllBusyInfo({
    required this.order,
    required this.orders,
    required this.position,
    required this.wait,
    required this.nextWasherName,
  });

  @override
  State<_AllBusyInfo> createState() => _AllBusyInfoState();
}

class _AllBusyInfoState extends State<_AllBusyInfo> {
  Future<void> _collectNow() async {
    final paid =
        await showAmountDueDialog(context, widget.order, widget.orders);
    if (paid) {
      _paidUpfront.add(widget.order.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFB7791F);
    final order = widget.order;
    final wait = widget.wait;
    final String estimate;
    if (wait == null) {
      estimate = 'No washer is running right now, so there is no estimate '
          '(check whether they are in maintenance).';
    } else {
      final base = 'Estimated wait: about ${formatWait(wait)}';
      estimate = widget.nextWasherName != null
          ? '$base (${widget.nextWasherName} is next to finish).'
          : '$base.';
    }

    final isPaid = order.paymentStatus == PaymentStatus.paid ||
        _paidUpfront.contains(order.id);
    final canCollect = !isPaid && order.total > 0;
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.hourglass_bottom_rounded, size: 34, color: amber),
        const SizedBox(height: 8),
        const Text('All washers are busy',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('This order is #${widget.position} in line.',
            style: const TextStyle(fontWeight: FontWeight.w700, color: amber)),
        const SizedBox(height: 6),
        Text(estimate, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          'It stays in the queue as Waiting. When a washer frees up you '
          'will be asked to load the next order.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        if (canCollect) ...[
          FilledButton.icon(
            onPressed: _collectNow,
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F9E5B)),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: Text('Collect ${money.format(order.total)} now'),
          ),
          const SizedBox(height: 8),
        ] else if (isPaid && order.total > 0) ...[
          const Text('Paid ✓',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xFF2F9E5B))),
          const SizedBox(height: 8),
        ],
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep in queue'),
        ),
      ],
    );
  }
}

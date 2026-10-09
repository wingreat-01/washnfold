import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/order.dart';
import '../theme/app_theme.dart';
import 'machine_timer.dart';

class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback? onAdvance;
  final VoidCallback? onTap;

  /// Name of the washer this order is currently in, if any — shown inside
  /// the status pill ("Washing · Washer 2").
  final String? washerName;

  /// Name of the dryer this order is currently in, if any — shown inside the
  /// status pill ("Drying · Dryer 1").
  final String? dryerName;

  /// Shown as an "Assign washer" button when non-null (queue passes it only
  /// for orders that aren't in a machine yet).
  final VoidCallback? onAssignWasher;

  /// Shown as a green "Pay" button on unpaid orders (pay-later customers).
  final VoidCallback? onPay;

  /// "Waiting · #2 in line · ~12 min" for a Received order that isn't in a
  /// washer yet; shown as an amber pill next to the status.
  final String? waitingText;

  /// When the load in this order's washer / dryer should be done; shows a
  /// live "12 min left" / "Done" pill next to the status.
  final DateTime? machineEndsAt;

  const OrderCard({
    super.key,
    required this.order,
    this.onAdvance,
    this.onTap,
    this.washerName,
    this.dryerName,
    this.onAssignWasher,
    this.onPay,
    this.waitingText,
    this.machineEndsAt,
  });

  /// "Washing · Washer 2", "Drying · Dryer 1", "Folding", ...
  String _statusText() {
    final machine = order.status == OrderStatus.washing
        ? washerName
        : order.status == OrderStatus.drying
            ? dryerName
            : null;
    return machine == null
        ? order.status.label
        : '${order.status.label} · $machine';
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
    final nextStatus = order.status.next;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.customerName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF123047),
                            ),
                          ),
                        ),
                        if (order.isRush) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.bolt,
                              size: 16, color: Color(0xFFE0A020)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Ref: ${order.publicReference}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 8),
                    // Service: one pill per service on the order.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const _FieldLabel('Service:'),
                        for (final item in order.items)
                          _Pill(
                            text: item.serviceName,
                            color: const Color(0xFF123047),
                          ),
                        if (order.items.isEmpty)
                          const _Pill(text: '—', color: Color(0xFF718096)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Status: current stage, plus the machine it's in.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const _FieldLabel('Status:'),
                        _Pill(
                          text: _statusText(),
                          color: statusColor(order.status.asString),
                          strong: true,
                        ),
                        if (machineEndsAt != null)
                          MachineTimerPill(endsAt: machineEndsAt!),
                        if (waitingText != null)
                          _Pill(
                            text: waitingText!,
                            color: const Color(0xFFB7791F),
                            strong: true,
                          ),
                        if (order.paymentStatus.name == 'unpaid')
                          _Pill(
                            text: order.payLater
                                ? 'Unpaid · pay at pickup'
                                : 'Unpaid',
                            color: Colors.red,
                            small: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        currency.format(order.total),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF123047),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (onAssignWasher != null) ...[
                    FilledButton.tonalIcon(
                      onPressed: onAssignWasher,
                      icon: const Icon(Icons.local_laundry_service, size: 14),
                      label: const Text('Washer',
                          style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (onPay != null &&
                      order.paymentStatus == PaymentStatus.unpaid &&
                      order.total > 0) ...[
                    FilledButton.icon(
                      onPressed: onPay,
                      icon: const Icon(Icons.payments_outlined, size: 14),
                      label: const Text('Pay',
                          style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2F9E5B),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  // The washer / dryer buttons now move an order through
                  // Received -> Washing -> Drying -> Folding, so this
                  // "next stage" button is hidden for those. It stays only
                  // where nothing else can move the order: Folding
                  // -> Ready, and Ready -> Picked up (which also takes the
                  // payment).
                  if (nextStatus != null &&
                      (order.status == OrderStatus.foldingPressing ||
                          order.status == OrderStatus.ready))
                    OutlinedButton(
                      onPressed: onAdvance,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                          nextStatus == OrderStatus.pickedUp &&
                                  order.paymentStatus == PaymentStatus.unpaid &&
                                  order.total > 0
                              ? 'Collect & release'
                              : '→ ${nextStatus.label}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF718096),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
}

/// Rounded tinted pill used for the service names and the status.
class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool strong; // status pill: a bit bolder
  final bool small;

  const _Pill({
    required this.text,
    required this.color,
    this.strong = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: small ? 8 : 10, vertical: small ? 3 : 4),
        decoration: BoxDecoration(
          color: color.withOpacity(strong ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
            fontSize: small ? 11 : 12,
          ),
        ),
      );
}

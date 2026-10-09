import 'package:flutter/material.dart';

import '../models/dryer.dart';
import '../models/order.dart';
import '../models/washer.dart';

/// Modal shown when someone taps "Dry" on a busy washer: pick the dryer the
/// load goes into. Available dryers are tappable; busy / out-of-service ones
/// are shown greyed out so it's clear why they can't be chosen.
/// Returns the chosen [Dryer], or null if dismissed.
Future<Dryer?> showDryerPicker(
  BuildContext context, {
  required Order order,
  required List<Dryer> dryers,
  required Map<String, Order> ordersById,
}) {
  return showModalBottomSheet<Dryer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DryerPicker(
      order: order,
      dryers: dryers,
      ordersById: ordersById,
    ),
  );
}

class _DryerPicker extends StatelessWidget {
  final Order order;
  final List<Dryer> dryers;
  final Map<String, Order> ordersById;

  const _DryerPicker({
    required this.order,
    required this.dryers,
    required this.ordersById,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.of(context).size.height * 0.7;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Assign to dryer', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              "${order.customerName}'s load will leave the washer and start drying.",
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (dryers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No dryers yet.\nAdd your dryers in the Dryers tab first.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: dryers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final d = dryers[i];
                  final available = d.status == WasherStatus.available;
                  final busyWith = d.currentOrderId == null
                      ? null
                      : ordersById[d.currentOrderId]?.customerName;
                  final cap = d.capacityKg;
                  final subtitle = available
                      ? [
                          'Available',
                          if (cap != null)
                            '${cap == cap.roundToDouble() ? cap.toInt() : cap} kg',
                        ].join(' • ')
                      : d.status == WasherStatus.inUse
                          ? 'In use${busyWith != null ? ' — $busyWith' : ''}'
                          : 'Out of service';
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.dividerColor),
                    ),
                    child: ListTile(
                      enabled: available,
                      leading: Icon(
                        Icons.dry_cleaning_outlined,
                        color: available ? const Color(0xFF2F9E5B) : null,
                      ),
                      title: Text(d.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(subtitle),
                      trailing: available
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: available ? () => Navigator.pop(context, d) : null,
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

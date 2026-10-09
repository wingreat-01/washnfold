import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/washer.dart';
import '../providers/order_provider.dart';
import '../providers/waitlist.dart';
import '../providers/washer_provider.dart';
import 'washer_picker.dart';

/// Wraps the app shell and, whenever a washer frees up while orders are
/// waiting, asks the cashier whether to load the next one (rush first, then
/// first-come first-served). One tap assigns it.
///
/// Must sit below the shop providers (WasherProvider / OrderProvider).
class WasherFreePromptHost extends StatefulWidget {
  final Widget child;
  const WasherFreePromptHost({super.key, required this.child});

  @override
  State<WasherFreePromptHost> createState() => _WasherFreePromptHostState();
}

class _WasherFreePromptHostState extends State<WasherFreePromptHost> {
  StreamSubscription<Washer>? _sub;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _sub = context.read<WasherProvider>().onWasherFreed.listen(_onFreed);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onFreed(Washer freed) async {
    // Skip if a prompt is already up, or the picker sheet is open (it
    // updates live and would clash with this dialog).
    if (_showing || washerPickerOpen || !mounted) return;

    final washers = context.read<WasherProvider>();
    final orders = context.read<OrderProvider>();
    final waiting =
        computeWaitlist(orders.orders, washers.assignedOrderIds);
    if (waiting.isEmpty) return;
    final next = waiting.first;
    final services = next.items.map((i) => i.serviceName).join(', ');

    _showing = true;
    final load = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${freed.name} is free'),
        content: Text(
          'Load next in line: ${next.customerName}'
          '${services.isEmpty ? '' : ' ($services)'}'
          '${next.isRush ? ' — rush order' : ''}?'
          '${waiting.length > 1 ? '\n\n${waiting.length - 1} more waiting.' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Load ${next.customerName}')),
        ],
      ),
    );
    _showing = false;
    if (load != true || !mounted) return;

    // The machine or the order may have been taken while the dialog was open
    // (e.g. by another cashier), so check again against the live state.
    final stillFree = washers.washers
        .any((w) => w.id == freed.id && w.status == WasherStatus.available);
    if (!stillFree) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${freed.name} was just taken.')));
      return;
    }
    await loadOrderIntoWasher(context, next, freed);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

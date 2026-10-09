import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/order.dart';
import '../models/order_queue_info.dart';
import '../providers/waitlist.dart';
import '../models/public_order_status.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// The page a customer lands on after scanning their order's QR code.
/// No sign-in of any kind — the order id in the URL is the only thing
/// needed, via the get_order_public_status function (see supabase_service).
///
/// Polls every 15s instead of a realtime subscription, since anon isn't
/// granted direct table access (see schema.sql notes) — fine at MVP status-
/// check frequency; revisit if customers want live push updates instead.
class CustomerTrackingScreen extends StatefulWidget {
  final String orderId;
  const CustomerTrackingScreen({super.key, required this.orderId});

  @override
  State<CustomerTrackingScreen> createState() =>
      _CustomerTrackingScreenState();
}

class _CustomerTrackingScreenState extends State<CustomerTrackingScreen> {
  PublicOrderStatus? _status;
  OrderQueueInfo? _queue;
  bool _loading = true;
  bool _notFound = false;
  Timer? _poll;

  static const _pipeline = [
    OrderStatus.received,
    OrderStatus.washing,
    OrderStatus.drying,
    OrderStatus.foldingPressing,
    OrderStatus.ready,
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final result = await SupabaseService.instance
          .fetchPublicOrderStatus(widget.orderId);
      // Place in line, only while the order is waiting for a washer. Optional:
      // if the SQL function isn't deployed yet, the page works without it.
      OrderQueueInfo? queue;
      if (result != null && result.status == OrderStatus.received) {
        try {
          queue = await SupabaseService.instance
              .fetchOrderQueueInfo(widget.orderId);
        } catch (_) {
          queue = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _status = result;
        _notFound = result == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _notFound = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_notFound || _status == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            "We couldn't find that order.",
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Double-check the link, or ask the shop for a new QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      );
    }

    final order = _status!;
    final isPickedUp = order.status == OrderStatus.pickedUp;
    final isReady = order.status == OrderStatus.ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          order.shopName,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          'Laundry order status',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 24),
        if (isReady || isPickedUp)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: (isPickedUp ? Colors.grey : const Color(0xFF2F9E5B))
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  isPickedUp ? Icons.check_circle : Icons.local_laundry_service,
                  color: isPickedUp ? Colors.grey.shade700 : const Color(0xFF2F9E5B),
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  isPickedUp ? 'Already picked up' : 'Ready for pickup!',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isPickedUp
                            ? Colors.grey.shade700
                            : const Color(0xFF2F9E5B),
                      ),
                ),
              ],
            ),
          )
        else ...[
          if (_queue != null && order.status == OrderStatus.received) ...[
            _QueueCard(info: _queue!),
            const SizedBox(height: 16),
          ],
          _StatusStepper(currentStatus: order.status, pipeline: _pipeline),
        ],
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row(context, 'Order placed',
                    DateFormat.yMMMd().add_jm().format(order.createdAt)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatusStepper extends StatelessWidget {
  final OrderStatus currentStatus;
  final List<OrderStatus> pipeline;

  const _StatusStepper({required this.currentStatus, required this.pipeline});

  @override
  Widget build(BuildContext context) {
    final currentIndex = pipeline.indexOf(currentStatus);
    return Column(
      children: pipeline.asMap().entries.map((entry) {
        final i = entry.key;
        final status = entry.value;
        final isDone = i < currentIndex;
        final isCurrent = i == currentIndex;
        final color = isDone || isCurrent
            ? statusColor(status.asString)
            : Colors.grey.shade300;

        return Row(
          children: [
            Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone || isCurrent ? color : Colors.white,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                if (i != pipeline.length - 1)
                  Container(width: 2, height: 28, color: color),
              ],
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Text(
                status.label,
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isDone || isCurrent
                      ? Colors.black87
                      : Colors.grey.shade500,
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// "You're #2 in line" for an order still waiting for a washer.
class _QueueCard extends StatelessWidget {
  final OrderQueueInfo info;
  const _QueueCard({required this.info});

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFB7791F);
    final wait = info.estimatedWait;
    final String title;
    final String? detail;
    if (info.washerFree) {
      title = 'A washer is free';
      detail = "We'll start your laundry shortly.";
    } else {
      title = "You're #${info.position} in line";
      detail = wait == null
          ? 'Waiting for a washer to open up.'
          : 'Estimated wait for a washer: about ${formatWait(wait)}. '
              'This is only an estimate.';
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_bottom_rounded, color: amber, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: amber)),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';
import '../models/order.dart';

/// Shown right after an order is created (and re-openable from an order
/// card later) so staff can hand the customer their tracking QR — no
/// customer account, no app install, just this code.
class OrderQrDialog extends StatelessWidget {
  final Order order;

  /// When true (right after creating an order) the dialog also offers an
  /// "Assign to washer" button and pops with `true` if it's tapped.
  final bool offerWasherAssign;

  const OrderQrDialog({
    super.key,
    required this.order,
    this.offerWasherAssign = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = AppConfig.trackingUrl(order.id);

    return AlertDialog(
      title: const Text('Order created'),
      // AlertDialog measures its content with IntrinsicWidth, and QrImageView
      // contains a LayoutBuilder, which can't answer intrinsic-size queries
      // (that throws and leaves a gray screen). A fixed-width SizedBox at the
      // root answers the query itself, so the children are never asked.
      content: SizedBox(
        width: 320,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            order.customerName,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Show this to the customer, or print it on the receipt — '
            'scanning it lets them check status with no app or account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          SelectableText('Receipt reference: ${order.publicReference}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: url,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  url,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy link',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied.')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      ),
      actions: [
        if (offerWasherAssign)
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.local_laundry_service),
            label: const Text('Assign to washer'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

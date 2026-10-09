import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';

/// Permanent QR for the current shop. Print/display this at the counter;
/// customers scan it and type the reference from their receipt.
class ShopQrDialog extends StatelessWidget {
  final String shopId;
  const ShopQrDialog({super.key, required this.shopId});

  @override
  Widget build(BuildContext context) {
    final url = AppConfig.shopTrackingUrl(shopId);
    return AlertDialog(
      title: const Text('Shop tracking QR code'),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Display or print this permanent QR code at your counter. Customers scan it and enter the reference number on their receipt.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(data: url, size: 220, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          SelectableText(url, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tracking link copied.')),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy link'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

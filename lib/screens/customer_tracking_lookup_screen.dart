import 'package:flutter/material.dart';

import '../models/public_order_status.dart';
import '../services/supabase_service.dart';
import 'customer_tracking_screen.dart';

/// Public entry point for a shop's permanent QR code. Customers enter the
/// reference printed on their receipt; no account or app installation needed.
class CustomerTrackingLookupScreen extends StatefulWidget {
  final String? shopId;
  const CustomerTrackingLookupScreen({super.key, this.shopId});

  @override
  State<CustomerTrackingLookupScreen> createState() =>
      _CustomerTrackingLookupScreenState();
}

class _CustomerTrackingLookupScreenState
    extends State<CustomerTrackingLookupScreen> {
  final _referenceController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final reference = _referenceController.text.trim();
    if (reference.isEmpty) {
      setState(() => _error = 'Enter the reference number on your receipt.');
      return;
    }
    if (widget.shopId == null || widget.shopId!.isEmpty) {
      setState(() => _error =
          'This QR code is missing its shop information. Please scan the QR code displayed by your laundry shop.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await SupabaseService.instance.fetchPublicOrderStatusByReference(
        shopId: widget.shopId!,
        reference: reference,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _loading = false;
          _error = 'We could not find that order. Check the reference number and try again.';
        });
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CustomerTrackingScreen(orderId: result.id),
      ));
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Tracking is temporarily unavailable. Please try again shortly.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_laundry_service_rounded,
                          size: 52, color: colors.primary),
                      const SizedBox(height: 12),
                      Text('Track Your Laundry',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter the reference number printed on your laundry receipt.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _referenceController,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _loading ? null : _track(),
                        decoration: const InputDecoration(
                          labelText: 'Order reference number',
                          hintText: 'e.g. WF-8FEC9X',
                          prefixIcon: Icon(Icons.receipt_long_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(color: colors.error),
                            textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loading ? null : _track,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search),
                        label: Text(_loading ? 'Checking order…' : 'Track my laundry'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'For your privacy, only the order status is shown here. Keep your receipt reference private.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

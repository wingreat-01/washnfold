import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../providers/billing_provider.dart';
import '../services/supabase_service.dart';

/// Shown instead of the app once the 30-day trial is over and the shop has no
/// active subscription.
class TrialEndedScreen extends StatelessWidget {
  final bool isOwner;
  final VoidCallback onRefresh;
  const TrialEndedScreen({
    super.key,
    required this.isOwner,
    required this.onRefresh,
  });

  Future<void> _getLifetime(BuildContext context) async {
    final billing = context.read<BillingProvider>();
    if (billing.supported) {
      await billing.buyLifetime(); // Google Play (Android)
    } else {
      await _contact(); // web: no Google Play, so email
    }
  }

  Future<void> _contact() async {
    final subject = Uri.encodeComponent('Laundry Mate Lifetime Plan');
    final body = Uri.encodeComponent(
        'I would like the Lifetime Plan (₱${AppConfig.lifetimePricePhp}).');
    await launchUrl(Uri.parse(
        'mailto:${AppConfig.supportEmail}?subject=$subject&body=$body'));
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingProvider>();
    final price =
        billing.product?.price ?? '₱${AppConfig.lifetimePricePhp}';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_clock_rounded, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    'Your free trial has ended',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isOwner
                        ? 'Your 30 days are up. Get the Lifetime Plan for a '
                            'one-time ₱${AppConfig.lifetimePricePhp} (early '
                            'launch promo) to keep taking orders. Your shop '
                            'and order history are safe and will be there '
                            'when you do.'
                        : 'The shop\'s free trial is over. Ask the shop '
                            'owner to subscribe, then tap Check again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (isOwner) ...[
                    FilledButton(
                      onPressed:
                          billing.purchasing ? null : () => _getLifetime(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: billing.purchasing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text('Get the Lifetime Plan · $price'),
                      ),
                    ),
                    if (billing.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        billing.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    if (billing.supported)
                      TextButton(
                        onPressed: billing.purchasing ? null : billing.restore,
                        child: const Text('Restore purchase'),
                      ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton(
                    onPressed: onRefresh,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Check again'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => SupabaseService.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

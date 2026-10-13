import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
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

  Future<void> _contact() async {
    await launchUrl(Uri(
      scheme: 'mailto',
      path: AppConfig.supportEmail,
      queryParameters: {'subject': 'Laundry Mate subscription'},
    ));
  }

  @override
  Widget build(BuildContext context) {
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
                        ? 'Your 30 days are up. Subscribe to keep taking '
                            'orders. Your shop and order history are safe '
                            'and will be there when you do.'
                        : 'The shop\'s free trial is over. Ask the shop '
                            'owner to subscribe, then tap Check again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (isOwner) ...[
                    FilledButton(
                      onPressed: _contact,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Contact us to subscribe'),
                      ),
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

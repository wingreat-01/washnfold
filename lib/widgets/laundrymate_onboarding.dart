import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Short first-run guide for owners and staff. It explains the existing app
/// screens without changing or blocking their normal workflows.
class LaundryMateOnboarding {
  static String seenKey(String shopId, bool canViewReports) =>
      'laundrymate_guide_seen_${shopId}_${canViewReports ? 'owner' : 'staff'}';

  static Future<bool> hasSeen(String shopId, bool canViewReports) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(seenKey(shopId, canViewReports)) ?? false;
  }

  static Future<void> markSeen(String shopId, bool canViewReports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(seenKey(shopId, canViewReports), true);
  }

  static Future<void> show(BuildContext context, {required String shopId, required bool canViewReports}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OnboardingDialog(shopId: shopId, canViewReports: canViewReports),
    );
  }
}

class _GuideStep {
  final IconData icon;
  final String title;
  final String description;
  final String tip;

  const _GuideStep(this.icon, this.title, this.description, this.tip);
}

const _steps = <_GuideStep>[
  _GuideStep(
    Icons.storefront_outlined,
    'Welcome to LaundryMate',
    'This quick guide shows you how to set up your laundry shop and handle an order from drop-off to pickup.',
    'You can skip this guide and replay it anytime from Help & Tutorial.',
  ),
  _GuideStep(
    Icons.design_services_outlined,
    'Add your services',
    'Owners: open Settings, then Services. Add the services your shop offers, such as Wash & Fold, ironing, or dry cleaning, and set the correct price and pricing unit.',
    'Set up your service list before creating your first order so the correct services and prices appear.',
  ),
  _GuideStep(
    Icons.local_laundry_service_outlined,
    'Register your washers',
    'Open the Washers tab and tap Add washer. Give each machine a clear name or number so staff can identify it quickly.',
    'Use the machine status to see which washers are available, in use, or under maintenance.',
  ),
  _GuideStep(
    Icons.dry_cleaning_outlined,
    'Register your dryers',
    'Open the Dryers tab and tap Add dryer. Add each dryer your shop uses so loads can be moved from washing to drying.',
    'Keep the machine names consistent with the labels on the actual machines.',
  ),
  _GuideStep(
    Icons.add_circle_outline_rounded,
    'Create an order',
    'Open New order, enter the customer name, choose the required services, and enter the weight or quantity. Check the total, then create the order.',
    'For services priced per piece, tap the service to add pieces. For weight-based services, select the service and enter the weight.',
  ),
  _GuideStep(
    Icons.view_kanban_outlined,
    'Follow the order queue',
    'Open Queue to see orders as they move through the workflow. Update each order as work progresses and mark it ready when it is finished.',
    'Use the washer and dryer screens to assign loads and monitor machine status when those steps apply to your workflow.',
  ),
  _GuideStep(
    Icons.bar_chart_outlined,
    'Review your business',
    'Owners can use Dashboard and Sales reports to review revenue, active orders, and service activity.',
    'Check that orders and payments are recorded correctly to keep your reports useful.',
  ),
];

class _OnboardingDialog extends StatefulWidget {
  final String shopId;
  final bool canViewReports;
  const _OnboardingDialog({required this.shopId, required this.canViewReports});

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  int _index = 0;
  bool _saving = false;

  List<_GuideStep> get _visibleSteps => widget.canViewReports
      ? _steps
      : _steps.where((step) =>
          step.title != 'Add your services' &&
          step.title != 'Review your business').toList();

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    await LaundryMateOnboarding.markSeen(widget.shopId, widget.canViewReports);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _visibleSteps;
    final step = steps[_index];
    final isLast = _index == steps.length - 1;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(step.icon, size: 28,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                const Spacer(),
                Text('${_index + 1} of ${steps.length}',
                    style: Theme.of(context).textTheme.labelMedium),
              ]),
              const SizedBox(height: 20),
              Text(step.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 10),
              Text(step.description,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step.tip,
                      style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: (_index + 1) / steps.length,
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                TextButton(
                  onPressed: _saving ? null : _finish,
                  child: const Text('Skip guide'),
                ),
                const Spacer(),
                if (_index > 0)
                  TextButton(
                    onPressed: _saving ? null : () => setState(() => _index--),
                    child: const Text('Back'),
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () {
                          if (isLast) {
                            _finish();
                          } else {
                            setState(() => _index++);
                          }
                        },
                  child: Text(isLast ? 'Get started' : 'Next'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

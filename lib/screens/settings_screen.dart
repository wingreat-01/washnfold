import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/shop_access.dart';
import '../models/staff.dart';
import '../providers/billing_provider.dart';
import '../providers/currency_settings.dart';
import '../providers/service_catalog_provider.dart';
import '../providers/theme_settings.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'services_screen.dart';
import 'staff_screen.dart';
import '../widgets/privacy_policy_link.dart';
import '../utils/app_errors.dart';
import '../widgets/laundrymate_onboarding.dart';

/// Account settings: who you're signed in as, sign out, and permanent
/// account deletion (required by Google Play for apps with accounts).
class SettingsScreen extends StatelessWidget {
  final StaffRole role;
  final String shopId;
  const SettingsScreen({super.key, required this.role, required this.shopId});

  bool get _isOwner => role == StaffRole.owner;

  void _openServices(BuildContext context) {
    final catalog = context.read<ServiceCatalogProvider>();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<ServiceCatalogProvider>.value(
        value: catalog,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Services'),
            surfaceTintColor: Colors.transparent,
          ),
          body: const ServicesScreen(),
        ),
      ),
    ));
  }

  void _openStaff(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: const Text('Staff'),
          surfaceTintColor: Colors.transparent,
        ),
        body: StaffScreen(shopId: shopId),
      ),
    ));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    // Capture these now: deleting the account signs the user out, which
    // rebuilds the app root and may unmount this screen.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeleteAccountDialog(isOwner: _isOwner),
    );
    if (deleted == true) {
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = SupabaseService.instance.currentUser?.email ?? '—';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        surfaceTintColor: Colors.transparent,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionLabel('Account'),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(email),
                      subtitle: Text(_isOwner ? 'Shop owner' : 'Attendant'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text('Sign out'),
                      onTap: () {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                        SupabaseService.instance.signOut();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (_isOwner) ...[
                const _SectionLabel('Plan'),
                _PlanSection(shopId: shopId),
                const SizedBox(height: 28),
              ],
              const _SectionLabel('Appearance'),
              const Card(
                margin: EdgeInsets.zero,
                child: _ThemePicker(),
              ),
              const SizedBox(height: 28),
              const _SectionLabel('Currency'),
              const Card(
                margin: EdgeInsets.zero,
                child: _CurrencyTile(),
              ),
              if (role.canManagePricing || role.canManageStaff) ...[
                const SizedBox(height: 28),
                const _SectionLabel('Shop'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (role.canManagePricing)
                        ListTile(
                          leading: const Icon(Icons.tune_rounded),
                          title: const Text('Services'),
                          subtitle: const Text('Prices and service types'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openServices(context),
                        ),
                      if (role.canManagePricing && role.canManageStaff)
                        const Divider(height: 1),
                      if (role.canManageStaff)
                        ListTile(
                          leading: const Icon(Icons.group_outlined),
                          title: const Text('Staff'),
                          subtitle: const Text(
                              'Add attendants and switch them on or off'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openStaff(context),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              const _SectionLabel('Help'),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.help_outline_rounded),
                  title: const Text('Help & Tutorial'),
                  subtitle: const Text('Learn how to set up and use LaundryMate'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => LaundryMateOnboarding.show(context, shopId: shopId, canViewReports: role.canViewReports),
                ),
              ),
              const SizedBox(height: 28),
              const _SectionLabel('About'),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => openPrivacyPolicy(context),
                ),
              ),
              const SizedBox(height: 28),
              const _SectionLabel('Danger zone'),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.shade200),
                ),
                child: ListTile(
                  leading: Icon(Icons.delete_forever_outlined,
                      color: Colors.red.shade700),
                  title: Text(
                    'Delete account',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(_isOwner
                      ? 'Permanently deletes your login, your shop and all its orders, customers and staff accounts.'
                      : 'Permanently deletes your login. Your shop and its orders are not affected.'),
                  onTap: () => _confirmDelete(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: .6,
            color: context.palette.muted,
          ),
        ),
      );
}

/// Light / Dark / System switch. Applies immediately and is remembered on
/// this device (see ThemeSettings).
class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeSettings>().mode;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Dark'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              context.read<ThemeSettings>().setMode(selection.first),
        ),
      ),
    );
  }
}

/// The two plans: the free 30-day Trial Plan and the one-time Lifetime Plan.
/// Buying is by email for now (no in-app payment yet); the shop is switched
/// to lifetime on the server afterwards.
class _PlanSection extends StatefulWidget {
  final String shopId;
  const _PlanSection({required this.shopId});

  @override
  State<_PlanSection> createState() => _PlanSectionState();
}

class _PlanSectionState extends State<_PlanSection> {
  ShopAccess? _access;
  bool _loading = true;
  int _seenActivations = 0;

  @override
  void initState() {
    super.initState();
    _seenActivations = context.read<BillingProvider>().activations;
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await SupabaseService.instance.fetchShopAccess();
      if (mounted) setState(() => _access = a);
    } catch (e) {
      logDebug('load plan failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _getLifetime() async {
    final billing = context.read<BillingProvider>();
    if (billing.supported) {
      await billing.buyLifetime(); // Google Play (Android)
      return;
    }
    // Web: Google Play isn't available there, so fall back to email.
    final subject = Uri.encodeComponent('Laundry Mate Lifetime Plan');
    final body = Uri.encodeComponent(
        'I would like the Lifetime Plan (₱${AppConfig.lifetimePricePhp}).\n\n'
        'Shop ID: ${widget.shopId}');
    await launchUrl(Uri.parse(
        'mailto:${AppConfig.supportEmail}?subject=$subject&body=$body'));
  }

  Widget _chip(BuildContext context, String text, {bool good = true}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: good ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: good ? scheme.onPrimaryContainer : scheme.onErrorContainer,
        ),
      ),
    );
  }

  Widget _point(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final primary = Theme.of(context).colorScheme.primary;
    final billing = context.watch<BillingProvider>();
    // A purchase was just verified: re-read the plan so this card updates.
    if (billing.activations != _seenActivations) {
      _seenActivations = billing.activations;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    Widget? trialChip;
    String trialNote = 'Free for 30 days, full features.';
    if (access != null) {
      if (access.isLifetime || access.hasSubscription) {
        trialNote = 'Your trial is behind you.';
      } else if (access.onTrial) {
        final d = access.trialDaysLeft;
        trialChip = _chip(context, 'Current plan');
        trialNote = d <= 1 ? 'Last day of your trial.' : '$d days left.';
      } else {
        trialChip = _chip(context, 'Ended', good: false);
        trialNote = 'Your 30-day trial has ended.';
      }
    }
    final hasLifetime = access?.isLifetime ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Trial Plan',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    if (_loading)
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else if (trialChip != null)
                      trialChip,
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Free', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(trialNote),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: primary, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Lifetime Plan',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    if (hasLifetime)
                      _chip(context, 'Active')
                    else
                      _chip(context, 'Early launch promo'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      billing.product?.price ?? '₱${AppConfig.lifetimePricePhp}',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: primary,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 5),
                      child: Text('one-time'),
                    ),
                  ],
                ),
                _point(context, 'Pay once, use it for good'),
                _point(context, 'No monthly fees'),
                _point(context, 'Everything in the Trial Plan, with no 30-day limit'),
                if (!hasLifetime) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: billing.purchasing ? null : _getLifetime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: billing.purchasing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Get the Lifetime Plan'),
                      ),
                    ),
                  ),
                  if (billing.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      billing.error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  if (billing.supported)
                    TextButton(
                      onPressed: billing.purchasing ? null : billing.restore,
                      child: const Text('Restore purchase'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows the current currency and opens a list to change it. Remembered on
/// this device (see CurrencySettings). Only changes how amounts are shown;
/// stored prices are not converted.
class _CurrencyTile extends StatelessWidget {
  const _CurrencyTile();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CurrencySettings>().currency;
    return ListTile(
      leading: const Icon(Icons.payments_outlined),
      title: const Text('Currency'),
      subtitle: Text('${c.symbol.trim()}  ${c.name} (${c.code})'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final settings = context.read<CurrencySettings>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Choose currency',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Changes how prices and totals are shown on this device. '
                  'Existing prices are not converted.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
              ),
              for (final cur in AppCurrency.all)
                ListTile(
                  leading: SizedBox(
                    width: 40,
                    child: Text(
                      cur.symbol.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                  title: Text(cur.name),
                  subtitle: Text(cur.code),
                  trailing: cur.code == settings.currency.code
                      ? Icon(Icons.check_circle,
                          color: Theme.of(sheetContext).colorScheme.primary)
                      : null,
                  onTap: () {
                    settings.setCurrency(cur.code);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the password and the word DELETE before anything is removed.
/// Pops `true` once the account is gone.
class _DeleteAccountDialog extends StatefulWidget {
  final bool isOwner;
  const _DeleteAccountDialog({required this.isOwner});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  // Google-only logins have no password, so only ask for one when it exists.
  final bool _needsPassword = SupabaseService.instance.hasPasswordLogin;

  bool get _ready =>
      (!_needsPassword || _password.text.isNotEmpty) &&
      _confirm.text.trim().toUpperCase() == 'DELETE';

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.deleteAccount(
          password: _needsPassword ? _password.text : null);
      if (mounted) Navigator.of(context).pop(true);
    } on AccountDeletionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      logDebug('delete account failed: $e');
      if (mounted) {
        setState(() => _error = "Couldn't delete the account. Try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isOwner
                  ? 'This permanently deletes your login and your whole shop: orders, customers, services, machines, expenses and all staff accounts. Customer tracking links stop working. This cannot be undone.'
                  : 'This permanently deletes your login. Your shop and its orders stay as they are. This cannot be undone.',
            ),
            if (_needsPassword) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Your password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: (_ready && !_busy) ? _delete : null,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Delete forever'),
        ),
      ],
    );
  }
}

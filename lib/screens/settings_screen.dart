import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/staff.dart';
import '../providers/service_catalog_provider.dart';
import '../services/supabase_service.dart';
import 'services_screen.dart';
import 'staff_screen.dart';
import '../widgets/privacy_policy_link.dart';
import '../utils/app_errors.dart';

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
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: .6,
            color: Color(0xFF718096),
          ),
        ),
      );
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

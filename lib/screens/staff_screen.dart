import 'package:flutter/material.dart';

import '../models/staff.dart';
import '../services/supabase_service.dart';

/// Owner-only tab: see everyone who works in the shop, add an attendant
/// account (name + email + password), and switch an attendant on or off.
///
/// Accounts are created through the `manage-staff` Edge Function, so the
/// owner stays signed in. The new staff member signs in on the normal login
/// screen with the email and password set here.
class StaffScreen extends StatefulWidget {
  final String shopId;
  const StaffScreen({super.key, required this.shopId});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Staff> _staff = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await SupabaseService.instance.fetchStaff(widget.shopId);
      if (mounted) setState(() => _staff = list);
    } catch (e) {
      debugPrint('load staff failed: $e');
      if (mounted) setState(() => _error = "Couldn't load your staff.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddStaffSheet(),
    );
    if (added == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff account created.')),
      );
      _load();
    }
  }

  Future<void> _toggleActive(Staff s, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.setStaffActive(s.id, value);
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (_loading && _staff.isEmpty) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _staff.isEmpty) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              'Staff sign in on the login screen with the email and password '
              'you set here. Attendants can take orders and use the queue and '
              'washers; they cannot see the dashboard, prices or staff.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final s in _staff)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      s.role == StaffRole.owner
                          ? Icons.verified_user_outlined
                          : Icons.person_outline,
                    ),
                  ),
                  title: Text(
                    s.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: s.active ? null : theme.disabledColor,
                    ),
                  ),
                  subtitle: Text(
                    s.role == StaffRole.owner
                        ? 'Owner'
                        : 'Attendant${s.active ? '' : '  •  Off'}',
                  ),
                  trailing: s.role == StaffRole.owner
                      ? null
                      : Switch(
                          value: s.active,
                          onChanged: (v) => _toggleActive(s, v),
                        ),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: content,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add staff'),
      ),
    );
  }
}

class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet();

  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Please enter a name and an email.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'That email does not look right.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.createStaffAccount(
        name: name,
        email: email,
        password: password,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('create staff failed: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add staff account',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email (their login)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password (min 6 characters)',
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide' : 'Show',
                  icon: Icon(_showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              onSubmitted: (_) => _saving ? null : _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}

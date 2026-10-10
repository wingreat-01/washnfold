import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../utils/app_errors.dart';

/// Shown after the user opens the link in the "reset your password" email.
/// Supabase has already signed them in temporarily, so all that is left is
/// choosing a new password.
class ResetPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onCancel;
  const ResetPasswordScreen({
    super.key,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _passwordController.text;
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.updatePassword(password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
      widget.onDone();
    } catch (e) {
      logDebug('update password failed: $e');
      if (mounted) {
        setState(() => _error = "Couldn't update the password. If the link "
            'expired, request a new one from the sign-in screen.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/icon/logo.png', height: 72),
                  const SizedBox(height: 16),
                  Text(
                    'Set a new password',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'New password'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm new password'),
                    onSubmitted: (_) => _loading ? null : _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save new password'),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : widget.onCancel,
                    child: const Text('Cancel'),
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

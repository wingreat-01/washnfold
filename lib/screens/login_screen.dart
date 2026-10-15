import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInException, GoogleSignInExceptionCode;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/supabase_service.dart';
import '../widgets/privacy_policy_link.dart';
import '../utils/app_errors.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onSignedIn;
  const LoginScreen({super.key, required this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _shopController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // Create account is the first thing people see.
  bool _createMode = true;
  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _error;
  String? _info;

  Future<void> _google() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await SupabaseService.instance.signInWithGoogle();
      // Android: the session is ready now. Web: the page redirects to Google
      // and the app restarts signed in, so this is never reached there.
      if (mounted && SupabaseService.instance.isSignedIn) {
        widget.onSignedIn();
      }
    } on GoogleSignInException catch (e) {
      logDebug('google sign-in failed: $e');
      // Closing the account picker is not an error worth showing.
      if (e.code != GoogleSignInExceptionCode.canceled && mounted) {
        setState(() => _error = 'Google sign-in failed. Please try again.');
      }
    } catch (e) {
      logDebug('google sign-in failed: $e');
      if (mounted) {
        setState(() =>
            _error = 'Could not sign in with Google. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _info = null;
        _error = 'Type your email above first, then tap "Forgot password?".';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await SupabaseService.instance.sendPasswordReset(email);
      if (mounted) {
        setState(() => _info = 'If an account exists for $email, a reset '
            'link is on its way. Check your inbox (and spam folder).');
      }
    } catch (e) {
      logDebug('password reset failed: $e');
      if (mounted) {
        setState(() => _error =
            "Couldn't send the reset email. Wait a minute and try again.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchMode() {
    setState(() {
      _createMode = !_createMode;
      _error = null;
      _info = null;
    });
  }

  Future<void> _submit() => _createMode ? _createAccount() : _signIn();

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await SupabaseService.instance.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      widget.onSignedIn();
    } catch (e) {
      setState(() => _error = 'Could not sign in. Check your credentials.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAccount() async {
    final shop = _shopController.text.trim();
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (shop.isEmpty || name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
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
      _info = null;
    });
    try {
      final hasSession = await SupabaseService.instance
          .signUp(email: email, password: password);
      if (!hasSession) {
        // Email confirmation is turned on in Supabase.
        setState(() {
          _createMode = false;
          _info = 'Account created. Check your email to confirm it, '
              'then sign in.';
        });
        return;
      }
      await SupabaseService.instance
          .createShop(shopName: shop, ownerName: name);
      widget.onSignedIn();
    } catch (e) {
      logDebug('create account failed: $e');
      setState(() {
        if (e is AuthException) {
          // Show Supabase's real reason (already registered, weak password,
          // email rate limit, sign-ups disabled...) instead of the generic
          // "session expired" text, which is wrong for sign-up.
          _error = _signUpMessage(e);
        } else {
          _error = friendlyError(e,
              fallback: 'Could not create the account. Please try again.');
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _signUpMessage(AuthException e) {
    final m = e.message.toLowerCase();
    // Supabase sometimes puts a raw JSON blob in the message; never show that.
    final readable = e.message.trimLeft().startsWith('{') ? null : e.message;
    const generic = 'Could not create the account. Please try again.';

    if (m.contains('sending confirmation email') ||
        m.contains('error sending')) {
      return "We couldn't send your confirmation email right now. "
          'Please try again in a few minutes.';
    }
    if (m.contains('already registered') ||
        m.contains('already been registered')) {
      return 'That email already has an account. Try signing in instead.';
    }
    if (m.contains('rate limit') || e.statusCode == '429') {
      return 'Too many sign-up emails were sent. Please wait a few minutes '
          'and try again.';
    }
    if (m.contains('signups not allowed') || m.contains('signup is disabled')) {
      return 'New sign-ups are turned off right now.';
    }
    if (m.contains('password')) return readable ?? generic;
    return readable ?? generic;
  }

  @override
  void dispose() {
    _shopController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/icon/logo.png',
                  height: 88,
                  // Never show Flutter's red-X box if the logo is missing.
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.local_laundry_service_rounded,
                    size: 88,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Image.asset(
                  'assets/icon/wordmark.png',
                  height: 46,
                  fit: BoxFit.contain,
                  semanticLabel: 'Laundry Mate',
                  // Falls back to plain text if the image is missing.
                  errorBuilder: (_, __, ___) => Text(
                    'Laundry Mate',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _createMode ? 'Create your owner account' : 'Welcome back',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                if (_createMode) ...[
                  TextField(
                    controller: _shopController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Shop name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Your name'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'Hide password' : 'Show password',
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  onSubmitted: (_) => _createMode ? null : _submit(),
                ),
                if (!_createMode)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _loading ? null : _forgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                if (_createMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: !_showConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      suffixIcon: IconButton(
                        tooltip: _showConfirmPassword ? 'Hide password' : 'Show password',
                        icon: Icon(_showConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  Text(_info!, style: const TextStyle(color: Colors.green)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_createMode ? 'Create owner account' : 'Sign in'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or'),
                  ),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _google,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Continue with Google'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : _switchMode,
                  child: Text(_createMode
                      ? 'Already have an account? Sign in'
                      : "New shop? Create an owner account"),
                ),
                if (!_createMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Staff: sign in with the email and password your shop owner set up for you.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: PrivacyPolicyNotice(agreeText: _createMode),
                ),
              ],
            ),
          ),
        ),
      )),
    );
  }
}

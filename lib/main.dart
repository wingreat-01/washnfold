import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models/staff.dart';
import 'screens/app_shell.dart';
import 'screens/customer_tracking_screen.dart';
import 'screens/customer_tracking_lookup_screen.dart';
import 'screens/login_screen.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clean URLs on web (washnfold.app/track/xxxx instead of /#/track/xxxx) —
  // matters here since the tracking link is what's encoded in the QR code
  // and handed to customers.
  usePathUrlStrategy();

  await SupabaseService.instance.init(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  runApp(const WashNFoldApp());
}

/// Two branches:
///  - "/"            → staff app, requires sign-in (_RootGate → AppShell)
///  - "/track/:id"    → public customer tracking page, no login at all
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _RootGate(),
    ),
    GoRoute(
      path: '/track',
      builder: (context, state) => CustomerTrackingLookupScreen(
        shopId: state.uri.queryParameters['shop'],
      ),
    ),
    GoRoute(
      path: '/track/:orderId',
      builder: (context, state) => CustomerTrackingScreen(
        orderId: state.pathParameters['orderId']!,
      ),
    ),
  ],
);

class WashNFoldApp extends StatelessWidget {
  const WashNFoldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WashNFold',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}

/// Decides between the login screen and the app shell based on auth state,
/// and resolves the signed-in user's shop_id via the staff table before
/// handing off to AppShell (every provider downstream is scoped to a shop).
/// Only ever reached via "/" — the customer tracking route never touches
/// this or Supabase auth at all.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  String? _shopId;
  Staff? _staff; // the signed-in user's own staff row (role, active flag)
  bool _resolvingShop = false;
  String? _error;
  StreamSubscription<AuthState>? _authSub;
  final _shopNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  bool _creatingShop = false;
  String? _setupError;

  Future<void> _createShop() async {
    final shop = _shopNameController.text.trim();
    final owner = _ownerNameController.text.trim();
    if (shop.isEmpty || owner.isEmpty) {
      setState(() => _setupError = 'Please enter your shop name and your name.');
      return;
    }
    setState(() {
      _creatingShop = true;
      _setupError = null;
    });
    try {
      await SupabaseService.instance
          .createShop(shopName: shop, ownerName: owner);
      await _resolveShop();
    } catch (e) {
      debugPrint('createShop failed: $e');
      if (mounted) setState(() => _setupError = e.toString());
    } finally {
      if (mounted) setState(() => _creatingShop = false);
    }
  }

  Future<void> _resolveShop() async {
    setState(() {
      _resolvingShop = true;
      _error = null;
    });
    try {
      final staff = await SupabaseService.instance.fetchCurrentStaff();
      _staff = staff;
      _shopId = staff?.shopId;
    } catch (e) {
      debugPrint('resolveShop failed: $e');
      _staff = null;
      _shopId = null;
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _resolvingShop = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Rebuild on sign-in / sign-out so signOut() actually returns to login.
    _authSub =
        SupabaseService.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        if (mounted) {
          setState(() {
            _shopId = null;
            _staff = null;
            _error = null;
          });
        }
      }
    });
    if (SupabaseService.instance.isSignedIn) {
      _resolveShop();
    }
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.instance.isSignedIn) {
      return LoginScreen(onSignedIn: _resolveShop);
    }

    if (_resolvingShop) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_shopId == null) {
      // Signed in but no staff row yet: either a lookup error, or the
      // account was created before a shop was set up.
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      "Couldn't load your shop.\n\n$_error",
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: _resolveShop,
                      child: const Text('Retry'),
                    ),
                    const Divider(height: 32),
                  ],
                  Text(
                    'Set up your shop',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "This account isn't linked to a shop yet.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _shopNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Shop name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ownerNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    onSubmitted: (_) => _createShop(),
                  ),
                  if (_setupError != null) ...[
                    const SizedBox(height: 12),
                    Text(_setupError!,
                        style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _creatingShop ? null : _createShop,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _creatingShop
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create my shop'),
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
      );
    }

    // Switched off by the owner: block the app (the login itself is also
    // disabled server-side, this covers a session that was already open).
    if (_staff!.active == false) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'This account has been switched off',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ask the shop owner to turn it back on.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => SupabaseService.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppShell(shopId: _shopId!, role: _staff!.role);
  }
}

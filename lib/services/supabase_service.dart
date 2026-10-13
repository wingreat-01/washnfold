import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import '../config.dart';
import '../models/order_queue_info.dart';
import '../models/public_order_status.dart';
import '../models/shop_access.dart';
import '../models/sales_today.dart';
import '../models/staff.dart';

/// Thin wrapper around the Supabase client so the rest of the app never
/// touches `Supabase.instance` directly — keeps providers testable and
/// makes it obvious where all backend calls live.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  late final SupabaseClient client;

  Future<void> init({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
    client = Supabase.instance.client;
  }

  User? get currentUser => client.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  /// Starts "Continue with Google". On the web the page leaves for Google and
  /// comes back signed in (the app restarts and picks the session up). On
  /// Android the browser opens and returns through the deep link in
  /// AndroidManifest.xml; listen to the auth stream to know when it is done.
  Future<void> signInWithGoogle() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : AppConfig.mobileAuthRedirect,
      // On Android use the real system browser (it has the Google session and
      // reliably hands the custom-scheme deep link back to the app).
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  /// Sends the "reset your password" email. The link in the email opens the
  /// hosted page at <WEB_BASE_URL>/reset-password (web/reset-password/
  /// index.html), where the person chooses a new password in any browser.
  /// Supabase answers the same way whether or not the email has an account,
  /// so this never reveals who is registered.
  Future<void> sendPasswordReset(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

  /// True when this login has an email + password (owner-created staff, or a
  /// normal sign-up). A Google-only login has no password to re-check.
  bool get hasPasswordLogin {
    final providers = currentUser?.appMetadata['providers'];
    if (providers is List) return providers.contains('email');
    return currentUser?.appMetadata['provider'] == 'email';
  }

  /// Returns true if a session was created right away. Returns false when
  /// the Supabase project requires email confirmation first.
  Future<bool> signUp({
    required String email,
    required String password,
  }) async {
    final res = await client.auth.signUp(email: email, password: password);
    return res.session != null;
  }

  /// Creates the shop + owner staff row for the signed-in user via the
  /// `create_shop_for_user` Postgres function (RLS blocks direct inserts).
  Future<void> createShop({
    required String shopName,
    required String ownerName,
  }) async {
    await client.rpc('create_shop_for_user', params: {
      'p_shop_name': shopName,
      'p_owner_name': ownerName,
    });
  }

  Future<void> signOut() => client.auth.signOut();

  /// Permanently deletes the signed-in user's account (Settings → Delete
  /// account). Re-checks the password first so a borrowed, unlocked phone
  /// can't wipe a shop, then calls the `delete-account` Edge Function (it
  /// needs the service-role key). Owners lose the whole shop; attendants
  /// only lose their own login. Throws [AccountDeletionException] with a
  /// readable message on failure.
  Future<void> deleteAccount({String? password}) async {
    final email = currentUser?.email;
    if (email == null) {
      throw AccountDeletionException('You are not signed in.');
    }
    // Google-only logins have no password; the dialog's "type DELETE" step is
    // their confirmation.
    if (hasPasswordLogin) {
      if (password == null || password.isEmpty) {
        throw AccountDeletionException('Enter your password to continue.');
      }
      try {
        await client.auth.signInWithPassword(email: email, password: password);
      } on AuthException {
        throw AccountDeletionException('That password is not correct.');
      }
    }
    try {
      final res = await client.functions
          .invoke('delete-account', body: {'confirm': true});
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw AccountDeletionException(data['error'].toString());
      }
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        throw AccountDeletionException(d['error'].toString());
      }
      throw AccountDeletionException(
          "Couldn't delete the account right now. Please try again.");
    }
    // The login no longer exists server-side, so only clear the local
    // session (a global sign-out would be rejected).
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  /// The signed-in user's own staff row (shop, name, role, active flag), or
  /// null if this login isn't linked to a shop yet.
  Future<Staff?> fetchCurrentStaff() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final row = await client
        .from('staff')
        .select()
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    return row == null ? null : Staff.fromJson(row);
  }

  /// Trial / subscription status of the signed-in user's shop, read from the
  /// server (see supabase/trial_30_days.sql). Null if nothing comes back.
  Future<ShopAccess?> fetchShopAccess() async {
    final res = await client
        .rpc('get_shop_access')
        .timeout(const Duration(seconds: 10));
    if (res is! List || res.isEmpty) return null;
    return ShopAccess.fromJson(Map<String, dynamic>.from(res.first as Map));
  }

  /// All staff of a shop, owner first. Visible to the owner via the Staff tab.
  Future<List<Staff>> fetchStaff(String shopId) async {
    final rows = await client
        .from('staff')
        .select()
        .eq('shop_id', shopId)
        .order('created_at');
    final list = (rows as List)
        .map((r) => Staff.fromJson(r as Map<String, dynamic>))
        .toList();
    list.sort((a, b) {
      if (a.role != b.role) return a.role == StaffRole.owner ? -1 : 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  /// Creates an attendant login + staff row. Goes through the `manage-staff`
  /// Edge Function (service role) so the owner stays signed in.
  Future<void> createStaffAccount({
    required String name,
    required String email,
    required String password,
  }) =>
      _manageStaff({
        'action': 'create',
        'name': name,
        'email': email,
        'password': password,
      });

  Future<void> setStaffActive(String staffId, bool active) => _manageStaff({
        'action': 'set_active',
        'staff_id': staffId,
        'active': active,
      });

  Future<void> _manageStaff(Map<String, dynamic> body) async {
    try {
      final res = await client.functions.invoke('manage-staff', body: body);
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw StaffActionException(data['error'].toString());
      }
    } on FunctionException catch (e) {
      // Non-2xx replies from the function arrive here; its JSON body
      // ({"error": "..."}) is in `details`.
      final d = e.details;
      if (d is Map && d['error'] != null) {
        throw StaffActionException(d['error'].toString());
      }
      throw StaffActionException(
          "Couldn't reach the server. Please try again.");
    }
  }

  /// The signed-in staff member's own collections today plus the shop's total
  /// today (see get_my_sales_today in the part 3 SQL).
  Future<SalesToday> fetchSalesToday() async {
    final rows = await client.rpc('get_my_sales_today');
    return SalesToday.fromRows(
        (rows as List).map((r) => r as Map<String, dynamic>).toList());
  }

  /// Public, no-login lookup used by the customer tracking page (`/track/:id`).
  /// Calls the `get_order_public_status` Postgres function rather than
  /// selecting from `orders` directly, so this works even for a browser
  /// that never signed in — see supabase/schema.sql for why that's safe.
  /// Returns null if the id doesn't match any order (e.g. a mistyped link).
  Future<PublicOrderStatus?> fetchPublicOrderStatus(String orderId) async {
    final rows = await client
        .rpc('get_order_public_status', params: {'p_order_id': orderId});
    final list = rows as List;
    if (list.isEmpty) return null;
    return PublicOrderStatus.fromJson(list.first as Map<String, dynamic>);
  }

  /// Public lookup from the permanent shop QR + reference printed on receipt.
  /// The database function must scope the reference to the supplied shop and
  /// return only the minimal public status fields.
  Future<PublicOrderStatus?> fetchPublicOrderStatusByReference({
    required String shopId,
    required String reference,
  }) async {
    final rows = await client.rpc('get_order_public_status_by_reference',
        params: {
          'p_shop_id': shopId,
          'p_reference': reference.trim().toUpperCase(),
        });
    final list = rows as List;
    if (list.isEmpty) return null;
    return PublicOrderStatus.fromJson(list.first as Map<String, dynamic>);
  }

  /// Public, no-login: where a waiting order sits in line (see
  /// supabase/queue_position.sql). Returns null when the order isn't
  /// waiting for a washer. Throws if the function isn't deployed yet, so
  /// callers should treat this as optional.
  Future<OrderQueueInfo?> fetchOrderQueueInfo(String orderId) async {
    final rows = await client.rpc('get_order_queue_position', params: {
      'p_order_id': orderId,
      'p_cycle_minutes': AppConfig.washerCycleMinutes,
    });
    final list = rows as List;
    if (list.isEmpty) return null;
    return OrderQueueInfo.fromJson(list.first as Map<String, dynamic>);
  }
}

/// A readable error from the manage-staff function (e.g. "That email is
/// already in use."), safe to show to the user as-is.
class StaffActionException implements Exception {
  final String message;
  StaffActionException(this.message);
  @override
  String toString() => message;
}

/// A readable error from the delete-account function, safe to show as-is.
class AccountDeletionException implements Exception {
  final String message;
  AccountDeletionException(this.message);
  @override
  String toString() => message;
}

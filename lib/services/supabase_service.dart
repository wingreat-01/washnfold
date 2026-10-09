import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/order_queue_info.dart';
import '../models/public_order_status.dart';
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
  Future<void> deleteAccount({required String password}) async {
    final email = currentUser?.email;
    if (email == null) {
      throw AccountDeletionException('You are not signed in.');
    }
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException {
      throw AccountDeletionException('That password is not correct.');
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
          "Couldn't reach the server (${e.status}). Is the delete-account function deployed?");
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
          "Couldn't reach the server (${e.status}). Is the manage-staff function deployed?");
    }
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

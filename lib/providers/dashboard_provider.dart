import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../services/supabase_service.dart';

/// Computes the owner-facing daily/weekly/monthly numbers. Deliberately
/// simple for MVP — pulls orders in range and aggregates client-side rather
/// than standing up SQL views yet; revisit once a shop's order volume makes
/// that worth it.
class DashboardProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService.instance;
  final String shopId;

  StreamSubscription<List<Map<String, dynamic>>>? _ordersSubscription;
  Timer? _fallbackRefreshTimer;
  DateTime? _lastUpdatedAt;
  bool _disposed = false;

  DashboardProvider({required this.shopId}) {
    _subscribeToRealtimeOrders();
    // A light fallback keeps the dashboard reasonably fresh if Realtime is
    // temporarily disconnected or not enabled for the orders table.
    _fallbackRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refresh(),
    );
  }

  DateTime? get lastUpdatedAt => _lastUpdatedAt;

  void _subscribeToRealtimeOrders() {
    try {
      _ordersSubscription = _supabase.client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('shop_id', shopId)
          .listen(
        (_) => refresh(),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('dashboard realtime subscription failed: $error');
          // The periodic fallback remains active if the Realtime stream fails.
        },
      );
    } catch (e) {
      debugPrint('dashboard realtime setup failed: $e');
    }
  }

  bool _loading = false;
  String? _errorMessage;
  double _todayRevenue = 0;
  double _weekRevenue = 0;
  double _monthRevenue = 0;
  Map<String, int> _topServices = {};
  int _activeOrderCount = 0;

  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  double get todayRevenue => _todayRevenue;
  double get weekRevenue => _weekRevenue;
  double get monthRevenue => _monthRevenue;
  Map<String, int> get topServices => _topServices;
  int get activeOrderCount => _activeOrderCount;

  Future<void> refresh() async {
    if (_disposed) return;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    final rows = await _supabase.client
        .from('orders')
        .select('*, order_items(*)')
        .eq('shop_id', shopId)
        .gte('created_at', startOfMonth.toIso8601String());

    final orders = (rows as List)
        .map((r) => Order.fromJson(r as Map<String, dynamic>))
        .toList();

    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));

    double sumSince(DateTime since) => orders
        .where((o) =>
            o.paymentStatus.name == 'paid' && o.createdAt.isAfter(since))
        .fold<double>(0, (sum, o) => sum + o.total);

    _todayRevenue = sumSince(startOfToday);
    _weekRevenue = sumSince(startOfWeek);
    _monthRevenue = sumSince(startOfMonth);

    final serviceCounts = <String, int>{};
    for (final order in orders) {
      for (final item in order.items) {
        serviceCounts[item.serviceName] =
            (serviceCounts[item.serviceName] ?? 0) + 1;
      }
    }
    _topServices = Map.fromEntries(
      serviceCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
    );

    _activeOrderCount =
        orders.where((o) => o.status != OrderStatus.pickedUp).length;
    _lastUpdatedAt = DateTime.now();

    } catch (e, stackTrace) {
      _errorMessage = e.toString();
      debugPrint('dashboard refresh failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ordersSubscription?.cancel();
    _fallbackRefreshTimer?.cancel();
    super.dispose();
  }
}

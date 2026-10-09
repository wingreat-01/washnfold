import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/payment.dart';
import '../services/supabase_service.dart';

/// Thrown when a new order's customer name is already taken in this shop.
class DuplicateCustomerNameException implements Exception {
  final String name;
  const DuplicateCustomerNameException(this.name);

  @override
  String toString() => 'A customer named "$name" already exists.';
}

/// Owns the live order queue for the shop. Realtime sync is the point of
/// using Supabase here — staff on the counter and the owner's dashboard
/// both see status changes the moment they happen, no refresh needed.
class OrderProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService.instance;
  final String shopId;
  final _uuid = const Uuid();

  List<Order> _orders = [];
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  bool _loading = false;

  OrderProvider({required this.shopId});

  List<Order> get orders => List.unmodifiable(_orders);
  bool get loading => _loading;

  List<Order> get activeQueue =>
      _orders.where((o) => o.status != OrderStatus.pickedUp).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<Order> ordersByStatus(OrderStatus status) =>
      _orders.where((o) => o.status == status).toList();

  Future<void> start() async {
    _loading = true;
    notifyListeners();

    // Initial load, then subscribe to realtime changes.
    try {
      final rows = await _supabase.client
          .from('orders')
          .select('*, order_items(*)')
          .eq('shop_id', shopId)
          .order('created_at');
      _orders = (rows as List)
          .map((r) => Order.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('load orders failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }

    _sub = _supabase.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .listen((rows) async {
      try {
      // The realtime stream doesn't nest order_items, so re-fetch with the
      // join whenever something changes. Fine at MVP order volumes; revisit
      // if a shop's queue gets large enough for this to matter.
      final refreshed = await _supabase.client
          .from('orders')
          .select('*, order_items(*)')
          .eq('shop_id', shopId)
          .order('created_at');
      _orders = (refreshed as List)
          .map((r) => Order.fromJson(r as Map<String, dynamic>))
          .toList();
      notifyListeners();
      } catch (e) {
        debugPrint('refresh orders failed: $e');
      }
    });
  }

  /// Inserts a customer row for [name] using [newId]. Refuses (throws
  /// [DuplicateCustomerNameException]) if this shop already has a customer
  /// with that name, case-insensitive.
  Future<String> _ensureCustomer(String newId, String name) async {
    final escaped = name
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final existing = await _supabase.client
        .from('customers')
        .select('id')
        .eq('shop_id', shopId)
        .ilike('name', escaped)
        .limit(1)
        .maybeSingle();
    if (existing != null) throw DuplicateCustomerNameException(name);

    await _supabase.client.from('customers').insert(Customer(
          id: newId,
          shopId: shopId,
          name: name,
          createdAt: DateTime.now(),
        ).toJson());
    return newId;
  }

  /// Creates a new order with its line items, computing the total
  /// (including rush surcharge) from the items passed in.
  Future<Order> createOrder({
    required String customerId,
    required String customerName,
    String? staffId,
    required List<OrderItem> lineItems,
    bool isRush = false,
    double rushSurcharge = 0,
  }) async {
    final orderId = _uuid.v4();
    // orders.customer_id has a foreign key to customers, so the customer
    // row must exist first.
    customerId = await _ensureCustomer(customerId, customerName);
    final itemsTotal = lineItems.fold<double>(0, (sum, i) => sum + i.subtotal);
    final total = itemsTotal + (isRush ? rushSurcharge : 0);

    final order = Order(
      id: orderId,
      shopId: shopId,
      customerId: customerId,
      customerName: customerName,
      staffId: staffId,
      status: OrderStatus.received,
      isRush: isRush,
      rushSurcharge: isRush ? rushSurcharge : 0,
      total: total,
      items: lineItems,
      createdAt: DateTime.now(),
    );

    await _supabase.client.from('orders').insert(order.toJson());
    try {
      await _supabase.client.from('order_items').insert(
            lineItems
                .map((i) => {...i.toJson(), 'order_id': orderId})
                .toList(),
          );
    } catch (e) {
      // Don't leave an order with no items sitting in the queue.
      try {
        await _supabase.client.from('orders').delete().eq('id', orderId);
      } catch (_) {}
      rethrow;
    }

    return order;
  }

  /// Advances an order to the given status, stamping ready_at/picked_up_at
  /// as the pipeline reaches those stages.
  Future<void> advanceStatus(String orderId, OrderStatus status) async {
    final patch = <String, dynamic>{'status': status.asString};
    if (status == OrderStatus.ready) {
      patch['ready_at'] = DateTime.now().toIso8601String();
    }
    if (status == OrderStatus.pickedUp) {
      patch['picked_up_at'] = DateTime.now().toIso8601String();
    }
    await _supabase.client.from('orders').update(patch).eq('id', orderId);
    // Realtime subscription will pick up the change; no local mutation
    // needed, which keeps this the single source of truth.
  }

  /// Marks (or unmarks) an order as "pay after all services are finished".
  /// Stored on the order so every staff/owner device sees the same thing.
  Future<void> setPayLater(String orderId, bool value) async {
    await _supabase.client
        .from('orders')
        .update({'pay_later': value}).eq('id', orderId);
  }

  Future<void> recordPayment({
    required String orderId,
    required PaymentMethod method,
    required double amount,
  }) async {
    final payment = Payment(
      id: _uuid.v4(),
      orderId: orderId,
      method: method,
      amount: amount,
      paidAt: DateTime.now(),
    );
    await _supabase.client.from('payments').insert(payment.toJson());
    await _supabase.client
        .from('orders')
        .update({'payment_status': 'paid'}).eq('id', orderId);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

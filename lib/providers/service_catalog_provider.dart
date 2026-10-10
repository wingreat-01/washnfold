import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/service_item.dart';
import '../services/supabase_service.dart';
import '../utils/app_errors.dart';

/// Owns the shop's configurable services and pricing — what shows up when
/// an attendant builds an order (Wash & Fold, Dry Clean, add-ons, etc).
class ServiceCatalogProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService.instance;
  final String shopId;
  final _uuid = const Uuid();

  List<ServiceItem> _services = [];
  bool _loading = false;

  ServiceCatalogProvider({required this.shopId});

  List<ServiceItem> get services => List.unmodifiable(_services);
  List<ServiceItem> get activeServices =>
      _services.where((s) => s.active && !s.isAddOn).toList();
  List<ServiceItem> get activeAddOns =>
      _services.where((s) => s.active && s.isAddOn).toList();
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final rows = await _supabase.client
          .from('services')
          .select()
          .eq('shop_id', shopId)
          .order('name');
      _services = (rows as List)
          .map((r) => ServiceItem.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logDebug('load services failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Adds a new service. Throws on failure so the form can show the error.
  Future<void> addService({
    required String name,
    required PricingUnit unit,
    required double price,
    bool isAddOn = false,
    bool active = true,
    ServiceType serviceType = ServiceType.selfService,
    double? maxKg,
    double? maxKgPrice,
  }) async {
    final service = ServiceItem(
      id: _uuid.v4(),
      shopId: shopId,
      name: name,
      unit: unit,
      price: price,
      isAddOn: isAddOn,
      active: active,
      serviceType: serviceType,
      maxKg: maxKg,
      maxKgPrice: maxKgPrice,
    );
    await _supabase.client.from('services').insert(service.toJson());
    await load();
  }

  /// Edits name, price, unit, add-on flag and active flag in one go.
  Future<void> updateService(ServiceItem service) async {
    await _supabase.client.from('services').update({
      'name': service.name,
      'unit': service.unit.asString,
      'price': service.price,
      'is_add_on': service.isAddOn,
      'active': service.active,
      'service_type': service.serviceType.asString,
      'max_kg': service.maxKg,
      'max_kg_price': service.maxKgPrice,
    }).eq('id', service.id);
    await load();
  }

  /// Deletes a service. Fails if past orders reference it — in that case
  /// the caller should offer to deactivate it instead.
  Future<void> deleteService(String serviceId) async {
    await _supabase.client.from('services').delete().eq('id', serviceId);
    await load();
  }

  Future<void> updatePrice(String serviceId, double newPrice) async {
    await _supabase.client
        .from('services')
        .update({'price': newPrice}).eq('id', serviceId);
    await load();
  }

  Future<void> setActive(String serviceId, bool active) async {
    await _supabase.client
        .from('services')
        .update({'active': active}).eq('id', serviceId);
    await load();
  }
}

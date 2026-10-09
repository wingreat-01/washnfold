enum PricingUnit { kg, piece }

/// Which New order sub-tab a service shows under.
enum ServiceType { selfService, fullService }

ServiceType serviceTypeFromString(String value) =>
    value == 'full' ? ServiceType.fullService : ServiceType.selfService;

extension ServiceTypeX on ServiceType {
  String get asString => this == ServiceType.fullService ? 'full' : 'self';
  String get label =>
      this == ServiceType.fullService ? 'Full Service' : 'Self Service';
}

PricingUnit pricingUnitFromString(String value) {
  return value == 'piece' ? PricingUnit.piece : PricingUnit.kg;
}

extension PricingUnitX on PricingUnit {
  String get asString => this == PricingUnit.piece ? 'piece' : 'kg';
  String get label => this == PricingUnit.piece ? 'per piece' : 'per kg';
}

/// A configurable service the shop offers, e.g. "Wash & Fold" priced per kg,
/// or "Dry Clean — Barong" priced per piece.
class ServiceItem {
  final String id;
  final String shopId;
  final String name;
  final PricingUnit unit;
  final double price;
  final bool isAddOn;
  final bool active;
  final ServiceType serviceType;

  /// Optional flat-price tier for per-kg services: up to [maxKg] kg costs
  /// [maxKgPrice] in total. Weight beyond that is charged at the same
  /// rate, computed automatically as maxKgPrice / maxKg.
  /// e.g. maxKg 7, maxKgPrice 70  →  7 kg = ₱70, 7.5 kg = ₱75, 8 kg = ₱80.
  final double? maxKg;
  final double? maxKgPrice;

  const ServiceItem({
    required this.id,
    required this.shopId,
    required this.name,
    required this.unit,
    required this.price,
    this.isAddOn = false,
    this.active = true,
    this.serviceType = ServiceType.selfService,
    this.maxKg,
    this.maxKgPrice,
  });

  bool get hasMaxKgPricing =>
      unit == PricingUnit.kg &&
      !isAddOn &&
      maxKg != null &&
      maxKg! > 0 &&
      maxKgPrice != null;

  /// Auto-computed rate for each kg above [maxKg]: flat price ÷ max kg.
  double get extraKgRate => hasMaxKgPricing ? maxKgPrice! / maxKg! : price;

  /// Total charge for [qty] kg (or pieces). Single source of truth —
  /// used for the live total, the saved line item, and receipts.
  double priceFor(double qty) {
    if (qty <= 0) return 0;
    if (!hasMaxKgPricing) return qty * price;
    if (qty <= maxKg!) return maxKgPrice!;
    return maxKgPrice! + (qty - maxKg!) * extraKgRate;
  }

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Human-readable pricing line, e.g. "₱70.00 up to 7 kg, then ₱7.00 per extra kg".
  String pricingSummary(String Function(double) fmt) {
    if (hasMaxKgPricing) {
      return '${fmt(maxKgPrice!)} up to ${_kg(maxKg!)} kg, '
          'then ${fmt(extraKgRate)} per extra kg';
    }
    return '${fmt(price)} ${unit.label}';
  }

  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    return ServiceItem(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      name: json['name'] as String,
      unit: pricingUnitFromString(json['unit'] as String? ?? 'kg'),
      price: (json['price'] as num).toDouble(),
      isAddOn: json['is_add_on'] as bool? ?? false,
      active: json['active'] as bool? ?? true,
      serviceType:
          serviceTypeFromString(json['service_type'] as String? ?? 'self'),
      maxKg: (json['max_kg'] as num?)?.toDouble(),
      maxKgPrice: (json['max_kg_price'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'name': name,
        'unit': unit.asString,
        'price': price,
        'is_add_on': isAddOn,
        'active': active,
        'service_type': serviceType.asString,
        'max_kg': maxKg,
        'max_kg_price': maxKgPrice,
      };
}

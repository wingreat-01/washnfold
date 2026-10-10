import 'dart:math';

import 'order_item.dart';

enum OrderStatus {
  received,
  washing,
  drying,
  foldingPressing,
  ready,
  pickedUp,
}

OrderStatus orderStatusFromString(String value) {
  switch (value) {
    case 'washing':
      return OrderStatus.washing;
    case 'drying':
      return OrderStatus.drying;
    case 'folding_pressing':
      return OrderStatus.foldingPressing;
    case 'ready':
      return OrderStatus.ready;
    case 'picked_up':
      return OrderStatus.pickedUp;
    case 'received':
    default:
      return OrderStatus.received;
  }
}

extension OrderStatusX on OrderStatus {
  String get asString {
    switch (this) {
      case OrderStatus.received:
        return 'received';
      case OrderStatus.washing:
        return 'washing';
      case OrderStatus.drying:
        return 'drying';
      case OrderStatus.foldingPressing:
        return 'folding_pressing';
      case OrderStatus.ready:
        return 'ready';
      case OrderStatus.pickedUp:
        return 'picked_up';
    }
  }

  String get label {
    switch (this) {
      case OrderStatus.received:
        return 'Received';
      case OrderStatus.washing:
        return 'Washing';
      case OrderStatus.drying:
        return 'Drying';
      case OrderStatus.foldingPressing:
        return 'Folding';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.pickedUp:
        return 'Picked up';
    }
  }

  /// The pipeline is linear; this returns the next stage, or null if
  /// already at the end.
  OrderStatus? get next {
    const pipeline = OrderStatus.values;
    final i = pipeline.indexOf(this);
    if (i == -1 || i == pipeline.length - 1) return null;
    return pipeline[i + 1];
  }
}

enum PaymentStatus { unpaid, paid }

PaymentStatus paymentStatusFromString(String value) =>
    value == 'paid' ? PaymentStatus.paid : PaymentStatus.unpaid;

/// Short receipt reference such as "WF-8FEC9X" (9 characters including the dash).
/// Uses an alphabet without look-alike characters (no 0/O, 1/I/L).
const _refAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
final _refRandom = Random.secure();

String generatePublicReference() {
  final code = List.generate(
    6,
    (_) => _refAlphabet[_refRandom.nextInt(_refAlphabet.length)],
  ).join();
  return 'WF-$code';
}

class Order {
  final String id;
  /// Human-friendly tracking reference printed on the receipt.
  final String publicReference;
  final String shopId;
  final String customerId;
  final String customerName;
  final String? staffId;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final bool isRush;

  /// Cashier chose "Keep in queue" while every washer was busy, so payment
  /// is collected after all services are finished (shared across devices).
  final bool payLater;
  final double rushSurcharge;
  final double total;
  final List<OrderItem> items;
  final DateTime createdAt;
  final DateTime? readyAt;
  final DateTime? pickedUpAt;

  Order({
    required this.id,
    String? publicReference,
    required this.shopId,
    required this.customerId,
    required this.customerName,
    this.staffId,
    required this.status,
    this.paymentStatus = PaymentStatus.unpaid,
    this.isRush = false,
    this.payLater = false,
    this.rushSurcharge = 0,
    required this.total,
    this.items = const [],
    required this.createdAt,
    this.readyAt,
    this.pickedUpAt,
  }) : publicReference = publicReference ?? generatePublicReference();

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      publicReference: json['public_reference'] as String?,
      shopId: json['shop_id'] as String,
      customerId: json['customer_id'] as String,
      customerName: json['customer_name'] as String? ?? 'Walk-in',
      staffId: json['staff_id'] as String?,
      status: orderStatusFromString(json['status'] as String? ?? 'received'),
      paymentStatus:
          paymentStatusFromString(json['payment_status'] as String? ?? 'unpaid'),
      isRush: json['is_rush'] as bool? ?? false,
      payLater: json['pay_later'] as bool? ?? false,
      rushSurcharge: (json['rush_surcharge'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num).toDouble(),
      items: (json['order_items'] as List<dynamic>? ?? [])
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      readyAt: json['ready_at'] != null
          ? DateTime.parse(json['ready_at'] as String)
          : null,
      pickedUpAt: json['picked_up_at'] != null
          ? DateTime.parse(json['picked_up_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'public_reference': publicReference,
        'shop_id': shopId,
        'customer_id': customerId,
        'customer_name': customerName,
        'staff_id': staffId,
        'status': status.asString,
        'payment_status':
            paymentStatus == PaymentStatus.paid ? 'paid' : 'unpaid',
        'is_rush': isRush,
        'rush_surcharge': rushSurcharge,
        'total': total,
        'created_at': createdAt.toIso8601String(),
        'ready_at': readyAt?.toIso8601String(),
        'picked_up_at': pickedUpAt?.toIso8601String(),
      };

  Order copyWith({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    bool? payLater,
    DateTime? readyAt,
    DateTime? pickedUpAt,
  }) {
    return Order(
      id: id,
      publicReference: publicReference,
      shopId: shopId,
      customerId: customerId,
      customerName: customerName,
      staffId: staffId,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      isRush: isRush,
      payLater: payLater ?? this.payLater,
      rushSurcharge: rushSurcharge,
      total: total,
      items: items,
      createdAt: createdAt,
      readyAt: readyAt ?? this.readyAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
    );
  }
}

/// Which flow an order follows, decided from its service NAMES (there is no
/// separate flag on a service):
///  - wash only  : some item has "wash" in its name and no item mentions
///                 dry / fold / full  -> the customer takes the load out of
///                 the washer, so the washer gets a Release button.
///  - everything else (wash+dry, wash+dry+fold, full service, dry clean...)
///                 follows the queue: Washer -> "Assign to dryer" -> dryer ->
///                 "Send to folding area".
extension OrderFlowX on Order {
  Iterable<String> get _serviceNames =>
      items.map((i) => i.serviceName.toLowerCase());

  bool get isWashOnly {
    final names = _serviceNames.toList();
    final hasWash = names.any((n) => n.contains('wash'));
    final hasMore = names.any(
        (n) => n.contains('dry') || n.contains('fold') || n.contains('full'));
    return hasWash && !hasMore;
  }
}

import 'order.dart';

/// The minimal, non-sensitive slice of an order that the public tracking
/// page (no customer login) is allowed to see — returned by the
/// `get_order_public_status` Postgres function, never by querying the
/// `orders` table directly.
class PublicOrderStatus {
  final String id;
  final String shopName;
  final String customerName;
  final OrderStatus status;
  final bool isRush;
  final double total;
  final String paymentStatus;
  final DateTime createdAt;
  final DateTime? readyAt;
  final DateTime? pickedUpAt;

  const PublicOrderStatus({
    required this.id,
    required this.shopName,
    required this.customerName,
    required this.status,
    required this.isRush,
    required this.total,
    required this.paymentStatus,
    required this.createdAt,
    this.readyAt,
    this.pickedUpAt,
  });

  factory PublicOrderStatus.fromJson(Map<String, dynamic> json) {
    return PublicOrderStatus(
      id: json['id'] as String,
      shopName: json['shop_name'] as String? ?? 'Laundry shop',
      customerName: json['customer_name'] as String? ?? 'Customer',
      status: orderStatusFromString(json['status'] as String? ?? 'received'),
      isRush: json['is_rush'] as bool? ?? false,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      createdAt: DateTime.parse(json['created_at'] as String),
      readyAt: json['ready_at'] != null
          ? DateTime.parse(json['ready_at'] as String)
          : null,
      pickedUpAt: json['picked_up_at'] != null
          ? DateTime.parse(json['picked_up_at'] as String)
          : null,
    );
  }
}

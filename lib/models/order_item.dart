/// One line item on an order — a service applied at a given weight/piece count.
class OrderItem {
  final String id;
  final String orderId;
  final String serviceId;
  final String serviceName;
  final double quantity; // kg or piece count, depending on the service's unit
  final double subtotal;

  const OrderItem({
    required this.id,
    required this.orderId,
    required this.serviceId,
    required this.serviceName,
    required this.quantity,
    required this.subtotal,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      serviceId: json['service_id'] as String,
      serviceName: json['service_name'] as String? ?? '',
      quantity: (json['quantity'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'order_id': orderId,
        'service_id': serviceId,
        'service_name': serviceName,
        'quantity': quantity,
        'subtotal': subtotal,
      };
}

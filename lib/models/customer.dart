class Customer {
  final String id;
  final String shopId;
  final String name;
  final String? phone;
  final int loyaltyPoints;
  final DateTime createdAt;

  const Customer({
    required this.id,
    required this.shopId,
    required this.name,
    this.phone,
    this.loyaltyPoints = 0,
    required this.createdAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      loyaltyPoints: json['loyalty_points'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'name': name,
        'phone': phone,
        'loyalty_points': loyaltyPoints,
        'created_at': createdAt.toIso8601String(),
      };
}

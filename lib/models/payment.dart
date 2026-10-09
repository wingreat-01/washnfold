enum PaymentMethod { cash, gcash, maya, card }

PaymentMethod paymentMethodFromString(String value) {
  switch (value) {
    case 'gcash':
      return PaymentMethod.gcash;
    case 'maya':
      return PaymentMethod.maya;
    case 'card':
      return PaymentMethod.card;
    case 'cash':
    default:
      return PaymentMethod.cash;
  }
}

extension PaymentMethodX on PaymentMethod {
  String get asString => name;
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.gcash:
        return 'GCash';
      case PaymentMethod.maya:
        return 'Maya';
      case PaymentMethod.card:
        return 'Card';
    }
  }
}

class Payment {
  final String id;
  final String orderId;
  final PaymentMethod method;
  final double amount;
  final DateTime paidAt;

  const Payment({
    required this.id,
    required this.orderId,
    required this.method,
    required this.amount,
    required this.paidAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      method: paymentMethodFromString(json['method'] as String? ?? 'cash'),
      amount: (json['amount'] as num).toDouble(),
      paidAt: DateTime.parse(json['paid_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'order_id': orderId,
        'method': method.asString,
        'amount': amount,
        'paid_at': paidAt.toIso8601String(),
      };
}

class Expense {
  final String id;
  final String shopId;
  final String category;
  final double amount;
  final DateTime date;

  const Expense({
    required this.id,
    required this.shopId,
    required this.category,
    required this.amount,
    required this.date,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'category': category,
        'amount': amount,
        'date': date.toIso8601String(),
      };
}

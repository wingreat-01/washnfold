class InventoryItem {
  final String id;
  final String shopId;
  final String itemName;
  final double qty;
  final double reorderThreshold;

  const InventoryItem({
    required this.id,
    required this.shopId,
    required this.itemName,
    required this.qty,
    required this.reorderThreshold,
  });

  bool get isLow => qty <= reorderThreshold;

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      itemName: json['item_name'] as String,
      qty: (json['qty'] as num).toDouble(),
      reorderThreshold: (json['reorder_threshold'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'item_name': itemName,
        'qty': qty,
        'reorder_threshold': reorderThreshold,
      };
}

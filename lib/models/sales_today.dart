/// Today's collections for the signed-in staff member, plus the whole shop's
/// total, as returned by the `get_my_sales_today` database function.
/// "Today" is the Philippine calendar day (decided in the database).
class SalesToday {
  /// This person's own collections today, by payment method
  /// (cash / gcash / maya / card).
  final Map<String, double> mineByMethod;
  final int mineOrders;
  final int minePayments;

  /// Everything the shop collected today, all staff together.
  final double shopTotal;
  final int shopOrders;

  const SalesToday({
    this.mineByMethod = const {},
    this.mineOrders = 0,
    this.minePayments = 0,
    this.shopTotal = 0,
    this.shopOrders = 0,
  });

  double get mineTotal => mineByMethod.values.fold(0.0, (a, b) => a + b);
  double get mineCash => mineByMethod['cash'] ?? 0;

  factory SalesToday.fromRows(List<Map<String, dynamic>> rows) {
    final mine = <String, double>{};
    var mineOrders = 0;
    var minePayments = 0;
    var shopTotal = 0.0;
    var shopOrders = 0;
    for (final r in rows) {
      final total = (r['total'] as num?)?.toDouble() ?? 0;
      final orders = (r['order_count'] as num?)?.toInt() ?? 0;
      final payments = (r['payment_count'] as num?)?.toInt() ?? 0;
      if (r['scope'] == 'shop') {
        shopTotal = total;
        shopOrders = orders;
      } else if (r['scope'] == 'mine') {
        final method = (r['method'] as String? ?? 'cash').toLowerCase();
        mine[method] = (mine[method] ?? 0) + total;
        minePayments += payments;
        // An order paid with two methods is counted once per method here; the
        // payment count is the reliable figure, orders is a close estimate.
        mineOrders += orders;
      }
    }
    return SalesToday(
      mineByMethod: mine,
      mineOrders: mineOrders,
      minePayments: minePayments,
      shopTotal: shopTotal,
      shopOrders: shopOrders,
    );
  }
}

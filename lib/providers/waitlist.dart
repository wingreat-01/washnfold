import '../models/order.dart';

/// Orders that are Received but not yet loaded into any washer, in the order
/// they will be served: rush orders first, then first-come first-served.
///
/// [assignedOrderIds] is WasherProvider.assignedOrderIds (orders currently
/// sitting in a machine).
List<Order> computeWaitlist(
  Iterable<Order> orders,
  Set<String> assignedOrderIds,
) {
  final waiting = orders
      .where((o) =>
          o.status == OrderStatus.received && !assignedOrderIds.contains(o.id))
      .toList();
  waiting.sort((a, b) {
    if (a.isRush != b.isRush) return a.isRush ? -1 : 1;
    return a.createdAt.compareTo(b.createdAt);
  });
  return waiting;
}

/// "any moment now", "12 min", "1 h 5 min".
String formatWait(Duration d) {
  final mins = (d.inSeconds / 60).ceil();
  if (mins <= 0) return 'any moment now';
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Rough wait for the order at [position] in the waitlist (1 = next in
/// line).
///
/// [availableCount]: washers free right now. [remainingFinishes]: for each
/// running washer, how long until its current load is expected to finish
/// (may be negative if overdue). Beyond the running machines, each one is
/// assumed to be reloaded and run another full [cycle].
///
/// Returns Duration.zero if a washer is free for this position, or null if
/// nothing is running so there is nothing to base an estimate on.
Duration? estimateWait({
  required int position,
  required int availableCount,
  required List<Duration> remainingFinishes,
  required Duration cycle,
}) {
  if (position <= availableCount) return Duration.zero;
  if (remainingFinishes.isEmpty) return null;
  final sorted = [...remainingFinishes]..sort();
  final idx = position - availableCount - 1;
  final wait = sorted[idx % sorted.length] + cycle * (idx ~/ sorted.length);
  return wait.isNegative ? Duration.zero : wait;
}

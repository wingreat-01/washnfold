import '../config.dart';
import '../providers/waitlist.dart';

/// Where a still-waiting order stands in line, as returned by the public
/// `get_order_queue_position` Postgres function (see
/// supabase/queue_position.sql). Only exists for orders that are Received
/// and not yet in a washer.
class OrderQueueInfo {
  final int position;
  final int availableWashers;

  /// Time left on each running washer's current load, soonest first.
  final List<Duration> runningRemaining;

  const OrderQueueInfo({
    required this.position,
    required this.availableWashers,
    required this.runningRemaining,
  });

  factory OrderQueueInfo.fromJson(Map<String, dynamic> json) {
    final secs = (json['running_remaining_secs'] as List<dynamic>? ?? [])
        .map((e) => Duration(seconds: (e as num).toInt()))
        .toList();
    return OrderQueueInfo(
      position: (json['queue_position'] as num).toInt(),
      availableWashers: (json['available_washers'] as num?)?.toInt() ?? 0,
      runningRemaining: secs,
    );
  }

  /// A washer is free for this order right now.
  bool get washerFree => position <= availableWashers;

  /// Estimated wait, zero if a washer is free, null if nothing is running.
  Duration? get estimatedWait => estimateWait(
        position: position,
        availableCount: availableWashers,
        remainingFinishes: runningRemaining,
        cycle: Duration(minutes: AppConfig.washerCycleMinutes),
      );
}

import '../config.dart';
import 'washer.dart';

/// A physical dryer in the shop. Same shape as [Washer] and it reuses
/// [WasherStatus] (available / in use / maintenance) since the states are
/// identical. When in use, [currentOrderId] is the order being dried and
/// [startedAt] is when the load went in.
class Dryer {
  final String id;
  final String shopId;
  final String name;
  final double? capacityKg;
  final WasherStatus status;
  final String? currentOrderId;
  final DateTime? startedAt;
  final String? notes;

  /// Minutes one load takes on this machine; null = shop default.
  final int? cycleMinutes;

  /// Adjusted finish time for the load now in the machine; null = start +
  /// this machine's cycle.
  final DateTime? endsAt;

  const Dryer({
    required this.id,
    required this.shopId,
    required this.name,
    this.capacityKg,
    this.status = WasherStatus.available,
    this.currentOrderId,
    this.startedAt,
    this.notes,
    this.cycleMinutes,
    this.endsAt,
  });

  factory Dryer.fromJson(Map<String, dynamic> json) {
    return Dryer(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      name: json['name'] as String,
      capacityKg: (json['capacity_kg'] as num?)?.toDouble(),
      status: washerStatusFromString(json['status'] as String? ?? 'available'),
      currentOrderId: json['current_order_id'] as String?,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String).toLocal()
          : null,
      notes: json['notes'] as String?,
      cycleMinutes: (json['cycle_minutes'] as num?)?.toInt(),
      endsAt: json['ends_at'] != null
          ? DateTime.parse(json['ends_at'] as String).toLocal()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'name': name,
        'capacity_kg': capacityKg,
        'status': status.asString,
        'current_order_id': currentOrderId,
        'started_at': startedAt?.toUtc().toIso8601String(),
        'notes': notes,
        if (cycleMinutes != null) 'cycle_minutes': cycleMinutes,
        if (endsAt != null) 'ends_at': endsAt!.toUtc().toIso8601String(),
      };

  /// Minutes one load takes here (this machine's setting, else the default).
  int get effectiveCycleMinutes =>
      cycleMinutes ?? AppConfig.dryerCycleMinutes;

  /// When the load now in the machine should be done: the adjusted end time
  /// if someone set one, else start + this machine's cycle. Null when idle.
  DateTime? get expectedEnd {
    if (status != WasherStatus.inUse) return null;
    return endsAt ??
        startedAt?.add(Duration(minutes: effectiveCycleMinutes));
  }
}

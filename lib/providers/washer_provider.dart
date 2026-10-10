import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models/washer.dart';
import '../services/supabase_service.dart';
import 'waitlist.dart';
import '../utils/app_errors.dart';

/// Owns the shop's washers. Same realtime pattern as OrderProvider: initial
/// load, then a Supabase stream so every cashier's screen updates the moment
/// someone assigns or releases a machine.
class WasherProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService.instance;
  final String shopId;
  final _uuid = const Uuid();

  List<Washer> _washers = [];

  /// Fires whenever a washer goes from In use / Maintenance back to
  /// Available (from this device or any other). The app shell listens to it
  /// to offer the next waiting order.
  final _freedController = StreamController<Washer>.broadcast();
  Stream<Washer> get onWasherFreed => _freedController.stream;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  bool _loading = false;

  WasherProvider({required this.shopId});

  List<Washer> get washers => List.unmodifiable(_washers);
  bool get loading => _loading;

  int countByStatus(WasherStatus s) =>
      _washers.where((w) => w.status == s).length;

  int get availableCount => countByStatus(WasherStatus.available);

  /// Replaces the washer list and announces any machine that just became
  /// available. Both the realtime stream and manual reloads go through here
  /// so a release is announced exactly once.
  void _applyWashers(List<Washer> next) {
    final before = {for (final w in _washers) w.id: w.status};
    _washers = next;
    for (final w in next) {
      final was = before[w.id];
      if (was != null &&
          was != WasherStatus.available &&
          w.status == WasherStatus.available) {
        _freedController.add(w);
      }
    }
  }

  /// When each running washer is expected to finish (start + typical cycle),
  /// soonest first.
  List<MapEntry<Washer, DateTime>> _expectedFinishes() {
    final now = DateTime.now();
    final list = _washers
        .where((w) => w.status == WasherStatus.inUse)
        .map((w) => MapEntry(
            w, w.expectedEnd ?? now.add(Duration(minutes: w.effectiveCycleMinutes))))
        .toList();
    list.sort((a, b) => a.value.compareTo(b.value));
    return list;
  }

  /// The running washer expected to finish first, or null if none is running.
  Washer? get nextWasherToFree {
    final f = _expectedFinishes();
    return f.isEmpty ? null : f.first.key;
  }

  /// Rough wait until a washer is free for the order at [position] in the
  /// waitlist (1 = next in line). Zero if a washer is free for it right now
  /// or is overdue; null if nothing is running, so there is nothing to base
  /// an estimate on (e.g. every washer is in maintenance).
  Duration? estimatedWait({int position = 1}) {
    final now = DateTime.now();
    return estimateWait(
      position: position,
      availableCount: availableCount,
      remainingFinishes:
          _expectedFinishes().map((e) => e.value.difference(now)).toList(),
      cycle: Duration(minutes: AppConfig.washerCycleMinutes),
    );
  }

  /// Order ids currently sitting in a washer — used to hide them from the
  /// "assign" picker so one order can't be put in two machines.
  Set<String> get assignedOrderIds => _washers
      .where((w) => w.currentOrderId != null)
      .map((w) => w.currentOrderId!)
      .toSet();

  Future<void> start() async {
    _loading = true;
    notifyListeners();
    try {
      await _reload();
    } catch (e) {
      logDebug('load washers failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }

    _sub = _supabase.client
        .from('washers')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .listen((rows) {
      _applyWashers(_sorted(rows.map(Washer.fromJson).toList()));
      notifyListeners();
    }, onError: (e) => logDebug('washer stream error: $e'));
  }

  Future<void> _reload() async {
    final rows = await _supabase.client
        .from('washers')
        .select()
        .eq('shop_id', shopId);
    _applyWashers(_sorted((rows as List)
        .map((r) => Washer.fromJson(r as Map<String, dynamic>))
        .toList()));
  }

  /// Natural-ish sort so "Washer 2" comes before "Washer 10".
  List<Washer> _sorted(List<Washer> list) {
    int? num(String s) {
      final m = RegExp(r'(\d+)').firstMatch(s);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    list.sort((a, b) {
      final na = num(a.name), nb = num(b.name);
      if (na != null && nb != null && na != nb) return na.compareTo(nb);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Future<void> addWasher({
    required String name,
    double? capacityKg,
    String? notes,
    int? cycleMinutes,
  }) async {
    final washer = Washer(
      id: _uuid.v4(),
      shopId: shopId,
      name: name,
      capacityKg: capacityKg,
      notes: notes,
      cycleMinutes: cycleMinutes,
    );
    await _supabase.client.from('washers').insert(washer.toJson());
    await _reload();
    notifyListeners();
  }

  /// Edits name / capacity / notes, and lets the user flip between
  /// available and maintenance (never touches an in-use machine's order).
  Future<void> updateWasher(
    String id, {
    required String name,
    double? capacityKg,
    String? notes,
    int? cycleMinutes,
    WasherStatus? status,
  }) async {
    final patch = <String, dynamic>{
      'name': name,
      'capacity_kg': capacityKg,
      'notes': notes,
      if (cycleMinutes != null) 'cycle_minutes': cycleMinutes,
    };
    if (status != null) patch['status'] = status.asString;
    await _supabase.client.from('washers').update(patch).eq('id', id);
    await _reload();
    notifyListeners();
  }

  Future<void> deleteWasher(String id) async {
    await _supabase.client.from('washers').delete().eq('id', id);
    await _reload();
    notifyListeners();
  }

  /// How long one load runs on this machine (its own setting, else the
  /// shop default).
  Duration _cycleFor(String id) {
    int? mins;
    for (final m in _washers) {
      if (m.id == id) mins = m.cycleMinutes;
    }
    return Duration(minutes: mins ?? AppConfig.washerCycleMinutes);
  }

  /// Sets when the load now in the machine will be done (the timer edit
  /// on the card). Only touches a machine that is currently in use.
  Future<void> setEndsAt(String id, DateTime endsAt) async {
    await _supabase.client
        .from('washers')
        .update({'ends_at': endsAt.toUtc().toIso8601String()})
        .eq('id', id)
        .eq('status', WasherStatus.inUse.asString);
    await _reload();
    notifyListeners();
  }

  /// Puts [orderId] into the washer. The `.eq('status', 'available')` guard
  /// makes this safe when two cashiers tap the same machine at once: the
  /// second update matches zero rows and we throw instead of overwriting.
  Future<void> assignOrder(String washerId, String orderId) async {
    final startedUtc = DateTime.now().toUtc();
    final updated = await _supabase.client
        .from('washers')
        .update({
          'status': WasherStatus.inUse.asString,
          'current_order_id': orderId,
          'started_at': startedUtc.toIso8601String(),
          'ends_at': startedUtc.add(_cycleFor(washerId)).toIso8601String(),
        })
        .eq('id', washerId)
        .eq('status', WasherStatus.available.asString)
        .select();
    if ((updated as List).isEmpty) {
      await _reload();
      notifyListeners();
      throw StateError('That washer is no longer available.');
    }
    await _reload();
    notifyListeners();
  }

  /// Frees the washer (load finished or assigned by mistake).
  Future<void> release(String washerId) async {
    await _supabase.client.from('washers').update({
      'status': WasherStatus.available.asString,
      'current_order_id': null,
      'started_at': null,
      'ends_at': null,
    }).eq('id', washerId);
    await _reload();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _freedController.close();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models/dryer.dart';
import '../models/washer.dart'; // WasherStatus is shared by washers and dryers
import '../services/supabase_service.dart';
import '../utils/app_errors.dart';

/// Owns the shop's dryers. Same realtime pattern as OrderProvider: initial
/// load, then a Supabase stream so every cashier's screen updates the moment
/// someone assigns or releases a dryer.
class DryerProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService.instance;
  final String shopId;
  final _uuid = const Uuid();

  List<Dryer> _dryers = [];
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  bool _loading = false;

  DryerProvider({required this.shopId});

  List<Dryer> get dryers => List.unmodifiable(_dryers);
  bool get loading => _loading;

  int countByStatus(WasherStatus s) =>
      _dryers.where((w) => w.status == s).length;

  /// Order ids currently sitting in a dryer — used to hide them from the
  /// "assign" picker so one order can't be put in two machines.
  Set<String> get assignedOrderIds => _dryers
      .where((w) => w.currentOrderId != null)
      .map((w) => w.currentOrderId!)
      .toSet();

  Future<void> start() async {
    _loading = true;
    notifyListeners();
    try {
      await _reload();
    } catch (e) {
      logDebug('load dryers failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }

    _sub = _supabase.client
        .from('dryers')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .listen((rows) {
      _dryers = _sorted(rows.map(Dryer.fromJson).toList());
      notifyListeners();
    }, onError: (e) => logDebug('dryer stream error: $e'));
  }

  Future<void> _reload() async {
    final rows = await _supabase.client
        .from('dryers')
        .select()
        .eq('shop_id', shopId);
    _dryers = _sorted((rows as List)
        .map((r) => Dryer.fromJson(r as Map<String, dynamic>))
        .toList());
  }

  /// Natural-ish sort so "Dryer 2" comes before "Dryer 10".
  List<Dryer> _sorted(List<Dryer> list) {
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

  Future<void> addDryer({
    required String name,
    double? capacityKg,
    String? notes,
    int? cycleMinutes,
  }) async {
    final dryer = Dryer(
      id: _uuid.v4(),
      shopId: shopId,
      name: name,
      capacityKg: capacityKg,
      notes: notes,
      cycleMinutes: cycleMinutes,
    );
    await _supabase.client.from('dryers').insert(dryer.toJson());
    await _reload();
    notifyListeners();
  }

  /// Edits name / capacity / notes, and lets the user flip between
  /// available and maintenance (never touches an in-use machine's order).
  Future<void> updateDryer(
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
    await _supabase.client.from('dryers').update(patch).eq('id', id);
    await _reload();
    notifyListeners();
  }

  Future<void> deleteDryer(String id) async {
    await _supabase.client.from('dryers').delete().eq('id', id);
    await _reload();
    notifyListeners();
  }

  /// How long one load runs on this machine (its own setting, else the
  /// shop default).
  Duration _cycleFor(String id) {
    int? mins;
    for (final m in _dryers) {
      if (m.id == id) mins = m.cycleMinutes;
    }
    return Duration(minutes: mins ?? AppConfig.dryerCycleMinutes);
  }

  /// Sets when the load now in the machine will be done (the timer edit
  /// on the card). Only touches a machine that is currently in use.
  Future<void> setEndsAt(String id, DateTime endsAt) async {
    await _supabase.client
        .from('dryers')
        .update({'ends_at': endsAt.toUtc().toIso8601String()})
        .eq('id', id)
        .eq('status', WasherStatus.inUse.asString);
    await _reload();
    notifyListeners();
  }

  /// Puts [orderId] into the dryer. The `.eq('status', 'available')` guard
  /// makes this safe when two cashiers tap the same machine at once: the
  /// second update matches zero rows and we throw instead of overwriting.
  Future<void> assignOrder(String dryerId, String orderId) async {
    final startedUtc = DateTime.now().toUtc();
    final updated = await _supabase.client
        .from('dryers')
        .update({
          'status': WasherStatus.inUse.asString,
          'current_order_id': orderId,
          'started_at': startedUtc.toIso8601String(),
          'ends_at': startedUtc.add(_cycleFor(dryerId)).toIso8601String(),
        })
        .eq('id', dryerId)
        .eq('status', WasherStatus.available.asString)
        .select();
    if ((updated as List).isEmpty) {
      await _reload();
      notifyListeners();
      throw StateError('That dryer is no longer available.');
    }
    await _reload();
    notifyListeners();
  }

  /// Frees the dryer (load finished or assigned by mistake).
  Future<void> release(String dryerId) async {
    await _supabase.client.from('dryers').update({
      'status': WasherStatus.available.asString,
      'current_order_id': null,
      'started_at': null,
      'ends_at': null,
    }).eq('id', dryerId);
    await _reload();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

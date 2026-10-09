import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-level preference: how many machine tiles to show per row on a
/// phone-sized screen, separately for the Washers and Dryers tabs.
/// Remembered on this device. Wider screens keep their automatic layout.
class TileLayoutSettings extends ChangeNotifier {
  static const options = [2, 3, 4];
  static const _washerKey = 'washer_tile_columns';
  static const _dryerKey = 'dryer_tile_columns';

  int _washerColumns = 2;
  int _dryerColumns = 2;
  int get washerColumns => _washerColumns;
  int get dryerColumns => _dryerColumns;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final w = prefs.getInt(_washerKey);
      final d = prefs.getInt(_dryerKey);
      if (w != null && options.contains(w)) _washerColumns = w;
      if (d != null && options.contains(d)) _dryerColumns = d;
      notifyListeners();
    } catch (e) {
      debugPrint('load tile layout failed: $e');
    }
  }

  Future<void> setWasherColumns(int n) async {
    if (!options.contains(n)) return;
    _washerColumns = n;
    notifyListeners();
    await _save(_washerKey, n);
  }

  Future<void> setDryerColumns(int n) async {
    if (!options.contains(n)) return;
    _dryerColumns = n;
    notifyListeners();
    await _save(_dryerKey, n);
  }

  Future<void> _save(String key, int n) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, n);
    } catch (e) {
      debugPrint('save tile layout failed: $e');
    }
  }
}

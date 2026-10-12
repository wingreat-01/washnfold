import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_errors.dart';

/// Device-level preference: Light, Dark, or follow the phone/browser setting.
/// Remembered on this device. Defaults to following the system.
class ThemeSettings extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      final loaded = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      if (loaded != _mode) {
        _mode = loaded;
        notifyListeners();
      }
    } catch (e) {
      logDebug('load theme mode failed: $e');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (e) {
      logDebug('save theme mode failed: $e');
    }
  }
}

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_errors.dart';

/// Device-level preference: play a chime when a washer or dryer finishes.
/// Off by default; remembered on this device. The banner is always shown
/// regardless of this setting.
class AlertSettings extends ChangeNotifier {
  static const _key = 'machine_finished_sound';

  bool _soundOn = false;
  bool get soundOn => _soundOn;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundOn = prefs.getBool(_key) ?? false;
      notifyListeners();
    } catch (e) {
      logDebug('load alert settings failed: $e');
    }
  }

  Future<void> setSound(bool on) async {
    _soundOn = on;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (e) {
      logDebug('save alert settings failed: $e');
    }
  }
}

/// Plays the bundled chime (assets/sounds/finished.wav). Never throws: on the
/// web a browser may refuse to play until the user has tapped something on
/// the page, which is why turning the sound on also plays it once.
class AlertSound {
  static AudioPlayer? _player;

  static Future<void> play() async {
    try {
      final p = _player ??= AudioPlayer();
      await p.stop();
      await p.play(AssetSource('sounds/finished.wav'));
    } catch (e) {
      logDebug('alert sound failed: $e');
    }
  }
}

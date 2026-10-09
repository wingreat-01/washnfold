import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/alert_settings.dart';
import '../providers/dryer_provider.dart';
import '../providers/order_provider.dart';
import '../providers/washer_provider.dart';

const _green = Color(0xFF2F9E5B);

/// How long the "finished" banner stays on screen before hiding itself.
const _bannerDuration = Duration(seconds: 6);

final Set<String> _silencedMachines = {};

/// Call when staff deliberately end a timer ("Mark finished") so the
/// banner and chime don't fire for something they just did themselves.
void silenceNextMachineAlert(String machineId) =>
    _silencedMachines.add(machineId);

class _FinishedAlert {
  final String key;
  final String machineId;
  final String machineName;
  final String? customer;
  const _FinishedAlert({
    required this.key,
    required this.machineId,
    required this.machineName,
    required this.customer,
  });
}

/// Watches every washer and dryer and, when a load's timer runs out, shows a
/// banner at the top of the screen (auto-hides after a few seconds, or sooner
/// if dismissed or the machine is emptied) and, if the device's sound option is on, plays a chime.
///
/// Must sit below the shop providers and AlertSettings.
class MachineAlertHost extends StatefulWidget {
  final Widget child;
  const MachineAlertHost({super.key, required this.child});

  @override
  State<MachineAlertHost> createState() => _MachineAlertHostState();
}

class _MachineAlertHostState extends State<MachineAlertHost> {
  Timer? _timer;
  final Map<String, _FinishedAlert> _alerts = {};
  final Set<String> _announced = {};
  final Map<String, Timer> _hideTimers = {};
  bool _primed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _scan());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final t in _hideTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _scan() {
    if (!mounted) return;
    final washers = context.read<WasherProvider>();
    final dryers = context.read<DryerProvider>();
    final orders = context.read<OrderProvider>();
    if (washers.loading || dryers.loading) return;

    final now = DateTime.now();
    final customerByOrder = {
      for (final o in orders.orders) o.id: o.customerName,
    };

    // Every machine whose current load's timer has run out.
    final finished = <String, _FinishedAlert>{};
    for (final w in washers.washers) {
      final end = w.expectedEnd;
      if (end == null || end.isAfter(now)) continue;
      final key = 'w:${w.id}:${end.millisecondsSinceEpoch}';
      finished[key] = _FinishedAlert(
        key: key,
        machineId: w.id,
        machineName: w.name,
        customer: customerByOrder[w.currentOrderId],
      );
    }
    for (final d in dryers.dryers) {
      final end = d.expectedEnd;
      if (end == null || end.isAfter(now)) continue;
      final key = 'd:${d.id}:${end.millisecondsSinceEpoch}';
      finished[key] = _FinishedAlert(
        key: key,
        machineId: d.id,
        machineName: d.name,
        customer: customerByOrder[d.currentOrderId],
      );
    }

    var changed = false;
    var playSound = false;

    // Drop banners for machines that were emptied or whose timer changed.
    final stale =
        _alerts.keys.where((k) => !finished.containsKey(k)).toList();
    for (final k in stale) {
      _alerts.remove(k);
      _hideTimers.remove(k)?.cancel();
      changed = true;
    }

    for (final e in finished.entries) {
      if (!_announced.add(e.key)) continue; // already announced / dismissed
      if (_silencedMachines.remove(e.value.machineId)) continue;
      _alerts[e.key] = e.value;
      _hideTimers[e.key]?.cancel();
      _hideTimers[e.key] = Timer(_bannerDuration, () => _dismiss(e.key));
      changed = true;
      // The first scan after start-up shows what finished while nobody was
      // looking, but stays quiet.
      if (_primed) playSound = true;
    }
    _primed = true;

    if (playSound && context.read<AlertSettings>().soundOn) {
      AlertSound.play();
    }
    if (changed) setState(() {});
  }

  void _dismiss(String key) {
    _hideTimers.remove(key)?.cancel();
    if (!mounted || !_alerts.containsKey(key)) return;
    setState(() => _alerts.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_alerts.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final a in _alerts.values)
                          _AlertBanner(
                            alert: a,
                            onDismiss: () => _dismiss(a.key),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final _FinishedAlert alert;
  final VoidCallback onDismiss;
  const _AlertBanner({required this.alert, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        elevation: 6,
        color: _green,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.machineName} finished',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15),
                    ),
                    Text(
                      alert.customer == null
                          ? 'Ready to take out'
                          : "${alert.customer}'s load is ready to take out",
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Speaker icon that turns the finish chime on or off for this device.
/// Turning it on plays the chime once, which also lets a web browser allow
/// later sounds.
class SoundToggleButton extends StatelessWidget {
  const SoundToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AlertSettings>();
    final on = settings.soundOn;
    return IconButton(
      tooltip: on ? 'Finish chime: on' : 'Finish chime: off',
      icon: Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded),
      onPressed: () {
        final turnOn = !on;
        settings.setSound(turnOn);
        if (turnOn) AlertSound.play();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(turnOn
              ? 'Chime on: plays when a washer or dryer finishes.'
              : 'Chime off. The banner still shows.'),
        ));
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

const _doneGreen = Color(0xFF2F9E5B);

/// "12:34" or "1:05:09".
String formatClock(Duration d) {
  final t = d.isNegative ? Duration.zero : d;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = t.inHours;
  final m = t.inMinutes % 60;
  final s = t.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// "12 min", "1 h 5 min" (rounded up so "0 min left" never shows).
String _minutesLabel(Duration d) {
  final mins = (d.inSeconds / 60).ceil();
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Live countdown for the load in a machine: mm:ss left with a progress
/// bar, then a green "Finished · 3 min ago" once the time is up. Tap to
/// adjust the timer ([onEdit]).
class MachineTimer extends StatefulWidget {
  final DateTime endsAt;
  final DateTime? startedAt;
  final Color color;
  final VoidCallback onEdit;

  /// Tighter version for small tiles: just the clock and a thin bar.
  final bool compact;

  const MachineTimer({
    super.key,
    required this.endsAt,
    required this.startedAt,
    required this.color,
    required this.onEdit,
    this.compact = false,
  });

  @override
  State<MachineTimer> createState() => _MachineTimerState();
}

class _MachineTimerState extends State<MachineTimer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final remaining = widget.endsAt.difference(now);

    if (remaining <= Duration.zero) {
      final over = now.difference(widget.endsAt);
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onEdit,
        child: Container(
          padding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 5, vertical: 4)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _doneGreen.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle,
                  size: widget.compact ? 13 : 16, color: _doneGreen),
              SizedBox(width: widget.compact ? 3 : 6),
              Expanded(
                child: Text(
                  widget.compact
                      ? (over.inMinutes >= 1
                          ? 'Done ${over.inMinutes}m'
                          : 'Done')
                      : (over.inMinutes >= 1
                          ? 'Finished · ${over.inMinutes} min ago'
                          : 'Finished · just now'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: _doneGreen,
                      fontWeight: FontWeight.w800,
                      fontSize: widget.compact ? 11 : 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final start = widget.startedAt;
    final total = start == null ? null : widget.endsAt.difference(start);
    final progress = (total == null || total.inSeconds <= 0)
        ? null
        : (1 - remaining.inSeconds / total.inSeconds).clamp(0.0, 1.0);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: widget.onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: widget.compact ? 13 : 15, color: widget.color),
                SizedBox(width: widget.compact ? 3 : 4),
                Expanded(
                  child: Text(
                    widget.compact
                        ? formatClock(remaining)
                        : '${formatClock(remaining)} left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: widget.color,
                        fontWeight: FontWeight.w800,
                        fontSize: widget.compact ? 12 : 13),
                  ),
                ),
                if (!widget.compact)
                  Icon(Icons.edit_outlined, size: 14, color: widget.color),
              ],
            ),
            SizedBox(height: widget.compact ? 3 : 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: widget.compact ? 3 : 5,
                color: widget.color,
                backgroundColor: widget.color.withOpacity(0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill for the queue cards: "12 min left" or "Done".
class MachineTimerPill extends StatefulWidget {
  final DateTime endsAt;
  const MachineTimerPill({super.key, required this.endsAt});

  @override
  State<MachineTimerPill> createState() => _MachineTimerPillState();
}

class _MachineTimerPillState extends State<MachineTimerPill> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endsAt.difference(DateTime.now());
    final done = remaining <= Duration.zero;
    final color = done
        ? _doneGreen
        : (context.isDark ? const Color(0xFF5AA2E8) : const Color(0xFF1E6FB8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle : Icons.timer_outlined,
              size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            done ? 'Done' : '${_minutesLabel(remaining)} left',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Lets staff correct the timer for the load in [machineName]: type the
/// minutes actually left, nudge with +/-, or mark it finished. Returns the
/// new finish time, or null if cancelled.
Future<DateTime?> showMachineTimerEditor(
  BuildContext context, {
  required String machineName,
  required DateTime endsAt,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _TimerEditor(machineName: machineName, endsAt: endsAt),
  );
}

class _TimerEditor extends StatefulWidget {
  final String machineName;
  final DateTime endsAt;
  const _TimerEditor({required this.machineName, required this.endsAt});

  @override
  State<_TimerEditor> createState() => _TimerEditorState();
}

class _TimerEditorState extends State<_TimerEditor> {
  late final TextEditingController _minutes;
  String? _error;

  @override
  void initState() {
    super.initState();
    final left = widget.endsAt.difference(DateTime.now());
    final mins = left.isNegative ? 0 : (left.inSeconds / 60).ceil();
    _minutes = TextEditingController(text: '$mins');
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _bump(int delta) {
    final cur = int.tryParse(_minutes.text.trim()) ?? 0;
    final next = (cur + delta).clamp(0, 600);
    setState(() {
      _minutes.text = '$next';
      _error = null;
    });
  }

  void _save() {
    final m = int.tryParse(_minutes.text.trim());
    if (m == null || m < 0 || m > 600) {
      setState(() => _error = 'Enter minutes between 0 and 600.');
      return;
    }
    Navigator.pop(context, DateTime.now().add(Duration(minutes: m)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.machineName} timer'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Minutes left on this load'),
            const SizedBox(height: 8),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                suffixText: 'min',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(label: const Text('−5'), onPressed: () => _bump(-5)),
                ActionChip(label: const Text('+5'), onPressed: () => _bump(5)),
                ActionChip(
                    label: const Text('+10'), onPressed: () => _bump(10)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, DateTime.now()),
          child: const Text('Mark finished'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Set timer')),
      ],
    );
  }
}

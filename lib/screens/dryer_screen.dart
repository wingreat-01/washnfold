import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/dryer.dart';
import '../models/order.dart';
import '../models/washer.dart';
import '../providers/dryer_provider.dart';
import '../providers/order_provider.dart';
import '../providers/tile_layout_settings.dart';
import '../widgets/machine_alert_host.dart';
import '../widgets/machine_timer.dart';
import '../widgets/tile_columns_menu.dart';

const _availableColor = Color(0xFF2F9E5B);
const _inUseColor = Color(0xFFD97706); // same amber the "Drying" stage uses
const _maintenanceColor = Color(0xFF8A94A6);

Color _colorFor(WasherStatus s) {
  switch (s) {
    case WasherStatus.available:
      return _availableColor;
    case WasherStatus.inUse:
      return _inUseColor;
    case WasherStatus.maintenance:
      return _maintenanceColor;
  }
}

IconData _iconFor(WasherStatus s) {
  switch (s) {
    case WasherStatus.available:
      return Icons.check_circle_outline;
    case WasherStatus.inUse:
      return Icons.autorenew;
    case WasherStatus.maintenance:
      return Icons.build_outlined;
  }
}

String _shortId(String id) =>
    '#${id.replaceAll('-', '').substring(0, 6).toUpperCase()}';

/// Dryer floor view. Loads arrive here from a washer's "Assign to dryer"
/// button; this tab is where you see what each dryer is doing, send a
/// finished load to the folding area, and add or edit the dryers.
class DryerScreen extends StatefulWidget {
  const DryerScreen({super.key});

  @override
  State<DryerScreen> createState() => _DryerScreenState();
}

class _DryerScreenState extends State<DryerScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Re-render every 30s so "drying for X min" stays current.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openForm({Dryer? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<DryerProvider>(),
        child: _DryerForm(existing: existing),
      ),
    );
  }

  /// Correct the timer for the load in a dryer.
  Future<void> _editTimer(Dryer dryer) async {
    final end = dryer.expectedEnd;
    if (end == null) return;
    final provider = context.read<DryerProvider>();
    final newEnd = await showMachineTimerEditor(context,
        machineName: dryer.name, endsAt: end);
    if (newEnd == null) return;
    // "Mark finished" / 0 minutes: staff just did this themselves, so
    // don't pop a banner or chime about it.
    if (newEnd.difference(DateTime.now()) < const Duration(seconds: 5)) {
      silenceNextMachineAlert(dryer.id);
    }
    try {
      await provider.setEndsAt(dryer.id, newEnd);
    } catch (e) {
      _snack('Could not update the timer: $e');
    }
  }

  /// Load finished drying: free the dryer and send the order to the
  /// folding area (Folding stage in the queue).
  Future<void> _finish(Dryer dryer, Order? order) async {
    final dryers = context.read<DryerProvider>();
    final orders = context.read<OrderProvider>();
    const next = OrderStatus.foldingPressing;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send to folding area?'),
        content: Text(
          order == null
              ? '${dryer.name} will be marked Available.'
              : "${order.customerName}'s order moves to ${next.label} and "
                  '${dryer.name} is marked Available.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send to folding')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await dryers.release(dryer.id);
      if (order != null) await orders.advanceStatus(order.id, next);
    } catch (e) {
      debugPrint('finish drying failed: $e');
      _snack('Could not finish: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DryerProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final orderById = {for (final o in orderProvider.orders) o.id: o};

    if (provider.loading && provider.dryers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final layout = context.watch<TileLayoutSettings>();
    final phone = isPhoneWidth(context);
    final cols = phone ? layout.dryerColumns : 2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add dryer'),
      ),
      body: provider.dryers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No dryers yet.\nTap "Add dryer" to set up your first machine.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    gridDelegate: phone
                        ? SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisExtent:
                                cols == 2 ? 198 : (cols == 3 ? 152 : 140),
                            crossAxisSpacing: cols == 2 ? 12 : 8,
                            mainAxisSpacing: cols == 2 ? 12 : 8,
                          )
                        : const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 240,
                            mainAxisExtent: 198,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                    itemCount: provider.dryers.length,
                    itemBuilder: (context, i) {
                      final d = provider.dryers[i];
                      final order = d.currentOrderId == null
                          ? null
                          : orderById[d.currentOrderId];
                      return _DryerCard(
                        dryer: d,
                        order: order,
                        onFinish: () => _finish(d, order),
                        onConfigure: () => _openForm(existing: d),
                        onEditTimer: () => _editTimer(d),
                        columns: cols,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _DryerCard extends StatelessWidget {
  final Dryer dryer;
  final Order? order;
  final VoidCallback onFinish;
  final VoidCallback onConfigure;
  final VoidCallback onEditTimer;

  /// Tiles per row on the screen (2 = full card, 3-4 = compact tile).
  final int columns;

  const _DryerCard({
    required this.dryer,
    required this.order,
    required this.onFinish,
    required this.onConfigure,
    required this.onEditTimer,
    this.columns = 2,
  });

  /// Small tile used when 3 or 4 tiles are shown per row.
  Widget _buildCompact(BuildContext context) {
    final color = _colorFor(dryer.status);
    final theme = Theme.of(context);
    final tiny = columns >= 4;
    final pad = tiny ? 6.0 : 8.0;
    final fs = tiny ? 11.0 : 12.0;

    Widget btn(String label, VoidCallback? onPressed, {required int kind}) {
      final shape =
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
      const padding = EdgeInsets.symmetric(horizontal: 4);
      const size = Size(0, 32);
      final text = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label,
            maxLines: 1,
            style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700)),
      );
      switch (kind) {
        case 0:
          return FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: color.withOpacity(0.15),
              foregroundColor: color,
              padding: padding,
              minimumSize: size,
              shape: shape,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onPressed,
            child: text,
          );
        case 1:
          return FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: padding,
              minimumSize: size,
              shape: shape,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onPressed,
            child: text,
          );
        default:
          return OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color),
              padding: padding,
              minimumSize: size,
              shape: shape,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onPressed,
            child: text,
          );
      }
    }

    Widget body;
    Widget? action;

    switch (dryer.status) {
      case WasherStatus.available:
        body = Text('Ready',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: fs + 1));
        break;
      case WasherStatus.inUse:
        final hasOrder = dryer.currentOrderId != null;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order?.customerName ?? (hasOrder ? 'Order not found' : 'Unknown'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800, fontSize: tiny ? 12.5 : 13.5),
            ),
            if (!tiny && hasOrder)
              Text(
                _shortId(dryer.currentOrderId!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Colors.black54,
                ),
              ),
            const SizedBox(height: 4),
            if (dryer.expectedEnd != null)
              MachineTimer(
                endsAt: dryer.expectedEnd!,
                startedAt: dryer.startedAt,
                color: color,
                onEdit: onEditTimer,
                compact: true,
              ),
          ],
        );
        action = btn(tiny ? 'Fold' : 'To folding', onFinish, kind: 2);
        break;
      case WasherStatus.maintenance:
        body = Text(
          dryer.notes?.isNotEmpty == true ? dryer.notes! : 'Out of service',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: fs),
        );
        action = null;
        break;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: Color.alphaBlend(color.withOpacity(0.06), Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: InkWell(
        onTap: onConfigure,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dryer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: tiny ? 12.5 : 14),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_iconFor(dryer.status),
                      size: tiny ? 14 : 16, color: color),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(child: body),
              if (action != null)
                SizedBox(width: double.infinity, child: action),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (columns >= 3) return _buildCompact(context);
    final color = _colorFor(dryer.status);
    final theme = Theme.of(context);
    final cap = dryer.capacityKg;

    Widget body;
    Widget? action;

    switch (dryer.status) {
      case WasherStatus.available:
        body = Text(
          'Ready — load it with "Assign to dryer" on a washer',
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        );
        break;
      case WasherStatus.inUse:
        final hasOrder = dryer.currentOrderId != null;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    order?.customerName ??
                        (hasOrder ? 'Order not found' : 'Unknown'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (hasOrder) ...[
                  const SizedBox(width: 8),
                  Text(
                    _shortId(dryer.currentOrderId!),
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
            if (order != null && order!.items.isNotEmpty)
              Text(
                order!.items.map((e) => e.serviceName).join(' + '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            if (dryer.expectedEnd != null) ...[
              const SizedBox(height: 4),
              MachineTimer(
                endsAt: dryer.expectedEnd!,
                startedAt: dryer.startedAt,
                color: color,
                onEdit: onEditTimer,
              ),
            ],
          ],
        );
        action = OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
          ),
          onPressed: onFinish,
          child: const Text('Send to folding area'),
        );
        break;
      case WasherStatus.maintenance:
        body = Text(
          dryer.notes?.isNotEmpty == true ? dryer.notes! : 'Out of service',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        );
        break;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: Color.alphaBlend(color.withOpacity(0.06), Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: InkWell(
        onTap: onConfigure,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.dry_cleaning_outlined,
                        color: color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dryer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (cap != null)
                          Text(
                            '${cap == cap.roundToDouble() ? cap.toInt() : cap} kg',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_iconFor(dryer.status), size: 14, color: color),
                        const SizedBox(width: 4),
                        Text(
                          dryer.status.label,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(child: body),
              if (action != null)
                SizedBox(width: double.infinity, child: action),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add / edit sheet. Name ("Dryer 1"), optional capacity and notes, and an
/// "Out of service" switch for machines that are broken. A busy dryer's
/// order is never touched from here.
class _DryerForm extends StatefulWidget {
  final Dryer? existing;
  const _DryerForm({this.existing});

  @override
  State<_DryerForm> createState() => _DryerFormState();
}

class _DryerFormState extends State<_DryerForm> {
  late final TextEditingController _name;
  late final TextEditingController _capacity;
  late final TextEditingController _notes;
  late final TextEditingController _cycle;
  late bool _outOfService;
  bool _saving = false;
  String? _error;

  bool get _isBusy => widget.existing?.status == WasherStatus.inUse;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    final cap = e?.capacityKg;
    _capacity = TextEditingController(
      text: cap == null
          ? ''
          : (cap == cap.roundToDouble() ? '${cap.toInt()}' : '$cap'),
    );
    _notes = TextEditingController(text: e?.notes ?? '');
    _cycle = TextEditingController(
        text: '${e?.cycleMinutes ?? AppConfig.dryerCycleMinutes}');
    _outOfService = e?.status == WasherStatus.maintenance;
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _notes.dispose();
    _cycle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name, e.g. "Dryer 1".');
      return;
    }
    final capText = _capacity.text.trim();
    final cap = capText.isEmpty ? null : double.tryParse(capText);
    if (capText.isNotEmpty && cap == null) {
      setState(() => _error = 'Capacity must be a number.');
      return;
    }
    final cycle = int.tryParse(_cycle.text.trim());
    if (cycle == null || cycle < 1 || cycle > 600) {
      setState(() => _error = 'Cycle time must be 1 to 600 minutes.');
      return;
    }
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    final provider = context.read<DryerProvider>();
    try {
      if (widget.existing == null) {
        await provider.addDryer(
            name: name, capacityKg: cap, notes: notes, cycleMinutes: cycle);
      } else {
        await provider.updateDryer(
          widget.existing!.id,
          name: name,
          capacityKg: cap,
          notes: notes,
          cycleMinutes: cycle,
          // Never flip a busy dryer's status from here.
          status: _isBusy
              ? null
              : (_outOfService
                  ? WasherStatus.maintenance
                  : WasherStatus.available),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('save dryer failed: $e');
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.existing!.name}?'),
        content: const Text('This removes the dryer from your shop.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final provider = context.read<DryerProvider>();
    try {
      await provider.deleteDryer(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit dryer' : 'Add dryer',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name (e.g. Dryer 1)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacity,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Capacity in kg (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cycle,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cycle time',
                suffixText: 'min',
                helperText: 'How long one load runs. The timer counts down '
                    'from this; you can adjust it per load on the card.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (editing && !_isBusy)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Out of service'),
                value: _outOfService,
                onChanged: (v) => setState(() => _outOfService = v),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(editing ? 'Save' : 'Add dryer'),
            ),
            if (editing && !_isBusy)
              TextButton(
                onPressed: _saving ? null : _delete,
                child: const Text('Delete dryer'),
              ),
          ],
        ),
      ),
    );
  }
}

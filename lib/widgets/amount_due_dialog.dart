import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/order.dart';
import '../models/payment.dart';
import '../providers/order_provider.dart';
import '../utils/app_errors.dart';

/// Shows the "Amount due" checkout modal for [order] and, if the cashier
/// confirms, records the payment. Returns true when the order was marked
/// paid, false if the cashier closed it (pay later) or there was nothing
/// to collect.
///
/// Mirrors MERQ POS's CheckoutModal: LED-style total, payment method chips,
/// cash tendered field with Exact / +bill / round-up / CLR quick buttons,
/// and a live CHANGE readout.
///
/// [orders] is passed in rather than looked up from the dialog's context,
/// because dialogs are built under the root navigator and may not see the
/// shop-scoped providers.
Future<bool> showAmountDueDialog(
  BuildContext context,
  Order order,
  OrderProvider orders,
) async {
  if (order.paymentStatus == PaymentStatus.paid || order.total <= 0) {
    return false;
  }
  final paid = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    barrierDismissible: false,
    builder: (_) => AmountDueDialog(order: order, orders: orders),
  );
  return paid == true;
}

class AmountDueDialog extends StatefulWidget {
  final Order order;
  final OrderProvider orders;

  const AmountDueDialog({
    super.key,
    required this.order,
    required this.orders,
  });

  @override
  State<AmountDueDialog> createState() => _AmountDueDialogState();
}

class _AmountDueDialogState extends State<AmountDueDialog> {
  // Palette for the LED readouts / chips (the laundry app has no AppColors).
  static const _ledAmber = Color(0xFFFFB020);
  static const _tillGreen = Color(0xFF2F9E5B);
  static const _ledgerRed = Color(0xFFE5484D);
  static const _readoutBg = Color(0xFF14171C);

  // PHP cash values, same as MERQ's peso Currency config.
  // ₱200 is left out on purpose (BSP halted production in 2021).
  static const _bills = <double>[20, 50, 100, 500, 1000];
  static const _stackStep = 100.0;
  static const _roundUpSteps = <double>[50, 100, 500];
  static const _largestBill = 1000.0;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  PaymentMethod _method = PaymentMethod.cash;
  String? _error;
  bool _submitting = false;

  bool get _isCash => _method == PaymentMethod.cash;

  double get _total => widget.order.total;

  int get _decimals => (_total - _total.roundToDouble()).abs() < 0.005 ? 0 : 2;

  double? get _tendered {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  double get _change {
    final tendered = _tendered;
    if (tendered == null) return 0;
    final change = tendered - _total;
    return change > 0 ? change : 0;
  }

  bool get _canConfirm {
    if (!_isCash) return true;
    final tendered = _tendered;
    return tendered != null && tendered + 0.005 >= _total;
  }

  String _money(double v) {
    final isWhole = (v - v.roundToDouble()).abs() < 0.005;
    return NumberFormat.currency(
      symbol: '₱',
      decimalDigits: isWhole ? 0 : 2,
    ).format(v);
  }

  // After a quick chip fills the tendered field, CHANGE and Confirm are
  // what the cashier needs next; scroll them into view post-frame.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _setExact() {
    _controller.text = _total.toStringAsFixed(_decimals);
    setState(() => _error = null);
    _scrollToBottom();
  }

  /// Bill chips stack: each tap adds to what's already entered.
  void _addQuickAmount(double amount) {
    final current = _tendered ?? 0;
    _controller.text = (current + amount).toStringAsFixed(_decimals);
    setState(() => _error = null);
    _scrollToBottom();
  }

  /// Round-up chips set the tendered amount directly.
  void _setQuickTarget(double amount) {
    _controller.text = amount.toStringAsFixed(_decimals);
    setState(() => _error = null);
    _scrollToBottom();
  }

  void _clearTendered() {
    _controller.clear();
    setState(() => _error = null);
    _focusNode.requestFocus();
  }

  double _ceilToMultiple(double value, double multiple) =>
      (value / multiple).ceil() * multiple;

  // Up to the largest bill: real bills that alone cover the total, plus
  // the total rounded up to a stack of ₱100s (e.g. ₱220 → ₱300).
  List<double> get _billBasedOptions => <double>{
        ..._bills.where((a) => a >= _total),
        if (_total > 0) _ceilToMultiple(_total, _stackStep),
      }.toList()
        ..sort();

  // Above the largest bill nothing single covers it, so offer round-up
  // targets instead (₱1043 → ₱1050 / ₱1100 / ₱1500).
  List<double> get _quickRoundUpTargets => <double>{
        for (final step in _roundUpSteps) _ceilToMultiple(_total, step),
      }.toList()
        ..sort();

  bool get _useRoundUpTargets => _total > _largestBill;

  List<double> get _quickAmountOptions =>
      _useRoundUpTargets ? _quickRoundUpTargets : _billBasedOptions;

  Future<void> _confirm() async {
    if (_isCash && !_canConfirm) {
      setState(() => _error = 'Amount tendered is less than the total due.');
      return;
    }
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // The payment row stores what the order cost, not the cash handed
      // over, so daily totals stay correct. Change is display-only.
      await widget.orders.recordPayment(
        orderId: widget.order.id,
        method: _method,
        amount: _total,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      logDebug('record payment failed: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not save the payment — check your connection and try again.';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  TextStyle _mono(
          {double size = 12,
          FontWeight weight = FontWeight.w600,
          Color? color,
          double letterSpacing = 0}) =>
      TextStyle(
        fontFamily: 'monospace',
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color ?? Colors.grey;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'AMOUNT DUE',
                        style: _mono(
                            size: 13,
                            weight: FontWeight.w700,
                            color: muted,
                            letterSpacing: 2),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Pay later',
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: Icon(Icons.close, color: muted, size: 20),
                      splashRadius: 18,
                    ),
                  ],
                ),
                Text(widget.order.customerName,
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                _LedReadout(
                  label: 'TOTAL DUE',
                  value: _money(_total),
                  color: _ledAmber,
                  background: _readoutBg,
                ),
                if (widget.order.isRush)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Includes ${_money(widget.order.rushSurcharge)} rush surcharge',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 18),
                Text('PAYMENT METHOD',
                    style: _mono(
                        size: 11,
                        color: muted,
                        letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in PaymentMethod.values)
                      _Chip(
                        label: m.label,
                        selected: _method == m,
                        accent: _ledAmber,
                        textStyle: _mono(size: 12, weight: FontWeight.w700),
                        onTap: () => setState(() {
                          _method = m;
                          _error = null;
                          _controller.clear();
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_isCash) ...[
                  Text('CASH TENDERED',
                      style: _mono(
                          size: 11, color: muted, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    style: _mono(
                        size: 22, weight: FontWeight.w700, color: _ledAmber),
                    decoration: InputDecoration(
                      prefixText: '₱ ',
                      prefixStyle: _mono(
                          size: 22,
                          weight: FontWeight.w700,
                          color: _ledAmber),
                      hintText: '0',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _confirm(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Chip(
                          label: 'Exact',
                          compact: true,
                          textStyle: _mono(),
                          onTap: _setExact),
                      for (final amount in _quickAmountOptions)
                        _Chip(
                          label: _useRoundUpTargets
                              ? '₱${amount.toStringAsFixed(0)}'
                              : '+₱${amount.toStringAsFixed(0)}',
                          compact: true,
                          textStyle: _mono(),
                          onTap: () => _useRoundUpTargets
                              ? _setQuickTarget(amount)
                              : _addQuickAmount(amount),
                        ),
                      _Chip(
                        label: 'CLR',
                        compact: true,
                        destructive: true,
                        textStyle: _mono(),
                        onTap: _clearTendered,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _LedReadout(
                    label: 'CHANGE',
                    value: _money(_change),
                    color: _tillGreen,
                    background: _readoutBg,
                    fontSize: 26,
                  ),
                ] else
                  Text(
                    'Confirming ${_money(_total)} via ${_method.label}. No change due.',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _ledgerRed),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _submitting ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: _tillGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Confirm payment'),
                  ),
                ),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Pay later'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark LED-style readout used for TOTAL DUE and CHANGE.
class _LedReadout extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color background;
  final double fontSize;

  const _LedReadout({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
    this.fontSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: color.withOpacity(0.7),
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Used for both payment-method chips and the smaller quick-amount chips.
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool compact;
  final bool destructive;
  final Color accent;
  final TextStyle textStyle;

  const _Chip({
    required this.label,
    required this.onTap,
    required this.textStyle,
    this.selected = false,
    this.compact = false,
    this.destructive = false,
    this.accent = const Color(0xFFFFB020),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const red = Color(0xFFE5484D);
    final fg = destructive
        ? red
        : selected
            ? accent
            : (theme.textTheme.bodyMedium?.color ?? Colors.black);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14, vertical: compact ? 8 : 10),
        decoration: BoxDecoration(
          color: destructive
              ? red.withOpacity(0.12)
              : selected
                  ? accent.withOpacity(0.15)
                  : theme.dividerColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: destructive
                ? red
                : selected
                    ? accent
                    : theme.dividerColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label, style: textStyle.copyWith(color: fg)),
      ),
    );
  }
}

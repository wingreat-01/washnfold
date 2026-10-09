import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/order.dart';
import '../models/order_item.dart';
import '../models/service_item.dart';
import '../providers/order_provider.dart';
import '../providers/service_catalog_provider.dart';
import '../widgets/order_qr_dialog.dart';
import '../widgets/washer_picker.dart';

/// New-order intake: pick services, enter weight/piece count, see the running
/// total, submit. This is the screen an attendant lives in.
class OrderIntakeScreen extends StatefulWidget {
  const OrderIntakeScreen({super.key});

  @override
  State<OrderIntakeScreen> createState() => _OrderIntakeScreenState();
}

class _OrderIntakeScreenState extends State<OrderIntakeScreen> {
  final _customerNameController = TextEditingController();
  final _uuid = const Uuid();
  bool _submitting = false;
  String? _nameError;
  ServiceType _serviceTab = ServiceType.selfService;

  // serviceId -> quantity entered
  final Map<String, double> _quantities = {};

  // Services whose card has been tapped (they get a weight/pcs input).
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _qtyControllers = {};

  TextEditingController _controllerFor(String serviceId) =>
      _qtyControllers.putIfAbsent(serviceId, () => TextEditingController());

  /// Flat-rate services (priced per piece) are counted by tapping the card:
  /// one tap = 1, two taps = 2, and so on. kg-priced services keep the
  /// original behavior (tap to select, then type the weight).
  /// To change which services count as flat-rate, edit only this getter.
  bool _isTapCounted(ServiceItem service) => service.unit == PricingUnit.piece;

  String _fmtQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _toggleService(ServiceItem service) {
    setState(() {
      if (_isTapCounted(service)) {
        final next = (_quantities[service.id] ?? 0) + 1;
        _quantities[service.id] = next;
        _selected.add(service.id);
        _controllerFor(service.id).text = _fmtQty(next);
        return;
      }
      if (_selected.contains(service.id)) {
        _selected.remove(service.id);
        _quantities.remove(service.id);
        _qtyControllers[service.id]?.clear();
      } else {
        _selected.add(service.id);
      }
    });
  }

  /// Trash icon on a line in the order: drops the service from this order
  /// entirely (does not touch the service catalog).
  void _removeFromOrder(ServiceItem service) {
    setState(() {
      _selected.remove(service.id);
      _quantities.remove(service.id);
      _qtyControllers[service.id]?.clear();
    });
  }

  /// Minus button on a tap-counted card: 2 → 1, and 1 → removed.
  void _decrementService(ServiceItem service) {
    setState(() {
      final next = (_quantities[service.id] ?? 0) - 1;
      if (next <= 0) {
        _selected.remove(service.id);
        _quantities.remove(service.id);
        _qtyControllers[service.id]?.clear();
      } else {
        _quantities[service.id] = next;
        _controllerFor(service.id).text = _fmtQty(next);
      }
    });
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _money(double v) {
    final isWhole = (v - v.roundToDouble()).abs() < 0.005;
    return NumberFormat.currency(
      symbol: '₱',
      decimalDigits: isWhole ? 0 : 2,
    ).format(v);
  }

  String _kg(double v) {
    final r = (v * 100).round() / 100; // avoid 0.0999999… from float math
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  double _lineSubtotal(ServiceItem service) {
    final qty = _quantities[service.id] ?? 0;
    return service.priceFor(qty);
  }

  double get _itemsTotal {
    final catalog = context.read<ServiceCatalogProvider>().services;
    return catalog.fold<double>(
        0, (sum, s) => sum + _lineSubtotal(s));
  }

  double get _grandTotal => _itemsTotal;

  Future<void> _submit() async {
    final catalog = context.read<ServiceCatalogProvider>();
    final orderProvider = context.read<OrderProvider>();
    final name = _customerNameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a customer name.')),
      );
      return;
    }

    final lineItems = <OrderItem>[];
    for (final service in catalog.services) {
      final qty = _quantities[service.id] ?? 0;
      if (qty > 0) {
        lineItems.add(OrderItem(
          id: _uuid.v4(),
          orderId: '', // filled in by OrderProvider.createOrder
          serviceId: service.id,
          serviceName: service.name,
          quantity: qty,
          subtotal: service.priceFor(qty),
        ));
      }
    }

    if (lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one service.')),
      );
      return;
    }

    // MVP: customer_id is generated per walk-in order rather than requiring
    // a saved customer profile first. Swap in a customer picker/search once
    // the CRM-lite module is built.
    if (_submitting) return;
    setState(() => _submitting = true);
    final Order createdOrder;
    try {
      createdOrder = await orderProvider.createOrder(
        customerId: _uuid.v4(),
        customerName: name,
        lineItems: lineItems,
      );
    } on DuplicateCustomerNameException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _nameError = 'Name already exists. Use a different name.';
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return;
    } catch (e) {
      // Previously a failure here was silent, which looked like the button
      // doing nothing. Show the real reason.
      debugPrint('createOrder failed: $e');
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 10),
          content: Text('Could not create order: $e'),
        ));
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _nameError = null;
      _customerNameController.clear();
      _quantities.clear();
      _selected.clear();
      for (final c in _qtyControllers.values) {
        c.clear();
      }
    });

    // Hand the customer their no-login tracking QR right away — this is
    // the moment they're standing at the counter, so it's the easiest
    // point to show/print/share it.
    final wantsWasher = await showDialog<bool>(
      context: context,
      builder: (_) =>
          OrderQrDialog(order: createdOrder, offerWasherAssign: true),
    );

    // Cashier tapped "Assign to washer": pick one of the free machines.
    if (wantsWasher == true && mounted) {
      await assignOrderToWasher(context, createdOrder,
          collectPayment: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ServiceCatalogProvider>();
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    if (catalog.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final serviceList = _buildServiceList(catalog, currency);
        final summary = _buildSummary(currency);

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: serviceList),
                const SizedBox(width: 16),
                SizedBox(width: 340, child: summary),
              ],
            ),
          );
        }
        return Column(
          children: [
            Expanded(child: serviceList),
            summary,
          ],
        );
      },
    );
  }

  Widget _buildServiceList(
      ServiceCatalogProvider catalog, NumberFormat currency) {
    final selected = catalog.activeServices
        .where((s) => _selected.contains(s.id))
        .toList();

    final tabServices = catalog.activeServices
        .where((s) => s.serviceType == _serviceTab)
        .toList();
    // Selected-service count per sub-tab, shown on the tab so nothing
    // chosen on the other tab is forgotten.
    int countFor(ServiceType t) => selected.where((s) => s.serviceType == t).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      children: [
        // On phones the shared AppBar (same as every other tab) shows the
        // title and the Settings / sound / sign-out buttons, so they sit in
        // the same place on every tab. The side-rail layout has no AppBar,
        // so it keeps the big title here.
        if (MediaQuery.of(context).size.width >= 900)
          Text(
            'New Order',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF123047),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
          ),
        const SizedBox(height: 2),
        Text(
          'Select services and enter the customer details.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
              ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _customerNameController,
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
          decoration: InputDecoration(
            labelText: 'Customer name',
            prefixIcon: const Icon(Icons.person_outline),
            errorText: _nameError,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            for (final t in ServiceType.values) ...[
              if (t != ServiceType.values.first) const SizedBox(width: 12),
              Expanded(
                child: _ServiceTypeCard(
                  type: t,
                  selected: _serviceTab == t,
                  count: countFor(t),
                  onTap: () => setState(() => _serviceTab = t),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (tabServices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
                'No ${_serviceTab.label} services yet. Add some in the Services tab.'),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              const gap = 10.0;
              // Up to 3 services share one row on phones; more than 3 fall
              // back to 2 columns (3 on wide screens).
              final n = tabServices.length;
              final cols = c.maxWidth >= 600 ? 3 : (n <= 3 ? n : 2);
              final w =
                  ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
              final compact = w < 160;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: tabServices
                    .map((s) => _serviceCard(s, w, compact: compact))
                    .toList(),
              );
            },
          ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Enter weight or quantity',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...selected.map(_quantityRow),
        ],
        if (catalog.activeAddOns.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Add-ons', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...catalog.activeAddOns.map((service) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(service.name),
                subtitle: Text(_money(service.price)),
                value: (_quantities[service.id] ?? 0) > 0,
                onChanged: (checked) {
                  setState(() {
                    _quantities[service.id] = (checked ?? false) ? 1 : 0;
                  });
                },
              )),
        ],
      ],
    );
  }

  /// Tappable card: NAME, amount, and "max X kg" (or "per kg" / "per piece").
  Widget _serviceCard(ServiceItem service, double width,
      {bool compact = false}) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selected.contains(service.id);
    final counted = _isTapCounted(service);
    final count = _quantities[service.id] ?? 0;
    final amount = service.hasMaxKgPricing
        ? _money(service.maxKgPrice!)
        : _money(service.price);
    final caption = service.hasMaxKgPricing
        ? 'max ${_kg(service.maxKg!)} kg'
        : service.unit.label;

    // Narrow layout (three cards in one row): everything centered, with a
    // fixed-height slot at the bottom for the count controls so all cards
    // stay the same height whether or not they're selected.
    final compactChild = Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            service.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF123047),
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 5),
          // Keep price and unit on one line to make each service card shorter.
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: -0.2,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: Center(
              child: (counted && count > 0)
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkResponse(
                          onTap: () => _decrementService(service),
                          radius: 18,
                          child: Icon(Icons.remove_circle_outline,
                              size: 24, color: cs.primary),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '×${_fmtQty(count)}',
                            style: TextStyle(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    )
                  : (isSelected
                      ? Icon(Icons.check_circle, size: 22, color: cs.primary)
                      : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add, size: 16, color: cs.primary),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Add',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            )),
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      width: width,
      child: Material(
        color: isSelected ? cs.primaryContainer : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? cs.primary : Theme.of(context).dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _toggleService(service),
          child: compact
              ? compactChild
              : Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        service.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF123047),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (counted && count > 0) ...[
                      IconButton(
                        tooltip: 'Remove one',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Icon(Icons.remove_circle_outline,
                            size: 22, color: cs.primary),
                        onPressed: () => _decrementService(service),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '×${_fmtQty(count)}',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ] else if (isSelected)
                      Icon(Icons.check_circle, size: 20, color: cs.primary),
                  ],
                ),
                const SizedBox(height: 7),
                // Price + unit share one row, keeping the card compact.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          amount,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.35,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Weight / piece input for a tapped service, with its computed amount.
  Widget _quantityRow(ServiceItem service) {
    final qty = _quantities[service.id] ?? 0;
    String? detail;
    if (service.hasMaxKgPricing) {
      detail = qty > service.maxKg!
          ? '${_money(service.maxKgPrice!)} + '
              '${_kg(qty - service.maxKg!)} kg × ${_money(service.extraKgRate)}'
          : 'Up to ${_kg(service.maxKg!)} kg = ${_money(service.maxKgPrice!)}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (detail != null)
                    Text(detail,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _controllerFor(service.id),
                // Tap-counted rows already have a value; don't pop the keyboard.
                autofocus: !_isTapCounted(service),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: service.unit == PricingUnit.kg ? 'kg' : 'pcs',
                ),
                onChanged: (value) {
                  setState(() {
                    _quantities[service.id] = double.tryParse(value) ?? 0;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: Text(
                _money(_lineSubtotal(service)),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Remove from order',
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              visualDensity: VisualDensity.compact,
              onPressed: () => _removeFromOrder(service),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(NumberFormat currency) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: Theme.of(context).textTheme.titleMedium),
              Text(
                _money(_grandTotal),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create order'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Big tappable card used to switch between Self Service and Full Service.
class _ServiceTypeCard extends StatelessWidget {
  const _ServiceTypeCard({
    required this.type,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final ServiceType type;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isFull = type == ServiceType.fullService;
    final fg = selected ? Colors.white : const Color(0xFF123047);
    return Material(
      color: selected ? primary : Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: selected ? 3 : 0,
      shadowColor: primary.withOpacity(0.4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? primary : const Color(0xFFDCE5EF),
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isFull
                        ? Icons.local_laundry_service
                        : Icons.touch_app_outlined,
                    size: 32,
                    color: fg,
                  ),
                  if (count > 0)
                    Positioned(
                      right: -12,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : Theme.of(context).colorScheme.secondary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: selected ? primary : Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                type.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

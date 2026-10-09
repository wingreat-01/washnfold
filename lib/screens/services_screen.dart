import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/service_item.dart';
import '../providers/service_catalog_provider.dart';

/// Manage the shop's services — add, edit price, switch on/off, delete.
/// Works like adding a product in a POS: whatever is active here shows up
/// on the New order screen.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  String _query = '';

  Future<void> _openForm({ServiceItem? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ServiceCatalogProvider>(),
        child: _ServiceForm(existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(ServiceItem service) async {
    final catalog = context.read<ServiceCatalogProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete service?'),
        content: Text('"${service.name}" will be removed from your catalog.'),
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
    if (ok != true) return;
    try {
      await catalog.deleteService(service.id);
      messenger.showSnackBar(
          SnackBar(content: Text('Deleted "${service.name}".')));
    } catch (e) {
      debugPrint('delete service failed: $e');
      messenger.showSnackBar(const SnackBar(
        content: Text(
            "Can't delete — it's used by past orders. Switch it off instead."),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ServiceCatalogProvider>();
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    if (catalog.loading && catalog.services.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    bool matches(ServiceItem s) =>
        _query.isEmpty || s.name.toLowerCase().contains(_query.toLowerCase());

    final main = catalog.services.where((s) => !s.isAddOn && matches(s)).toList();
    final addOns = catalog.services.where((s) => s.isAddOn && matches(s)).toList();

    Widget tile(ServiceItem s) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => _openForm(existing: s),
            title: Text(
              s.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: s.active ? null : Theme.of(context).disabledColor,
              ),
            ),
            subtitle: Text(
              '${s.isAddOn ? '' : '${s.serviceType.label}  •  '}'
              '${s.pricingSummary(currency.format)}'
              '${s.active ? '' : '  •  Off'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: s.active,
                  onChanged: (v) async {
                    try {
                      await catalog.setActive(s.id, v);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not update: $e')));
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(s),
                ),
              ],
            ),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search services',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 16),
          if (catalog.services.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No services yet.\nTap "Add service" to create your first one.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (main.isNotEmpty) ...[
            Text('Services', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...main.map(tile),
          ],
          if (addOns.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Add-ons', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...addOns.map(tile),
          ],
        ],
      ),
    );
  }
}

class _ServiceForm extends StatefulWidget {
  final ServiceItem? existing;
  const _ServiceForm({this.existing});

  @override
  State<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<_ServiceForm> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _maxKg;
  late final TextEditingController _maxKgPrice;
  late bool _useMaxKg;
  late PricingUnit _unit;
  late bool _isAddOn;
  late bool _active;
  late ServiceType _serviceType;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(
        text: e == null ? '' : e.price.toStringAsFixed(2));
    _useMaxKg = e?.hasMaxKgPricing ?? false;
    _maxKg = TextEditingController(
        text: e?.maxKg == null ? '' : e!.maxKg!.toString().replaceAll(RegExp(r'\.0$'), ''));
    _maxKgPrice = TextEditingController(
        text: e?.maxKgPrice == null ? '' : e!.maxKgPrice!.toStringAsFixed(2));
    _unit = e?.unit ?? PricingUnit.kg;
    _isAddOn = e?.isAddOn ?? false;
    _active = e?.active ?? true;
    _serviceType = e?.serviceType ?? ServiceType.selfService;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _maxKg.dispose();
    _maxKgPrice.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Enter a service name.');
      return;
    }
    final useMax = _useMaxKg && _unit == PricingUnit.kg && !_isAddOn;
    if (!useMax && (price == null || price < 0)) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    double? maxKg;
    double? maxKgPrice;
    if (useMax) {
      maxKg = double.tryParse(_maxKg.text.trim());
      maxKgPrice = double.tryParse(_maxKgPrice.text.trim());
      if (maxKg == null || maxKg <= 0) {
        setState(() => _error = 'Enter the max kg (e.g. 7).');
        return;
      }
      if (maxKgPrice == null || maxKgPrice < 0) {
        setState(() => _error = 'Enter the flat price for the max kg.');
        return;
      }
    }

    // With a max-kg tier, the per-kg rate is derived (flat price ÷ max kg)
    // so the stored `price` always matches what customers are charged.
    final storedPrice = useMax ? maxKgPrice! / maxKg! : price!;

    setState(() {
      _saving = true;
      _error = null;
    });
    final catalog = context.read<ServiceCatalogProvider>();
    final navigator = Navigator.of(context);
    try {
      if (_editing) {
        final e = widget.existing!;
        await catalog.updateService(ServiceItem(
          id: e.id,
          shopId: e.shopId,
          name: name,
          unit: _unit,
          price: storedPrice,
          isAddOn: _isAddOn,
          active: _active,
          serviceType: _serviceType,
          maxKg: maxKg,
          maxKgPrice: maxKgPrice,
        ));
      } else {
        await catalog.addService(
          name: name,
          unit: _unit,
          price: storedPrice,
          isAddOn: _isAddOn,
          active: _active,
          serviceType: _serviceType,
          maxKg: maxKg,
          maxKgPrice: maxKgPrice,
        );
      }
      navigator.pop();
    } catch (e) {
      debugPrint('save service failed: $e');
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _flatActive =>
      _useMaxKg && _unit == PricingUnit.kg && !_isAddOn;

  Widget _buildPreview() {
    final maxKg = double.tryParse(_maxKg.text.trim());
    final flat = double.tryParse(_maxKgPrice.text.trim());
    if (maxKg == null || maxKg <= 0 || flat == null) {
      return const SizedBox.shrink();
    }
    final fmt = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final sample = ServiceItem(
      id: '',
      shopId: '',
      name: '',
      unit: PricingUnit.kg,
      price: flat / maxKg,
      maxKg: maxKg,
      maxKgPrice: flat,
    );
    String kg(double x) => x % 1 == 0 ? x.toInt().toString() : x.toString();
    final over = maxKg + 0.5;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Extra weight is charged at ${fmt.format(sample.extraKgRate)} per kg '
        '(flat price ÷ max kg).\n'
        '${kg(maxKg)} kg = ${fmt.format(sample.priceFor(maxKg))}  •  '
        '${kg(over)} kg = ${fmt.format(sample.priceFor(over))}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_editing ? 'Edit service' : 'Add service',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !_editing,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Service name',
                hintText: 'e.g. Wash & Fold',
              ),
            ),
            const SizedBox(height: 12),
            if (!_flatActive) ...[
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Price',
                prefixText: '₱ ',
              ),
            ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<PricingUnit>(
              segments: const [
                ButtonSegment(
                    value: PricingUnit.kg,
                    label: Text('Per kg'),
                    icon: Icon(Icons.scale_outlined)),
                ButtonSegment(
                    value: PricingUnit.piece,
                    label: Text('Per piece'),
                    icon: Icon(Icons.checkroom_outlined)),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
            if (!_isAddOn) ...[
              const SizedBox(height: 12),
              // Decides which New order sub-tab this service appears under.
              SegmentedButton<ServiceType>(
                segments: const [
                  ButtonSegment(
                      value: ServiceType.selfService,
                      label: Text('Self Service'),
                      icon: Icon(Icons.person_outline)),
                  ButtonSegment(
                      value: ServiceType.fullService,
                      label: Text('Full Service'),
                      icon: Icon(Icons.support_agent)),
                ],
                selected: {_serviceType},
                onSelectionChanged: (s) =>
                    setState(() => _serviceType = s.first),
              ),
            ],
            if (_unit == PricingUnit.kg && !_isAddOn) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Flat price up to a max weight'),
                subtitle: const Text('e.g. ₱70 for up to 7 kg'),
                value: _useMaxKg,
                onChanged: (v) => setState(() => _useMaxKg = v),
              ),
              if (_useMaxKg)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _maxKg,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Max weight',
                          suffixText: 'kg',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _maxKgPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Flat price',
                          prefixText: '₱ ',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              if (_useMaxKg) _buildPreview(),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add-on'),
              subtitle: const Text('e.g. fabric softener, extra rinse'),
              value: _isAddOn,
              onChanged: (v) => setState(() {
                _isAddOn = v;
                if (v) _useMaxKg = false;
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Available for new orders'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_editing ? 'Save changes' : 'Add service'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

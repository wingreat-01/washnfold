import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/staff.dart';
import '../providers/dryer_provider.dart';
import '../providers/order_provider.dart';
import '../providers/service_catalog_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/washer_provider.dart';
import '../services/supabase_service.dart';
import '../providers/alert_settings.dart';
import '../providers/tile_layout_settings.dart';
import '../widgets/machine_alert_host.dart';
import '../widgets/tile_columns_menu.dart';
import '../widgets/shop_qr_dialog.dart';
import '../widgets/washer_free_prompt.dart';
import 'dashboard_screen.dart';
import 'dryer_screen.dart';
import 'my_sales_screen.dart';
import 'order_intake_screen.dart';
import 'order_queue_screen.dart';
import 'settings_screen.dart';
import 'washer_screen.dart';

/// Wraps the screens behind a responsive nav: a side rail on wide/web
/// layouts, a bottom nav bar on phones. Also where the shop-scoped
/// providers are created, since they all need the current shop's id once
/// the user is signed in.
///
/// Which tabs show depends on the signed-in user's role: owners get
/// everything (Dashboard; Services and Staff live in Settings); attendants get New order,
/// Queue and Washers. This only hides the tabs -- what an attendant can
/// actually read/change is enforced by the database's row-level security.
class AppShell extends StatefulWidget {
  final String shopId;
  final StaffRole role;
  const AppShell({super.key, required this.shopId, required this.role});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  List<_Tab> _tabsFor(StaffRole role) => [
        const _Tab(Icons.add_circle_outline_rounded, Icons.add_circle_rounded, 'New order', OrderIntakeScreen()),
        const _Tab(Icons.view_kanban_outlined, Icons.view_kanban_rounded, 'Queue', OrderQueueScreen()),
        const _Tab(Icons.local_laundry_service_outlined, Icons.local_laundry_service_rounded, 'Washers', WasherScreen()),
        const _Tab(Icons.dry_cleaning_outlined, Icons.dry_cleaning_rounded, 'Dryers', DryerScreen()),
        if (role.canViewReports)
          const _Tab(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Dashboard', DashboardScreen())
        else
          // Attendants: own collections + shop total for TODAY only (the
          // database enforces "today"; the full dashboard stays owner-only).
          _Tab(Icons.payments_outlined, Icons.payments_rounded, 'My sales',
              MySalesScreen(active: _index == 4)),
      ];

  void _openSettings(BuildContext context) {
    // Settings is a separate route, so it sits outside the providers created
    // in build(); hand it the service catalog so the Services page works.
    final catalog = context.read<ServiceCatalogProvider>();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<ServiceCatalogProvider>.value(
        value: catalog,
        child: SettingsScreen(role: widget.role, shopId: widget.shopId),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabsFor(widget.role);
    if (_index >= tabs.length) _index = 0;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ServiceCatalogProvider(shopId: widget.shopId)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => OrderProvider(shopId: widget.shopId)..start(),
        ),
        ChangeNotifierProvider(
          create: (_) => WasherProvider(shopId: widget.shopId)..start(),
        ),
        ChangeNotifierProvider(
          create: (_) => DryerProvider(shopId: widget.shopId)..start(),
        ),
        ChangeNotifierProvider(
          create: (_) => DashboardProvider(shopId: widget.shopId),
        ),
        ChangeNotifierProvider(
          create: (_) => AlertSettings()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => TileLayoutSettings()..load(),
        ),
      ],
      child: WasherFreePromptHost(
        child: MachineAlertHost(
        child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final body = IndexedStack(
            index: _index,
            children: tabs.map((t) => t.screen).toList(),
          );

          if (isWide) {
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    backgroundColor: Colors.white,
                    indicatorColor: const Color(0xFF2677C9).withOpacity(.12),
                    selectedIconTheme: const IconThemeData(color: Color(0xFF2677C9)),
                    unselectedIconTheme: const IconThemeData(color: Color(0xFF718096)),
                    selectedLabelTextStyle: const TextStyle(color: Color(0xFF123047), fontWeight: FontWeight.w700),
                    unselectedLabelTextStyle: const TextStyle(color: Color(0xFF718096)),
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(color: const Color(0xFF2677C9).withOpacity(.11), borderRadius: BorderRadius.circular(15)),
                            child: const Icon(Icons.local_laundry_service_rounded, color: Color(0xFF2677C9), size: 27),
                          ),
                          const SizedBox(height: 4),
                          const Text('WashNFold', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF123047))),
                        ],
                      ),
                    ),
                    trailing: Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SoundToggleButton(),
                              IconButton(
                                icon: const Icon(Icons.settings_outlined),
                                tooltip: 'Settings',
                                onPressed: () => _openSettings(context),
                              ),
                              IconButton(
                                icon: const Icon(Icons.logout),
                                tooltip: 'Sign out',
                                onPressed: () =>
                                    SupabaseService.instance.signOut(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    destinations: tabs
                        .map((d) => NavigationRailDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: Text(d.label),
                            ))
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              ),
            );
          }

          return Scaffold(
            // Same AppBar on every tab (including New order) so the action
            // icons never jump position when switching tabs.
            appBar: AppBar(
                    title: Builder(builder: (context) {
                      final screen = tabs[_index].screen;
                      final isWasher = screen is WasherScreen;
                      final isDryer = screen is DryerScreen;
                      final layout = context.watch<TileLayoutSettings>();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tabs[_index].label),
                          // Tiles-per-row picker, phone widths only.
                          if ((isWasher || isDryer) && isPhoneWidth(context))
                            TileColumnsMenu(
                              columns: isWasher
                                  ? layout.washerColumns
                                  : layout.dryerColumns,
                              onChanged: isWasher
                                  ? layout.setWasherColumns
                                  : layout.setDryerColumns,
                            ),
                        ],
                      );
                    }),
                    surfaceTintColor: Colors.transparent,
                    actions: [
                      if (widget.role.canManageStaff)
                        IconButton(
                          tooltip: 'Shop tracking QR code',
                          icon: const Icon(Icons.qr_code_2_rounded),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => ShopQrDialog(shopId: widget.shopId),
                          ),
                        ),
                      const SoundToggleButton(),
                      IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => _openSettings(context),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: () => SupabaseService.instance.signOut(),
                      ),
                    ],
                  ),
            body: body,
            // Shows 5 tabs at a time; any more (6th, 7th) are reached by
            // scrolling the bar sideways.
            bottomNavigationBar: _ScrollableNavBar(
              tabs: tabs,
              selectedIndex: _index,
              onSelected: (i) => setState(() => _index = i),
            ),
          );
        },
      ),
      ),
      ),
    );
  }
}

class _Tab {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget screen;
  const _Tab(this.icon, this.selectedIcon, this.label, this.screen);
}

/// Bottom navigation that fits 5 tabs on screen and scrolls sideways for the
/// rest (Material's NavigationBar can't scroll). With 5 or fewer tabs it just
/// splits the width evenly. A fade + arrow on the right edge hints that more
/// tabs are off-screen, and the selected tab is scrolled into view.
class _ScrollableNavBar extends StatefulWidget {
  final List<_Tab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _ScrollableNavBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<_ScrollableNavBar> createState() => _ScrollableNavBarState();
}

class _ScrollableNavBarState extends State<_ScrollableNavBar> {
  static const _visibleTabs = 5;
  static const _blue = Color(0xFF2677C9);
  static const _navy = Color(0xFF123047);
  static const _grey = Color(0xFF718096);

  final _controller = ScrollController();
  double _itemWidth = 0;
  bool _moreToRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateHint);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHint());
  }

  @override
  void didUpdateWidget(covariant _ScrollableNavBar old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHint());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateHint() {
    if (!mounted || !_controller.hasClients) return;
    final more =
        _controller.offset < _controller.position.maxScrollExtent - 4;
    if (more != _moreToRight) setState(() => _moreToRight = more);
  }

  /// Scrolls just enough to bring the selected tab fully into view.
  void _reveal() {
    if (!mounted || !_controller.hasClients || _itemWidth == 0) return;
    final left = widget.selectedIndex * _itemWidth;
    final right = left + _itemWidth;
    final viewport = _controller.position.viewportDimension;
    double? target;
    if (left < _controller.offset) {
      target = left;
    } else if (right > _controller.offset + viewport) {
      target = right - viewport;
    }
    if (target != null) {
      _controller.animateTo(
        target.clamp(0.0, _controller.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.tabs.length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE7EDF4))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final perScreen = count < _visibleTabs ? count : _visibleTabs;
              _itemWidth = constraints.maxWidth / perScreen;
              return Stack(
                children: [
                  // Mouse / trackpad drag is enabled explicitly because
                  // Flutter web only drags with touch by default.
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: ListView.builder(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      physics: count <= _visibleTabs
                          ? const NeverScrollableScrollPhysics()
                          : const ClampingScrollPhysics(),
                      itemCount: count,
                      itemBuilder: (context, i) => SizedBox(
                        width: _itemWidth,
                        child: _NavItem(
                          tab: widget.tabs[i],
                          selected: i == widget.selectedIndex,
                          onTap: () => widget.onSelected(i),
                        ),
                      ),
                    ),
                  ),
                  if (_moreToRight)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          width: 30,
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0),
                                Colors.white,
                              ],
                            ),
                          ),
                          child: const Icon(Icons.chevron_right_rounded,
                              size: 20, color: _grey),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 56,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? _ScrollableNavBarState._blue.withOpacity(.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              selected ? tab.selectedIcon : tab.icon,
              size: 24,
              color: selected
                  ? _ScrollableNavBarState._blue
                  : _ScrollableNavBarState._grey,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected
                    ? _ScrollableNavBarState._navy
                    : _ScrollableNavBarState._grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

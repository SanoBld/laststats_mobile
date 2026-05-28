// lib/screens/home_screen.dart
// ══════════════════════════════════════════════════════════════════════════
//  Main screen with adaptive navigation.
//
//  Layout modes (controlled by pcModeNotifier in app_state.dart):
//    'auto'  → NavigationRail when width ≥ 720 dp, BottomBar otherwise
//    'on'    → always NavigationRail (side rail, extended above 1200 dp)
//    'off'   → always bottom NavigationBar
// ══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' show sqrt;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../services/lastfm_service.dart';
import '../services/image_service.dart';
import '../services/update_service.dart';
import '../services/data_cache.dart';
import '../services/prefetch_service.dart';
import '../services/all_scrobbles_service.dart';

// ── Settings sub-pages ────────────────────────────────────────────────────────
import 'settings/appearance_page.dart';
import 'settings/dashboard_settings_page.dart';
import 'settings/startup_page.dart';
import 'settings/language_page.dart';
import 'settings/account_page.dart';
import 'settings/backup_page.dart';
import 'settings/cache_page.dart';
import 'settings/updates_page.dart';
import 'settings/about_page.dart';

// Parts
part '_dashboard_page.dart';
part '_search_page.dart';
part '_rankings_page.dart';
part '_detail_sheet.dart';
part '_charts_page.dart';
part '_history_page.dart';
part '_settings_page.dart';
part '_shared_widgets.dart';


// ── Breakpoints ───────────────────────────────────────────────────────────────
/// Minimum width (dp) to automatically activate the side-rail layout.
const double _kWideBreakpoint     = 720.0;
/// Minimum width (dp) to expand the rail and show destination labels inline.
const double _kExtendedBreakpoint = 1200.0;


/// Returns localised (key, label) pairs for period filter chips.
List<(String, String)> _localizedPeriods() => [
  ('7day',    L.period7day),
  ('1month',  L.period1month),
  ('3month',  L.period3month),
  ('6month',  L.period6month),
  ('12month', L.period12month),
  ('overall', L.periodOverall),
];

// ── Month abbreviations (from L, for shared_widgets) ─────────────────────────
List<String> get _kMonths => L.months;

// ── Card border helper ────────────────────────────────────────────────────────
BorderSide _cardBorder(ColorScheme s, {double alpha = 0.45}) =>
    BorderSide(color: s.outlineVariant.withValues(alpha: alpha), width: 1);


// ══════════════════════════════════════════════════════════════════════════════
//  HomeScreen
// ══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  final String username;
  final String apiKey;
  final int    startupTab;
  const HomeScreen({
    super.key,
    required this.username,
    required this.apiKey,
    this.startupTab = 0,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _idx;
  late final LastFmService _service;

  @override
  void initState() {
    super.initState();
    _idx     = widget.startupTab.clamp(0, 4);
    _service = LastFmService(apiKey: widget.apiKey, username: widget.username);

    localeNotifier.addListener(_onLocaleChange);
    pcModeNotifier.addListener(_onLocaleChange); // reacts to layout changes

    DataCache.init().then((_) {
      PrefetchService.prefetchAll(_service);

      if (AllScrobblesService.isFirstLoad) {
        AllScrobblesService.loadAll(_service);
      } else {
        AllScrobblesService.syncNew(_service);
      }
    });
  }

  @override
  void dispose() {
    localeNotifier.removeListener(_onLocaleChange);
    pcModeNotifier.removeListener(_onLocaleChange);
    super.dispose();
  }

  void _onLocaleChange() => setState(() {});

  // ── Layout decision ─────────────────────────────────────────────────────────

  /// Returns true when the wide (side-rail) layout should be used.
  bool _useWideLayout(BuildContext context) {
    final mode  = pcModeNotifier.value;
    if (mode == 'on')  return true;
    if (mode == 'off') return false;
    // 'auto' → screen-width based
    return MediaQuery.of(context).size.width >= _kWideBreakpoint;
  }

  // ── Navigation destinations (shared by both layouts) ───────────────────────

  List<NavigationDestination> get _navDestinations => [
    NavigationDestination(
      icon:         const Icon(Icons.dashboard_outlined),
      selectedIcon: const Icon(Icons.dashboard_rounded),
      label: L.navDashboard,
    ),
    NavigationDestination(
      icon:         const Icon(Icons.search_outlined),
      selectedIcon: const Icon(Icons.search_rounded),
      label: L.navSearch,
    ),
    NavigationDestination(
      icon:         const Icon(Icons.emoji_events_outlined),
      selectedIcon: const Icon(Icons.emoji_events_rounded),
      label: L.navRankings,
    ),
    NavigationDestination(
      icon:         const Icon(Icons.auto_graph_outlined),
      selectedIcon: const Icon(Icons.auto_graph_rounded),
      label: L.navCharts,
    ),
    NavigationDestination(
      icon:         const Icon(Icons.history_outlined),
      selectedIcon: const Icon(Icons.history_rounded),
      label: L.navHistory,
    ),
  ];

  List<NavigationRailDestination> get _railDestinations => [
    NavigationRailDestination(
      icon:         const Icon(Icons.dashboard_outlined),
      selectedIcon: const Icon(Icons.dashboard_rounded),
      label: Text(L.navDashboard),
    ),
    NavigationRailDestination(
      icon:         const Icon(Icons.search_outlined),
      selectedIcon: const Icon(Icons.search_rounded),
      label: Text(L.navSearch),
    ),
    NavigationRailDestination(
      icon:         const Icon(Icons.emoji_events_outlined),
      selectedIcon: const Icon(Icons.emoji_events_rounded),
      label: Text(L.navRankings),
    ),
    NavigationRailDestination(
      icon:         const Icon(Icons.auto_graph_outlined),
      selectedIcon: const Icon(Icons.auto_graph_rounded),
      label: Text(L.navCharts),
    ),
    NavigationRailDestination(
      icon:         const Icon(Icons.history_outlined),
      selectedIcon: const Icon(Icons.history_rounded),
      label: Text(L.navHistory),
    ),
  ];

  // ── Page stack (kept alive via AnimatedOpacity + IgnorePointer) ────────────

  List<Widget> _buildPages() => [
    _DashboardPage(service: _service, username: widget.username),
    _SearchPage(service: _service),
    _RankingsPage(service: _service),
    _ChartsPage(service: _service),
    _HistoryPage(service: _service),
  ];

  /// The page stack is shared between both layouts: every page is always kept
  /// in the widget tree (preserving scroll position and loaded data), and only
  /// the selected one is visible through AnimatedOpacity.
  Widget _pageStack(List<Widget> pages) {
    return Stack(
      children: List.generate(pages.length, (i) => IgnorePointer(
        ignoring: _idx != i,
        child: AnimatedOpacity(
          opacity: _idx == i ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: pages[i],
        ),
      )),
    );
  }

  // ── Narrow layout (bottom NavigationBar) ───────────────────────────────────

  Widget _buildNarrowLayout(List<Widget> pages) {
    return Scaffold(
      body: _pageStack(pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: _navDestinations,
      ),
    );
  }

  // ── Wide layout (side NavigationRail) ──────────────────────────────────────

  Widget _buildWideLayout(BuildContext context, List<Widget> pages) {
    final scheme   = Theme.of(context).colorScheme;
    final width    = MediaQuery.of(context).size.width;
    final extended = width >= _kExtendedBreakpoint;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // ── Side rail ─────────────────────────────────────────────────
            NavigationRail(
              selectedIndex:        _idx,
              onDestinationSelected: (i) => setState(() => _idx = i),

              // Extended rail (labels inline, wider) above 1200 dp.
              extended: extended,

              // When compact, show all labels below icons for clarity.
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,

              // Increase the minimum width so labels aren't clipped.
              minWidth:         72,
              minExtendedWidth: 200,

              // Leading: app logo / title when the rail is extended.
              leading: extended
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(children: [
                        Icon(Icons.equalizer_rounded,
                            color: scheme.primary, size: 22),
                        const SizedBox(width: 10),
                        Text('LastStats',
                            style: TextStyle(
                              color:      scheme.primary,
                              fontSize:   16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            )),
                      ]),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Icon(Icons.equalizer_rounded,
                          color: scheme.primary, size: 22),
                    ),

              destinations: _railDestinations,
            ),

            // ── Separator ────────────────────────────────────────────────
            VerticalDivider(
              width:     1,
              thickness: 1,
              color:     scheme.outlineVariant.withValues(alpha: 0.35),
            ),

            // ── Content area ─────────────────────────────────────────────
            Expanded(child: _pageStack(pages)),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();
    final wide  = _useWideLayout(context);

    return wide
        ? _buildWideLayout(context, pages)
        : _buildNarrowLayout(pages);
  }
}
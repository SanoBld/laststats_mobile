// lib/screens/home_screen.dart
// ══════════════════════════════════════════════════════════════════════════
//  Écran principal avec navigation bas de page.
//  Les paramètres sont désormais dans des sous-pages dédiées.
// ══════════════════════════════════════════════════════════════════════════

import 'dart:async';
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
import '../services/all_scrobbles_service.dart'; // ← Nouveau

// ── Sous-pages de paramètres ──────────────────────────────────────────────────
import 'settings/appearance_page.dart';
import 'settings/dashboard_settings_page.dart';
import 'settings/startup_page.dart';
import 'settings/language_page.dart';
import 'settings/account_page.dart';
import 'settings/backup_page.dart';
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


/// Returns the localized (key, label) pairs for period filter chips.
List<(String, String)> _localizedPeriods() => [
  ('7day',    L.period7day),
  ('1month',  L.period1month),
  ('3month',  L.period3month),
  ('6month',  L.period6month),
  ('12month', L.period12month),
  ('overall', L.periodOverall),
];

// ── Month abbreviations (from L, for shared_widgets) ─────────────────────
List<String> get _kMonths => L.months;

// ── Card border helper ────────────────────────────────────────────────────
BorderSide _cardBorder(ColorScheme s, {double alpha = 0.45}) =>
    BorderSide(color: s.outlineVariant.withValues(alpha: alpha), width: 1);


// ── Home screen ───────────────────────────────────────────────────────────

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
    _idx     = widget.startupTab.clamp(0, 5);
    _service = LastFmService(apiKey: widget.apiKey, username: widget.username);
    localeNotifier.addListener(_onLocaleChange);

    // Initialiser le cache puis lancer les préchargements en arrière-plan
    DataCache.init().then((_) {
      // 1. Données Dashboard / Rankings / Search (prefetch standard)
      PrefetchService.prefetchAll(_service);
      // 2. Historique complet pour les graphiques (silencieux, paginé)
      AllScrobblesService.loadAll(_service);
    });
  }

  @override
  void dispose() {
    localeNotifier.removeListener(_onLocaleChange);
    super.dispose();
  }

  void _onLocaleChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardPage(service: _service, username: widget.username),
      _SearchPage(service: _service),
      _RankingsPage(service: _service),
      _ChartsPage(service: _service),
      _HistoryPage(service: _service),
    ];

    return Scaffold(
      body: Stack(
        children: List.generate(pages.length, (i) => IgnorePointer(
          ignoring: _idx != i,
          child: AnimatedOpacity(
            opacity: _idx == i ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: pages[i],
          ),
        )),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: [
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
        ],
      ),
    );
  }
}
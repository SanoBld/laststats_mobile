import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../services/lastfm_service.dart';
import '../services/image_service.dart';
import '../services/update_service.dart';
import 'setup_screen.dart';

// Parts
part '_dashboard_page.dart';
part '_search_page.dart';
part '_rankings_page.dart';
part '_detail_sheet.dart';
part '_charts_page.dart';
part '_history_page.dart';
part '_settings_page.dart';
part '_shared_widgets.dart';


// ── Period API keys (labels come from L) ──────────────────────────────────
const _kPeriodKeys = [
  '7day', '1month', '3month', '6month', '12month', 'overall',
];

/// Returns the localized (key, label) pairs for period filter chips.
List<(String, String)> _localizedPeriods() => [
  ('7day',    L.period7day),
  ('1month',  L.period1month),
  ('3month',  L.period3month),
  ('6month',  L.period6month),
  ('12month', L.period12month),
  ('overall', L.periodOverall),
];


List<(String, String, IconData)> _localizedHeaderSources() => [
  ('nowplaying',  L.headerNowPlaying,  Icons.play_circle_rounded),
  ('top_track',   L.headerTopTrack,    Icons.music_note_rounded),
  ('top_album',   L.headerTopAlbum,    Icons.album_rounded),
  ('top_artist',  L.headerTopArtist,   Icons.mic_rounded),
  ('custom',      L.headerCustomImage, Icons.image_rounded),
  ('none',        L.headerThemeColor,  Icons.palette_rounded),
];

// ── Header animations ─────────────────────────────────────────────────────
List<(String, String, IconData)> _localizedHeaderAnimations() => [
  ('none',  L.headerAnimNone,  Icons.block_rounded),
  ('fade',  L.headerAnimFade,  Icons.opacity_rounded),
  ('slide', L.headerAnimSlide, Icons.swap_horiz_rounded),
  ('zoom',  L.headerAnimZoom,  Icons.zoom_in_rounded),
];

// ── Header periods ────────────────────────────────────────────────────────
List<(String, String)> _localizedHeaderPeriods() => [
  ('7day',    L.headerPeriodWeek),
  ('1month',  L.headerPeriodMonth),
  ('overall', L.headerPeriodAllTime),
];

// ── Accent presets ────────────────────────────────────────────────────────
const _kAccentOptions = [
  (Color(0xFF7C3AED), 'purple', 'Violet / Purple'),
  (Color(0xFF1D4ED8), 'blue',   'Bleu / Blue'),
  (Color(0xFF059669), 'green',  'Vert / Green'),
  (Color(0xFFDC2626), 'red',    'Rouge / Red'),
  (Color(0xFFD97706), 'orange', 'Orange'),
  (Color(0xFFDB2777), 'pink',   'Rose / Pink'),
  (Color(0xFF0F766E), 'teal',   'Sarcelle / Teal'),
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
    // Rebuild nav labels when language changes
    localeNotifier.addListener(_onLocaleChange);
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
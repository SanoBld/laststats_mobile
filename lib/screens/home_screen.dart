import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
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


// Constants
const _kPeriods = [
  ('7day',    'Semaine'),
  ('1month',  'Mois'),
  ('3month',  '3 mois'),
  ('6month',  '6 mois'),
  ('12month', 'Année'),
  ('overall', 'Tout'),
];

const _kMonths = ['', 'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
    'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];

// Header image source
const _kHeaderSources = [
  ('nowplaying',  'Musique en cours',  Icons.play_circle_rounded),
  ('top_track',   'Titre #1',          Icons.music_note_rounded),
  ('top_album',   'Album #1',          Icons.album_rounded),
  ('top_artist',  'Artiste #1',        Icons.mic_rounded),
  ('custom',      'Image perso.',      Icons.image_rounded),
  ('none',        'Couleur du thème',  Icons.palette_rounded),
];

// Header transition animations
const _kHeaderAnimations = [
  ('none',  'Aucune',     Icons.block_rounded),
  ('fade',  'Fondu',      Icons.opacity_rounded),
  ('slide', 'Glissement', Icons.swap_horiz_rounded),
  ('zoom',  'Zoom',       Icons.zoom_in_rounded),
];

// Periods for top_* sources
const _kHeaderPeriods = [
  ('7day',    'Semaine'),
  ('1month',  'Mois'),
  ('overall', 'Tout temps'),
];


// Accent presets (Color, key, label)
const _kAccentOptions = [
  (Color(0xFF7C3AED), 'purple', 'Violet'),
  (Color(0xFF1D4ED8), 'blue',   'Bleu'),
  (Color(0xFF059669), 'green',  'Vert'),
  (Color(0xFFDC2626), 'red',    'Rouge'),
  (Color(0xFFD97706), 'orange', 'Orange'),
  (Color(0xFFDB2777), 'pink',   'Rose'),
  (Color(0xFF0F766E), 'teal',   'Sarcelle'),
];

// Card border helper — fixes invisible cards in Material You
// Fixes invisible cards in Material You
BorderSide _cardBorder(ColorScheme s, {double alpha = 0.45}) =>
    BorderSide(color: s.outlineVariant.withValues(alpha: alpha), width: 1);


// Home screen

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
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardPage(service: _service, username: widget.username),
      _SearchPage(service: _service),
      _RankingsPage(service: _service),
      _ChartsPage(service: _service),
      _HistoryPage(service: _service),
      _SettingsPage(username: widget.username),
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
        destinations: const [
          NavigationDestination(
            icon:         Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon:         Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Recherche',
          ),
          NavigationDestination(
            icon:         Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded),
            label: 'Classements',
          ),
          NavigationDestination(
            icon:         Icon(Icons.auto_graph_outlined),
            selectedIcon: Icon(Icons.auto_graph_rounded),
            label: 'Graphiques',
          ),
          NavigationDestination(
            icon:         Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Historique',
          ),
          NavigationDestination(
            icon:         Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../services/lastfm_service.dart';
import '../services/image_service.dart';
import '../services/update_service.dart';
import 'setup_screen.dart';

// ─── Constantes ────────────────────────────────────────
const _kDefaultImg =
    'https://lastfm.freetls.fastly.net/i/u/300x300/2a96cbd8b46e442fc41c2b86b821562f.png';

const _kPeriods = [
  ('7day',    'Semaine'),
  ('1month',  'Mois'),
  ('3month',  '3 mois'),
  ('6month',  '6 mois'),
  ('12month', 'Année'),
  ('overall', 'Tout'),
];

const _kGreetingOptions = [
  'Bonjour', 'Bonsoir', 'Salut', 'Hey', 'Coucou', 'Bienvenue',
];

// ═══════════════════════════════════════════════════════
// HOME SCREEN — navigation principale
// ═══════════════════════════════════════════════════════
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
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardPage(service: _service, username: widget.username),
      _RankingsPage(service: _service),
      _ChartsPage(service: _service),
      _HistoryPage(service: _service),
      _SettingsPage(username: widget.username),
    ];

    return Scaffold(
      body: IndexedStack(index: _idx, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard_rounded),
            label: 'Classements',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Graphiques',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Historique',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════
class _DashboardPage extends StatefulWidget {
  final LastFmService service;
  final String username;
  const _DashboardPage({required this.service, required this.username});

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  Map<String, dynamic>? _userInfo;
  List<dynamic> _topArtists = [];
  List<dynamic> _topTracks  = [];
  Map<String, dynamic>? _nowPlaying;
  bool _loading = true;
  String? _error;
  Timer? _npTimer;

  String _greeting     = 'Bonjour';
  bool   _showNowPlay  = true;
  bool   _showStats    = true;
  bool   _showArtists  = true;
  bool   _showTracks   = true;
  String _artistPeriod = 'overall';
  String _trackPeriod  = '7day';

  @override
  void initState() {
    super.initState();
    _loadPrefs().then((_) => _load());
    _npTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _refreshNowPlaying());
  }

  @override
  void dispose() {
    _npTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _greeting     = prefs.getString('ls_greeting')           ?? 'Bonjour';
      _showNowPlay  = prefs.getBool('ls_show_nowplay')         ?? true;
      _showStats    = prefs.getBool('ls_show_stats')           ?? true;
      _showArtists  = prefs.getBool('ls_show_artists')         ?? true;
      _showTracks   = prefs.getBool('ls_show_tracks')          ?? true;
      _artistPeriod = prefs.getString('ls_dash_artist_period') ?? 'overall';
      _trackPeriod  = prefs.getString('ls_dash_track_period')  ?? '7day';
    });
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.service.getUserInfo(),
        widget.service.getTopArtists(period: _artistPeriod, limit: 5),
        widget.service.getTopTracks(period: _trackPeriod, limit: 5),
        widget.service.getNowPlaying(),
      ]);
      final np = results[3] as Map<String, dynamic>?;
      setState(() {
        _userInfo   = results[0] as Map<String, dynamic>?;
        _topArtists = results[1] as List<dynamic>;
        _topTracks  = results[2] as List<dynamic>;
        _nowPlaying = np;
        _loading    = false;
      });
      if (np != null) _extractColorFromNowPlaying(np);
    } catch (e) {
      setState(() {
        _error   = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _refreshNowPlaying() async {
    try {
      final np = await widget.service.getNowPlaying();
      if (mounted) {
        setState(() => _nowPlaying = np);
        if (np != null) _extractColorFromNowPlaying(np);
      }
    } catch (_) {}
  }

  /// Extrait la couleur dominante de la pochette et l'applique si l'option est activée.
  Future<void> _extractColorFromNowPlaying(Map<String, dynamic> track) async {
    if (!useNowPlayingColorNotifier.value) return;
    final url = _extractImage(track['image']);
    if (url.isEmpty || url.contains('2a96cbd8b46e442fc41c2b86b821562f')) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        size: const Size(200, 200),
        maximumColorCount: 16,
      );
      final color = palette.vibrantColor?.color
          ?? palette.dominantColor?.color;
      if (color != null && mounted) {
        accentNotifier.value = color;
      }
    } catch (_) {}
  }

  String _periodLabel(String p) =>
      _kPeriods.firstWhere((x) => x.$1 == p, orElse: () => (p, p)).$2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

    final info       = _userInfo!;
    final name       = (info['name']      ?? widget.username).toString();
    final realName   = (info['realname']  ?? '').toString();
    final country    = (info['country']   ?? '').toString();
    final scrobbles  = (info['playcount'] ?? '0').toString();
    final regRaw     = info['registered'];
    final registered = _parseRegistered(regRaw);
    final avatarUrl  = _extractImage(info['image']);

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [scheme.primaryContainer, scheme.surface],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_greeting, $name 👋',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor:
                                  scheme.primary.withValues(alpha: 0.2),
                              backgroundImage: avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl.isEmpty
                                  ? Icon(Icons.person_rounded,
                                      size: 36,
                                      color: scheme.onPrimaryContainer)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: Theme.of(context).textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w800)),
                                  if (realName.isNotEmpty)
                                    Text(realName,
                                        style: Theme.of(context).textTheme
                                            .bodyMedium
                                            ?.copyWith(color: scheme.onSurfaceVariant)),
                                  if (country.isNotEmpty && country != 'None')
                                    Text(country,
                                        style: Theme.of(context).textTheme
                                            .bodySmall
                                            ?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              title: Text('@$name',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Now Playing ──
                if (_showNowPlay && _nowPlaying != null) ...[
                  _NowPlayingCard(track: _nowPlaying!),
                  const SizedBox(height: 16),
                ],

                // ── Stats ──
                if (_showStats) ...[
                  _StatCard(
                    icon: Icons.headphones_rounded,
                    value: _formatNumber(int.tryParse(scrobbles) ?? 0),
                    label: 'Scrobbles au total',
                    sub: registered.isNotEmpty
                        ? 'Membre depuis $registered'
                        : null,
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Top Artistes ──
                if (_showArtists) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(
                          title: 'Top Artistes', icon: Icons.mic_rounded),
                      _PeriodBadge(
                        label: _periodLabel(_artistPeriod),
                        onTap: () => _showPeriodSheet(
                          title: 'Période — Artistes',
                          current: _artistPeriod,
                          prefKey: 'ls_dash_artist_period',
                          onChanged: (p) {
                            setState(() => _artistPeriod = p);
                            _load();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._topArtists.asMap().entries.map((e) => _ItemTile(
                        name: (e.value['name'] ?? '').toString(),
                        sub:  '${_formatNumber(int.tryParse((e.value['playcount'] ?? '0').toString()) ?? 0)} écoutes',
                        imageUrl: _extractImage(e.value['image']),
                        imageFuture: ImageService.resolveArtist(
                          (e.value['name'] ?? '').toString(),
                          lastfmUrl: _extractImage(e.value['image']),
                        ),
                        rank: '${e.key + 1}',
                      )),
                  const SizedBox(height: 20),
                ],

                // ── Top Titres ──
                if (_showTracks) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(
                          title: 'Top Titres', icon: Icons.music_note_rounded),
                      _PeriodBadge(
                        label: _periodLabel(_trackPeriod),
                        onTap: () => _showPeriodSheet(
                          title: 'Période — Titres',
                          current: _trackPeriod,
                          prefKey: 'ls_dash_track_period',
                          onChanged: (p) {
                            setState(() => _trackPeriod = p);
                            _load();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._topTracks.asMap().entries.map((e) {
                    final artist = (e.value['artist']?['name'] ?? '').toString();
                    final trackName = (e.value['name'] ?? '').toString();
                    return _ItemTile(
                      name:  trackName,
                      sub:   artist,
                      imageUrl: _extractImage(e.value['image']),
                      imageFuture: ImageService.resolveTrack(
                        trackName, artist,
                        lastfmUrl: _extractImage(e.value['image']),
                      ),
                      rank:  '${e.key + 1}',
                      plays: _formatNumber(
                          int.tryParse((e.value['playcount'] ?? '0').toString()) ?? 0),
                    );
                  }),
                  const SizedBox(height: 20),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showPeriodSheet({
    required String title,
    required String current,
    required String prefKey,
    required void Function(String) onChanged,
  }) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Text(title,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._kPeriods.map((p) => ListTile(
                  title: Text(p.$2),
                  trailing: current == p.$1
                      ? Icon(Icons.check_rounded,
                          color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(prefKey, p.$1);
                    onChanged(p.$1);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// NOW PLAYING CARD
// ═══════════════════════════════════════════════════════
class _NowPlayingCard extends StatelessWidget {
  final Map<String, dynamic> track;
  const _NowPlayingCard({required this.track});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final title  = (track['name']             ?? '').toString();
    final artist = (track['artist']?['#text'] ?? '').toString();
    final rawUrl = _extractImage(track['image']);

    return Card(
      elevation: 0,
      color: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _SmartImage(
              size: 56,
              borderRadius: 10,
              initialUrl: rawUrl,
              resolver: () => ImageService.resolveTrack(title, artist,
                  lastfmUrl: rawUrl.isNotEmpty ? rawUrl : null),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: scheme.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('EN COURS',
                        style: text.labelSmall?.copyWith(
                          color: scheme.secondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        )),
                  ]),
                  const SizedBox(height: 2),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                          color: scheme.onSecondaryContainer
                              .withValues(alpha: 0.75))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CLASSEMENTS (Artists + Albums + Tracks)
// ═══════════════════════════════════════════════════════
class _RankingsPage extends StatefulWidget {
  final LastFmService service;
  const _RankingsPage({required this.service});

  @override
  State<_RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<_RankingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _period = 'overall';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Classements',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            // ── Pillules de période ──
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                children: _kPeriods.map((p) {
                  final sel = p.$1 == _period;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(p.$2),
                      selected: sel,
                      onSelected: (_) {
                        if (!sel) setState(() => _period = p.$1);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Artistes'),
                Tab(text: 'Albums'),
                Tab(text: 'Titres'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _TopListBody(
                      service: widget.service,
                      type: 'artists',
                      period: _period),
                  _TopListBody(
                      service: widget.service,
                      type: 'albums',
                      period: _period),
                  _TopListBody(
                      service: widget.service,
                      type: 'tracks',
                      period: _period),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopListBody extends StatefulWidget {
  final LastFmService service;
  final String type;
  final String period;
  const _TopListBody(
      {required this.service, required this.type, required this.period});

  @override
  State<_TopListBody> createState() => _TopListBodyState();
}

class _TopListBodyState extends State<_TopListBody>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _items     = [];
  bool _loading            = true;
  bool _loadingMore        = false;
  bool _exhausted          = false;
  String? _error;
  int _page                = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(_TopListBody old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading   = true;
        _error     = null;
        _page      = 1;
        _exhausted = false;
        _items     = [];
      });
    } else {
      if (_loadingMore || _exhausted) return;
      setState(() => _loadingMore = true);
    }

    try {
      List<dynamic> fresh;
      switch (widget.type) {
        case 'artists':
          fresh = await widget.service
              .getTopArtists(period: widget.period, limit: 50, page: _page);
          break;
        case 'albums':
          fresh = await widget.service
              .getTopAlbums(period: widget.period, limit: 50, page: _page);
          break;
        default:
          fresh = await widget.service
              .getTopTracks(period: widget.period, limit: 50, page: _page);
      }
      if (mounted) {
        setState(() {
          _items.addAll(fresh);
          _exhausted   = fresh.length < 50;
          _loading     = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error       = e.toString().replaceFirst('Exception: ', '');
          _loading     = false;
          _loadingMore = false;
        });
      }
    }
  }

  /// Affiche le bottom sheet de détail pour un item.
  void _showDetail(BuildContext ctx, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemDetailSheet(
        item:    item,
        type:    widget.type,
        service: widget.service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return Center(
          child: Text('Aucun résultat',
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (!_exhausted &&
            !_loadingMore &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
          _page++;
          _load();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == _items.length) {
            return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()));
          }
          final item   = _items[i] as Map<String, dynamic>;
          final name   = (item['name'] ?? '').toString();
          final plays  = _formatNumber(
              int.tryParse((item['playcount'] ?? '0').toString()) ?? 0);
          final artist = (item['artist']?['name'] ?? '').toString();
          final rawUrl = _extractImage(item['image']);

          Future<String> imgFuture;
          switch (widget.type) {
            case 'artists':
              imgFuture = ImageService.resolveArtist(name,
                  lastfmUrl: rawUrl.isNotEmpty ? rawUrl : null);
              break;
            case 'albums':
              imgFuture = ImageService.resolveAlbum(name, artist,
                  lastfmUrl: rawUrl.isNotEmpty ? rawUrl : null);
              break;
            default:
              imgFuture = ImageService.resolveTrack(name, artist,
                  lastfmUrl: rawUrl.isNotEmpty ? rawUrl : null);
          }

          // ── Tap → detail sheet ──
          return InkWell(
            onTap: () => _showDetail(ctx, item),
            borderRadius: BorderRadius.circular(8),
            child: _ItemTile(
              name:        name,
              sub:         widget.type != 'artists'
                  ? '$artist · $plays écoutes'
                  : '$plays écoutes',
              imageUrl:    rawUrl,
              imageFuture: imgFuture,
              rank:        '${i + 1}',
              plays:       widget.type != 'artists' ? plays : null,
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ITEM DETAIL SHEET  — bottom sheet avec pillules de période
// ═══════════════════════════════════════════════════════
class _PeriodStats {
  final int rank;
  final int playcount;
  const _PeriodStats({required this.rank, required this.playcount});
}

class _ItemDetailSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final String type;      // 'artists' | 'albums' | 'tracks'
  final LastFmService service;

  const _ItemDetailSheet({
    required this.item,
    required this.type,
    required this.service,
  });

  @override
  State<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<_ItemDetailSheet> {
  String _period = 'overall';
  final Map<String, _PeriodStats?> _cache = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPeriod('overall');
  }

  Future<void> _loadPeriod(String period) async {
    if (_cache.containsKey(period)) {
      setState(() => _period = period);
      return;
    }
    setState(() { _period = period; _loading = true; });

    final name       = (widget.item['name'] ?? '').toString();
    final artistName = widget.type != 'artists'
        ? (widget.item['artist']?['name'] ?? '').toString()
        : '';

    try {
      List<dynamic> items;
      if (widget.type == 'artists') {
        items = await widget.service
            .getTopArtists(period: period, limit: 200);
      } else if (widget.type == 'albums') {
        items = await widget.service
            .getTopAlbums(period: period, limit: 200);
      } else {
        items = await widget.service
            .getTopTracks(period: period, limit: 200);
      }

      int rank = -1;
      int playcount = 0;
      for (var i = 0; i < items.length; i++) {
        final n = (items[i]['name'] ?? '').toString();
        final a = widget.type != 'artists'
            ? (items[i]['artist']?['name'] ?? '').toString()
            : '';
        final nameMatch = n == name;
        final artistMatch = widget.type == 'artists' || a == artistName;
        if (nameMatch && artistMatch) {
          rank = i + 1;
          playcount =
              int.tryParse((items[i]['playcount'] ?? '0').toString()) ?? 0;
          break;
        }
      }

      setState(() {
        _cache[period] = _PeriodStats(rank: rank, playcount: playcount);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _cache[period] = _PeriodStats(rank: -1, playcount: 0);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme     = Theme.of(context).colorScheme;
    final text       = Theme.of(context).textTheme;
    final item       = widget.item;
    final name       = (item['name'] ?? '').toString();
    final artistName = widget.type != 'artists'
        ? (item['artist']?['name'] ?? '').toString()
        : '';
    final rawUrl     = _extractImage(item['image']);
    final stats      = _cache[_period];
    final periodLabel =
        _kPeriods.firstWhere((p) => p.$1 == _period, orElse: () => (_period, _period)).$2;

    Future<String> imgFuture;
    switch (widget.type) {
      case 'artists':
        imgFuture = ImageService.resolveArtist(name,
            lastfmUrl: rawUrl.isNotEmpty ? rawUrl : null);
        break;
      case 'albums':
        imgFuture = ImageService.resolveAlbum(name, artistName,
            lastfmUrl: rawUrl.isNotEmpty ? rawUrl : null);
        break;
      default:
        imgFuture = ImageService.resolveTrack(name, artistName,
            lastfmUrl: rawUrl.isNotEmpty ? rawUrl : null);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize:     0.35,
      maxChildSize:     0.85,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color:        scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle ──
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header : image + nom ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(children: [
                _SmartImage(
                  size: 72,
                  borderRadius: 12,
                  initialUrl: rawUrl,
                  resolver: () => imgFuture,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      if (artistName.isNotEmpty)
                        Text(artistName,
                            style: text.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          switch (widget.type) {
                            'artists' => 'Artiste',
                            'albums'  => 'Album',
                            _         => 'Titre',
                          },
                          style: text.labelSmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),

            const Divider(height: 24),

            // ── Pillules de période ──
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                children: _kPeriods.map((p) {
                  final sel = p.$1 == _period;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(p.$2),
                      selected: sel,
                      showCheckmark: false,
                      onSelected: (_) => _loadPeriod(p.$1),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // ── Stats pour la période sélectionnée ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      child: stats == null
                          ? const SizedBox.shrink()
                          : Column(children: [
                              // Rang
                              if (stats.rank > 0 && stats.rank <= 200)
                                _DetailStatCard(
                                  icon:  Icons.leaderboard_rounded,
                                  value: '#${stats.rank}',
                                  label: 'Classement · $periodLabel',
                                  color: scheme.primaryContainer,
                                  onColor: scheme.onPrimaryContainer,
                                ),
                              const SizedBox(height: 12),
                              // Écoutes
                              _DetailStatCard(
                                icon:  Icons.headphones_rounded,
                                value: _formatNumber(stats.playcount),
                                label: 'Écoutes · $periodLabel',
                                color: scheme.secondaryContainer,
                                onColor: scheme.onSecondaryContainer,
                              ),
                              // Non classé
                              if (stats.rank == -1 || stats.rank > 200)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(
                                    'Non classé dans le top 200 pour cette période.',
                                    textAlign: TextAlign.center,
                                    style: text.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ),
                            ]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color onColor;
  const _DetailStatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(icon, color: onColor, size: 32),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: onColor)),
            Text(label,
                style: text.bodySmall
                    ?.copyWith(color: onColor.withValues(alpha: 0.8))),
          ]),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// GRAPHIQUES
// ═══════════════════════════════════════════════════════
class _ChartsPage extends StatefulWidget {
  final LastFmService service;
  const _ChartsPage({required this.service});

  @override
  State<_ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<_ChartsPage>
    with AutomaticKeepAliveClientMixin {
  Map<String, int>? _monthly;
  List<dynamic>     _topArtists = [];
  bool _loading     = true;
  String? _error;
  bool _gemsLoading = false;
  List<_GemEntry> _gems = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Future.wait([
        widget.service.getMonthlyScrobbles(months: 12),
        widget.service.getTopArtists(period: 'overall', limit: 10),
      ]);
      setState(() {
        _monthly    = res[0] as Map<String, int>;
        _topArtists = res[1] as List<dynamic>;
        _loading    = false;
      });
    } catch (e) {
      setState(() {
        _error   = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _computeGems() async {
    if (_topArtists.isEmpty) return;
    setState(() { _gemsLoading = true; _gems = []; });
    final artists  = _topArtists.take(15).toList();
    final futures  = artists.map(
        (a) => widget.service.getArtistListeners((a['name'] ?? '').toString()));
    final listeners = await Future.wait(futures);

    final entries = <_GemEntry>[];
    for (var i = 0; i < artists.length; i++) {
      entries.add(_GemEntry(
        name:      (artists[i]['name'] ?? '').toString(),
        plays:     int.tryParse((artists[i]['playcount'] ?? '0').toString()) ?? 0,
        listeners: listeners[i] ?? 0,
      ));
    }
    entries.sort((a, b) => a.listeners.compareTo(b.listeners));
    setState(() { _gems = entries; _gemsLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

    final monthly = _monthly!;
    final maxVal  = monthly.values.fold(0, (a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Graphiques',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),

          _SectionHeader(
              title: 'Scrobbles — 12 derniers mois',
              icon: Icons.calendar_month_rounded),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Column(children: [
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: monthly.entries.map((e) {
                      final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
                      final month = e.key.substring(5);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (ratio > 0)
                                Text(_formatNumber(e.value),
                                    style: text.labelSmall?.copyWith(
                                        fontSize: 8,
                                        color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Flexible(
                                fit: FlexFit.loose,
                                child: FractionallySizedBox(
                                  heightFactor: ratio.clamp(0.02, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: scheme.primary
                                          .withValues(alpha: 0.5 + ratio * 0.5),
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(month,
                                  style: text.labelSmall
                                      ?.copyWith(fontSize: 9)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 24),

          _SectionHeader(
              title: 'Top artistes — distribution',
              icon: Icons.mic_rounded),
          const SizedBox(height: 12),
          if (_topArtists.isNotEmpty) ...[
            () {
              final maxPlays = _topArtists
                  .map((a) =>
                      int.tryParse((a['playcount'] ?? '0').toString()) ?? 0)
                  .fold(0, (a, b) => a > b ? a : b);
              return Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: _topArtists.asMap().entries.map((e) {
                      final plays = int.tryParse(
                              (e.value['playcount'] ?? '0').toString()) ?? 0;
                      final ratio = maxPlays > 0 ? plays / maxPlays : 0.0;
                      final name  = (e.value['name'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          SizedBox(
                            width: 24,
                            child: Text('${e.key + 1}',
                                textAlign: TextAlign.center,
                                style: text.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 8,
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.15),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    scheme.primary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_formatNumber(plays),
                              style: text.bodySmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
              );
            }(),
          ],

          const SizedBox(height: 24),

          _SectionHeader(
              title: 'Mainstream vs Pépites',
              icon: Icons.diamond_outlined),
          const SizedBox(height: 8),
          Text(
            'Compare tes artistes favoris à leur popularité mondiale sur Last.fm.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          if (_gems.isEmpty && !_gemsLoading)
            FilledButton.icon(
              onPressed: _computeGems,
              icon: const Icon(Icons.calculate_rounded),
              label: const Text('Calculer mon score'),
            )
          else if (_gemsLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator()))
          else ...[
            ..._gems.asMap().entries.map((e) {
              final gem   = e.value;
              final isGem = gem.listeners < 500000;
              return Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: Text(isGem ? '💎' : '🎤',
                      style: const TextStyle(fontSize: 24)),
                  title: Text(gem.name,
                      style: text.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${_formatNumber(gem.listeners)} auditeurs mondiaux',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  trailing: Text(isGem ? 'Pépite' : 'Mainstream',
                      style: text.labelSmall?.copyWith(
                          color: isGem ? scheme.tertiary : scheme.primary,
                          fontWeight: FontWeight.w700)),
                ),
              );
            }),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                  onPressed: _computeGems, child: const Text('Recalculer')),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _GemEntry {
  final String name;
  final int plays;
  final int listeners;
  const _GemEntry({required this.name, required this.plays, required this.listeners});
}

// ═══════════════════════════════════════════════════════
// HISTORIQUE  —  avec filtres de dates
// ═══════════════════════════════════════════════════════
class _HistoryPage extends StatefulWidget {
  final LastFmService service;
  const _HistoryPage({required this.service});

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _tracks    = [];
  bool _loading            = true;
  bool _loadingMore        = false;
  bool _exhausted          = false;
  String? _error;
  int _page                = 1;
  Map<String, dynamic>? _nowPlaying;

  // ── Filtre de dates ────────────────────────────────
  String          _preset      = 'all';   // 'all' | 'today' | '7d' | '30d' | 'month' | 'custom'
  DateTimeRange?  _customRange;

  static const _presets = [
    ('all',    'Tout',        null),
    ('today',  "Aujourd'hui", null),
    ('7d',     '7 jours',     null),
    ('30d',    '30 jours',    null),
    ('month',  'Ce mois',     null),
    ('custom', 'Personnalisé', null),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  /// Calcule from/to en Unix timestamp selon le preset sélectionné.
  (int?, int?) _getRange() {
    final now = DateTime.now();
    switch (_preset) {
      case 'today':
        final start = DateTime(now.year, now.month, now.day);
        return (start.millisecondsSinceEpoch ~/ 1000,
                now.millisecondsSinceEpoch   ~/ 1000);
      case '7d':
        return (now.subtract(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
                now.millisecondsSinceEpoch ~/ 1000);
      case '30d':
        return (now.subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
                now.millisecondsSinceEpoch ~/ 1000);
      case 'month':
        final start = DateTime(now.year, now.month, 1);
        return (start.millisecondsSinceEpoch ~/ 1000,
                now.millisecondsSinceEpoch   ~/ 1000);
      case 'custom':
        if (_customRange != null) {
          return (
            _customRange!.start.millisecondsSinceEpoch ~/ 1000,
            _customRange!.end
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch ~/ 1000,
          );
        }
        return (null, null);
      default:
        return (null, null);
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading    = true;
        _error      = null;
        _page       = 1;
        _exhausted  = false;
        _tracks     = [];
      });
    } else {
      if (_loadingMore || _exhausted) return;
      setState(() => _loadingMore = true);
    }

    try {
      final (from, to) = _getRange();
      final data  = await widget.service.getRecentTracks(
        limit: 50,
        page:  _page,
        from:  from,
        to:    to,
      );
      final raw   = data['track'];
      final fresh = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);
      final attr  = data['@attr'] as Map?;
      final totalP =
          int.tryParse(attr?['totalPages']?.toString() ?? '1') ?? 1;

      Map<String, dynamic>? np;
      final list = <dynamic>[];
      for (final t in fresh) {
        if ((t as Map?)?['@attr']?['nowplaying'] == 'true') {
          np = t as Map<String, dynamic>;
        } else {
          list.add(t);
        }
      }

      setState(() {
        if (reset) {
          _tracks = list;
        } else {
          _tracks.addAll(list);
        }
        _nowPlaying  = reset ? np : (_nowPlaying ?? np);
        _exhausted   = _page >= totalP;
        _loading     = false;
        _loadingMore = false;
      });
    } catch (e) {
      setState(() {
        _error       = e.toString().replaceFirst('Exception: ', '');
        _loading     = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate:  now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end:   now,
          ),
      helpText:        'Sélectionner une plage',
      cancelText:      'Annuler',
      confirmText:     'Valider',
      saveText:        'Valider',
      fieldStartHintText: 'Début',
      fieldEndHintText:   'Fin',
    );

    if (range != null) {
      setState(() {
        _customRange = range;
        _preset      = 'custom';
      });
      _load(reset: true);
    }
  }

  void _selectPreset(String preset) {
    if (preset == 'custom') {
      _pickCustomRange();
      return;
    }
    if (_preset == preset) return;
    setState(() => _preset = preset);
    _load(reset: true);
  }

  String get _customLabel {
    if (_customRange == null) return 'Personnalisé';
    final s = _customRange!.start;
    final e = _customRange!.end;
    return '${s.day}/${s.month} → ${e.day}/${e.month}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Historique',
                        style: text.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (_preset != 'all')
                    IconButton(
                      icon: const Icon(Icons.filter_alt_off_rounded),
                      tooltip: 'Réinitialiser le filtre',
                      onPressed: () => _selectPreset('all'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => _load(reset: true),
                    tooltip: 'Rafraîchir',
                  ),
                ],
              ),
            ),

            // ── Pillules de date ──
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                children: [
                  // Presets standard
                  for (final p in _presets.take(5))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(p.$1 == 'all' ? 'Tout' : p.$2),
                        selected: _preset == p.$1,
                        onSelected: (_) => _selectPreset(p.$1),
                        showCheckmark: false,
                      ),
                    ),
                  // Personnalisé (avec icône calendrier)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_preset == 'custom'
                          ? _customLabel
                          : 'Personnalisé'),
                      selected: _preset == 'custom',
                      avatar: Icon(Icons.date_range_rounded,
                          size: 16,
                          color: _preset == 'custom'
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant),
                      onSelected: (_) => _pickCustomRange(),
                      showCheckmark: false,
                    ),
                  ),
                ],
              ),
            ),

            // ── Résumé de la plage active ──
            if (_preset != 'all')
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  _presetDescription(),
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),

            const Divider(height: 12),

            // ── Liste ──
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                  child: _ErrorView(
                      message: _error!,
                      onRetry: () => _load(reset: true)))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (!_exhausted &&
                          !_loadingMore &&
                          n.metrics.pixels >=
                              n.metrics.maxScrollExtent - 300) {
                        _page++;
                        _load();
                      }
                      return false;
                    },
                    child: _tracks.isEmpty
                        ? Center(
                            child: Text('Aucune écoute sur cette période.',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant)))
                        : ListView.builder(
                            itemCount:
                                (_nowPlaying != null ? 1 : 0) +
                                    _tracks.length +
                                    (_loadingMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (_nowPlaying != null && i == 0) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                  child: _NowPlayingCard(track: _nowPlaying!),
                                );
                              }
                              final idx =
                                  _nowPlaying != null ? i - 1 : i;
                              if (idx == _tracks.length) {
                                return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                        child: CircularProgressIndicator()));
                              }
                              final t      = _tracks[idx] as Map;
                              final title  = (t['name']             ?? '').toString();
                              final artist = (t['artist']?['#text'] ?? '').toString();
                              final album  = (t['album']?['#text']  ?? '').toString();
                              final rawUrl = _extractImage(t['image']);
                              final dateRaw = t['date']?['#text'] ?? '';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 2),
                                leading: _SmartImage(
                                  size: 46,
                                  borderRadius: 6,
                                  initialUrl: rawUrl,
                                  resolver: () => ImageService.resolveTrack(
                                      title, artist,
                                      lastfmUrl:
                                          rawUrl.isNotEmpty ? rawUrl : null),
                                ),
                                title: Text(title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    album.isNotEmpty
                                        ? '$artist · $album'
                                        : artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant)),
                                trailing: Text(_formatDate(dateRaw),
                                    style: text.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant)),
                              );
                            },
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _presetDescription() {
    final now = DateTime.now();
    switch (_preset) {
      case 'today':
        return "Aujourd'hui (${now.day}/${now.month}/${now.year})";
      case '7d':
        final from = now.subtract(const Duration(days: 7));
        return 'Du ${from.day}/${from.month} au ${now.day}/${now.month}';
      case '30d':
        final from = now.subtract(const Duration(days: 30));
        return 'Du ${from.day}/${from.month} au ${now.day}/${now.month}';
      case 'month':
        return 'Ce mois-ci (${now.month}/${now.year})';
      case 'custom':
        if (_customRange != null) {
          final s = _customRange!.start;
          final e = _customRange!.end;
          return 'Du ${s.day}/${s.month}/${s.year} au ${e.day}/${e.month}/${e.year}';
        }
        return 'Plage personnalisée';
      default:
        return '';
    }
  }
}

// ═══════════════════════════════════════════════════════
// PARAMÈTRES
// ═══════════════════════════════════════════════════════

const _kAccentOptions = [
  (Color(0xFF7C3AED), 'purple', 'Violet'),
  (Color(0xFF1D4ED8), 'blue',   'Bleu'),
  (Color(0xFF059669), 'green',  'Vert'),
  (Color(0xFFDC2626), 'red',    'Rouge'),
  (Color(0xFFD97706), 'orange', 'Orange'),
  (Color(0xFFDB2777), 'pink',   'Rose'),
];

const _kStartupLabels = [
  (Icons.dashboard_rounded,   'Dashboard'),
  (Icons.leaderboard_rounded, 'Classements'),
  (Icons.bar_chart_rounded,   'Graphiques'),
  (Icons.history_rounded,     'Historique'),
];

class _SettingsPage extends StatefulWidget {
  final String username;
  const _SettingsPage({required this.username});

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  // Apparence
  String _theme           = 'system';
  String _accent          = 'purple';
  bool   _useDynamicColor = false;
  bool   _useNowPlayingColor = false;
  int    _startupTab      = 0;

  // Dashboard
  String _greeting        = 'Bonjour';
  bool   _showNowPlay     = true;
  bool   _showStats       = true;
  bool   _showArtists     = true;
  bool   _showTracks      = true;
  String _artistPeriod    = 'overall';
  String _trackPeriod     = '7day';

  // Mises à jour
  bool        _autoUpdate     = true;
  UpdateInfo? _updateInfo;
  bool        _checkingUpdate = false;
  String?     _updateError;

  @override
  void initState() {
    super.initState();
    _loadPrefs().then((_) => _maybeCheckUpdate());
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _theme             = prefs.getString('ls_theme')               ?? 'system';
      _accent            = prefs.getString('ls_accent')              ?? 'purple';
      _useDynamicColor   = prefs.getBool('ls_use_dynamic_color')     ?? false;
      _useNowPlayingColor = prefs.getBool('ls_use_nowplaying_color') ?? false;
      _startupTab        = prefs.getInt('ls_startup_tab')            ?? 0;
      _greeting          = prefs.getString('ls_greeting')            ?? 'Bonjour';
      _showNowPlay       = prefs.getBool('ls_show_nowplay')          ?? true;
      _showStats         = prefs.getBool('ls_show_stats')            ?? true;
      _showArtists       = prefs.getBool('ls_show_artists')          ?? true;
      _showTracks        = prefs.getBool('ls_show_tracks')           ?? true;
      _artistPeriod      = prefs.getString('ls_dash_artist_period')  ?? 'overall';
      _trackPeriod       = prefs.getString('ls_dash_track_period')   ?? '7day';
      _autoUpdate        = prefs.getBool('ls_auto_update_check')     ?? true;
    });
  }

  Future<void> _maybeCheckUpdate() async {
    if (!_autoUpdate) return;
    final prefs     = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt('ls_last_update_check') ?? 0;
    final now       = DateTime.now().millisecondsSinceEpoch;
    if (now - lastCheck < const Duration(days: 1).inMilliseconds) return;
    await _checkUpdate(auto: true);
  }

  Future<void> _checkUpdate({bool auto = false}) async {
    if (!mounted) return;
    setState(() { _checkingUpdate = true; _updateError = null; });
    try {
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ls_last_update_check',
          DateTime.now().millisecondsSinceEpoch);
      setState(() {
        _updateInfo     = info;
        _checkingUpdate = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _updateError    = 'Vérification impossible.';
        _checkingUpdate = false;
      });
    }
  }

  Future<void> _setPref<T>(String key, T value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool)   await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
    if (value is int)    await prefs.setInt(key, value);
  }

  Future<void> _setTheme(String value) async {
    await _setPref('ls_theme', value);
    setState(() => _theme = value);
    themeModeNotifier.value = themeFromString(value);
  }

  Future<void> _setAccent(String key, Color color) async {
    await _setPref('ls_accent', key);
    setState(() => _accent = key);
    if (!_useDynamicColor && !_useNowPlayingColor) {
      accentNotifier.value = color;
    }
  }

  Future<void> _setStartupTab(int idx) async {
    await _setPref('ls_startup_tab', idx);
    setState(() => _startupTab = idx);
  }

  void _pickGreeting() {
    final ctrl = TextEditingController(text: _greeting);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salutation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _kGreetingOptions.map((g) => ActionChip(
                label: Text(g),
                onPressed: () { ctrl.text = g; },
              )).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Ou saisir librement',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) {
                await _setPref('ls_greeting', v);
                setState(() => _greeting = v);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Paramètres',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),

          // ── Bannière mise à jour ──
          if (_updateInfo != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Icon(Icons.system_update_rounded,
                    color: scheme.onTertiaryContainer, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mise à jour — v${_updateInfo!.version}',
                          style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onTertiaryContainer)),
                      if (_updateInfo!.notes.isNotEmpty)
                        Text(
                          _updateInfo!.notes.length > 120
                              ? '${_updateInfo!.notes.substring(0, 120)}…'
                              : _updateInfo!.notes,
                          style: text.bodySmall?.copyWith(
                              color: scheme.onTertiaryContainer
                                  .withValues(alpha: 0.8)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final url = Uri.parse(_updateInfo!.hasApk
                        ? _updateInfo!.apkUrl!
                        : _updateInfo!.releaseUrl);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.tertiary,
                    foregroundColor: scheme.onTertiary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: text.labelMedium,
                  ),
                  child:
                      Text(_updateInfo!.hasApk ? 'Télécharger' : 'Voir'),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ════════════════════
          // APPARENCE — THÈME
          // ════════════════════
          _SettingsSection(label: 'Apparence', children: [

            // Thème
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.contrast_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Thème',
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'system',
                          icon: Icon(Icons.brightness_auto_rounded),
                          label: Text('Auto')),
                      ButtonSegment(
                          value: 'light',
                          icon: Icon(Icons.light_mode_rounded),
                          label: Text('Clair')),
                      ButtonSegment(
                          value: 'dark',
                          icon: Icon(Icons.dark_mode_rounded),
                          label: Text('Sombre')),
                    ],
                    selected: {_theme},
                    onSelectionChanged: (s) => _setTheme(s.first),
                    style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Couleur d'accent (désactivée si dynamic color actif)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.palette_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text("Couleur d'accent",
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (_useDynamicColor || _useNowPlayingColor) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Auto',
                            style: text.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  Opacity(
                    opacity: (_useDynamicColor || _useNowPlayingColor) ? 0.35 : 1.0,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _kAccentOptions.map((opt) {
                        final (color, key, label) = opt;
                        final selected = _accent == key;
                        return GestureDetector(
                          onTap: (_useDynamicColor || _useNowPlayingColor)
                              ? null
                              : () => _setAccent(key, color),
                          child: Tooltip(
                            message: label,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: selected
                                    ? Border.all(
                                        color: scheme.onSurface, width: 3)
                                    : Border.all(
                                        color: Colors.transparent, width: 3),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                            color: color.withValues(alpha: 0.5),
                                            blurRadius: 8)
                                      ]
                                    : [],
                              ),
                              child: selected
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 18)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ════════════════════
          // COULEUR DYNAMIQUE
          // ════════════════════
          _SettingsSection(label: 'Couleur dynamique', children: [

            // Material You
            SwitchListTile(
              secondary: Icon(Icons.colorize_rounded, color: scheme.primary),
              title: const Text('Material You'),
              subtitle: const Text('Utilise la couleur du thème Android'),
              value: _useDynamicColor,
              onChanged: (v) async {
                await _setPref('ls_use_dynamic_color', v);
                setState(() {
                  _useDynamicColor = v;
                  if (v) _useNowPlayingColor = false;
                });
                useDynamicColorNotifier.value  = v;
                useNowPlayingColorNotifier.value = false;
                if (!v) accentNotifier.value = accentFromString(_accent);
              },
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Couleur depuis la musique
            SwitchListTile(
              secondary: Icon(Icons.album_rounded,
                  color: _useDynamicColor
                      ? scheme.onSurfaceVariant
                      : scheme.primary),
              title: const Text('Couleur depuis la musique'),
              subtitle: Text(
                _useDynamicColor
                    ? 'Désactiver Material You d\'abord'
                    : 'Extrait la couleur de la pochette en cours',
              ),
              value: _useNowPlayingColor,
              onChanged: _useDynamicColor
                  ? null
                  : (v) async {
                      await _setPref('ls_use_nowplaying_color', v);
                      setState(() => _useNowPlayingColor = v);
                      useNowPlayingColorNotifier.value = v;
                      if (!v) accentNotifier.value = accentFromString(_accent);
                    },
            ),

            // Explication
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Quand une musique est en lecture, sa couleur dominante remplace la couleur d\'accent.',
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ════════════════════
          // PAGE DE DÉMARRAGE
          // ════════════════════
          _SettingsSection(label: 'Page de démarrage', children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.rocket_launch_rounded,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text("Onglet à l'ouverture",
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _kStartupLabels.asMap().entries.map((e) {
                      final sel = _startupTab == e.key;
                      return FilterChip(
                        avatar: Icon(e.value.$1, size: 16),
                        label: Text(e.value.$2),
                        selected: sel,
                        onSelected: (_) => _setStartupTab(e.key),
                        showCheckmark: false,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ════════════════════
          // DASHBOARD
          // ════════════════════
          _SettingsSection(label: 'Dashboard', children: [

            ListTile(
              leading: Icon(Icons.waving_hand_rounded,
                  color: scheme.primary, size: 22),
              title: const Text('Salutation'),
              subtitle: Text(_greeting),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickGreeting,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Sections visibles',
                  style: text.bodySmall?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('En cours de lecture'),
              value: _showNowPlay,
              onChanged: (v) async {
                await _setPref('ls_show_nowplay', v);
                setState(() => _showNowPlay = v);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.bar_chart_rounded),
              title: const Text('Statistiques'),
              value: _showStats,
              onChanged: (v) async {
                await _setPref('ls_show_stats', v);
                setState(() => _showStats = v);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.mic_rounded),
              title: const Text('Top Artistes'),
              value: _showArtists,
              onChanged: (v) async {
                await _setPref('ls_show_artists', v);
                setState(() => _showArtists = v);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.music_note_rounded),
              title: const Text('Top Titres'),
              value: _showTracks,
              onChanged: (v) async {
                await _setPref('ls_show_tracks', v);
                setState(() => _showTracks = v);
              },
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Périodes par défaut',
                  style: text.bodySmall?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading:
                  Icon(Icons.mic_rounded, size: 20, color: scheme.secondary),
              title: const Text('Artistes'),
              trailing: Text(
                _kPeriods.firstWhere((p) => p.$1 == _artistPeriod,
                    orElse: () => (_artistPeriod, _artistPeriod)).$2,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              onTap: () => _showPeriodSheet(
                title: 'Période — Artistes',
                current: _artistPeriod,
                onPick: (p) async {
                  await _setPref('ls_dash_artist_period', p);
                  setState(() => _artistPeriod = p);
                },
              ),
            ),
            ListTile(
              leading: Icon(Icons.music_note_rounded,
                  size: 20, color: scheme.secondary),
              title: const Text('Titres'),
              trailing: Text(
                _kPeriods.firstWhere((p) => p.$1 == _trackPeriod,
                    orElse: () => (_trackPeriod, _trackPeriod)).$2,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              onTap: () => _showPeriodSheet(
                title: 'Période — Titres',
                current: _trackPeriod,
                onPick: (p) async {
                  await _setPref('ls_dash_track_period', p);
                  setState(() => _trackPeriod = p);
                },
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ════════════════════
          // COMPTE
          // ════════════════════
          _SettingsSection(label: 'Compte', children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  widget.username.isNotEmpty
                      ? widget.username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(widget.username,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Profil Last.fm connecté'),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: scheme.error),
              title: Text('Se déconnecter',
                  style: TextStyle(color: scheme.error)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Se déconnecter ?'),
                    content: const Text(
                        'Tes identifiants seront supprimés de l\'appareil.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Déconnecter')),
                    ],
                  ),
                );
                if (ok == true && mounted) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('ls_username');
                  await prefs.remove('ls_apikey');
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const SetupScreen()),
                      (_) => false,
                    );
                  }
                }
              },
            ),
          ]),

          const SizedBox(height: 16),

          // ════════════════════
          // MISES À JOUR
          // ════════════════════
          _SettingsSection(label: 'Mises à jour', children: [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Vérification automatique'),
              subtitle: const Text('1 fois par jour'),
              value: _autoUpdate,
              onChanged: (v) async {
                await _setPref('ls_auto_update_check', v);
                setState(() => _autoUpdate = v);
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: _checkingUpdate
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.system_update_outlined),
              title: const Text('Vérifier maintenant'),
              subtitle: _updateError != null
                  ? Text(_updateError!,
                      style: TextStyle(color: scheme.error))
                  : (_updateInfo == null
                      ? const Text("À jour")
                      : Text('v${_updateInfo!.version} disponible')),
              onTap: _checkingUpdate ? null : () => _checkUpdate(),
            ),
          ]),

          const SizedBox(height: 16),

          // ════════════════════
          // À PROPOS
          // ════════════════════
          _SettingsSection(label: 'À propos', children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Version'),
              trailing: Text(UpdateService.currentVersion,
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.web_rounded),
              title: const Text('Version web complète'),
              subtitle: const Text('sanobld.github.io/LastStats'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16),
              onTap: () async {
                final uri = Uri.parse('https://sanobld.github.io/LastStats');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.code_rounded),
              title: const Text('Code source'),
              subtitle: const Text('github.com/sanobld/LastStats'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16),
              onTap: () async {
                final uri =
                    Uri.parse('https://github.com/sanobld/LastStats');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ]),

          const SizedBox(height: 24),
          Center(
            child: Text('LastStats Mobile v${UpdateService.currentVersion}',
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showPeriodSheet({
    required String title,
    required String current,
    required void Function(String) onPick,
  }) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ..._kPeriods.map((p) => ListTile(
                  title: Text(p.$2),
                  trailing: current == p.$1
                      ? Icon(Icons.check_rounded,
                          color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () {
                    onPick(p.$1);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// WIDGETS RÉUTILISABLES
// ═══════════════════════════════════════════════════════

class _SettingsSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _SettingsSection({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label.toUpperCase(),
              style: text.labelSmall?.copyWith(
                color:         scheme.primary,
                fontWeight:    FontWeight.w700,
                letterSpacing: 1.2,
              )),
        ),
        Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Image résolvable multi-sources via ImageService.
class _SmartImage extends StatelessWidget {
  final String? initialUrl;
  final Future<String> Function() resolver;
  final double size;
  final double borderRadius;

  const _SmartImage({
    required this.resolver,
    required this.size,
    required this.borderRadius,
    this.initialUrl,
  });

  static const _placeholder = '2a96cbd8b46e442fc41c2b86b821562f';

  bool get _needsResolve =>
      initialUrl == null ||
      initialUrl!.isEmpty ||
      initialUrl!.contains(_placeholder);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_needsResolve) return _buildImage(context, initialUrl!, scheme);
    return FutureBuilder<String>(
      future: resolver(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingBox(scheme);
        }
        final url = snap.data ?? '';
        if (url.isEmpty) return _fallbackBox(scheme);
        return _buildImage(context, url, scheme);
      },
    );
  }

  Widget _buildImage(BuildContext ctx, String url, ColorScheme scheme) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallbackBox(scheme)),
      );

  Widget _loadingBox(ColorScheme scheme) => ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: size, height: size,
          color: scheme.surfaceContainerHighest,
          child: Center(
            child: SizedBox(
              width: size * 0.4, height: size * 0.4,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: scheme.primary.withValues(alpha: 0.5)),
            ),
          ),
        ),
      );

  Widget _fallbackBox(ColorScheme scheme) => ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: size, height: size,
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.music_note_rounded,
              color: scheme.onSurfaceVariant, size: size * 0.5),
        ),
      );
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String? sub;
  const _StatCard(
      {required this.icon, required this.value, required this.label, this.sub});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Icon(icon, color: scheme.onPrimaryContainer, size: 36),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimaryContainer)),
            Text(label,
                style: text.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
            if (sub != null)
              Text(sub!,
                  style: text.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer
                          .withValues(alpha: 0.65))),
          ]),
        ]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, color: scheme.primary, size: 20),
      const SizedBox(width: 8),
      Text(title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

class _PeriodBadge extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PeriodBadge({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    )),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded,
                size: 14, color: scheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final String  name;
  final String  sub;
  final String  imageUrl;
  final Future<String>? imageFuture;
  final String  rank;
  final String? plays;

  const _ItemTile({
    required this.name,
    required this.sub,
    required this.imageUrl,
    required this.rank,
    this.imageFuture,
    this.plays,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text(rank,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        _SmartImage(
          size: 48,
          borderRadius: 8,
          initialUrl: imageUrl,
          resolver: imageFuture != null
              ? () => imageFuture!
              : () => Future.value(''),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        if (plays != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(plays!,
                style: text.bodySmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ]),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────

String _extractImage(dynamic images) {
  if (images == null) return '';
  final list = images is List ? images : [];
  if (list.isEmpty) return '';
  try {
    final large = list.lastWhere(
      (i) => i is Map && i['size'] == 'extralarge',
      orElse: () => list.last,
    );
    return (large is Map ? large['#text'] ?? '' : '').toString();
  } catch (_) { return ''; }
}

String _formatNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

String _formatDate(String raw) {
  if (raw.isEmpty) return '';
  try {
    final parts = raw.split(', ');
    if (parts.length == 2) return '${parts[0]} · ${parts[1]}';
  } catch (_) {}
  return raw;
}

/// Gère les deux formats Last.fm pour `registered` :
/// `#text` = date lisible ou timestamp Unix.
String _parseRegistered(dynamic raw) {
  if (raw == null) return '';
  if (raw is Map) {
    final txt = raw['#text'];
    if (txt == null) return '';
    final ts = int.tryParse(txt.toString());
    if (ts != null && ts > 0) {
      final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      const months = ['', 'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
          'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];
      return '${d.day} ${months[d.month]} ${d.year}';
    }
    return txt.toString();
  }
  return raw.toString();
}

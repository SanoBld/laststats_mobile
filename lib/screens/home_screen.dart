import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/lastfm_service.dart';
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

// ═══════════════════════════════════════════════════════
// HOME SCREEN — navigation principale
// ═══════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  final String username;
  final String apiKey;
  const HomeScreen({super.key, required this.username, required this.apiKey});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _idx = 0;
  late final LastFmService _service;

  @override
  void initState() {
    super.initState();
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

  @override
  void initState() {
    super.initState();
    _load();
    // Rafraîchit le "En cours" toutes les 30 secondes
    _npTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshNowPlaying());
  }

  @override
  void dispose() {
    _npTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.service.getUserInfo(),
        widget.service.getTopArtists(period: 'overall', limit: 5),
        widget.service.getTopTracks(period: '7day', limit: 5),
        widget.service.getNowPlaying(),
      ]);
      setState(() {
        _userInfo   = results[0] as Map<String, dynamic>?;
        _topArtists = results[1] as List<dynamic>;
        _topTracks  = results[2] as List<dynamic>;
        _nowPlaying = results[3] as Map<String, dynamic>?;
        _loading    = false;
      });
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
      if (mounted) setState(() => _nowPlaying = np);
    } catch (_) {}
  }

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
    final registered = regRaw is Map
        ? (regRaw['#text'] ?? '').toString()
        : regRaw?.toString() ?? '';
    final avatarUrl  = _extractImage(info['image']);

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          // ── AppBar profil ──
          SliverAppBar(
            expandedHeight: 190,
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: scheme.primary.withValues(alpha: 0.2),
                          backgroundImage: avatarUrl.isNotEmpty
                              ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty
                              ? Icon(Icons.person_rounded, size: 40,
                                  color: scheme.onPrimaryContainer)
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                              if (realName.isNotEmpty)
                                Text(realName,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: scheme.onSurfaceVariant)),
                              if (country.isNotEmpty && country != 'None')
                                Text(country,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ),
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

                // ── En cours de lecture ──
                if (_nowPlaying != null) ...[
                  _NowPlayingCard(track: _nowPlaying!),
                  const SizedBox(height: 16),
                ],

                // ── Stat scrobbles ──
                _StatCard(
                  icon: Icons.headphones_rounded,
                  value: _formatNumber(int.tryParse(scrobbles) ?? 0),
                  label: 'Scrobbles au total',
                  sub: registered.isNotEmpty ? 'Membre depuis $registered' : null,
                ),
                const SizedBox(height: 20),

                // ── Top Artistes (all time) ──
                _SectionHeader(title: 'Top Artistes', icon: Icons.mic_rounded),
                const SizedBox(height: 8),
                ..._topArtists.asMap().entries.map((e) => _ItemTile(
                  name:     (e.value['name'] ?? '').toString(),
                  sub:      '${_formatNumber(int.tryParse((e.value['playcount'] ?? '0').toString()) ?? 0)} écoutes',
                  imageUrl: _extractImage(e.value['image']),
                  rank:     '${e.key + 1}',
                )),
                const SizedBox(height: 20),

                // ── Top Titres (semaine) ──
                _SectionHeader(title: 'Top Titres — Semaine', icon: Icons.music_note_rounded),
                const SizedBox(height: 8),
                ..._topTracks.asMap().entries.map((e) => _ItemTile(
                  name:     (e.value['name'] ?? '').toString(),
                  sub:      (e.value['artist']?['name'] ?? '').toString(),
                  imageUrl: _extractImage(e.value['image']),
                  rank:     '${e.key + 1}',
                  plays:    _formatNumber(int.tryParse((e.value['playcount'] ?? '0').toString()) ?? 0),
                )),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
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
    final scheme  = Theme.of(context).colorScheme;
    final text    = Theme.of(context).textTheme;
    final title   = (track['name']             ?? '').toString();
    final artist  = (track['artist']?['#text'] ?? '').toString();
    final imgUrl  = _extractImage(track['image']);

    return Card(
      elevation: 0,
      color: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imgUrl.isNotEmpty ? imgUrl : _kDefaultImg,
                width: 56, height: 56, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 56, height: 56,
                  color: scheme.surfaceContainerHighest,
                  child: Icon(Icons.music_note_rounded,
                      color: scheme.onSurfaceVariant),
                ),
              ),
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
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer.withValues(alpha: 0.75))),
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
// CLASSEMENTS (Artists + Albums + Tracks fusionnés)
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
            // ── Titre ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Classements',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            ),

            // ── Période ──
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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

            // ── Tabs ──
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Artistes'),
                Tab(text: 'Albums'),
                Tab(text: 'Titres'),
              ],
            ),

            // ── Contenu ──
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _TopListBody(service: widget.service, type: 'artists', period: _period),
                  _TopListBody(service: widget.service, type: 'albums',  period: _period),
                  _TopListBody(service: widget.service, type: 'tracks',  period: _period),
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
  const _TopListBody({required this.service, required this.type, required this.period});

  @override
  State<_TopListBody> createState() => _TopListBodyState();
}

class _TopListBodyState extends State<_TopListBody>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _items      = [];
  bool _loading             = true;
  bool _loadingMore         = false;
  bool _exhausted           = false;
  String? _error;
  int _page                 = 1;

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
      setState(() { _loading = true; _error = null; _page = 1; _exhausted = false; _items = []; });
    } else {
      if (_loadingMore || _exhausted) return;
      setState(() => _loadingMore = true);
    }

    try {
      List<dynamic> fresh;
      switch (widget.type) {
        case 'artists':
          fresh = await widget.service.getTopArtists(period: widget.period, limit: 50, page: _page);
          break;
        case 'albums':
          fresh = await widget.service.getTopAlbums(period: widget.period, limit: 50, page: _page);
          break;
        default:
          fresh = await widget.service.getTopTracks(period: widget.period, limit: 50, page: _page);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return Center(child: Text('Aucun résultat',
          style: TextStyle(color: scheme.onSurfaceVariant)));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (!_exhausted && !_loadingMore &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
          _page++;
          _load();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item  = _items[i];
          final name  = (item['name'] ?? '').toString();
          final plays = _formatNumber(
              int.tryParse((item['playcount'] ?? '0').toString()) ?? 0);
          final sub   = widget.type != 'artists'
              ? (item['artist']?['name'] ?? '').toString()
              : '$plays écoutes';
          return _ItemTile(
            name:     name,
            sub:      sub,
            imageUrl: _extractImage(item['image']),
            rank:     '${i + 1}',
            plays:    widget.type != 'artists' ? plays : null,
          );
        },
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
  bool _loading  = true;
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

  /// Calcule le score Mainstream vs Pépites
  Future<void> _computeGems() async {
    if (_topArtists.isEmpty) return;
    setState(() { _gemsLoading = true; _gems = []; });
    final artists = _topArtists.take(15).toList();
    final futures = artists.map((a) =>
        widget.service.getArtistListeners((a['name'] ?? '').toString()));
    final listeners = await Future.wait(futures);

    final entries = <_GemEntry>[];
    for (var i = 0; i < artists.length; i++) {
      final count = listeners[i] ?? 0;
      entries.add(_GemEntry(
        name:      (artists[i]['name'] ?? '').toString(),
        plays:     int.tryParse((artists[i]['playcount'] ?? '0').toString()) ?? 0,
        listeners: count,
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
          // ── Titre ──
          Text('Graphiques',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),

          // ── Scrobbles par mois ──
          _SectionHeader(title: 'Scrobbles — 12 derniers mois',
              icon: Icons.calendar_month_rounded),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Column(children: [
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: monthly.entries.map((e) {
                      final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
                      final month = e.key.substring(5); // MM
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
                                    color: scheme.onSurfaceVariant,
                                  )),
                              const SizedBox(height: 2),
                              Flexible(
                                fit: FlexFit.loose,
                                child: FractionallySizedBox(
                                  heightFactor: ratio.clamp(0.02, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(
                                          alpha: 0.5 + ratio * 0.5),
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(month,
                                style: text.labelSmall?.copyWith(fontSize: 9)),
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

          // ── Top artistes — distribution ──
          _SectionHeader(title: 'Top artistes — distribution',
              icon: Icons.mic_rounded),
          const SizedBox(height: 12),
          if (_topArtists.isNotEmpty) ...[
            () {
              final maxPlays = _topArtists
                  .map((a) => int.tryParse((a['playcount'] ?? '0').toString()) ?? 0)
                  .fold(0, (a, b) => a > b ? a : b);
              return Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                ClipRRect(
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
                              ],
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

          // ── Mainstream vs Pépites ──
          _SectionHeader(title: 'Mainstream vs Pépites',
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
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ))
          else ...[
            ..._gems.asMap().entries.map((e) {
              final gem = e.value;
              final isGem = gem.listeners < 500000;
              return Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: Text(
                    isGem ? '💎' : '🎤',
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(gem.name,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${_formatNumber(gem.listeners)} auditeurs mondiaux',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  trailing: Text(
                    isGem ? 'Pépite' : 'Mainstream',
                    style: text.labelSmall?.copyWith(
                      color: isGem ? scheme.tertiary : scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _computeGems,
                child: const Text('Recalculer'),
              ),
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
// HISTORIQUE
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() { _loading = true; _error = null; _page = 1; _exhausted = false; _tracks = []; });
    } else {
      if (_loadingMore || _exhausted) return;
      setState(() => _loadingMore = true);
    }

    try {
      final data   = await widget.service.getRecentTracks(limit: 50, page: _page);
      final raw    = data['track'];
      final fresh  = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);
      final attr   = data['@attr'] as Map?;
      final totalP = int.tryParse(attr?['totalPages']?.toString() ?? '1') ?? 1;

      // Extrait le "now playing" s'il est en tête
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
        if (reset) { _tracks = list; } else { _tracks.addAll(list); }
        _nowPlaying  = np;
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Historique',
                      style: text.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => _load(reset: true),
                    tooltip: 'Rafraîchir',
                  ),
                ],
              ),
            ),

            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: _ErrorView(
                  message: _error!, onRetry: () => _load(reset: true)))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (!_exhausted && !_loadingMore &&
                          n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                        _page++;
                        _load();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      itemCount: (_nowPlaying != null ? 1 : 0) +
                          _tracks.length +
                          (_loadingMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        // Now playing banner
                        if (_nowPlaying != null && i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: _NowPlayingCard(track: _nowPlaying!),
                          );
                        }
                        final idx = _nowPlaying != null ? i - 1 : i;
                        if (idx == _tracks.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final t       = _tracks[idx] as Map;
                        final title   = (t['name']             ?? '').toString();
                        final artist  = (t['artist']?['#text'] ?? '').toString();
                        final album   = (t['album']?['#text']  ?? '').toString();
                        final imgUrl  = _extractImage(t['image']);
                        final dateRaw = t['date']?['#text'] ?? '';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 2),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              imgUrl.isNotEmpty ? imgUrl : _kDefaultImg,
                              width: 46, height: 46, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 46, height: 46,
                                color: scheme.surfaceContainerHighest,
                                child: Icon(Icons.music_note_rounded,
                                    color: scheme.onSurfaceVariant, size: 20),
                              ),
                            ),
                          ),
                          title: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            album.isNotEmpty ? '$artist · $album' : artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          trailing: Text(
                            _formatDate(dateRaw),
                            style: text.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
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
}

// ═══════════════════════════════════════════════════════
// PARAMÈTRES
// ═══════════════════════════════════════════════════════
class _SettingsPage extends StatelessWidget {
  final String username;
  const _SettingsPage({required this.username});

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

          // ── Compte ──
          _SettingsSection(label: 'Compte', children: [
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: const Text('Profil connecté'),
              subtitle: Text('@$username'),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: scheme.error),
              title: Text('Se déconnecter',
                  style: TextStyle(color: scheme.error)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Se déconnecter ?'),
                    content: const Text(
                        'Tes identifiants seront supprimés de l\'appareil.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Déconnecter'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('ls_username');
                  await prefs.remove('ls_apikey');
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const SetupScreen()),
                      (_) => false,
                    );
                  }
                }
              },
            ),
          ]),

          const SizedBox(height: 16),

          // ── À propos ──
          _SettingsSection(label: 'À propos', children: [
            ListTile(
              leading: const Icon(Icons.web_rounded),
              title: const Text('Version web complète'),
              subtitle: const Text('sanobld.github.io/LastStats'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16),
              onTap: () {
                // URL launch : ajouter url_launcher si besoin
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('LastStats Mobile'),
              subtitle: Text('v1.1.0 · Propulsé par l\'API Last.fm'),
            ),
          ]),

          const SizedBox(height: 12),
          Center(
            child: Text('LastStats Mobile v1.1.0',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

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
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            )),
        ),
        Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// WIDGETS RÉUTILISABLES
// ═══════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String? sub;
  const _StatCard({required this.icon, required this.value,
      required this.label, this.sub});

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
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.65))),
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
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

class _ItemTile extends StatelessWidget {
  final String name;
  final String sub;
  final String imageUrl;
  final String rank;
  final String? plays;
  const _ItemTile({required this.name, required this.sub,
      required this.imageUrl, required this.rank, this.plays});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final url    = imageUrl.isNotEmpty &&
            !imageUrl.contains('2a96cbd8b46e442fc41c2b86b821562f')
        ? imageUrl
        : _kDefaultImg;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(url,
            width: 48, height: 48, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 48, height: 48,
              color: scheme.surfaceContainerHighest,
              child: Icon(Icons.music_note_rounded,
                  color: scheme.onSurfaceVariant, size: 24),
            )),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
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
        )),
        if (plays != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(plays!,
              style: text.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600)),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
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
  } catch (_) {
    return '';
  }
}

String _formatNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

String _formatDate(String raw) {
  // raw: "12 May 2025, 14:23"  → "12 mai · 14:23"
  if (raw.isEmpty) return '';
  try {
    final parts = raw.split(', ');
    if (parts.length == 2) return '${parts[0]} · ${parts[1]}';
  } catch (_) {}
  return raw;
}

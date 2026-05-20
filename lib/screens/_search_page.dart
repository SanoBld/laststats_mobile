// ignore_for_file: unused_import
part of 'home_screen.dart';

// ── Tab constants ────────────────────────────────────────────────────────────
const int _kSearchProfiles = 0;
const int _kSearchArtists  = 1;
const int _kSearchAlbums   = 2;
const int _kSearchTracks   = 3;

// ── Search page ──────────────────────────────────────────────────────────────

class _SearchPage extends StatefulWidget {
  final LastFmService service;
  const _SearchPage({required this.service});

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();

  int           _tab       = _kSearchArtists;
  List<dynamic> _results   = [];
  bool          _searching = false;
  String?       _error;
  Timer?        _debounce;

  // Favourite profiles stored locally
  Set<String> _favProfiles = {};

  static const _kTabs = [
    (_kSearchProfiles, 'Profils',  Icons.person_rounded),
    (_kSearchArtists,  'Artistes', Icons.mic_rounded),
    (_kSearchAlbums,   'Albums',   Icons.album_rounded),
    (_kSearchTracks,   'Titres',   Icons.music_note_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _favProfiles = Set<String>.from(p.getStringList('ls_fav_profiles') ?? []);
    });
  }

  Future<void> _toggleFavProfile(String username, bool nowFav) async {
    final updated = Set<String>.from(_favProfiles);
    if (nowFav) updated.add(username); else updated.remove(username);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('ls_fav_profiles', updated.toList());
    if (!mounted) return;
    setState(() => _favProfiles = updated);
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _results = []; _error = null; _searching = false; });
      return;
    }
    setState(() { _searching = true; _error = null; });
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) return;
    setState(() { _searching = true; _error = null; });
    try {
      List<dynamic> res;
      switch (_tab) {
        case _kSearchProfiles: res = await widget.service.searchUsers(q,   limit: 15); break;
        case _kSearchArtists:  res = await widget.service.searchArtists(q, limit: 15); break;
        case _kSearchAlbums:   res = await widget.service.searchAlbums(q,  limit: 15); break;
        default:               res = await widget.service.searchTracks(q,  limit: 15);
      }
      if (mounted) setState(() { _results = res; _searching = false; });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _searching = false;
      });
    }
  }

  void _switchTab(int tab) {
    if (_tab == tab) return;
    setState(() { _tab = tab; _results = []; _error = null; });
    final q = _ctrl.text.trim();
    if (q.isNotEmpty) _search(q);
  }

  void _openMusicDetail(BuildContext ctx, Map<String, dynamic> item, String type) =>
      showDetailSheet(ctx, item, type, widget.service);

  void _openProfile(BuildContext ctx, String username) {
    showModalBottomSheet(
      context:            ctx,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      useSafeArea:        true,
      builder: (_) => _FullProfileSheet(username: username, service: widget.service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'Recherche',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),

            // ── Search bar ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller:      _ctrl,
                focusNode:       _focusNode,
                onChanged:       _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) { if (v.trim().isNotEmpty) _search(v.trim()); },
                decoration: InputDecoration(
                  hintText:  'Artiste, album, titre ou profil…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() { _results = []; _error = null; _searching = false; });
                          },
                        )
                      : null,
                  filled:    true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Tab chips ───────────────────────────────────────
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _kTabs.map((t) {
                  final sel = t.$1 == _tab;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: Icon(t.$3, size: 14,
                          color: sel
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant),
                      label:  Text(t.$2),
                      selected: sel,
                      showCheckmark: false,
                      onSelected: (_) => _switchTab(t.$1),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),

            // ── Results ─────────────────────────────────────────
            Expanded(
              child: _buildResults(context, scheme, text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, ColorScheme scheme, TextTheme text) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _ErrorView(
          message: _error!,
          onRetry: () => _search(_ctrl.text.trim()));
    }

    if (_ctrl.text.trim().isEmpty) {
      return _SearchEmptyState(tab: _tab);
    }

    if (_results.isEmpty) {
      return Center(
        child: Text('Aucun résultat',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      );
    }

    if (_tab == _kSearchProfiles) {
      // Horizontal card grid for profiles
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: (_results.length / 2).ceil(),
        itemBuilder: (ctx, row) {
          final left  = _results[row * 2] as Map<String, dynamic>;
          final hasRight = row * 2 + 1 < _results.length;
          final right = hasRight ? _results[row * 2 + 1] as Map<String, dynamic> : null;
          return Row(children: [
            Expanded(child: _buildUserCard(ctx, left)),
            const SizedBox(width: 10),
            Expanded(child: right != null
                ? _buildUserCard(ctx, right)
                : const SizedBox()),
          ]);
        },
      );
    }

    // Music results — vertical list
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _results.length,
      itemBuilder: (ctx, i) {
        final m      = _results[i] as Map<String, dynamic>;
        final name   = (m['name']   ?? '').toString();
        final artist = (m['artist'] ?? '').toString();
        final imgRaw = _extractImage(m['image']);

        Future<String> imgF;
        String sub;
        String type;
        // Search API returns artist as a plain String; the detail sheet expects
        // {'name': '...'} — normalize here so taps on albums/tracks never crash.
        final normalized = Map<String, dynamic>.from(m);
        if (m['artist'] is String) {
          normalized['artist'] = {'name': artist};
        }

        switch (_tab) {
          case _kSearchArtists:
            type = 'artists';
            sub  = '${_fmt(int.tryParse((m['listeners'] ?? '0').toString()) ?? 0)} auditeurs';
            imgF = ImageService.resolveArtist(name,
                lastfmUrl: imgRaw.isNotEmpty ? imgRaw : null);
          case _kSearchAlbums:
            type = 'albums';
            sub  = artist;
            imgF = ImageService.resolveAlbum(name, artist,
                lastfmUrl: imgRaw.isNotEmpty ? imgRaw : null);
          default:
            type = 'tracks';
            sub  = artist;
            imgF = ImageService.resolveTrack(name, artist,
                lastfmUrl: imgRaw.isNotEmpty ? imgRaw : null);
        }

        return InkWell(
          onTap: () => _openMusicDetail(context, normalized, type),
          borderRadius: BorderRadius.circular(8),
          child: _ItemTile(
            name: name, sub: sub,
            imageUrl: imgRaw, imageFuture: imgF,
            rank: '${i + 1}',
          ),
        );
      },
    );
  }

  Widget _buildUserCard(BuildContext ctx, Map<String, dynamic> u) {
    final uname = (u['name'] ?? '').toString();
    final isFav = _favProfiles.contains(uname);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _SearchUserCard(
        user:        u,
        isFav:       isFav,
        onTap:       () => _openProfile(ctx, uname),
        onToggleFav: () => _toggleFavProfile(uname, !isFav),
      ),
    );
  }
}

// ── Empty state hint ─────────────────────────────────────────────────────────

class _SearchEmptyState extends StatelessWidget {
  final int tab;
  const _SearchEmptyState({required this.tab});

  static const _hints = [
    ('Profils', Icons.person_rounded,      'Recherche un utilisateur Last.fm'),
    ('Artistes', Icons.mic_rounded,         'Recherche un artiste'),
    ('Albums',   Icons.album_rounded,       'Recherche un album'),
    ('Titres',   Icons.music_note_rounded,  'Recherche une chanson'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final t = _hints[tab.clamp(0, 3)];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(t.$2, size: 56, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(t.$3,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Tape dans la barre ci-dessus',
              style: text.bodySmall?.copyWith(color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

// ── Search user card ─────────────────────────────────────────────────────────

class _SearchUserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool         isFav;
  final VoidCallback onTap;
  final VoidCallback onToggleFav;

  static const _ph = '2a96cbd8b46e442fc41c2b86b821562f';

  const _SearchUserCard({
    required this.user,
    required this.isFav,
    required this.onTap,
    required this.onToggleFav,
  });

  bool get _hasAvatar {
    final url = _extractImage(user['image']);
    return url.isNotEmpty && !url.contains(_ph);
  }
  String get _avatarUrl => _extractImage(user['image']);

  @override
  Widget build(BuildContext context) {
    final scheme   = Theme.of(context).colorScheme;
    final text     = Theme.of(context).textTheme;
    final username = (user['name']       ?? '').toString();
    final plays    = (user['playcount']  ?? '').toString();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 56, height: 56,
              child: Stack(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primary.withValues(alpha: 0.2),
                  backgroundImage: _hasAvatar ? NetworkImage(_avatarUrl) : null,
                  child: _hasAvatar ? null : Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: text.titleMedium?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.w800),
                  ),
                ),
                Positioned(
                  left: 0, top: 0,
                  child: GestureDetector(
                    onTap: onToggleFav,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 16,
                      color: isFav ? Colors.amber.shade600
                          : scheme.onSurfaceVariant.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Text(username,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            if (plays.isNotEmpty && plays != '0') ...[
              const SizedBox(height: 2),
              Text(
                '${_fmt(int.tryParse(plays) ?? 0)} écoutes',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Full profile sheet ───────────────────────────────────────────────────────

class _FullProfileSheet extends StatefulWidget {
  final String        username;
  final LastFmService service;
  const _FullProfileSheet({required this.username, required this.service});

  @override
  State<_FullProfileSheet> createState() => _FullProfileSheetState();
}

class _FullProfileSheetState extends State<_FullProfileSheet> {
  Map<String, dynamic>? _info;
  List<dynamic>         _topArtists = [];
  List<dynamic>         _recent     = [];
  bool                  _loading    = true;

  static const _ph = '2a96cbd8b46e442fc41c2b86b821562f';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        widget.service.getUserInfo(user: widget.username),
        widget.service.getTopArtists(user: widget.username, period: 'overall', limit: 5),
        widget.service.getRecentTracks(user: widget.username, limit: 10),
      ]);
      final recentRaw  = (res[2] as Map<String, dynamic>)['track'];
      final recentList = recentRaw is List ? recentRaw
          : (recentRaw != null ? [recentRaw] : <dynamic>[]);
      if (mounted) setState(() {
        _info       = res[0] as Map<String, dynamic>?;
        _topArtists = res[1] as List<dynamic>;
        _recent     = recentList;
        _loading    = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int    _total() => int.tryParse((_info?['playcount'] ?? '0').toString()) ?? 0;
  int    _days() {
    final raw = _info?['registered'];
    if (raw == null) return 0;
    int ts = 0;
    if (raw is Map) ts = int.tryParse((raw['#text'] ?? raw['unixtime'] ?? '0').toString()) ?? 0;
    else ts = int.tryParse(raw.toString()) ?? 0;
    if (ts <= 0) return 0;
    return ((DateTime.now().millisecondsSinceEpoch / 1000 - ts) / 86400).floor();
  }
  double _avg() { final d = _days(); return d > 0 ? _total() / d : 0; }
  bool _hasAvatar(String url) => url.isNotEmpty && !url.contains(_ph);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize:     0.4,
      maxChildSize:     1.0,
      expand: false,
      builder: (ctx, ctrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: scheme.surface,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(controller: ctrl, children: [

                  // Drag handle
                  Center(child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2)),
                  )),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: _buildHeader(ctx, scheme, text),
                  ),

                  // Stats
                  if (_info != null) _buildStatsRow(scheme, text),

                  const Divider(indent: 16, endIndent: 16, height: 20),

                  // Top artists
                  if (_topArtists.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text('Top Artistes',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    ..._topArtists.asMap().entries.map((e) {
                      final a      = e.value as Map<String, dynamic>;
                      final aName  = (a['name'] ?? '').toString();
                      final plays  = _fmt(int.tryParse((a['playcount'] ?? '0').toString()) ?? 0);
                      final imgRaw = _extractImage(a['image']);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: InkWell(
                          onTap: () => showDetailSheet(ctx,
                              Map<String, dynamic>.from(a), 'artists', widget.service),
                          borderRadius: BorderRadius.circular(8),
                          child: _ItemTile(
                            name: aName, sub: '$plays écoutes',
                            imageUrl: imgRaw, rank: '${e.key + 1}',
                            imageFuture: ImageService.resolveArtist(aName,
                                lastfmUrl: imgRaw.isNotEmpty ? imgRaw : null),
                          ),
                        ),
                      );
                    }),
                    const Divider(indent: 16, endIndent: 16, height: 20),
                  ],

                  // Recent tracks
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Écoutes récentes',
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (_recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text('Aucune écoute récente',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                    )
                  else
                    ..._recent.map((t) {
                      final tMap    = t as Map<String, dynamic>;
                      final isNp    = tMap['@attr']?['nowplaying'] == 'true';
                      final tName   = (tMap['name'] ?? '').toString();
                      final tArtist = (tMap['artist']?['#text'] ?? '').toString();
                      final tDate   = (tMap['date']?['#text'] ?? '').toString();
                      final rawUrl  = _extractImage(tMap['image']);
                      final hasImg  = rawUrl.isNotEmpty && !rawUrl.contains(_ph);

                      return ListTile(
                        leading: Stack(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: hasImg
                                ? Image.network(rawUrl, width: 40, height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                        width: 40, height: 40,
                                        color: scheme.surfaceContainerHighest,
                                        child: Icon(Icons.music_note_rounded,
                                            color: scheme.onSurfaceVariant)))
                                : Container(width: 40, height: 40,
                                    color: scheme.surfaceContainerHighest,
                                    child: Icon(Icons.music_note_rounded,
                                        color: scheme.onSurfaceVariant)),
                          ),
                          if (isNp) Positioned(right: 0, bottom: 0,
                            child: Container(width: 8, height: 8,
                                decoration: const BoxDecoration(
                                    color: Colors.green, shape: BoxShape.circle))),
                        ]),
                        title: Text(tName, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text(tArtist, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        trailing: isNp
                            ? Text('EN COURS', style: text.labelSmall?.copyWith(
                                color: Colors.green, fontWeight: FontWeight.w700))
                            : Text(_fmtDate(tDate),
                                style: text.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant, fontSize: 9)),
                        dense: true,
                      );
                    }),

                  const SizedBox(height: 32),
                ]),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext ctx, ColorScheme scheme, TextTheme text) {
    final info      = _info ?? {};
    final name      = (info['name']     ?? widget.username).toString();
    final realName  = (info['realname'] ?? '').toString();
    final country   = (info['country']  ?? '').toString();
    final avatarUrl = _extractImage(info['image']);

    String regStr = '';
    final raw = info['registered'];
    if (raw != null) {
      int ts = 0;
      if (raw is Map) ts = int.tryParse((raw['#text'] ?? raw['unixtime'] ?? '0').toString()) ?? 0;
      else ts = int.tryParse(raw.toString()) ?? 0;
      if (ts > 0) {
        final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        regStr = '${d.day} ${_kMonths[d.month]} ${d.year}';
      }
    }

    return Row(children: [
      CircleAvatar(
        radius: 34,
        backgroundColor: scheme.primaryContainer,
        backgroundImage: _hasAvatar(avatarUrl) ? NetworkImage(avatarUrl) : null,
        child: _hasAvatar(avatarUrl) ? null : Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: text.titleLarge?.copyWith(
              color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (realName.isNotEmpty)
          Text(realName, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Wrap(spacing: 10, children: [
          if (country.isNotEmpty && country != 'None')
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.location_on_outlined, size: 12, color: scheme.onSurfaceVariant),
              const SizedBox(width: 2),
              Text(country, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          if (regStr.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.calendar_today_outlined, size: 11, color: scheme.onSurfaceVariant),
              const SizedBox(width: 2),
              Text('Depuis $regStr',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
        ]),
      ])),
    ]);
  }

  Widget _buildStatsRow(ColorScheme scheme, TextTheme text) {
    final total = _total();
    final avg   = _avg();
    final days  = _days();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _MiniMetric('🎯', _fmtFull(total),        'scrobbles', scheme.onPrimaryContainer),
        Container(width: 1, height: 32,
            color: scheme.onPrimaryContainer.withValues(alpha: 0.15)),
        _MiniMetric('⚡', '~${_fmt(avg.round())}', 'par jour',  scheme.onPrimaryContainer),
        Container(width: 1, height: 32,
            color: scheme.onPrimaryContainer.withValues(alpha: 0.15)),
        _MiniMetric('🗓️', '$days j',               'd\'activité', scheme.onPrimaryContainer),
      ]),
    );
  }
}
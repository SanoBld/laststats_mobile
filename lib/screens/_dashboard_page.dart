// ignore_for_file: unused_import
part of 'home_screen.dart';


// ── Data model for a single friend entry ────────────────────────────────────

class _FriendData {
  final String username;
  final String realName;
  final String avatarUrl;
  final bool   isOnline;            // true  → currently scrobbling
  final String nowPlayingTrack;
  final String nowPlayingArtist;
  final String lastTrack;           // most recent track when offline
  final String lastArtist;

  const _FriendData({
    required this.username,
    required this.realName,
    required this.avatarUrl,
    required this.isOnline,
    this.nowPlayingTrack  = '',
    this.nowPlayingArtist = '',
    this.lastTrack        = '',
    this.lastArtist       = '',
  });
}


// Dashboard

class _DashboardPage extends StatefulWidget {
  final LastFmService service;
  final String username;
  const _DashboardPage({required this.service, required this.username});

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  Map<String, dynamic>? _userInfo;
  List<dynamic> _topArtists   = [];
  List<dynamic> _topAlbums    = [];
  List<dynamic> _topTracks    = [];
  List<dynamic> _recentTracks = [];
  Map<String, dynamic>? _nowPlaying;

  bool _loading = true;
  String? _error;
  Timer? _npTimer;

  String _headerSource          = 'nowplaying';
  String _headerImageUrl        = '';
  double _headerBlur            = 0.0;
  String _headerAnimation       = 'fade';
  String _headerCustomUrl       = '';
  String _headerFallbackUrl     = '';
  bool   _headerFallbackEnabled = false;
  String _headerPeriod          = 'overall';
  bool   _showNowPlay           = true;
  bool   _showStats             = true;
  bool   _showArtists           = true;
  bool   _showTracks            = true;

  // ── Friends state ───────────────────────────────────────
  bool             _showFriends   = true;
  List<_FriendData> _friends      = [];
  Set<String>      _favFriends    = {};
  Set<String>      _favProfiles   = {};  // profiles starred in search
  bool             _friendsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs().then((_) => _load());
    _npTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshNP());
  }

  @override
  void dispose() { _npTimer?.cancel(); super.dispose(); }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _headerSource          = p.getString('ls_header_source')         ?? 'nowplaying';
      _headerBlur            = p.getDouble('ls_header_blur')            ?? 0.0;
      _headerAnimation       = p.getString('ls_header_animation')      ?? 'fade';
      _headerCustomUrl       = p.getString('ls_header_custom_url')     ?? '';
      _headerFallbackUrl     = p.getString('ls_header_fallback_url')   ?? '';
      _headerFallbackEnabled = p.getBool('ls_header_fallback_enabled') ?? false;
      _headerPeriod          = p.getString('ls_header_period')         ?? 'overall';
      _showNowPlay           = p.getBool('ls_show_nowplay')            ?? true;
      _showStats             = p.getBool('ls_show_stats')              ?? true;
      _showArtists           = p.getBool('ls_show_artists')            ?? true;
      _showTracks            = p.getBool('ls_show_tracks')             ?? true;
      // Friends prefs
      _showFriends           = p.getBool('ls_show_friends')            ?? true;
      _favFriends            = Set<String>.from(p.getStringList('ls_fav_friends') ?? []);
      _favProfiles           = Set<String>.from(p.getStringList('ls_fav_profiles') ?? []);
    });
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Future.wait([
        widget.service.getUserInfo(),
        widget.service.getTopArtists(period: 'overall', limit: 50),
        widget.service.getTopAlbums (period: 'overall', limit: 50),
        widget.service.getTopTracks (period: 'overall', limit: 50),
        widget.service.getRecentTracks(limit: 10),
        widget.service.getNowPlaying(),
      ]);
      final recentRaw = (res[4] as Map<String, dynamic>)['track'];
      final allRecent = recentRaw is List ? recentRaw
          : (recentRaw != null ? [recentRaw] : <dynamic>[]);
      Map<String, dynamic>? np;
      final recentF = <dynamic>[];
      for (final t in allRecent) {
        if ((t as Map?)?['@attr']?['nowplaying'] == 'true') { np = t as Map<String, dynamic>; }
        else { recentF.add(t); }
      }
      setState(() {
        _userInfo     = res[0] as Map<String, dynamic>?;
        _topArtists   = res[1] as List<dynamic>;
        _topAlbums    = res[2] as List<dynamic>;
        _topTracks    = res[3] as List<dynamic>;
        _recentTracks = recentF;
        _nowPlaying   = np ?? res[5] as Map<String, dynamic>?;
        _loading      = false;
      });
      if (_nowPlaying != null) _extractColor(_nowPlaying!);
      _resolveHeaderImage();
      // Load friends asynchronously — does not block the main page
      if (_showFriends) _loadFriends();
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _refreshNP() async {
    try {
      final np = await widget.service.getNowPlaying();
      if (mounted) {
        setState(() => _nowPlaying = np);
        if (np != null) _extractColor(np);
        _resolveHeaderImage();
      }
    } catch (_) {}
  }

  // ── Friends loader ───────────────────────────────────────
  Future<void> _loadFriends() async {
    if (!mounted) return;
    setState(() => _friendsLoading = true);
    try {
      final raw = await widget.service.getFriends(limit: 50, withRecentTrack: true);
      final friends = <_FriendData>[];

      for (final u in raw) {
        final uname      = (u['name'] ?? '').toString();
        final rawRecent  = u['recenttrack'];

        // Last.fm renvoie une List quand l'ami est en train d'écouter
        // (nowplaying + dernier scrobble), ou un Map seul sinon.
        Map? recentMap;
        if (rawRecent is List && rawRecent.isNotEmpty) {
          recentMap = rawRecent.firstWhere(
            (t) => t is Map && t['@attr']?['nowplaying'] == 'true',
            orElse: () => rawRecent.first,
          ) as Map?;
        } else if (rawRecent is Map) {
          recentMap = rawRecent;
        }

        final isOnline = recentMap != null &&
            (recentMap['@attr']?['nowplaying'] == 'true');

        String trackName  = '';
        String artistName = '';
        if (recentMap != null) {
          trackName  = (recentMap['name'] ?? '').toString();
          // artist field varies: '#text' in recenttrack, plain string otherwise
          final rawArtist = recentMap['artist'];
          if (rawArtist is Map) {
            artistName = (rawArtist['#text'] ?? rawArtist['name'] ?? '').toString();
          } else {
            artistName = rawArtist?.toString() ?? '';
          }
        }

        friends.add(_FriendData(
          username:         uname,
          realName:         (u['realname'] ?? '').toString(),
          avatarUrl:        _extractImage(u['image']),
          isOnline:         isOnline,
          nowPlayingTrack:  isOnline  ? trackName  : '',
          nowPlayingArtist: isOnline  ? artistName : '',
          lastTrack:        !isOnline ? trackName  : '',
          lastArtist:       !isOnline ? artistName : '',
        ));
      }

      // Merge favorite profiles from search (ls_fav_profiles) that aren't
      // already in the friends list — fetch their info and add them.
      final existingNames = friends.map((f) => f.username.toLowerCase()).toSet();
      for (final favUsername in _favProfiles) {
        if (existingNames.contains(favUsername.toLowerCase())) continue;
        try {
          final info = await widget.service.getUserInfo(user: favUsername);
          if (info == null) continue;
          final uname = (info['name'] ?? favUsername).toString();
          // Try to get most recent track for this user
          String lastTrack = '', lastArtist = '';
          try {
            final recent = await widget.service.getRecentTracks(limit: 1, user: uname);
            final tracks = recent['track'];
            final tList  = tracks is List ? tracks : (tracks != null ? [tracks] : []);
            if (tList.isNotEmpty) {
              final t = tList.first as Map;
              if (t['@attr']?['nowplaying'] != 'true') {
                lastTrack  = (t['name'] ?? '').toString();
                final ra   = t['artist'];
                lastArtist = ra is Map
                    ? (ra['#text'] ?? ra['name'] ?? '').toString()
                    : (ra?.toString() ?? '');
              }
            }
          } catch (_) {}
          friends.add(_FriendData(
            username:  uname,
            realName:  (info['realname'] ?? '').toString(),
            avatarUrl: _extractImage(info['image']),
            isOnline:  false,
            lastTrack:  lastTrack,
            lastArtist: lastArtist,
          ));
          existingNames.add(uname.toLowerCase());
        } catch (_) {}
      }

      // Sort priority score: online+fav (3) > online (2) > offline+fav (1) > offline (0)
      friends.sort((a, b) {
        final aFav   = _favFriends.contains(a.username) || _favProfiles.contains(a.username);
        final bFav   = _favFriends.contains(b.username) || _favProfiles.contains(b.username);
        final aScore = (a.isOnline ? 2 : 0) + (aFav ? 1 : 0);
        final bScore = (b.isOnline ? 2 : 0) + (bFav ? 1 : 0);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      });

      if (mounted) setState(() { _friends = friends; _friendsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _friendsLoading = false);
    }
  }

  // ── Toggle a friend's favourite status ──────────────────
  Future<void> _toggleFav(String username, bool nowFav) async {
    final updatedFriends  = Set<String>.from(_favFriends);
    final updatedProfiles = Set<String>.from(_favProfiles);
    if (nowFav) {
      updatedFriends.add(username);
    } else {
      updatedFriends.remove(username);
      updatedProfiles.remove(username);
    }
    final p = await SharedPreferences.getInstance();
    await p.setStringList('ls_fav_friends',  updatedFriends.toList());
    await p.setStringList('ls_fav_profiles', updatedProfiles.toList());
    if (!mounted) return;
    setState(() {
      _favFriends  = updatedFriends;
      _favProfiles = updatedProfiles;
      _friends.sort((a, b) {
        final aFav   = updatedFriends.contains(a.username) || updatedProfiles.contains(a.username);
        final bFav   = updatedFriends.contains(b.username) || updatedProfiles.contains(b.username);
        final aScore = (a.isOnline ? 2 : 0) + (aFav ? 1 : 0);
        final bScore = (b.isOnline ? 2 : 0) + (bFav ? 1 : 0);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      });
    });
  }

  Future<void> _resolveHeaderImage() async {
    String url = '';
    switch (_headerSource) {
      case 'custom':
        url = _headerCustomUrl;
      case 'nowplaying':
        if (_nowPlaying != null) {
          final raw = _extractImage(_nowPlaying!['image']);
          url = await ImageService.resolveTrack(
            (_nowPlaying!['name'] ?? '').toString(),
            (_nowPlaying!['artist']?['#text'] ?? '').toString(),
            lastfmUrl: raw,
          );
        }
        if (url.isEmpty && _headerFallbackEnabled && _headerFallbackUrl.isNotEmpty) {
          url = _headerFallbackUrl;
        }
      case 'top_track':
        final tracks = _headerPeriod == 'overall'
            ? _topTracks
            : await widget.service.getTopTracks(period: _headerPeriod, limit: 1);
        if (tracks.isNotEmpty) {
          final t = tracks[0] as Map;
          url = await ImageService.resolveTrack(
            (t['name'] ?? '').toString(),
            (t['artist']?['name'] ?? '').toString(),
            lastfmUrl: _extractImage(t['image']),
          );
        }
      case 'top_album':
        final albums = _headerPeriod == 'overall'
            ? _topAlbums
            : await widget.service.getTopAlbums(period: _headerPeriod, limit: 1);
        if (albums.isNotEmpty) {
          final a = albums[0] as Map;
          url = await ImageService.resolveAlbum(
            (a['name'] ?? '').toString(),
            (a['artist']?['name'] ?? '').toString(),
            lastfmUrl: _extractImage(a['image']),
          );
        }
      case 'top_artist':
        final artists = _headerPeriod == 'overall'
            ? _topArtists
            : await widget.service.getTopArtists(period: _headerPeriod, limit: 1);
        if (artists.isNotEmpty) {
          final a = artists[0] as Map;
          url = await ImageService.resolveArtist(
            (a['name'] ?? '').toString(),
            lastfmUrl: _extractImage(a['image']),
          );
        }
      default:
        url = '';
    }
    if (mounted) setState(() => _headerImageUrl = url);
  }

  Future<void> _extractColor(Map<String, dynamic> track) async {
    if (!useNowPlayingColorNotifier.value) return;
    final url = _extractImage(track['image']);
    if (url.isEmpty || url.contains('2a96cbd8b46e442fc41c2b86b821562f')) return;
    try {
      final pal = await PaletteGenerator.fromImageProvider(
        NetworkImage(url), size: const Size(160, 160), maximumColorCount: 16);
      final c = pal.vibrantColor?.color ?? pal.dominantColor?.color;
      if (c != null && mounted) accentNotifier.value = c;
    } catch (_) {}
  }

  // Stats calculations
  int    _total()  => int.tryParse((_userInfo?['playcount'] ?? '0').toString()) ?? 0;
  int    _days()   {
    final raw = _userInfo?['registered'];
    if (raw == null) return 0;
    int ts = 0;
    if (raw is Map) { ts = int.tryParse((raw['#text'] ?? raw['unixtime'] ?? '0').toString()) ?? 0; }
    else { ts = int.tryParse(raw.toString()) ?? 0; }
    if (ts <= 0) return 0;
    return ((DateTime.now().millisecondsSinceEpoch / 1000 - ts) / 86400).floor();
  }
  double _avg()    { final d = _days(); return d > 0 ? _total() / d : 0; }
  int    _weekly() => (_avg() * 7).round();
  String _regDate() {
    final raw = _userInfo?['registered'];
    if (raw == null) return '';
    int ts = 0;
    if (raw is Map) { ts = int.tryParse((raw['#text'] ?? raw['unixtime'] ?? '0').toString()) ?? 0; }
    else { ts = int.tryParse(raw.toString()) ?? 0; }
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${d.day} ${_kMonths[d.month]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error   != null) return _ErrorView(message: _error!, onRetry: _load);

    final info      = _userInfo!;
    final name      = (info['name']     ?? widget.username).toString();
    final realName  = (info['realname'] ?? '').toString();
    final country   = (info['country']  ?? '').toString();
    final avatarUrl = _extractImage(info['image']);

    final total  = _total();
    final days   = _days();
    final avg    = _avg();
    final weekly = _weekly();
    final regStr = _regDate();

    final topArtist = _topArtists.isNotEmpty ? _topArtists[0] as Map : null;
    final topAlbum  = _topAlbums.isNotEmpty  ? _topAlbums[0]  as Map : null;
    final topTrack  = _topTracks.isNotEmpty  ? _topTracks[0]  as Map : null;
    final lastTrack = _recentTracks.isNotEmpty ? _recentTracks[0] as Map : null;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(slivers: [

        // Profile appbar — full screen cover
        SliverAppBar(
          expandedHeight: 230,
          pinned: true,
          stretch: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
              tooltip: 'Actualiser',
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [
              StretchMode.zoomBackground,
              StretchMode.blurBackground,
            ],
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Background image (cover or gradient, animated)
                AnimatedSwitcher(
                  duration: _headerAnimation == 'none'
                      ? Duration.zero
                      : const Duration(milliseconds: 700),
                  transitionBuilder: (child, anim) {
                    switch (_headerAnimation) {
                      case 'slide':
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.06, 0),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                          child: FadeTransition(opacity: anim, child: child),
                        );
                      case 'zoom':
                        return ScaleTransition(
                          scale: Tween<double>(begin: 1.10, end: 1.0)
                              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                          child: FadeTransition(opacity: anim, child: child),
                        );
                      default: // 'fade' or others
                        return FadeTransition(opacity: anim, child: child);
                    }
                  },
                  child: _headerImageUrl.isNotEmpty
                      ? _BlurredHeaderImage(
                          key: ValueKey(_headerImageUrl),
                          url: _headerImageUrl,
                          blur: _headerBlur,
                          scheme: scheme,
                        )
                      : _GradientHeader(key: const ValueKey('gradient'), scheme: scheme),
                ),

                // Dark overlay for readability
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                ),

                // Profile content
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 70, 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          // Avatar
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 28,
                              backgroundColor: scheme.primary.withValues(alpha: 0.3),
                              backgroundImage: avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl) : null,
                              child: avatarUrl.isEmpty
                                  ? const Icon(Icons.person_rounded,
                                      size: 28, color: Colors.white)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  shadows: [Shadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                  )],
                                )),
                              if (realName.isNotEmpty)
                                Text(realName,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    shadows: const [Shadow(
                                      color: Colors.black45, blurRadius: 4)],
                                  )),
                              Row(children: [
                                if (country.isNotEmpty && country != 'None') ...[
                                  Icon(Icons.location_on_outlined,
                                      size: 12,
                                      color: Colors.white.withValues(alpha: 0.75)),
                                  const SizedBox(width: 2),
                                  Text(country,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 12,
                                      shadows: const [Shadow(
                                        color: Colors.black45, blurRadius: 4)],
                                    )),
                                  const SizedBox(width: 8),
                                ],
                                if (regStr.isNotEmpty) ...[
                                  Icon(Icons.calendar_today_outlined,
                                      size: 11,
                                      color: Colors.white.withValues(alpha: 0.75)),
                                  const SizedBox(width: 2),
                                  Text('Depuis $regStr',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 12,
                                      shadows: const [Shadow(
                                        color: Colors.black45, blurRadius: 4)],
                                    )),
                                ],
                              ]),
                            ],
                          )),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([

              // Now playing
              if (_showNowPlay && _nowPlaying != null) ...[
                _NowPlayingCard(track: _nowPlaying!),
                const SizedBox(height: 14),
              ],

              // Stats block
              if (_showStats) ...[
                _SectionHeader(title: 'Statistiques', icon: Icons.bar_chart_rounded),
                const SizedBox(height: 10),

                // Total scrobbles — full width
                _HeroStatCard(
                  total: total,
                  avg: avg.round(),
                  days: days,
                  weekly: weekly,
                  regStr: regStr,
                ),

                const SizedBox(height: 10),

                // 2×3 secondary stats grid
                _StatGrid(children: [
                  _DashStatCard(
                    emoji: '🎤',
                    value: topArtist != null ? (topArtist['name'] ?? '—').toString() : '—',
                    label: 'Artiste #1',
                    sub:   topArtist != null
                        ? '${_fmt(int.tryParse((topArtist['playcount'] ?? '0').toString()) ?? 0)} écoutes'
                        : null,
                  ),
                  _DashStatCard(
                    emoji: '💿',
                    value: topAlbum != null ? (topAlbum['name'] ?? '—').toString() : '—',
                    label: 'Album #1',
                    sub:   topAlbum != null
                        ? (topAlbum['artist']?['name'] ?? '').toString()
                        : null,
                  ),
                  _DashStatCard(
                    emoji: '🎵',
                    value: topTrack != null ? (topTrack['name'] ?? '—').toString() : '—',
                    label: 'Titre #1',
                    sub:   topTrack != null
                        ? '${_fmt(int.tryParse((topTrack['playcount'] ?? '0').toString()) ?? 0)} écoutes'
                        : null,
                  ),
                  _DashStatCard(
                    emoji: '⏱️',
                    value: lastTrack != null ? (lastTrack['name'] ?? '—').toString() : '—',
                    label: 'Dernière écoute',
                    sub:   lastTrack != null ? _fmtTrackDateLocal(lastTrack) : null,
                  ),
                ]),

                const SizedBox(height: 20),
              ],

              // ── Friends horizontal scroll ──────────────────────────
              if (_showFriends) ...[
                _FriendsSection(
                  friends:     _friends,
                  favorites:   _favFriends,
                  favProfiles: _favProfiles,
                  service:     widget.service,
                  isLoading:   _friendsLoading,
                  onToggleFav: _toggleFav,
                  onRefresh:   _loadFriends,
                ),
                const SizedBox(height: 20),
              ],

              // Top artists (mini)
              if (_showArtists && _topArtists.isNotEmpty) ...[
                _SectionHeader(title: 'Top Artistes', icon: Icons.mic_rounded),
                const SizedBox(height: 8),
                ..._topArtists.take(5).toList().asMap().entries.map((e) => _ItemTile(
                  name:     (e.value['name'] ?? '').toString(),
                  sub:      '${_fmt(int.tryParse((e.value['playcount'] ?? '0').toString()) ?? 0)} écoutes',
                  imageUrl: _extractImage(e.value['image']),
                  imageFuture: ImageService.resolveArtist((e.value['name'] ?? '').toString(),
                      lastfmUrl: _extractImage(e.value['image'])),
                  rank: '${e.key + 1}',
                  onTap: () => showDetailSheet(context, Map<String, dynamic>.from(e.value as Map), 'artists', widget.service),
                )),
                const SizedBox(height: 20),
              ],

              // Top tracks (mini)
              if (_showTracks && _topTracks.isNotEmpty) ...[
                _SectionHeader(title: 'Top Titres', icon: Icons.music_note_rounded),
                const SizedBox(height: 8),
                ..._topTracks.take(5).toList().asMap().entries.map((e) {
                  final tName  = (e.value['name'] ?? '').toString();
                  final artist = (e.value['artist']?['name'] ?? '').toString();
                  return _ItemTile(
                    name:     tName,
                    sub:      artist,
                    imageUrl: _extractImage(e.value['image']),
                    imageFuture: ImageService.resolveTrack(tName, artist,
                        lastfmUrl: _extractImage(e.value['image'])),
                    rank:  '${e.key + 1}',
                    plays: _fmt(int.tryParse((e.value['playcount'] ?? '0').toString()) ?? 0),
                    onTap: () => showDetailSheet(context, Map<String, dynamic>.from(e.value as Map), 'tracks', widget.service),
                  );
                }),
                const SizedBox(height: 20),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}


// ── Friends section widget ───────────────────────────────────────────────────

class _FriendsSection extends StatelessWidget {
  final List<_FriendData>   friends;
  final Set<String>         favorites;
  final Set<String>         favProfiles;   // profiles starred from search
  final LastFmService       service;
  final bool                isLoading;
  final void Function(String username, bool nowFav) onToggleFav;
  final VoidCallback        onRefresh;

  const _FriendsSection({
    required this.friends,
    required this.favorites,
    required this.favProfiles,
    required this.service,
    required this.isLoading,
    required this.onToggleFav,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme      = Theme.of(context).colorScheme;
    final text        = Theme.of(context).textTheme;
    final onlineCount = friends.where((f) => f.isOnline).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Section header row
      Row(children: [
        _SectionHeader(title: 'Amis', icon: Icons.people_rounded),
        const Spacer(),
        // Online badge
        if (!isLoading && onlineCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                '$onlineCount en ligne',
                style: text.labelSmall?.copyWith(
                    color: Colors.green.shade700, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        // Refresh icon
        if (!isLoading)
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            tooltip: 'Actualiser les amis',
          ),
      ]),

      const SizedBox(height: 10),

      // Scrollable list
      SizedBox(
        height: 152,
        child: isLoading
            // Loading shimmer row
            ? ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                padding: EdgeInsets.zero,
                itemBuilder: (_, _) => _FriendCardSkeleton(scheme: scheme),
              )
            : friends.isEmpty
                // Empty state
                ? Center(
                    child: Text(
                      'Aucun ami trouvé',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                // Friend cards
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: friends.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (ctx, i) {
                      final f      = friends[i];
                      final isFav  = favorites.contains(f.username)
                                  || favProfiles.contains(f.username);
                      return _FriendCard(
                        friend:      f,
                        isFav:       isFav,
                        service:     service,
                        onToggleFav: () => onToggleFav(f.username, !isFav),
                      );
                    },
                  ),
      ),
    ]);
  }
}


// ── Single friend card ───────────────────────────────────────────────────────

class _FriendCard extends StatelessWidget {
  final _FriendData  friend;
  final bool         isFav;
  final LastFmService service;
  final VoidCallback onToggleFav;

  static const _ph = '2a96cbd8b46e442fc41c2b86b821562f';

  const _FriendCard({
    required this.friend,
    required this.isFav,
    required this.service,
    required this.onToggleFav,
  });

  bool get _hasAvatar =>
      friend.avatarUrl.isNotEmpty && !friend.avatarUrl.contains(_ph);

  @override
  Widget build(BuildContext context) {
    final scheme   = Theme.of(context).colorScheme;
    final text     = Theme.of(context).textTheme;

    // Subtitle: now-playing track or last track name
    final subtitle = friend.isOnline
        ? (friend.nowPlayingTrack.isNotEmpty ? friend.nowPlayingTrack : 'En écoute')
        : (friend.lastTrack.isNotEmpty       ? friend.lastTrack       : 'Hors ligne');

    final subtitleArtist = friend.isOnline
        ? friend.nowPlayingArtist
        : friend.lastArtist;

    return GestureDetector(
      onTap: () => _openProfile(context),
      child: Container(
        width: 116,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: friend.isOnline
              ? scheme.primaryContainer.withValues(alpha: 0.45)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: friend.isOnline
                ? scheme.primary.withValues(alpha: 0.28)
                : scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [

            // ── Avatar with status dot + fav star ─────────────
            SizedBox(
              width: 60, height: 60,
              child: Stack(children: [

                // Avatar circle
                CircleAvatar(
                  radius: 30,
                  backgroundColor: scheme.primary.withValues(alpha: 0.2),
                  backgroundImage: _hasAvatar ? NetworkImage(friend.avatarUrl) : null,
                  child: _hasAvatar
                      ? null
                      : Text(
                          friend.username.isNotEmpty
                              ? friend.username[0].toUpperCase()
                              : '?',
                          style: text.titleMedium?.copyWith(
                              color: scheme.primary, fontWeight: FontWeight.w800),
                        ),
                ),

                // Online / offline dot (bottom-right)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color:  friend.isOnline ? Colors.green : scheme.outline,
                      shape:  BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                  ),
                ),

                // Favourite star (top-left) — tappable independently
                Positioned(
                  left: 0, top: 0,
                  child: GestureDetector(
                    onTap: onToggleFav,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                      size:  16,
                      color: isFav
                          ? Colors.amber.shade600
                          : scheme.onSurfaceVariant.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 6),

            // Username
            Text(
              friend.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 2),

            // Status line (track name)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (friend.isOnline) ...[
                Container(
                  width: 5, height: 5,
                  decoration: const BoxDecoration(
                      color: Colors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.labelSmall?.copyWith(
                    color: friend.isOnline
                        ? Colors.green.shade700
                        : scheme.onSurfaceVariant,
                    fontWeight:
                        friend.isOnline ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ]),

            // Artist name (second line, only when something is available)
            if (subtitleArtist.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                subtitleArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 9),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openProfile(BuildContext context) {
    showModalBottomSheet(
      context:           context,
      isScrollControlled: true,
      backgroundColor:   Colors.transparent,
      useSafeArea:       true,
      builder: (_) => _FriendProfileSheet(friend: friend, service: service),
    );
  }
}


// ── Skeleton placeholder card shown while friends load ──────────────────────

class _FriendCardSkeleton extends StatelessWidget {
  final ColorScheme scheme;
  const _FriendCardSkeleton({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final base = scheme.surfaceContainerHighest;
    return Container(
      width: 116,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: scheme.outline.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 10, width: 60,
            decoration: BoxDecoration(
                color: scheme.outline.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 5),
        Container(height: 8, width: 80,
            decoration: BoxDecoration(
                color: scheme.outline.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4))),
      ]),
    );
  }
}


// ── Friend profile bottom sheet ──────────────────────────────────────────────

class _FriendProfileSheet extends StatefulWidget {
  final _FriendData   friend;
  final LastFmService service;
  const _FriendProfileSheet({required this.friend, required this.service});

  @override
  State<_FriendProfileSheet> createState() => _FriendProfileSheetState();
}

class _FriendProfileSheetState extends State<_FriendProfileSheet> {
  List<dynamic> _recent  = [];
  bool          _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.service.getRecentTracks(
          user: widget.friend.username, limit: 10);
      final raw    = d['track'];
      final tracks = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);
      if (mounted) setState(() { _recent = tracks; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _ph = '2a96cbd8b46e442fc41c2b86b821562f';

  bool _hasAvatar(String url) => url.isNotEmpty && !url.contains(_ph);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final f      = widget.friend;

    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize:     0.38,
      maxChildSize:     0.88,
      expand: false,
      builder: (ctx, ctrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: scheme.surface,
          child: ListView(controller: ctrl, children: [

            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),

            // ── Profile header ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(children: [

                // Avatar + status dot
                SizedBox(
                  width: 68, height: 68,
                  child: Stack(children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: scheme.primaryContainer,
                      backgroundImage: _hasAvatar(f.avatarUrl)
                          ? NetworkImage(f.avatarUrl) : null,
                      child: _hasAvatar(f.avatarUrl)
                          ? null
                          : Text(
                              f.username.isNotEmpty
                                  ? f.username[0].toUpperCase()
                                  : '?',
                              style: text.titleLarge?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w800),
                            ),
                    ),
                    Positioned(
                      right: 2, bottom: 2,
                      child: Container(
                        width: 16, height: 16,
                        decoration: BoxDecoration(
                          color:  f.isOnline ? Colors.green : scheme.outline,
                          shape:  BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(width: 16),

                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.username,
                        style: text.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    if (f.realName.isNotEmpty)
                      Text(f.realName,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    // Online / offline badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: f.isOnline
                            ? Colors.green.withValues(alpha: 0.12)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: f.isOnline
                                ? Colors.green
                                : scheme.outlineVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          f.isOnline ? 'En écoute' : 'Hors ligne',
                          style: text.labelSmall?.copyWith(
                            color: f.isOnline
                                ? Colors.green.shade700
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ]),
                    ),
                  ],
                )),
              ]),
            ),

            // ── Now playing card (if active) ──────────────────
            if (f.isOnline && f.nowPlayingTrack.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Card(
                  elevation: 0,
                  color: scheme.secondaryContainer,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: _cardBorder(scheme)),
                  child: ListTile(
                    leading: Icon(Icons.music_note_rounded,
                        color: scheme.secondary),
                    title: Text(f.nowPlayingTrack,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    subtitle: f.nowPlayingArtist.isNotEmpty
                        ? Text(f.nowPlayingArtist,
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),

            const Divider(indent: 16, endIndent: 16, height: 20),

            // ── Recent tracks ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Écoutes récentes',
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),

            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()))
            else if (_recent.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                    child: Text('Aucune écoute récente',
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant))),
              )
            else
              ..._recent.map((t) {
                final tMap    = t as Map<String, dynamic>;
                final isNp    = tMap['@attr']?['nowplaying'] == 'true';
                final tName   = (tMap['name'] ?? '').toString();
                final tArtist =
                    (tMap['artist']?['#text'] ?? '').toString();
                final rawUrl  = _extractImage(tMap['image']);
                final hasImg  = rawUrl.isNotEmpty && !rawUrl.contains(_ph);

                return ListTile(
                  leading: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: hasImg
                          ? Image.network(rawUrl,
                              width: 40, height: 40, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                  width: 40, height: 40,
                                  color: scheme.surfaceContainerHighest,
                                  child: Icon(Icons.music_note_rounded,
                                      color: scheme.onSurfaceVariant)))
                          : Container(
                              width: 40, height: 40,
                              color: scheme.surfaceContainerHighest,
                              child: Icon(Icons.music_note_rounded,
                                  color: scheme.onSurfaceVariant)),
                    ),
                    if (isNp)
                      Positioned(
                        right: 0, bottom: 0,
                        child: Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                              color: Colors.green, shape: BoxShape.circle),
                        ),
                      ),
                  ]),
                  title: Text(tName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(tArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  trailing: isNp
                      ? Text('EN COURS',
                          style: text.labelSmall?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.w700))
                      : Text(
                          _localTimeString(tMap),
                          style: text.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 9),
                        ),
                  dense: true,
                );
              }),

            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}


// Fallback gradient for header
class _GradientHeader extends StatelessWidget {
  final ColorScheme scheme;
  const _GradientHeader({super.key, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            scheme.secondary,
            scheme.tertiary,
          ],
        ),
      ),
    );
  }
}

// Header image with optional blur
class _BlurredHeaderImage extends StatelessWidget {
  final String url;
  final double blur;
  final ColorScheme scheme;
  const _BlurredHeaderImage({
    super.key,
    required this.url,
    required this.blur,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    Widget img = Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => _GradientHeader(scheme: scheme),
    );
    if (blur > 0.5) {
      img = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.clamp,
        ),
        child: img,
      );
    }
    return img;
  }
}

// Full number with thousand separator
String _fmtFull(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u202F');
    buf.write(s[i]);
  }
  return buf.toString();
}

// Full-width hero stat card

class _HeroStatCard extends StatelessWidget {
  final int total, avg, days, weekly;
  final String regStr;
  const _HeroStatCard({required this.total, required this.avg, required this.days,
      required this.weekly, required this.regStr});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: _cardBorder(scheme, alpha: 0.25),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Main row
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('🎯', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Text(_fmtFull(total),
                style: text.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onPrimaryContainer,
                    height: 1)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('scrobbles',
                  style: text.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 14),
          // Sub-metrics
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MiniMetric('⚡', '~${_fmt(avg)}', 'par jour', scheme.onPrimaryContainer),
                _vDivider(scheme.onPrimaryContainer),
                _MiniMetric('📅', '~${_fmt(weekly)}', 'par semaine', scheme.onPrimaryContainer),
                _vDivider(scheme.onPrimaryContainer),
                _MiniMetric('🗓️', '$days j', 'd\'activité', scheme.onPrimaryContainer),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _vDivider(Color c) => Container(
      width: 1, height: 32,
      color: c.withValues(alpha: 0.15));
}

class _MiniMetric extends StatelessWidget {
  final String emoji, value, label;
  final Color color;
  const _MiniMetric(this.emoji, this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 2),
      Text(value, style: text.bodyMedium?.copyWith(
          fontWeight: FontWeight.w800, color: color)),
      Text(label, style: text.labelSmall?.copyWith(
          color: color.withValues(alpha: 0.65))),
    ]);
  }
}

// 2-column grid
class _StatGrid extends StatelessWidget {
  final List<Widget> children;
  const _StatGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    final pairs = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final hasRight = i + 1 < children.length;
      pairs.add(Row(children: [
        Expanded(child: children[i]),
        const SizedBox(width: 10),
        Expanded(child: hasRight ? children[i + 1] : const SizedBox()),
      ]));
      if (i + 2 < children.length) pairs.add(const SizedBox(height: 10));
    }
    return Column(children: pairs);
  }
}

// Secondary stat card
class _DashStatCard extends StatelessWidget {
  final String emoji, value, label;
  final String? sub;
  const _DashStatCard({required this.emoji, required this.value,
      required this.label, this.sub});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: _cardBorder(scheme),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800, color: scheme.onSurface)),
          Text(label, style: text.bodySmall?.copyWith(
              color: scheme.primary, fontWeight: FontWeight.w600)),
          if (sub != null)
            Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}


// Now playing card

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: _cardBorder(scheme),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          _SmartImage(size: 52, borderRadius: 10, initialUrl: rawUrl,
              resolver: () => ImageService.resolveTrack(title, artist,
                  lastfmUrl: rawUrl.isNotEmpty ? rawUrl : null)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 7, height: 7,
                  decoration: BoxDecoration(color: scheme.secondary, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('EN COURS', style: text.labelSmall?.copyWith(
                  color: scheme.secondary, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
            ]),
            const SizedBox(height: 2),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.7))),
          ])),
        ]),
      ),
    );
  }
}
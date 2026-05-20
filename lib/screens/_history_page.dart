// ignore_for_file: unused_import
part of 'home_screen.dart';

class _HistoryPage extends StatefulWidget {
  final LastFmService service;
  const _HistoryPage({required this.service});
  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {

  DateTime _selectedDate = DateTime.now();
  List<dynamic> _tracks  = [];
  bool   _loading = true;
  String? _error;
  late TabController _tabController;

  @override bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _tracks = []; });
    try {
      final from = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final to   = from.add(const Duration(days: 1));
      final List<dynamic> all = [];
      int page = 1;
      while (true) {
        final data = await widget.service.getRecentTracks(
          limit: 200, page: page,
          from: from.millisecondsSinceEpoch ~/ 1000,
          to:   to.millisecondsSinceEpoch   ~/ 1000,
        );
        final raw   = data['track'];
        final fresh = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);
        all.addAll(fresh.where((t) => (t as Map?)?['@attr']?['nowplaying'] != 'true'));
        final totalP = int.tryParse((data['@attr'] as Map?)?['totalPages']?.toString() ?? '1') ?? 1;
        if (page >= totalP) break;
        page++;
      }
      setState(() { _tracks = all; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year && _selectedDate.month == n.month && _selectedDate.day == n.day;
  }

  void _prev()    { setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1))); _load(); }
  void _next()    { if (!_isToday) { setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1))); _load(); } }
  void _goToday() { final n = DateTime.now(); setState(() => _selectedDate = DateTime(n.year, n.month, n.day)); _load(); }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _selectedDate,
      firstDate: DateTime(2000), lastDate: DateTime.now(),
      helpText: 'Sélectionner une date', cancelText: 'Annuler', confirmText: 'OK',
    );
    if (picked != null && mounted) { setState(() => _selectedDate = picked); _load(); }
  }

  int get _uniqueArtists => _tracks.map((t) => (t as Map)['artist']?['#text'] ?? '').toSet().length;
  int get _uniqueAlbums  => _tracks.map((t) => (t as Map)['album']?['#text']  ?? '')
      .where((a) => (a as String).isNotEmpty).toSet().length;

  // Group by hour descending
  List<MapEntry<String, List<dynamic>>> get _byHour {
    final map = <String, List<dynamic>>{};
    for (final t in _tracks) {
      final dateStr = (t as Map)['date']?['#text']?.toString() ?? '';
      String hour = '—';
      if (dateStr.isNotEmpty) {
        final parts = dateStr.split(', ');
        if (parts.length == 2) {
          final h = parts[1].split(':')[0];
          hour = '$h:00';
        }
      }
      map.putIfAbsent(hour, () => []).add(t);
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return sorted;
  }

  String _dayLabel() {
    const jours = ['lundi','mardi','mercredi','jeudi','vendredi','samedi','dimanche'];
    const mois  = ['','janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'];
    final d = _selectedDate;
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month]} ${d.year}';
  }

  String _dateFmt() {
    final d = _selectedDate;
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final hasData = !_loading && _error == null && _tracks.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Historique', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text('Vos écoutes, jour par jour',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ])),
              IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
            ]),
          ),

          const SizedBox(height: 10),

          // Date navigation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _HistNavBtn(icon: Icons.chevron_left_rounded, onTap: _prev, scheme: scheme),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color:  scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(_dateFmt(),
                          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
                      Icon(Icons.calendar_month_rounded, size: 16, color: scheme.onSurfaceVariant),
                    ]),
                  ),
                ),
              ),
              if (!_isToday) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _goToday,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.today_rounded, size: 15, color: scheme.onPrimaryContainer),
                      const SizedBox(width: 5),
                      Text("Aujourd'hui", style: text.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              _HistNavBtn(
                icon: Icons.chevron_right_rounded,
                onTap: _isToday ? null : _next,
                scheme: scheme,
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // Day summary + tabs
          if (hasData) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_dayLabel(),
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 34, child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _HistStatPill(icon: Icons.headphones_rounded,
                    label: '${_tracks.length} scrobbles', scheme: scheme),
                const SizedBox(width: 8),
                _HistStatPill(icon: Icons.mic_rounded,
                    label: '$_uniqueArtists artistes', scheme: scheme),
                const SizedBox(width: 8),
                _HistStatPill(icon: Icons.album_rounded,
                    label: '$_uniqueAlbums albums', scheme: scheme),
              ],
            )),
            const SizedBox(height: 10),
            TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              indicatorColor: scheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: scheme.outlineVariant.withValues(alpha: 0.3),
              tabs: const [
                Tab(text: 'Chronologique'),
                Tab(text: 'Liste'),
                Tab(text: 'Statistiques'),
              ],
            ),
          ],

          // Content
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: _ErrorView(message: _error!, onRetry: _load))
          else if (_tracks.isEmpty)
            Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.music_off_rounded, size: 48,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35)),
              const SizedBox(height: 12),
              Text('Aucune écoute ce jour-là',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ])))
          else
            Expanded(child: TabBarView(
              controller: _tabController,
              children: [
                _HistChronView(tracks: _tracks, byHour: _byHour, service: widget.service),
                _HistListeView(tracks: _tracks, service: widget.service),
                _HistStatsView(tracks: _tracks),
              ],
            )),
        ]),
      ),
    );
  }
}

// Navigation button
class _HistNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final ColorScheme scheme;
  const _HistNavBtn({required this.icon, required this.onTap, required this.scheme});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: 22,
          color: onTap == null ? scheme.onSurface.withValues(alpha: 0.25) : scheme.onSurface),
    ),
  );
}

// Stat pill
class _HistStatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme scheme;
  const _HistStatPill({required this.icon, required this.label, required this.scheme});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: scheme.secondaryContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: scheme.primary),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: scheme.onSecondaryContainer)),
    ]),
  );
}

// Chronological view
class _HistChronView extends StatelessWidget {
  final List<dynamic> tracks;
  final List<MapEntry<String, List<dynamic>>> byHour;
  final LastFmService service;
  const _HistChronView({required this.tracks, required this.byHour, required this.service});

  static String _time(Map t) {
    final raw = t['date']?['#text']?.toString() ?? '';
    if (raw.isEmpty) return '';
    final parts = raw.split(', ');
    return parts.length == 2 ? parts[1] : '';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: byHour.length,
        itemBuilder: (_, i) {
          final entry  = byHour[i];
          final hour   = entry.key;
          final hTracks = entry.value;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Hour separator
            if (i > 0) const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(children: [
                Container(
                  width: 3, height: 18,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(hour, style: text.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                )),
                const SizedBox(width: 10),
                Expanded(child: Container(
                  height: 1,
                  color: scheme.primary.withValues(alpha: 0.15),
                )),
                const SizedBox(width: 8),
                Text(
                  '${hTracks.length} titre${hTracks.length > 1 ? "s" : ""}',
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ]),
            ),
            for (final t in hTracks)
              _HistTrackRow(track: t as Map, time: _time(t), service: service),
            const SizedBox(height: 6),
          ]);
        },
      ),
    );
  }
}

// Track row (chronological view)
class _HistTrackRow extends StatelessWidget {
  final Map track;
  final String time;
  final LastFmService service;
  const _HistTrackRow({required this.track, required this.time, required this.service});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final tit    = (track['name']             ?? '').toString();
    final art    = (track['artist']?['#text'] ?? '').toString();
    final alb    = (track['album']?['#text']  ?? '').toString();
    final raw    = _extractImage(track['image']);

    return InkWell(
      onTap: () => showDetailSheet(context,
        {'name': tit, 'artist': {'name': art}, 'album': {'title': alb}, 'image': track['image']},
        'tracks', service),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(children: [
          // Time
          SizedBox(width: 40,
            child: Text(time, style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500))),
          const SizedBox(width: 8),
          // Cover art
          _SmartImage(size: 42, borderRadius: 6, initialUrl: raw,
              resolver: () => ImageService.resolveTrack(tit, art, lastfmUrl: raw.isNotEmpty ? raw : null)),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tit, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(art, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (alb.isNotEmpty) Row(children: [
              Icon(Icons.album_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              const SizedBox(width: 3),
              Expanded(child: Text(alb, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                      fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)))),
            ]),
          ])),

        ]),
      ),
    );
  }
}

// List view
class _HistListeView extends StatelessWidget {
  final List<dynamic> tracks;
  final LastFmService service;
  const _HistListeView({required this.tracks, required this.service});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: tracks.length,
      itemBuilder: (_, i) {
        final t   = tracks[i] as Map;
        final tit = (t['name']             ?? '').toString();
        final art = (t['artist']?['#text'] ?? '').toString();
        final alb = (t['album']?['#text']  ?? '').toString();
        final raw = _extractImage(t['image']);
        final dateStr = t['date']?['#text']?.toString() ?? '';
        final timeParts = dateStr.split(', ');
        final timeOnly = timeParts.length == 2 ? timeParts[1] : '';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: _SmartImage(size: 44, borderRadius: 6, initialUrl: raw,
              resolver: () => ImageService.resolveTrack(tit, art, lastfmUrl: raw.isNotEmpty ? raw : null)),
          title: Text(tit, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(alb.isNotEmpty ? '$art · $alb' : art,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          trailing: Text(timeOnly,
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          onTap: () => showDetailSheet(context,
            {'name': tit, 'artist': {'name': art}, 'album': {'title': alb}, 'image': t['image']},
            'tracks', service),
        );
      },
    );
  }
}

// Stats view
class _HistStatsView extends StatelessWidget {
  final List<dynamic> tracks;
  const _HistStatsView({required this.tracks});

  Map<String, int> _count(Iterable<String> keys) {
    final map = <String, int>{};
    for (final k in keys) { if (k.isNotEmpty) map[k] = (map[k] ?? 0) + 1; }
    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(10));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final artists = _count(tracks.map((t) => (t as Map)['artist']?['#text']?.toString() ?? ''));
    final albums  = _count(tracks.map((t) => (t as Map)['album']?['#text']?.toString()  ?? ''));
    final tTracks = _count(tracks.map((t) => (t as Map)['name']?.toString()             ?? ''));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _HistStatSection(title: 'Top artistes', icon: Icons.mic_rounded,
            data: artists, scheme: scheme, text: text),
        const SizedBox(height: 20),
        _HistStatSection(title: 'Top albums', icon: Icons.album_rounded,
            data: albums, scheme: scheme, text: text),
        const SizedBox(height: 20),
        _HistStatSection(title: 'Top titres', icon: Icons.music_note_rounded,
            data: tTracks, scheme: scheme, text: text),
      ],
    );
  }
}

class _HistStatSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, int> data;
  final ColorScheme scheme;
  final TextTheme text;
  const _HistStatSection({required this.title, required this.icon,
      required this.data, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final max = data.values.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      for (final e in data.entries) ...[
        Row(children: [
          SizedBox(width: 24,
            child: Text('${data.keys.toList().indexOf(e.key) + 1}',
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
              Text('${e.value}×', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: max > 0 ? e.value / max : 0,
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ])),
        ]),
        const SizedBox(height: 10),
      ],
    ]);
  }
}


// Settings

const _kStartupLabels = [
  (Icons.dashboard_rounded,    'Dashboard'),
  (Icons.emoji_events_rounded, 'Classements'),
  (Icons.auto_graph_rounded,   'Graphiques'),
  (Icons.history_rounded,      'Historique'),
];
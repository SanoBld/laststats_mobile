// ignore_for_file: unused_import
part of 'home_screen.dart';

String _ct(String fr, String en) => localeNotifier.value == 'en' ? en : fr;

List<String> get _chartWeekdayLabels => localeNotifier.value == 'en'
    ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    : ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

const _kTwoPi  = 6.283185307179586;
const _kHalfPi = 1.5707963267948966;

/// Nombre exact pour les barres (jusqu'à 999 999, puis M).
/// Contrairement à _fmt qui abrège dès 1 000.
String _fmtExact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  return n.toString();
}

// ── Page ─────────────────────────────────────────────────────────────────────

class _ChartsPage extends StatefulWidget {
  final LastFmService service;
  const _ChartsPage({required this.service});

  @override
  State<_ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<_ChartsPage>
    with AutomaticKeepAliveClientMixin {

  // ── Données globales (tops all-time) ─────────────────────────────────────
  List<dynamic> _topArtists = [];
  List<dynamic> _topAlbums  = [];
  bool   _loading = true;
  String? _error;

  // ── Données liées à l'année sélectionnée ─────────────────────────────────
  Map<String, int>? _monthly;
  bool _hourlyLoading    = false;
  Map<int, int>?    _hourlyData;
  Map<int, int>?    _weekdayData;
  int  _hourlyCount      = 0;
  bool _calendarLoading  = false;
  Map<String, int>? _calendarData;
  bool _hasFullYearData  = false; // true = données depuis AllScrobblesService

  // ── Genres (dérivé des tops artistes, all-time) ───────────────────────────
  bool _tagsLoading = false;
  List<_TagEntry> _tags = [];

  // ── Sélection d'année ─────────────────────────────────────────────────────
  int        _selectedYear  = DateTime.now().year;
  List<int>  _availableYears = [DateTime.now().year];

  // ── Progression du chargement historique ─────────────────────────────────
  AllScrobblesProgress _historyProgress = AllScrobblesProgress.idle();

  @override
  bool get wantKeepAlive => true;

  // ══════════════════════════════════════════════════════════════════════════
  //  Cycle de vie
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    AllScrobblesService.progressNotifier.addListener(_onHistoryProgress);
    _load();
  }

  @override
  void dispose() {
    AllScrobblesService.progressNotifier.removeListener(_onHistoryProgress);
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Listeners
  // ══════════════════════════════════════════════════════════════════════════

  void _onHistoryProgress() {
    if (!mounted) return;
    final p = AllScrobblesService.progressNotifier.value;
    setState(() => _historyProgress = p);

    // Actualiser les années disponibles dès qu'une nouvelle est chargée
    _refreshAvailableYears();

    // Recharger dès que les données complètes de l'année arrivent,
    // même si on avait déjà du contenu via le fallback (page 1 incomplet)
    if (!_hasFullYearData && AllScrobblesService.isYearCached(_selectedYear)) {
      _hasFullYearData = true;
      _loadYearData(_selectedYear);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Chargement principal
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Future.wait([
        widget.service.getTopArtists(period: 'overall', limit: 10),
        widget.service.getTopAlbums(period: 'overall',  limit: 10),
      ]);
      if (!mounted) return;
      setState(() {
        _topArtists = res[0];
        _topAlbums  = res[1];
        _loading    = false;
      });

      _refreshAvailableYears();
      _loadTags();

      // Initialiser le flag avant de charger (évite un double-chargement inutile)
      _hasFullYearData = AllScrobblesService.isYearCached(_selectedYear);

      // Charger les données de l'année sélectionnée
      await _loadYearData(_selectedYear);

      // Démarrer le chargement de l'historique complet si pas encore lancé
      if (!AllScrobblesService.isRunning) {
        AllScrobblesService.loadAll(widget.service);
      }

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error  = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ── Chargement des données d'une année ────────────────────────────────────

  Future<void> _loadYearData(int year) async {
    // Priorité 1 : cache AllScrobbles (instantané)
    final records = AllScrobblesService.getRecordsForYear(year);
    if (records != null) {
      if (!mounted) return;
      setState(() {
        _monthly      = AllScrobblesService.computeMonthly(records);
        _hourlyData   = AllScrobblesService.computeHourly(records);
        _weekdayData  = AllScrobblesService.computeWeekday(records);
        _hourlyCount  = records.length;
        _calendarData = AllScrobblesService.computeCalendar(records);
        _hourlyLoading   = false;
        _calendarLoading = false;
      });
      return;
    }

    // Priorité 2 : fallback API (seulement utile pour l'année en cours)
    await Future.wait([
      _loadMonthlyFallback(),
      _loadHourlyFallback(),
      _loadCalendarFallback(year),
    ]);
  }

  // ── Fallbacks API ─────────────────────────────────────────────────────────

  Future<void> _loadMonthlyFallback() async {
    try {
      final data = await widget.service.getMonthlyScrobbles(months: 24);
      if (!mounted) return;
      // Filtrer sur l'année sélectionnée si possible
      final filtered = Map.fromEntries(
        data.entries.where((e) => e.key.startsWith('$_selectedYear')),
      );
      setState(() => _monthly = filtered.isNotEmpty ? filtered : data);
    } catch (_) {
      if (mounted) setState(() => _monthly = {});
    }
  }

  Future<void> _loadHourlyFallback() async {
    if (_hourlyLoading) return;
    setState(() {
      _hourlyLoading = true;
      _hourlyData    = null;
      _weekdayData   = null;
      _hourlyCount   = 0;
    });
    try {
      final pages = await Future.wait(
        List.generate(4, (i) => widget.service.getRecentTracks(limit: 50, page: i + 1)),
      );
      final hours    = <int, int>{for (var i = 0; i < 24; i++) i: 0};
      final weekdays = <int, int>{for (var i = 1; i <= 7; i++) i: 0};
      int count = 0;
      for (final page in pages) {
        final raw  = page['track'];
        final list = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);
        for (final t in list) {
          final m = t as Map?;
          if (m == null) continue;
          if (m['@attr']?['nowplaying'] == 'true') continue;
          final uts = (m['date'] as Map?)?['uts']?.toString() ?? '';
          if (uts.isEmpty) continue;
          final sec = int.tryParse(uts);
          if (sec == null) continue;
          final dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
          hours[dt.hour]       = (hours[dt.hour]       ?? 0) + 1;
          weekdays[dt.weekday] = (weekdays[dt.weekday] ?? 0) + 1;
          count++;
        }
      }
      if (!mounted) return;
      setState(() {
        _hourlyData    = hours;
        _weekdayData   = weekdays;
        _hourlyCount   = count;
        _hourlyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _hourlyLoading = false);
    }
  }

  Future<void> _loadCalendarFallback(int year) async {
    // Le fallback API n'est pertinent que pour l'année en cours
    if (year != DateTime.now().year) {
      if (mounted) setState(() => _calendarLoading = false);
      return;
    }
    if (_calendarLoading) return;
    setState(() { _calendarLoading = true; _calendarData = null; });
    try {
      final now  = DateTime.now();
      final data = <String, int>{};
      final futures = List.generate(12, (i) {
        final month = DateTime(now.year, now.month - (11 - i), 1);
        final nextM = DateTime(month.year, month.month + 1, 1);
        return widget.service.getRecentTracks(
          limit: 200, page: 1,
          from: month.millisecondsSinceEpoch ~/ 1000,
          to:   nextM.millisecondsSinceEpoch ~/ 1000,
        ).catchError((_) => <String, dynamic>{});
      });
      final pages = await Future.wait(futures);
      for (final pageData in pages) {
        final raw  = pageData['track'];
        final list = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);
        for (final t in list) {
          final m = t as Map?;
          if (m == null) continue;
          if (m['@attr']?['nowplaying'] == 'true') continue;
          final uts = (m['date'] as Map?)?['uts']?.toString() ?? '';
          if (uts.isEmpty) continue;
          final sec = int.tryParse(uts);
          if (sec == null) continue;
          final dt  = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
              '${dt.day.toString().padLeft(2, '0')}';
          data[key] = (data[key] ?? 0) + 1;
        }
      }
      if (!mounted) return;
      setState(() { _calendarData = data; _calendarLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  // ── Genres (all-time) ─────────────────────────────────────────────────────

  Future<void> _loadTags() async {
    if (_topArtists.isEmpty || _tagsLoading) return;
    setState(() { _tagsLoading = true; _tags = []; });
    try {
      final artists  = _topArtists.take(10).toList();
      final tagLists = await Future.wait(
        artists.map((a) => widget.service
            .getArtistTopTags((a['name'] ?? '').toString())
            .catchError((_) => <dynamic>[])),
      );
      final agg = <String, int>{};
      for (var i = 0; i < artists.length; i++) {
        final plays = int.tryParse((artists[i]['playcount'] ?? '1').toString()) ?? 1;
        for (final t in tagLists[i].take(5)) {
          final name = (t['name'] ?? '').toString().trim();
          if (name.isEmpty || name.length > 20) continue;
          agg[name] = (agg[name] ?? 0) + plays;
        }
      }
      final sorted = agg.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      if (!mounted) return;
      setState(() {
        _tags       = sorted.take(8).map((e) => _TagEntry(name: e.key, count: e.value)).toList();
        _tagsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _tagsLoading = false);
    }
  }

  // ── Années disponibles ────────────────────────────────────────────────────

  void _refreshAvailableYears() {
    if (!mounted) return;
    final cached      = AllScrobblesService.getCachedYears().toSet();
    final currentYear = DateTime.now().year;
    cached.add(currentYear); // l'année en cours est toujours accessible (fallback)
    final sorted = cached.toList()..sort();
    setState(() => _availableYears = sorted);
  }

  // ── Helpers all-time ─────────────────────────────────────────────────────

  /// Combine TOUS les timestamps disponibles en données mensuelles.
  /// Retombe sur _monthly (fallback API) si aucune année n'est encore en cache.
  Map<String, int> _buildAllTimeMonthly() {
    final result = <String, int>{};
    for (final year in _availableYears) {
      final ts = AllScrobblesService.getRecordsForYear(year);
      if (ts != null) {
        AllScrobblesService.computeMonthly(ts)
            .forEach((k, v) => result[k] = (result[k] ?? 0) + v);
      }
    }
    if (result.isEmpty && _monthly != null) result.addAll(_monthly!);
    return result;
  }

  /// Cumulative all-time, coupée au mois courant (pas de mois futurs vides).
  Map<String, int> _buildAllTimeCumulative(Map<String, int> monthly) {
    final now    = DateTime.now();
    final cutoff = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final keys   = monthly.keys
        .where((k) => k.compareTo(cutoff) <= 0)
        .toList()..sort();
    int cum = 0;
    final result = <String, int>{};
    for (final k in keys) {
      cum += monthly[k]!;
      result[k] = cum;
    }
    return result;
  }

  void _onYearChanged(int year) {
    if (year == _selectedYear) return;
    setState(() {
      _selectedYear    = year;
      _hasFullYearData = AllScrobblesService.isYearCached(year);
      // _monthly (fallback) n'est pas réinitialisé : il alimente _buildAllTimeMonthly
      _hourlyData      = null;
      _weekdayData     = null;
      _calendarData    = null;
      _hourlyLoading   = true;
      _calendarLoading = true;
    });
    _loadYearData(year);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Widgets de navigation
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildYearChips(ColorScheme s, TextTheme t) {
    final years = _availableYears.isNotEmpty ? _availableYears : [_selectedYear];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: years.map((year) {
          final selected = year == _selectedYear;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onYearChanged(year),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? s.primaryContainer.withValues(alpha: 0.6)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? s.primary.withValues(alpha: 0.5)
                        : s.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Text(
                  '$year',
                  style: t.labelMedium?.copyWith(
                    color: selected ? s.onPrimaryContainer : s.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHistoryBanner(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final p = _historyProgress;

    if (p.isDone) return const SizedBox.shrink();

    if (p.isLoading) {
      // Progression en cours
      final yearLabel = p.currentYear != null ? ' ${p.currentYear}' : '';
      final pct = (p.fraction * 100).round();
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: s.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: s.primary.withValues(alpha: 0.2), width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: s.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _ct(
                  'Chargement de l\'historique$yearLabel… $pct %',
                  'Loading history$yearLabel… $pct%',
                ),
                style: t.bodySmall?.copyWith(
                    color: s.onPrimaryContainer,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p.fraction,
              minHeight: 4,
              backgroundColor: s.primary.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(s.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _ct(
              'Les graphiques seront plus précis une fois chargé.',
              'Charts will be more accurate once loaded.',
            ),
            style: t.labelSmall?.copyWith(
                color: s.onPrimaryContainer.withValues(alpha: 0.65),
                fontSize: 10),
          ),
        ]),
      );
    }

    // Pas encore démarré (idle)
    if (p.isIdle) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: s.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: s.outlineVariant.withValues(alpha: 0.5), width: 1),
        ),
        child: Row(children: [
          Icon(Icons.cloud_download_outlined,
              size: 16, color: s.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _ct(
                'Chargez l\'historique complet pour accéder à toutes les années.',
                'Load the full history to access all years.',
              ),
              style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => AllScrobblesService.loadAll(widget.service),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: t.labelSmall,
            ),
            child: Text(_ct('Charger', 'Load')),
          ),
        ]),
      );
    }

    return const SizedBox.shrink();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    if (_loading)       return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

    // ── Données all-time (barres + courbe) ───────────────────────────────────
    final allTimeMonthly = _buildAllTimeMonthly();
    final cumulData      = _buildAllTimeCumulative(allTimeMonthly);

    // ── Source des habitudes d'écoute (année sélectionnée) ──────────────────
    final cachedTs    = AllScrobblesService.getTimestampsForYear(_selectedYear);
    final hasFullData = cachedTs != null;
    final habitsSubtitle = hasFullData
        ? _ct(
            'Basé sur $_hourlyCount scrobbles de $_selectedYear',
            'Based on $_hourlyCount scrobbles from $_selectedYear',
          )
        : _hourlyCount > 0
            ? _ct(
                'Basé sur $_hourlyCount scrobbles récents',
                'Based on $_hourlyCount recent scrobbles',
              )
            : _ct(
                'Analyse vos ~200 derniers scrobbles',
                'Analysing your last ~200 scrobbles',
              );

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header fixe ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 0, 0),
            child: Text(L.chartsTitle,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildYearChips(scheme, text),
          ),
          const SizedBox(height: 14),

          // ── Contenu scrollable ────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              children: [

                // ── Bannière chargement historique ──────────────────────────
                _buildHistoryBanner(context),

          // ── 1. Barres mensuelles (all-time, scroll depuis le 1er scrobble) ──
          _SectionHeader(title: L.chartsMonthly, icon: Icons.calendar_month_rounded),
          const SizedBox(height: 12),
          if (allTimeMonthly.isNotEmpty) _MonthlyCard(monthly: allTimeMonthly),
          const SizedBox(height: 24),

          // ── 2. Courbe cumulative (all-time, coupée au mois courant) ────────
          if (cumulData.length >= 2) ...[
            _SectionHeader(
              title: _ct(
                "Progression totale des scrobbles",
                'All-time scrobble progression',
              ),
              icon: Icons.trending_up_rounded,
            ),
            const SizedBox(height: 12),
            _CumulativeLineCard(data: cumulData),
            const SizedBox(height: 24),
          ],

          // ── 3. Genres musicaux (all-time) ─────────────────────────────────
          _SectionHeader(
            title: _ct('Vos genres musicaux', 'Your musical genres'),
            icon: Icons.equalizer_rounded,
          ),
          const SizedBox(height: 4),
          Text(
            _ct('Basé sur vos top artistes (all-time)',
                'Based on your top artists (all-time)'),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_tagsLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_tags.isNotEmpty)
            _TagsCard(tags: _tags),
          const SizedBox(height: 24),

          // ── 4. Habitudes d'écoute ─────────────────────────────────────────
          _SectionHeader(
            title: _ct("Habitudes d'écoute", 'Listening habits'),
            icon: Icons.access_time_rounded,
          ),
          const SizedBox(height: 4),
          Text(habitsSubtitle,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_hourlyLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_hourlyData != null) ...[
            _HourlyBarCard(data: _hourlyData!),
            const SizedBox(height: 12),
            _WeekdayBarCard(data: _weekdayData!),
          ],
          const SizedBox(height: 24),

          // ── 5. Répartition artistes (all-time) ────────────────────────────
          if (_topArtists.isNotEmpty) ...[
            _SectionHeader(title: L.chartsArtistDist, icon: Icons.mic_rounded),
            const SizedBox(height: 4),
            Text(_ct('All-time', 'All-time'),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            _DonutDistributionCard(
              items:      _topArtists,
              getLabel:   (e) => (e['name'] ?? '').toString(),
              getPlays:   (e) =>
                  int.tryParse((e['playcount'] ?? '0').toString()) ?? 0,
              baseColor:  scheme.primary,
              secondColor: scheme.tertiary,
              onTap: (e) => showDetailSheet(context,
                  Map<String, dynamic>.from(e as Map), 'artists', widget.service),
            ),
            const SizedBox(height: 24),
          ],

          // ── 6. Répartition albums (all-time) ──────────────────────────────
          if (_topAlbums.isNotEmpty) ...[
            _SectionHeader(
              title: _ct('Répartition par album', 'Album distribution'),
              icon: Icons.album_rounded,
            ),
            const SizedBox(height: 4),
            Text(_ct('All-time', 'All-time'),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            _DonutDistributionCard(
              items:      _topAlbums,
              getLabel:   (e) => (e['name'] ?? '').toString(),
              getPlays:   (e) =>
                  int.tryParse((e['playcount'] ?? '0').toString()) ?? 0,
              baseColor:  scheme.secondary,
              secondColor: scheme.primary,
              onTap: (e) => showDetailSheet(context,
                  Map<String, dynamic>.from(e as Map), 'albums', widget.service),
            ),
            const SizedBox(height: 24),
          ],

          // ── 7. Calendrier musical ─────────────────────────────────────────
          _SectionHeader(
            title: _ct('Calendrier musical', 'Listening calendar'),
            icon: Icons.grid_on_rounded,
          ),
          const SizedBox(height: 4),
          Text(
            hasFullData
                ? _ct(
                    'Activité journalière — $_selectedYear',
                    'Daily activity — $_selectedYear',
                  )
                : _ct(
                    'Activité journalière sur 12 mois',
                    'Daily activity over 12 months',
                  ),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_calendarLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_calendarData != null)
            _CalendarCard(data: _calendarData!, year: _selectedYear,
                fullYear: hasFullData),
          const SizedBox(height: 20),
        ],
      ),
      ),
      ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Shared helpers
// ══════════════════════════════════════════════════════════════════════════

/// Card decoration commune : surface M3, bord léger.
BoxDecoration _chartCardDecoration(ColorScheme s) => BoxDecoration(
  color: s.surfaceContainerLow,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: s.outlineVariant.withValues(alpha: 0.50), width: 1),
);

Widget _scrollHint(BuildContext context) {
  final s = Theme.of(context).colorScheme;
  final t = Theme.of(context).textTheme;
  return Center(
    child: Text(
      _ct('← glisser pour naviguer', '← swipe to navigate'),
      style: t.labelSmall?.copyWith(
          fontSize: 9, color: s.onSurfaceVariant.withValues(alpha: 0.5)),
    ),
  );
}

/// Palette M3 : interpole entre [base] et [second] puis HSL pour les suivants.
List<Color> _buildPalette(Color base, Color second, int count) {
  if (count == 0) return [];
  if (count == 1) return [base];

  return List.generate(count, (i) {
    final t = i / (count - 1);
    if (t <= 1.0) {
      final hslA = HSLColor.fromColor(base);
      final hslB = HSLColor.fromColor(second);
      double hueDiff = (hslB.hue - hslA.hue + 540) % 360 - 180;
      return HSLColor.fromAHSL(
        1.0,
        (hslA.hue + hueDiff * t + 360) % 360,
        (hslA.saturation + (hslB.saturation - hslA.saturation) * t)
            .clamp(0.40, 0.90),
        (hslA.lightness  + (hslB.lightness  - hslA.lightness)  * t)
            .clamp(0.35, 0.65),
      ).toColor();
    }
    return base;
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  _MonthlyCard — barres mensuelles scrollables
// ══════════════════════════════════════════════════════════════════════════

class _MonthlyCard extends StatefulWidget {
  final Map<String, int> monthly;
  const _MonthlyCard({required this.monthly});

  @override
  State<_MonthlyCard> createState() => _MonthlyCardState();
}

class _MonthlyCardState extends State<_MonthlyCard> {
  final _sc = ScrollController();
  static const _colW    = 46.0;
  static const _barMaxH = 100.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
    });
  }

  @override
  void dispose() { _sc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s      = Theme.of(context).colorScheme;
    final t      = Theme.of(context).textTheme;
    final sorted = widget.monthly.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxVal = sorted.isEmpty ? 1
        : sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final total  = sorted.fold<int>(0, (acc, e) => acc + e.value);
    final avg    = sorted.isEmpty ? 0 : (total / sorted.length).round();

    return Container(
      decoration: _chartCardDecoration(s),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, children: [
            _ChipStat(label: _ct('Total', 'Total'), value: _fmt(total), s: s, t: t),
            _ChipStat(label: _ct('Moy./mois', 'Avg/mo'), value: _fmt(avg), s: s, t: t),
          ]),
          const SizedBox(height: 16),

          // Y-axis fixe + barres scrollables
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Axe Y : 3 niveaux
            SizedBox(
              width: 34,
              height: _barMaxH + 14,
              child: Stack(
                children: [
                  Positioned(top: 0, right: 4,
                      child: Text(_fmt(maxVal),
                          style: t.labelSmall?.copyWith(
                              fontSize: 8, color: s.onSurfaceVariant))),
                  Positioned(top: _barMaxH * 0.5 - 5, right: 4,
                      child: Text(_fmt(maxVal ~/ 2),
                          style: t.labelSmall?.copyWith(
                              fontSize: 8, color: s.onSurfaceVariant.withValues(alpha: 0.6)))),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _sc,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: sorted.map((e) {
                    final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
                    final barH  = (_barMaxH * ratio).clamp(2.0, _barMaxH);
                    final isMax = e.value == maxVal;
                    final color = isMax
                        ? s.primary
                        : Color.lerp(s.primaryContainer, s.primary, ratio * 0.75)!;
                    return SizedBox(
                      width: _colW,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            ratio > 0.12 ? _fmtExact(e.value) : '',
                            textAlign: TextAlign.center,
                            style: t.labelSmall?.copyWith(
                              fontSize: 8,
                              color: isMax ? s.primary : s.onSurfaceVariant,
                              fontWeight: isMax ? FontWeight.w800 : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: _colW - 10,
                              height: barH,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.key.substring(5),
                            textAlign: TextAlign.center,
                            style: t.labelSmall?.copyWith(
                              fontSize: 9,
                              color: isMax ? s.primary : s.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          _scrollHint(context),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _CumulativeLineCard — ligne cumulative avec axe Y fixe
// ══════════════════════════════════════════════════════════════════════════

class _CumulativeLineCard extends StatefulWidget {
  final Map<String, int> data;
  const _CumulativeLineCard({required this.data});

  @override
  State<_CumulativeLineCard> createState() => _CumulativeLineCardState();
}

class _CumulativeLineCardState extends State<_CumulativeLineCard> {
  final _sc = ScrollController();
  static const _ptW    = 42.0;
  static const _chartH = 130.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
    });
  }

  @override
  void dispose() { _sc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s    = Theme.of(context).colorScheme;
    final t    = Theme.of(context).textTheme;
    final keys = widget.data.keys.toList()..sort();
    final vals = keys.map((k) => widget.data[k]!.toDouble()).toList();
    final maxVal = vals.isEmpty ? 0.0 : vals.last;
    final total  = vals.isEmpty ? 0 : vals.last.toInt();

    String bestMonth = ''; int bestDelta = 0;
    for (var i = 1; i < keys.length; i++) {
      final delta = widget.data[keys[i]]! - widget.data[keys[i - 1]]!;
      if (delta > bestDelta) { bestDelta = delta; bestMonth = keys[i]; }
    }

    final contentW = (_ptW * keys.length).clamp(1.0, double.infinity);

    // 4 niveaux Y : 100%, 75%, 50%, 25% du max
    final yLevels = [1.0, 0.75, 0.50, 0.25];

    return Container(
      decoration: _chartCardDecoration(s),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, children: [
            _ChipStat(label: _ct('Total', 'Total'), value: _fmt(total), s: s, t: t),
            if (bestMonth.isNotEmpty)
              _ChipStat(
                label: _ct('Meilleur mois', 'Best month'),
                value: '${bestMonth.substring(5)} (+${_fmt(bestDelta)})',
                s: s, t: t,
              ),
          ]),
          const SizedBox(height: 16),

          // Axe Y fixe + graphique scrollable
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Axe Y
            SizedBox(
              width: 38,
              height: _chartH,
              child: Stack(
                children: yLevels.map((ratio) {
                  final topFrac = 1.0 - ratio * 0.88;
                  return Positioned(
                    top: _chartH * topFrac - 7,
                    right: 4,
                    child: Text(
                      _fmt((maxVal * ratio).round()),
                      style: t.labelSmall?.copyWith(
                        fontSize: 8,
                        color: ratio == 1.0
                            ? s.primary
                            : s.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Zone scrollable
            Expanded(
              child: SingleChildScrollView(
                controller: _sc,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: contentW,
                      height: _chartH,
                      child: CustomPaint(
                        painter: _LinePainter(
                          keys:      keys,
                          values:    vals,
                          color:     s.primary,
                          gridColor: s.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: contentW,
                      child: Row(
                        children: keys.asMap().entries.map((e) {
                          final show = keys.length <= 12
                              || e.key % (keys.length ~/ 8).clamp(1, 99) == 0
                              || e.key == keys.length - 1;
                          return SizedBox(
                            width: _ptW,
                            child: show
                                ? Text(
                                    e.value.substring(5),
                                    textAlign: TextAlign.center,
                                    style: t.labelSmall?.copyWith(
                                        fontSize: 8, color: s.onSurfaceVariant),
                                  )
                                : const SizedBox.shrink(),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          _scrollHint(context),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<String> keys;
  final List<double> values;
  final Color        color;
  final Color        gridColor;
  const _LinePainter({
    required this.keys,
    required this.values,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2) return;
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final w = size.width;
    final h = size.height;

    // ── Lignes de grille horizontales ─────────────────────────────────────
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;
    for (final ratio in [1.0, 0.75, 0.50, 0.25]) {
      final y = h - ratio * h * 0.88;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    final pts = List.generate(n, (i) => Offset(
      i * w / (n - 1),
      h - (values[i] / maxVal) * h * 0.88,
    ));

    // ── Remplissage dégradé ───────────────────────────────────────────────
    final fill = Path()
      ..moveTo(pts[0].dx, h)
      ..lineTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      final cx = (pts[i - 1].dx + pts[i].dx) / 2;
      fill.cubicTo(cx, pts[i - 1].dy, cx, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    fill..lineTo(pts.last.dx, h)..close();
    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.03)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // ── Ligne ─────────────────────────────────────────────────────────────
    final line = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      final cx = (pts[i - 1].dx + pts[i].dx) / 2;
      line.cubicTo(cx, pts[i - 1].dy, cx, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(line, Paint()
      ..color = color ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round);

    // ── Point final ───────────────────────────────────────────────────────
    canvas.drawCircle(pts.last, 6, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawCircle(pts.last, 3.5, Paint()..color = color);
    canvas.drawCircle(pts.last, 1.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.color != color;
}

// ══════════════════════════════════════════════════════════════════════════
//  _TagsCard
// ══════════════════════════════════════════════════════════════════════════

class _TagsCard extends StatelessWidget {
  final List<_TagEntry> tags;
  const _TagsCard({required this.tags});

  @override
  Widget build(BuildContext context) {
    final s      = Theme.of(context).colorScheme;
    final t      = Theme.of(context).textTheme;
    final palette = _buildPalette(s.primary, s.tertiary, tags.length);
    final maxVal  = tags.isEmpty ? 1
        : tags.map((e) => e.count).reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: _chartCardDecoration(s),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: tags.asMap().entries.map((e) {
          final ratio = maxVal > 0 ? e.value.count / maxVal : 0.0;
          final color = palette[e.key % palette.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(e.value.name,
                    style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${(ratio * 100).round()}%',
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio, minHeight: 7,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _HourlyBarCard — répartition horaire
// ══════════════════════════════════════════════════════════════════════════

class _HourlyBarCard extends StatefulWidget {
  final Map<int, int> data;
  const _HourlyBarCard({required this.data});

  @override
  State<_HourlyBarCard> createState() => _HourlyBarCardState();
}

class _HourlyBarCardState extends State<_HourlyBarCard> {
  final _sc = ScrollController();
  static const _colW        = 33.0;
  static const _barMaxH     = 90.0;
  static const _kBandLabelH = 20.0;

  static const _bands = [
    (start: 0,  end: 5,  emoji: '🌙', fr: 'Nuit',       en: 'Night'),
    (start: 6,  end: 11, emoji: '☀️', fr: 'Matin',       en: 'Morning'),
    (start: 12, end: 17, emoji: '🌤', fr: 'Après-midi',  en: 'Afternoon'),
    (start: 18, end: 23, emoji: '🌆', fr: 'Soir',        en: 'Evening'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sc.hasClients) return;
      final peakH = widget.data.isEmpty ? 0
          : widget.data.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      final target = (peakH * _colW - 120.0)
          .clamp(0.0, _sc.position.maxScrollExtent);
      _sc.animateTo(target,
          duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() { _sc.dispose(); super.dispose(); }

  static String _emoji(int h) {
    if (h <= 5)  return '🌙';
    if (h <= 11) return '☀️';
    if (h <= 17) return '🌤';
    return '🌆';
  }

  @override
  Widget build(BuildContext context) {
    final s      = Theme.of(context).colorScheme;
    final t      = Theme.of(context).textTheme;
    final maxVal = widget.data.values.fold(0, (a, b) => a > b ? a : b);
    final peakH  = widget.data.isEmpty ? 0
        : widget.data.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final isEn   = localeNotifier.value == 'en';

    final bandColors = [
      s.primaryContainer.withValues(alpha: 0.08),
      s.tertiaryContainer.withValues(alpha: 0.10),
      s.secondaryContainer.withValues(alpha: 0.10),
      s.primaryContainer.withValues(alpha: 0.08),
    ];

    return Container(
      decoration: _chartCardDecoration(s),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_ct('Répartition horaire', 'Hourly distribution'),
                style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            _PeakChip(
              label: '${_emoji(peakH)} ${peakH}h',
              color: s.primaryContainer, onColor: s.onPrimaryContainer, t: t,
            ),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 30,
              height: _kBandLabelH + _barMaxH + 24,
              child: Stack(
                children: [
                  Positioned(top: _kBandLabelH, right: 4,
                      child: Text(_fmt(maxVal),
                          style: t.labelSmall?.copyWith(
                              fontSize: 8, color: s.onSurfaceVariant))),
                  Positioned(top: _kBandLabelH + _barMaxH * 0.5 - 5, right: 4,
                      child: Text(_fmt(maxVal ~/ 2),
                          style: t.labelSmall?.copyWith(
                              fontSize: 8,
                              color: s.onSurfaceVariant.withValues(alpha: 0.55)))),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _sc,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: 24 * _colW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: _bands.map((b) {
                          final bandW = (b.end - b.start + 1) * _colW;
                          final label = isEn ? b.en : b.fr;
                          return Container(
                            width: bandW,
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('${b.emoji} $label',
                                textAlign: TextAlign.center,
                                style: t.labelSmall?.copyWith(
                                    fontSize: 9,
                                    color: s.onSurfaceVariant.withValues(alpha: 0.7))),
                          );
                        }).toList(),
                      ),
                      Stack(
                        alignment: Alignment.bottomLeft,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: _bands.asMap().entries.map((e) {
                              final b = e.value;
                              final bandW = (b.end - b.start + 1) * _colW;
                              return Container(
                                width: bandW,
                                height: _barMaxH + 20,
                                decoration: BoxDecoration(
                                  color: bandColors[e.key],
                                  border: Border(
                                    left: BorderSide(
                                      color: s.outlineVariant.withValues(alpha: 0.25),
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(24, (h) {
                              final v      = widget.data[h] ?? 0;
                              final ratio  = maxVal > 0 ? v / maxVal : 0.0;
                              final barH   = (_barMaxH * ratio).clamp(2.0, _barMaxH);
                              final isPeak = h == peakH;
                              final color  = isPeak
                                  ? s.primary
                                  : Color.lerp(
                                      s.primaryContainer, s.primary, ratio * 0.8)!;
                              return SizedBox(
                                width: _colW,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      (isPeak || ratio > 0.20) && v > 0
                                          ? _fmt(v)
                                          : '',
                                      style: t.labelSmall?.copyWith(
                                          fontSize: 8,
                                          color: isPeak ? s.primary : s.onSurfaceVariant,
                                          fontWeight: isPeak
                                              ? FontWeight.w800 : FontWeight.w500),
                                    ),
                                    const SizedBox(height: 2),
                                    Center(
                                      child: Container(
                                        width: _colW - 8,
                                        height: barH,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: const BorderRadius.vertical(
                                              top: Radius.circular(4)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (h % 6 == 0 || isPeak) ? '${h}h' : '',
                                      style: t.labelSmall?.copyWith(
                                        fontSize: 8,
                                        color: isPeak
                                            ? s.primary
                                            : s.onSurfaceVariant.withValues(alpha: 0.7),
                                        fontWeight: isPeak
                                            ? FontWeight.w800 : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          _scrollHint(context),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _WeekdayBarCard — 7 barres pleine largeur
// ══════════════════════════════════════════════════════════════════════════

class _WeekdayBarCard extends StatelessWidget {
  final Map<int, int> data;
  const _WeekdayBarCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final s       = Theme.of(context).colorScheme;
    final t       = Theme.of(context).textTheme;
    final labels  = _chartWeekdayLabels;
    final maxVal  = data.values.fold(0, (a, b) => a > b ? a : b);
    final peakDay = data.isEmpty ? 1
        : data.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return Container(
      decoration: _chartCardDecoration(s),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_ct('Activité par jour de la semaine', 'Activity by day of week'),
                style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            _PeakChip(
              label: '📅 ${labels[peakDay - 1]}',
              color: s.secondaryContainer, onColor: s.onSecondaryContainer, t: t,
            ),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (_, constraints) {
            const barMaxH = 90.0;
            final colW    = constraints.maxWidth / 7;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final day   = i + 1;
                final v     = data[day] ?? 0;
                final ratio = maxVal > 0 ? v / maxVal : 0.0;
                final barH  = (barMaxH * ratio).clamp(2.0, barMaxH);
                final isPeak = day == peakDay;
                final color = isPeak
                    ? s.secondary
                    : Color.lerp(s.secondaryContainer, s.secondary, ratio * 0.8)!;
                return SizedBox(
                  width: colW,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(v > 0 ? _fmt(v) : '',
                          style: t.labelSmall?.copyWith(
                            fontSize: 8,
                            color: isPeak ? s.secondary : s.onSurfaceVariant,
                            fontWeight: isPeak ? FontWeight.w800 : FontWeight.normal,
                          )),
                      const SizedBox(height: 2),
                      Center(
                        child: Container(
                          width: colW - 10,
                          height: barH,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(labels[i], textAlign: TextAlign.center,
                          style: t.labelSmall?.copyWith(
                            fontSize: 10,
                            color: isPeak ? s.secondary : s.onSurfaceVariant,
                            fontWeight: isPeak ? FontWeight.w800 : FontWeight.normal,
                          )),
                    ],
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _DonutDistributionCard
// ══════════════════════════════════════════════════════════════════════════

class _DonutDistributionCard extends StatelessWidget {
  final List<dynamic>            items;
  final String Function(dynamic) getLabel;
  final int    Function(dynamic) getPlays;
  final Color                    baseColor;
  final Color                    secondColor;
  final void   Function(dynamic) onTap;
  const _DonutDistributionCard({
    required this.items,
    required this.getLabel,
    required this.getPlays,
    required this.baseColor,
    required this.secondColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s       = Theme.of(context).colorScheme;
    final t       = Theme.of(context).textTheme;
    final vals    = items.map(getPlays).toList();
    final total   = vals.fold<int>(0, (a, b) => a + b);
    final palette = _buildPalette(baseColor, secondColor, items.length);

    return Container(
      decoration: _chartCardDecoration(s),
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130, height: 130,
          child: CustomPaint(
            painter: _DonutPainter(
              values:    vals.map((v) => v.toDouble()).toList(),
              colors:    palette,
              holeColor: s.surfaceContainerLow,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.asMap().entries.map((e) {
              final plays = getPlays(e.value);
              final pct   = total > 0 ? (plays / total * 100).round() : 0;
              final color = palette[e.key % palette.length];
              return GestureDetector(
                onTap: () => onTap(e.value),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(getLabel(e.value),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Text('$pct%',
                        style: t.bodySmall?.copyWith(
                            color: s.onSurfaceVariant, fontSize: 10)),
                    const SizedBox(width: 4),
                    Text(_fmt(plays),
                        style: t.bodySmall?.copyWith(
                            color: color, fontWeight: FontWeight.w700, fontSize: 10)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color>  colors;
  final Color        holeColor;
  const _DonutPainter({required this.values, required this.colors, required this.holeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2; final cy = size.height / 2;
    final r  = (size.shortestSide / 2) - 4;
    final inner = r * 0.52;
    final total = values.fold(0.0, (a, b) => a + b);
    if (total == 0) return;

    double sweep = -_kHalfPi;
    const gap = 0.02;
    for (var i = 0; i < values.length; i++) {
      final angle = (values[i] / total) * _kTwoPi - gap;
      if (angle <= 0) continue;
      final path = Path()
        ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r), sweep, angle, false)
        ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: inner),
            sweep + angle, -angle, false)
        ..close();
      canvas.drawPath(path, Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill ..isAntiAlias = true);
      sweep += angle + gap;
    }
    canvas.drawCircle(Offset(cx, cy), inner - 1, Paint()..color = holeColor);
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values || old.colors != colors;
}

// ══════════════════════════════════════════════════════════════════════════
//  _CalendarCard — heatmap annuelle avec statistiques
// ══════════════════════════════════════════════════════════════════════════

class _CalendarCard extends StatefulWidget {
  final Map<String, int> data;
  final int  year;
  final bool fullYear; // true = données complètes depuis AllScrobblesService
  const _CalendarCard({
    required this.data,
    required this.year,
    this.fullYear = false,
  });

  @override
  State<_CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<_CalendarCard> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) {
        // Pour l'année en cours → scroller à la fin ; pour le passé → début
        final isCurrentYear = widget.year == DateTime.now().year;
        if (isCurrentYear) {
          _sc.jumpTo(_sc.position.maxScrollExtent);
        }
      }
    });
  }

  @override
  void dispose() { _sc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s   = Theme.of(context).colorScheme;
    final t   = Theme.of(context).textTheme;

    // Toujours afficher les 12 mois de l'année sélectionnée
    final months = List.generate(
        12, (i) => DateTime(widget.year, i + 1, 1));

    final maxVal = widget.data.values.fold(0, (a, b) => a > b ? a : b);

    final totalAll   = widget.data.values.fold(0, (a, b) => a + b);
    final activeDays = widget.data.entries.where((e) => e.value > 0).length;
    String bestDay = ''; int bestCount = 0;
    for (final e in widget.data.entries) {
      if (e.value > bestCount) { bestCount = e.value; bestDay = e.key; }
    }

    return Container(
      decoration: _chartCardDecoration(s),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            _ChipStat(
              label: widget.fullYear
                  ? '${widget.year}'
                  : _ct('12 mois', '12 months'),
              value: _fmt(totalAll), s: s, t: t,
            ),
            _ChipStat(
              label: _ct('Jours actifs', 'Active days'),
              value: '$activeDays', s: s, t: t,
            ),
            if (bestDay.isNotEmpty)
              _ChipStat(
                label: _ct('Record', 'Record'),
                value: '${bestDay.substring(5)} ($bestCount)',
                s: s, t: t,
              ),
          ]),
          const SizedBox(height: 14),
          SingleChildScrollView(
            controller: _sc,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: months.map((m) => Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _MonthHeatGrid(
                    month: m, data: widget.data, maxVal: maxVal, s: s, t: t),
              )).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _scrollHint(context),
            const Spacer(),
            Text(_ct('Moins', 'Less'),
                style: t.labelSmall?.copyWith(fontSize: 9, color: s.onSurfaceVariant)),
            const SizedBox(width: 4),
            ...List.generate(5, (i) => Container(
              width: 11, height: 11,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i == 0
                    ? s.surfaceContainerHigh
                    : Color.lerp(s.primaryContainer, s.primary,
                                 (i / 4).clamp(0.0, 1.0)),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(width: 4),
            Text(_ct('Plus', 'More'),
                style: t.labelSmall?.copyWith(fontSize: 9, color: s.onSurfaceVariant)),
          ]),
        ],
      ),
    );
  }
}

class _MonthHeatGrid extends StatelessWidget {
  final DateTime        month;
  final Map<String, int> data;
  final int             maxVal;
  final ColorScheme     s;
  final TextTheme       t;
  const _MonthHeatGrid({
    required this.month, required this.data,
    required this.maxVal, required this.s, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWd     = DateTime(month.year, month.month, 1).weekday;
    final label       = L.months[month.month];
    const cellSz      = 18.0;
    const gap         = 3.0;
    const cols        = 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label ${month.year}',
            style: t.labelSmall?.copyWith(
                color: s.onSurfaceVariant, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SizedBox(
          width: cols * (cellSz + gap) - gap,
          child: Wrap(
            spacing: gap, runSpacing: gap,
            children: [
              ...List.generate(firstWd - 1,
                  (_) => SizedBox(width: cellSz, height: cellSz)),
              ...List.generate(daysInMonth, (d) {
                final day   = d + 1;
                final key   = '${month.year}-'
                    '${month.month.toString().padLeft(2, '0')}-'
                    '${day.toString().padLeft(2, '0')}';
                final count = data[key] ?? 0;
                final ratio       = (maxVal > 0 && count > 0) ? count / maxVal : 0.0;
                final scaledRatio = ratio > 0 ? sqrt(ratio).clamp(0.0, 1.0) : 0.0;
                final color       = count == 0
                    ? s.surfaceContainerHigh
                    : Color.lerp(s.primaryContainer, s.primary,
                                 (scaledRatio * 0.85 + 0.15).clamp(0.0, 1.0))!;
                return Tooltip(
                  message: count > 0 ? '$day — $count scrobbles' : '',
                  child: Container(
                    width: cellSz, height: cellSz,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(3)),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Small sub-widgets
// ══════════════════════════════════════════════════════════════════════════

class _ChipStat extends StatelessWidget {
  final String label, value;
  final ColorScheme s;
  final TextTheme   t;
  const _ChipStat({required this.label, required this.value,
      required this.s, required this.t});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: s.primaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
          color: s.primary.withValues(alpha: 0.15), width: 1),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: t.labelSmall
          ?.copyWith(color: s.onPrimaryContainer.withValues(alpha: 0.75))),
      const SizedBox(width: 5),
      Text(value, style: t.labelSmall?.copyWith(
          color: s.onPrimaryContainer, fontWeight: FontWeight.w800)),
    ]),
  );
}

class _PeakChip extends StatelessWidget {
  final String label;
  final Color  color, onColor;
  final TextTheme t;
  const _PeakChip({required this.label, required this.color,
      required this.onColor, required this.t});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: t.labelSmall?.copyWith(color: onColor, fontWeight: FontWeight.w700)),
  );
}

class _TagEntry {
  final String name; final int count;
  const _TagEntry({required this.name, required this.count});
}
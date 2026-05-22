// ignore_for_file: unused_import
part of 'home_screen.dart';

// ── Bilingual inline helper (avoids touching l10n for new strings) ────────────
String _ct(String fr, String en) => localeNotifier.value == 'en' ? en : fr;

List<String> get _chartWeekdayLabels => localeNotifier.value == 'en'
    ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    : ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

// ── Page ─────────────────────────────────────────────────────────────────────

class _ChartsPage extends StatefulWidget {
  final LastFmService service;
  const _ChartsPage({required this.service});

  @override
  State<_ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<_ChartsPage>
    with AutomaticKeepAliveClientMixin {
  // ── Core data ─────────────────────────────────────────────────────────
  Map<String, int>? _monthly;
  List<dynamic> _topArtists = [];
  List<dynamic> _topAlbums  = [];
  List<dynamic> _topTracks  = [];
  bool _loading = true;
  String? _error;

  // ── Gems ──────────────────────────────────────────────────────────────
  bool _gemsLoading = false;
  List<_GemEntry> _gems = [];

  // ── Listening habits (hourly / weekday) ───────────────────────────────
  bool _hourlyLoading = false;
  Map<int, int>? _hourlyData;   // hour  0-23  → count
  Map<int, int>? _weekdayData;  // weekday 1-7 → count
  int _hourlyCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data loading ──────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Future.wait([
        widget.service.getMonthlyScrobbles(months: 12),
        widget.service.getTopArtists(period: 'overall', limit: 10),
        widget.service.getTopAlbums(period: 'overall',  limit: 10),
        widget.service.getTopTracks(period: 'overall',  limit: 10),
      ]);
      setState(() {
        _monthly    = res[0] as Map<String, int>;
        _topArtists = res[1] as List<dynamic>;
        _topAlbums  = res[2] as List<dynamic>;
        _topTracks  = res[3] as List<dynamic>;
        _loading    = false;
      });
    } catch (e) {
      setState(() {
        _error   = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Fetches last ~200 tracks and builds hourly / weekday histograms.
  Future<void> _loadHourly() async {
    setState(() {
      _hourlyLoading = true;
      _hourlyData    = null;
      _weekdayData   = null;
      _hourlyCount   = 0;
    });
    try {
      // 4 pages × 50 = up to 200 tracks
      final pages = await Future.wait(
        List.generate(4, (i) => widget.service.getRecentTracks(limit: 50, page: i + 1)),
      );
      final hours    = <int, int>{for (var i = 0;  i < 24; i++) i: 0};
      final weekdays = <int, int>{for (var i = 1;  i <= 7; i++) i: 0};
      int count = 0;

      for (final page in pages) {
        final trackRaw = page['track'];
        final list = trackRaw is List
            ? trackRaw
            : (trackRaw != null ? [trackRaw] : <dynamic>[]);
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
      setState(() {
        _hourlyData    = hours;
        _weekdayData   = weekdays;
        _hourlyCount   = count;
        _hourlyLoading = false;
      });
    } catch (_) {
      setState(() => _hourlyLoading = false);
    }
  }

  Future<void> _computeGems() async {
    if (_topArtists.isEmpty) return;
    setState(() { _gemsLoading = true; _gems = []; });
    List<dynamic> artists;
    try {
      artists = await widget.service.getTopArtists(period: 'overall', limit: 15);
    } catch (_) {
      artists = _topArtists.take(15).toList();
    }
    final listeners = await Future.wait(
        artists.map((a) => widget.service.getArtistListeners(
            (a['name'] ?? '').toString())));
    final entries = <_GemEntry>[];
    for (var i = 0; i < artists.length; i++) {
      entries.add(_GemEntry(
        name:      (artists[i]['name']      ?? '').toString(),
        plays:     int.tryParse((artists[i]['playcount'] ?? '0').toString()) ?? 0,
        listeners: listeners[i] ?? 0,
      ));
    }
    entries.sort((a, b) => a.listeners.compareTo(b.listeners));
    setState(() { _gems = entries; _gemsLoading = false; });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    if (_loading)       return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

    final monthly = _monthly!;
    final maxMonthly = monthly.values.fold(0, (a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(L.chartsTitle,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),

        // ── 1. Monthly bar chart ──────────────────────────────────────────
        _SectionHeader(title: L.chartsMonthly, icon: Icons.calendar_month_rounded),
        const SizedBox(height: 12),
        _MonthlyCard(monthly: monthly, maxVal: maxMonthly),
        const SizedBox(height: 24),

        // ── 2. Top albums distribution ────────────────────────────────────
        if (_topAlbums.isNotEmpty) ...[
          _SectionHeader(
            title: _ct('Top albums — distribution', 'Top albums — distribution'),
            icon: Icons.album_rounded,
          ),
          const SizedBox(height: 12),
          _DistributionCard(
            items:    _topAlbums,
            getLabel: (e) => (e['name']                ?? '').toString(),
            getSub:   (e) => (e['artist']?['name']     ?? '').toString(),
            getPlays: (e) => int.tryParse((e['playcount'] ?? '0').toString()) ?? 0,
            barColor: scheme.secondary,
            onTap: (e) => showDetailSheet(
              context,
              Map<String, dynamic>.from(e as Map),
              'albums',
              widget.service,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── 3. Artist distribution ────────────────────────────────────────
        _SectionHeader(title: L.chartsArtistDist, icon: Icons.mic_rounded),
        const SizedBox(height: 12),
        if (_topArtists.isNotEmpty) _DistributionCard(
          items:    _topArtists,
          getLabel: (e) => (e['name']            ?? '').toString(),
          getSub:   (_) => '',
          getPlays: (e) => int.tryParse((e['playcount'] ?? '0').toString()) ?? 0,
          barColor: scheme.primary,
          onTap: (e) => showDetailSheet(
            context,
            Map<String, dynamic>.from(e as Map),
            'artists',
            widget.service,
          ),
        ),
        const SizedBox(height: 24),

        // ── 4. Top tracks distribution ────────────────────────────────────
        if (_topTracks.isNotEmpty) ...[
          _SectionHeader(
            title: _ct('Top titres — distribution', 'Top tracks — distribution'),
            icon: Icons.music_note_rounded,
          ),
          const SizedBox(height: 12),
          _DistributionCard(
            items:    _topTracks,
            getLabel: (e) => (e['name']              ?? '').toString(),
            getSub:   (e) => (e['artist']?['name']   ?? '').toString(),
            getPlays: (e) => int.tryParse((e['playcount'] ?? '0').toString()) ?? 0,
            barColor: scheme.tertiary,
            onTap: (e) => showDetailSheet(
              context,
              Map<String, dynamic>.from(e as Map),
              'tracks',
              widget.service,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── 5. Listening habits ───────────────────────────────────────────
        _SectionHeader(
          title: _ct("Habitudes d'écoute", 'Listening habits'),
          icon: Icons.access_time_rounded,
        ),
        const SizedBox(height: 8),
        Text(
          _hourlyCount > 0
              ? _ct('Basé sur $_hourlyCount scrobbles récents',
                    'Based on $_hourlyCount recent scrobbles')
              : _ct('Analyse vos ~200 derniers scrobbles',
                    'Analyses your last ~200 scrobbles'),
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (_hourlyData == null && !_hourlyLoading)
          FilledButton.icon(
            onPressed: _loadHourly,
            icon: const Icon(Icons.bar_chart_rounded),
            label: Text(_ct('Analyser', 'Analyse')),
          )
        else if (_hourlyLoading)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else ...[
          _HourlyBarCard(data: _hourlyData!),
          const SizedBox(height: 12),
          _WeekdayBarCard(data: _weekdayData!),
          const SizedBox(height: 4),
          Center(child: TextButton(
            onPressed: _loadHourly,
            child: Text(_ct('Recalculer', 'Recalculate')),
          )),
        ],
        const SizedBox(height: 24),

        // ── 6. Mainstream vs gems ─────────────────────────────────────────
        _SectionHeader(title: L.chartsMainstreamTitle, icon: Icons.diamond_outlined),
        const SizedBox(height: 8),
        Text(L.chartsMainstreamSubtitle,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (_gems.isEmpty && !_gemsLoading)
          FilledButton.icon(
            onPressed: _computeGems,
            icon: const Icon(Icons.calculate_rounded),
            label: Text(L.chartsCompute),
          )
        else if (_gemsLoading)
          const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ))
        else ...[
          _GemsListenersChart(gems: _gems),
          const SizedBox(height: 12),
          ..._gems.map((gem) {
            final isGem = gem.listeners < 500000;
            return Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: _cardBorder(scheme)),
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: Text(isGem ? '💎' : '🎤',
                    style: const TextStyle(fontSize: 24)),
                title: Text(gem.name,
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text(L.globalListeners(_fmt(gem.listeners)),
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                trailing: Text(
                  isGem ? L.chartsGem : L.chartsMainstream,
                  style: text.labelSmall?.copyWith(
                    color: isGem ? scheme.tertiary : scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => showDetailSheet(
                  context,
                  {'name': gem.name},
                  'artists',
                  widget.service,
                ),
              ),
            );
          }),
          Center(child: TextButton(
            onPressed: _computeGems,
            child: Text(L.chartsRecompute),
          )),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _MonthlyCard
// ══════════════════════════════════════════════════════════════════════════

class _MonthlyCard extends StatelessWidget {
  final Map<String, int> monthly;
  final int maxVal;
  const _MonthlyCard({required this.monthly, required this.maxVal});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final total  = monthly.values.fold(0, (a, b) => a + b);
    final avg    = monthly.isNotEmpty ? (total / monthly.length).round() : 0;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Mini summary row
          Row(children: [
            _ChipStat(label: _ct('Total', 'Total'),  value: _fmt(total), scheme: scheme, text: text),
            const SizedBox(width: 8),
            _ChipStat(label: _ct('Moy./mois', 'Avg/mo'), value: _fmt(avg), scheme: scheme, text: text),
          ]),
          const SizedBox(height: 16),
          // Bars
          SizedBox(height: 140, child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: monthly.entries.map((e) {
              final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
              final isMax = e.value == maxVal && maxVal > 0;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (ratio > 0)
                    Text(_fmt(e.value),
                        style: text.labelSmall?.copyWith(
                            fontSize: 8,
                            color: isMax
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontWeight: isMax ? FontWeight.w800 : FontWeight.normal)),
                  const SizedBox(height: 2),
                  Flexible(fit: FlexFit.loose,
                    child: FractionallySizedBox(
                      heightFactor: ratio.clamp(0.02, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isMax
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.35 + ratio * 0.55),
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(e.key.substring(5),
                      style: text.labelSmall?.copyWith(fontSize: 9)),
                ]),
              ));
            }).toList(),
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _DistributionCard  (artistes, albums, titres)
// ══════════════════════════════════════════════════════════════════════════

class _DistributionCard extends StatelessWidget {
  final List<dynamic>        items;
  final String Function(dynamic) getLabel;
  final String Function(dynamic) getSub;
  final int    Function(dynamic) getPlays;
  final Color                barColor;
  final void   Function(dynamic) onTap;

  const _DistributionCard({
    required this.items,
    required this.getLabel,
    required this.getSub,
    required this.getPlays,
    required this.barColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final mx     = items.map(getPlays).fold(0, (a, b) => a > b ? a : b);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: items.asMap().entries.map((e) {
            final plays = getPlays(e.value);
            final ratio = mx > 0 ? plays / mx : 0.0;
            final label = getLabel(e.value);
            final sub   = getSub(e.value);
            return GestureDetector(
              onTap: () => onTap(e.value),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: 22, child: Text('${e.key + 1}',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: text.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (sub.isNotEmpty)
                          Text(sub,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: text.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    )),
                    const SizedBox(width: 8),
                    Expanded(flex: 5, child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        backgroundColor: barColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    )),
                    const SizedBox(width: 8),
                    Text(_fmt(plays), style: text.bodySmall?.copyWith(
                        color: barColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _HourlyBarCard  — 24-bar chart
// ══════════════════════════════════════════════════════════════════════════

class _HourlyBarCard extends StatelessWidget {
  final Map<int, int> data;
  const _HourlyBarCard({required this.data});

  String _peakEmoji(int h) {
    if (h < 6)  return '🌙';
    if (h < 12) return '☀️';
    if (h < 18) return '🌤';
    return '🌆';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final maxVal = data.values.fold(0, (a, b) => a > b ? a : b);
    final peakH  = data.isEmpty ? 0
        : data.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_ct('Par heure', 'By hour'),
                style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            _PeakChip(
              label: '${_peakEmoji(peakH)} ${peakH}h',
              color: scheme.primaryContainer,
              onColor: scheme.onPrimaryContainer,
              text: text,
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(height: 100, child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (h) {
              final v      = data[h] ?? 0;
              final ratio  = maxVal > 0 ? v / maxVal : 0.0;
              final isPeak = h == peakH;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Flexible(fit: FlexFit.loose,
                    child: FractionallySizedBox(
                      heightFactor: ratio.clamp(0.02, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isPeak
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.25 + ratio * 0.60),
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    h % 6 == 0 ? '${h}h' : '',
                    style: text.labelSmall?.copyWith(
                        fontSize: 8, color: scheme.onSurfaceVariant),
                  ),
                ]),
              ));
            }),
          )),
          // Time bands legend
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _BandLabel('🌙 0–5h',   scheme.onSurfaceVariant, text),
            _BandLabel('☀️ 6–11h',  scheme.onSurfaceVariant, text),
            _BandLabel('🌤 12–17h', scheme.onSurfaceVariant, text),
            _BandLabel('🌆 18–23h', scheme.onSurfaceVariant, text),
          ]),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _WeekdayBarCard  — 7-bar chart
// ══════════════════════════════════════════════════════════════════════════

class _WeekdayBarCard extends StatelessWidget {
  final Map<int, int> data; // 1 = Mon … 7 = Sun
  const _WeekdayBarCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final text    = Theme.of(context).textTheme;
    final labels  = _chartWeekdayLabels;
    final maxVal  = data.values.fold(0, (a, b) => a > b ? a : b);
    final peakDay = data.isEmpty ? 1
        : data.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_ct('Par jour', 'By day'),
                style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            _PeakChip(
              label: '📅 ${labels[peakDay - 1]}',
              color: scheme.secondaryContainer,
              onColor: scheme.onSecondaryContainer,
              text: text,
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(height: 110, child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final day    = i + 1;
              final v      = data[day] ?? 0;
              final ratio  = maxVal > 0 ? v / maxVal : 0.0;
              final isPeak = day == peakDay;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (v > 0)
                    Text(_fmt(v), style: text.labelSmall?.copyWith(
                        fontSize: 8,
                        color: isPeak ? scheme.secondary : scheme.onSurfaceVariant,
                        fontWeight: isPeak ? FontWeight.w800 : FontWeight.normal)),
                  const SizedBox(height: 2),
                  Flexible(fit: FlexFit.loose,
                    child: FractionallySizedBox(
                      heightFactor: ratio.clamp(0.02, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isPeak
                              ? scheme.secondary
                              : scheme.secondary.withValues(alpha: 0.25 + ratio * 0.60),
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(5)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(labels[i], style: text.labelSmall?.copyWith(
                      fontSize: 10,
                      color: isPeak ? scheme.secondary : scheme.onSurfaceVariant,
                      fontWeight: isPeak ? FontWeight.w800 : FontWeight.normal)),
                ]),
              ));
            }),
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _GemsListenersChart  — horizontal bar chart for gems section
// ══════════════════════════════════════════════════════════════════════════

class _GemsListenersChart extends StatelessWidget {
  final List<_GemEntry> gems;
  const _GemsListenersChart({required this.gems});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final mx     = gems.map((g) => g.listeners).fold(0, (a, b) => a > b ? a : b);
    if (mx == 0) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_ct('Auditeurs mondiaux', 'Global listeners'),
                style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...gems.map((gem) {
              final ratio  = mx > 0 ? gem.listeners / mx : 0.0;
              final isGem  = gem.listeners < 500000;
              final color  = isGem ? scheme.tertiary : scheme.primary;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Text(isGem ? '💎' : '🎤',
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: Text(gem.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Expanded(flex: 5, child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Text(_fmt(gem.listeners), style: text.bodySmall?.copyWith(
                      color: color, fontWeight: FontWeight.w600)),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Small shared sub-widgets
// ══════════════════════════════════════════════════════════════════════════

class _ChipStat extends StatelessWidget {
  final String label, value;
  final ColorScheme scheme;
  final TextTheme text;
  const _ChipStat({required this.label, required this.value,
      required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: scheme.primaryContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: text.labelSmall
          ?.copyWith(color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
      const SizedBox(width: 4),
      Text(value, style: text.labelSmall?.copyWith(
          color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800)),
    ]),
  );
}

class _PeakChip extends StatelessWidget {
  final String label;
  final Color color, onColor;
  final TextTheme text;
  const _PeakChip({required this.label, required this.color,
      required this.onColor, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: text.labelSmall
        ?.copyWith(color: onColor, fontWeight: FontWeight.w700)),
  );
}

class _BandLabel extends StatelessWidget {
  final String label;
  final Color color;
  final TextTheme text;
  const _BandLabel(this.label, this.color, this.text);

  @override
  Widget build(BuildContext context) =>
      Text(label, style: text.labelSmall?.copyWith(fontSize: 9, color: color));
}

// ══════════════════════════════════════════════════════════════════════════
//  _GemEntry  (data class)
// ══════════════════════════════════════════════════════════════════════════

class _GemEntry {
  final String name;
  final int plays, listeners;
  const _GemEntry({required this.name, required this.plays, required this.listeners});
}
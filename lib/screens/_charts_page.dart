// ignore_for_file: unused_import
part of 'home_screen.dart';

// ── Bilingual inline helper ───────────────────────────────────────────────────
String _ct(String fr, String en) => localeNotifier.value == 'en' ? en : fr;

List<String> get _chartWeekdayLabels => localeNotifier.value == 'en'
    ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    : ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

// Math constants (avoids needing dart:math import in part file)
const _kTwoPi  = 6.283185307179586;
const _kHalfPi = 1.5707963267948966;

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
  Map<String, int>? _monthly;      // 'YYYY-MM' → plays
  List<dynamic> _topArtists = [];
  List<dynamic> _topAlbums  = [];
  bool _loading = true;
  String? _error;

  // ── Listening habits ──────────────────────────────────────────────────
  bool _hourlyLoading = false;
  Map<int, int>? _hourlyData;
  Map<int, int>? _weekdayData;
  int _hourlyCount = 0;

  // ── Calendar ──────────────────────────────────────────────────────────
  bool _calendarLoading = false;
  Map<String, int>? _calendarData; // 'YYYY-MM-DD' → count

  // ── Genre tags ────────────────────────────────────────────────────────
  bool _tagsLoading = false;
  List<_TagEntry> _tags = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  // ── Main load ─────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Future.wait([
        widget.service.getMonthlyScrobbles(months: 24),
        widget.service.getTopArtists(period: 'overall', limit: 10),
        widget.service.getTopAlbums(period: 'overall',  limit: 10),
      ]);
      setState(() {
        _monthly    = res[0] as Map<String, int>;
        _topArtists = res[1] as List<dynamic>;
        _topAlbums  = res[2] as List<dynamic>;
        _loading    = false;
      });
      // Auto-load all secondary charts without user action
      _loadTags();
      _loadHourly();
      _loadCalendar();
    } catch (e) {
      setState(() {
        _error   = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ── Hourly / weekday ──────────────────────────────────────────────────

  Future<void> _loadHourly() async {
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
      final hours    = <int, int>{for (var i = 0;  i < 24; i++) i: 0};
      final weekdays = <int, int>{for (var i = 1;  i <= 7; i++) i: 0};
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
      setState(() {
        _hourlyData    = hours;
        _weekdayData   = weekdays;
        _hourlyCount   = count;
        _hourlyLoading = false;
      });
    } catch (_) { setState(() => _hourlyLoading = false); }
  }

  // ── Calendar heatmap ──────────────────────────────────────────────────

  Future<void> _loadCalendar() async {
    if (_calendarLoading) return;
    setState(() { _calendarLoading = true; _calendarData = null; });
    try {
      final pages = await Future.wait(
        List.generate(8, (i) => widget.service.getRecentTracks(limit: 50, page: i + 1)),
      );
      final data = <String, int>{};
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
          final dt  = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          data[key] = (data[key] ?? 0) + 1;
        }
      }
      setState(() { _calendarData = data; _calendarLoading = false; });
    } catch (_) { setState(() => _calendarLoading = false); }
  }

  // ── Genre tags ────────────────────────────────────────────────────────

  Future<void> _loadTags() async {
    if (_topArtists.isEmpty || _tagsLoading) return;
    setState(() { _tagsLoading = true; _tags = []; });
    try {
      final artists = _topArtists.take(10).toList();
      final tagLists = await Future.wait(
        artists.map((a) => widget.service
            .getArtistTopTags((a['name'] ?? '').toString())
            .catchError((_) => <dynamic>[])),
      );
      final agg = <String, int>{};
      for (var i = 0; i < artists.length; i++) {
        final plays = int.tryParse((artists[i]['playcount'] ?? '1').toString()) ?? 1;
        final tList = tagLists[i] as List<dynamic>;
        for (final t in tList.take(5)) {
          final name  = (t['name'] ?? '').toString().trim();
          if (name.isEmpty || name.length > 20) continue;
          // Weight by artist plays
          agg[name] = (agg[name] ?? 0) + plays;
        }
      }
      final sorted = agg.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      setState(() {
        _tags = sorted.take(8).map((e) => _TagEntry(name: e.key, count: e.value)).toList();
        _tagsLoading = false;
      });
    } catch (_) { setState(() => _tagsLoading = false); }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    if (_loading)       return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

    final monthly    = _monthly!;
    final maxMonthly = monthly.values.fold(0, (a, b) => a > b ? a : b);

    // Build cumulative series
    final sortedKeys = monthly.keys.toList()..sort();
    int cum = 0;
    final cumulData = <String, int>{};
    for (final k in sortedKeys) { cum += monthly[k]!; cumulData[k] = cum; }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        const SizedBox(height: 16),
        Text(L.chartsTitle,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(_ct('Vos écoutes en images — tendances et évolutions',
                 'Your scrobbles visualised — trends and evolutions'),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 20),

        // ── 1. Monthly bar chart ──────────────────────────────────────────
        _SectionHeader(title: L.chartsMonthly, icon: Icons.calendar_month_rounded),
        const SizedBox(height: 12),
        _MonthlyCard(monthly: monthly, maxVal: maxMonthly),
        const SizedBox(height: 24),

        // ── 2. Cumulative line chart ──────────────────────────────────────
        if (cumulData.length >= 2) ...[
          _SectionHeader(
            title: _ct('Progression du total d\'écoutes', 'Cumulative scrobble progression'),
            icon: Icons.trending_up_rounded,
          ),
          const SizedBox(height: 12),
          _CumulativeLineCard(data: cumulData),
          const SizedBox(height: 24),
        ],

        // ── 3. Genre tags ─────────────────────────────────────────────────
        _SectionHeader(
          title: _ct('Vos genres musicaux', 'Your musical genres'),
          icon: Icons.equalizer_rounded,
        ),
        const SizedBox(height: 8),
        Text(_ct('Basé sur vos top artistes', 'Based on your top artists'),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (_tagsLoading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (_tags.isNotEmpty) ...[
          _TagsCard(tags: _tags),
          const SizedBox(height: 4),
          Center(child: TextButton(onPressed: _loadTags, child: Text(_ct('Recalculer', 'Recalculate')))),
        ],
        const SizedBox(height: 24),

        // ── 4. Listening habits ───────────────────────────────────────────
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
        if (_hourlyLoading)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (_hourlyData != null) ...[
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

        // ── 5. Artist donut ───────────────────────────────────────────────
        if (_topArtists.isNotEmpty) ...[
          _SectionHeader(title: L.chartsArtistDist, icon: Icons.mic_rounded),
          const SizedBox(height: 12),
          _DonutDistributionCard(
            items:    _topArtists,
            getLabel: (e) => (e['name'] ?? '').toString(),
            getPlays: (e) => int.tryParse((e['playcount'] ?? '0').toString()) ?? 0,
            baseColor: scheme.primary,
            onTap: (e) => showDetailSheet(
              context,
              Map<String, dynamic>.from(e as Map),
              'artists',
              widget.service,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── 6. Album donut ────────────────────────────────────────────────
        if (_topAlbums.isNotEmpty) ...[
          _SectionHeader(
            title: _ct('Répartition par album', 'Album distribution'),
            icon: Icons.album_rounded,
          ),
          const SizedBox(height: 12),
          _DonutDistributionCard(
            items:    _topAlbums,
            getLabel: (e) => (e['name'] ?? '').toString(),
            getPlays: (e) => int.tryParse((e['playcount'] ?? '0').toString()) ?? 0,
            baseColor: scheme.secondary,
            onTap: (e) => showDetailSheet(
              context,
              Map<String, dynamic>.from(e as Map),
              'albums',
              widget.service,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── 7. Calendar heatmap ───────────────────────────────────────────
        _SectionHeader(
          title: _ct('Calendrier musical', 'Listening calendar'),
          icon: Icons.grid_on_rounded,
        ),
        const SizedBox(height: 8),
        Text(_ct('Activité récente jour par jour', 'Recent activity day by day'),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (_calendarLoading)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (_calendarData != null) ...[
          _CalendarCard(data: _calendarData!),
          const SizedBox(height: 4),
          Center(child: TextButton(
            onPressed: _loadCalendar,
            child: Text(_ct('Recalculer', 'Recalculate')),
          )),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _MonthlyCard  — bar chart (existing, preserved)
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
          Row(children: [
            _ChipStat(label: _ct('Total', 'Total'),     value: _fmt(total), scheme: scheme, text: text),
            const SizedBox(width: 8),
            _ChipStat(label: _ct('Moy./mois', 'Avg/mo'), value: _fmt(avg),   scheme: scheme, text: text),
          ]),
          const SizedBox(height: 16),
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
                            color: isMax ? scheme.primary : scheme.onSurfaceVariant,
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
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
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
//  _CumulativeLineCard  — filled area line chart
// ══════════════════════════════════════════════════════════════════════════

class _CumulativeLineCard extends StatelessWidget {
  final Map<String, int> data; // 'YYYY-MM' → cumulative count (sorted)
  const _CumulativeLineCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final keys   = data.keys.toList()..sort();
    final total  = data.isEmpty ? 0 : data[keys.last]!;

    // Find steepest month (biggest jump)
    String bestMonth = '';
    int bestDelta = 0;
    for (var i = 1; i < keys.length; i++) {
      final delta = data[keys[i]]! - data[keys[i - 1]]!;
      if (delta > bestDelta) { bestDelta = delta; bestMonth = keys[i]; }
    }

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _ChipStat(label: _ct('Total', 'Total'), value: _fmt(total), scheme: scheme, text: text),
            if (bestMonth.isNotEmpty) ...[
              const SizedBox(width: 8),
              _ChipStat(
                label: _ct('Meilleur mois', 'Best month'),
                value: '${bestMonth.substring(5)} (+${_fmt(bestDelta)})',
                scheme: scheme, text: text,
              ),
            ],
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _LinePainter(
                keys:   keys,
                values: keys.map((k) => data[k]!.toDouble()).toList(),
                color:  scheme.primary,
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),
          // X-axis labels
          Row(children: keys.asMap().entries.map((e) {
            final show = keys.length <= 8
                || e.key % (keys.length ~/ 6).clamp(1, 99) == 0
                || e.key == keys.length - 1;
            return Expanded(child: show
                ? Text(e.value.substring(5),
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(
                        fontSize: 8, color: scheme.onSurfaceVariant))
                : const SizedBox.shrink());
          }).toList()),
        ]),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<String> keys;
  final List<double> values;
  final Color        color;
  const _LinePainter({required this.keys, required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2) return;
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final w      = size.width;
    final h      = size.height;
    final stepX  = w / (n - 1);

    List<Offset> pts = List.generate(n, (i) {
      final x = i * stepX;
      final y = h - (values[i] / maxVal) * h * 0.92;
      return Offset(x, y);
    });

    // Filled gradient area
    final fillPath = Path()
      ..moveTo(pts[0].dx, h)
      ..lineTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      final cx1 = (pts[i - 1].dx + pts[i].dx) / 2;
      fillPath.cubicTo(cx1, pts[i - 1].dy, cx1, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    fillPath.lineTo(pts.last.dx, h);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.03)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Line
    final linePath = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      final cx1 = (pts[i - 1].dx + pts[i].dx) / 2;
      linePath.cubicTo(cx1, pts[i - 1].dy, cx1, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(linePath, Paint()
      ..color      = color
      ..strokeWidth = 2.5
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round);

    // Endpoint dot
    canvas.drawCircle(pts.last, 5, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(pts.last, 3, Paint()..color = color);
    canvas.drawCircle(pts.last, 1.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.color != color;
}

// ══════════════════════════════════════════════════════════════════════════
//  _TagsCard  — genre distribution (horizontal bars + color dots)
// ══════════════════════════════════════════════════════════════════════════

class _TagsCard extends StatelessWidget {
  final List<_TagEntry> tags;
  const _TagsCard({required this.tags});

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final text    = Theme.of(context).textTheme;
    final palette = _buildPalette(scheme.primary, tags.length);
    final maxVal  = tags.isEmpty ? 1 : tags.map((t) => t.count).reduce((a, b) => a > b ? a : b);

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
                      style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${(ratio * 100).round()}%',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _DonutDistributionCard  — donut + ranked legend
// ══════════════════════════════════════════════════════════════════════════

class _DonutDistributionCard extends StatelessWidget {
  final List<dynamic>            items;
  final String Function(dynamic) getLabel;
  final int    Function(dynamic) getPlays;
  final Color                    baseColor;
  final void   Function(dynamic) onTap;

  const _DonutDistributionCard({
    required this.items,
    required this.getLabel,
    required this.getPlays,
    required this.baseColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final text    = Theme.of(context).textTheme;
    final vals    = items.map(getPlays).toList();
    final total   = vals.fold<int>(0, (a, b) => a + b);
    final palette = _buildPalette(baseColor, items.length);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Donut
          SizedBox(
            width: 130, height: 130,
            child: CustomPaint(
              painter: _DonutPainter(
                values: vals.map((v) => v.toDouble()).toList(),
                colors: palette,
                holeColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Legend
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.asMap().entries.map((e) {
              final plays = getPlays(e.value);
              final pct   = total > 0 ? (plays / total * 100).round() : 0;
              final label = getLabel(e.value);
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
                    Expanded(child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                    Text('$pct%',
                        style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant, fontSize: 10)),
                    const SizedBox(width: 4),
                    Text(_fmt(plays),
                        style: text.bodySmall?.copyWith(
                            color: color, fontWeight: FontWeight.w700, fontSize: 10)),
                  ]),
                ),
              );
            }).toList(),
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _DonutPainter
// ══════════════════════════════════════════════════════════════════════════

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color>  colors;
  final Color        holeColor;
  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.holeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx    = size.width  / 2;
    final cy    = size.height / 2;
    final r     = (size.shortestSide / 2) - 4;
    final inner = r * 0.52;
    final total = values.fold(0.0, (a, b) => a + b);
    if (total == 0) return;

    double sweep = -_kHalfPi; // start at 12 o'clock
    const gap = 0.02;         // gap in radians between slices

    for (var i = 0; i < values.length; i++) {
      final angle = (values[i] / total) * _kTwoPi - gap;
      if (angle <= 0) continue;

      final outerRect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      final innerRect = Rect.fromCircle(center: Offset(cx, cy), radius: inner);

      final path = Path()
        ..arcTo(outerRect, sweep, angle, false)
        ..arcTo(innerRect, sweep + angle, -angle, false)
        ..close();

      canvas.drawPath(path, Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill
        ..isAntiAlias = true);

      sweep += angle + gap;
    }

    // Center hole fill (matches card background)
    canvas.drawCircle(
      Offset(cx, cy), inner - 1,
      Paint()..color = holeColor,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values || old.colors != colors;
}

// ══════════════════════════════════════════════════════════════════════════
//  _CalendarCard  — day-by-day heatmap (last 4 months)
// ══════════════════════════════════════════════════════════════════════════

class _CalendarCard extends StatelessWidget {
  final Map<String, int> data; // 'YYYY-MM-DD' → count
  const _CalendarCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final text    = Theme.of(context).textTheme;
    final maxVal  = data.values.fold(0, (a, b) => a > b ? a : b);
    final now     = DateTime.now();

    // Last 4 months
    final months = List.generate(4, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return DateTime(d.year, d.month, 1);
    }).reversed.toList();

    // Year stats
    final yearStr   = '${now.year}';
    final yearTotal = data.entries
        .where((e) => e.key.startsWith(yearStr))
        .fold(0, (a, b) => a + b.value);
    final activeDays = data.entries
        .where((e) => e.key.startsWith(yearStr) && e.value > 0)
        .length;
    String bestDay = '';
    int bestCount  = 0;
    for (final e in data.entries) {
      if (e.value > bestCount) { bestCount = e.value; bestDay = e.key; }
    }

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Stats chips
          Wrap(spacing: 8, runSpacing: 6, children: [
            _ChipStat(label: yearStr, value: _fmt(yearTotal), scheme: scheme, text: text),
            _ChipStat(
              label: _ct('Jours actifs', 'Active days'),
              value: '$activeDays',
              scheme: scheme, text: text,
            ),
            if (bestDay.isNotEmpty)
              _ChipStat(
                label: _ct('Record', 'Record'),
                value: '${bestDay.substring(5)} ($bestCount)',
                scheme: scheme, text: text,
              ),
          ]),
          const SizedBox(height: 14),

          // Month grids
          ...months.map((m) => _MonthHeatGrid(
            month:  m,
            data:   data,
            maxVal: maxVal,
            scheme: scheme,
            text:   text,
          )),

          // Legend
          const SizedBox(height: 6),
          Row(children: [
            Text(_ct('Moins', 'Less'),
                style: text.labelSmall?.copyWith(
                    fontSize: 9, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 4),
            ...List.generate(5, (i) => Container(
              width: 11, height: 11,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i == 0
                    ? scheme.surfaceContainerHigh
                    : scheme.primary.withValues(alpha: 0.15 + i * 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(width: 4),
            Text(_ct('Plus', 'More'),
                style: text.labelSmall?.copyWith(
                    fontSize: 9, color: scheme.onSurfaceVariant)),
          ]),
        ]),
      ),
    );
  }
}

class _MonthHeatGrid extends StatelessWidget {
  final DateTime     month;
  final Map<String, int> data;
  final int          maxVal;
  final ColorScheme  scheme;
  final TextTheme    text;
  const _MonthHeatGrid({
    required this.month,
    required this.data,
    required this.maxVal,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWd     = DateTime(month.year, month.month, 1).weekday; // 1=Mon
    final monthLabel  = L.months[month.month];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$monthLabel ${month.year}',
            style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 3, runSpacing: 3,
          children: [
            // Offset empty cells
            ...List.generate(firstWd - 1,
              (_) => const SizedBox(width: 20, height: 20)),
            // Day cells
            ...List.generate(daysInMonth, (d) {
              final day   = d + 1;
              final key   = '${month.year}-'
                  '${month.month.toString().padLeft(2, '0')}-'
                  '${day.toString().padLeft(2, '0')}';
              final count = data[key] ?? 0;
              final ratio = (maxVal > 0 && count > 0) ? count / maxVal : 0.0;
              final color = count == 0
                  ? scheme.surfaceContainerHigh
                  : scheme.primary.withValues(alpha: 0.18 + ratio.clamp(0.0, 1.0) * 0.80);

              return Tooltip(
                message: count > 0 ? '$day — $count scrobbles' : '',
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ],
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _HourlyBarCard  — 24-bar chart (preserved)
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
            Text(_ct('Répartition horaire', 'Hourly distribution'),
                style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            _PeakChip(
              label: '${_peakEmoji(peakH)} ${peakH}h',
              color:   scheme.primaryContainer,
              onColor: scheme.onPrimaryContainer,
              text:    text,
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(height: 100, child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (h) {
              final v     = data[h] ?? 0;
              final ratio = maxVal > 0 ? v / maxVal : 0.0;
              final isPeak = h == peakH;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Flexible(fit: FlexFit.loose,
                    child: FractionallySizedBox(
                      heightFactor: ratio.clamp(0.02, 1.0),
                      child: Container(decoration: BoxDecoration(
                        color: isPeak
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.25 + ratio * 0.60),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      )),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(h % 6 == 0 ? '${h}h' : '',
                      style: text.labelSmall
                          ?.copyWith(fontSize: 8, color: scheme.onSurfaceVariant)),
                ]),
              ));
            }),
          )),
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
//  _WeekdayBarCard  — 7-bar chart (preserved)
// ══════════════════════════════════════════════════════════════════════════

class _WeekdayBarCard extends StatelessWidget {
  final Map<int, int> data;
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
            Text(_ct('Activité par jour de la semaine', 'Activity by day of week'),
                style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            _PeakChip(
              label: '📅 ${labels[peakDay - 1]}',
              color:   scheme.secondaryContainer,
              onColor: scheme.onSecondaryContainer,
              text:    text,
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(height: 110, child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final day   = i + 1;
              final v     = data[day] ?? 0;
              final ratio = maxVal > 0 ? v / maxVal : 0.0;
              final isPeak = day == peakDay;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (v > 0)
                    Text(_fmt(v),
                        style: text.labelSmall?.copyWith(
                            fontSize: 8,
                            color: isPeak ? scheme.secondary : scheme.onSurfaceVariant,
                            fontWeight: isPeak ? FontWeight.w800 : FontWeight.normal)),
                  const SizedBox(height: 2),
                  Flexible(fit: FlexFit.loose,
                    child: FractionallySizedBox(
                      heightFactor: ratio.clamp(0.02, 1.0),
                      child: Container(decoration: BoxDecoration(
                        color: isPeak
                            ? scheme.secondary
                            : scheme.secondary.withValues(alpha: 0.25 + ratio * 0.60),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      )),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(labels[i],
                      style: text.labelSmall?.copyWith(
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
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
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
//  Palette helper — generates N distinct colors from a base hue
// ══════════════════════════════════════════════════════════════════════════

List<Color> _buildPalette(Color base, int count) {
  if (count == 0) return [];
  final hsl = HSLColor.fromColor(base);
  return List.generate(count, (i) {
    final hue = (hsl.hue + i * (360.0 / count)) % 360.0;
    return HSLColor.fromAHSL(
      1.0, hue,
      hsl.saturation.clamp(0.45, 0.85),
      hsl.lightness.clamp(0.38, 0.62),
    ).toColor();
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  Data classes
// ══════════════════════════════════════════════════════════════════════════

class _TagEntry {
  final String name;
  final int    count;
  const _TagEntry({required this.name, required this.count});
}
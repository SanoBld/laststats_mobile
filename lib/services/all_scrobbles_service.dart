// lib/services/all_scrobbles_service.dart
// ══════════════════════════════════════════════════════════════════════════
//  AllScrobblesService — chargement et cache de l'historique complet
//
//  Stratégie :
//    • 1ère connexion  : loadAll()  — pagine toutes les années depuis
//      l'inscription (200 tracks/page, délai 200 ms entre pages).
//    • Lancements suiv.: syncNew()  — ne récupère que les scrobbles
//      postérieurs au dernier timestamp connu (très rapide).
//    • Stocke les records complets : ts + track + artist + album.
//    • Si une année est en cache v1 (timestamps seulement), elle est
//      marquée incomplète et rechargée à la prochaine occasion.
//    • progressNotifier mis à jour en temps réel pour l'UI.
// ══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'data_cache.dart';
import 'scrobbles_file_cache.dart';
import 'lastfm_service.dart';

// ══════════════════════════════════════════════════════════════════════════
//  Mode de synchronisation
// ══════════════════════════════════════════════════════════════════════════

enum SyncMode { full, incremental }

// ══════════════════════════════════════════════════════════════════════════
//  Progress snapshot
// ══════════════════════════════════════════════════════════════════════════

class AllScrobblesProgress {
  final bool     isLoading;
  final bool     isDone;
  final bool     isIdle;
  final SyncMode mode;
  final int?     currentYear;
  final int      yearIndex;
  final int      totalYears;
  final int      loaded;
  final int      total;
  final int      newCount;

  const AllScrobblesProgress({
    this.isLoading  = false,
    this.isDone     = false,
    this.isIdle     = true,
    this.mode       = SyncMode.full,
    this.currentYear,
    this.yearIndex  = 0,
    this.totalYears = 0,
    this.loaded     = 0,
    this.total      = 0,
    this.newCount   = 0,
  });

  factory AllScrobblesProgress.idle() => const AllScrobblesProgress();

  factory AllScrobblesProgress.done({
    int totalYears = 0,
    int newCount   = 0,
    SyncMode mode  = SyncMode.full,
  }) => AllScrobblesProgress(
    isDone: true, isIdle: false,
    totalYears: totalYears,
    newCount:   newCount,
    mode:       mode,
  );

  double get fraction {
    if (mode == SyncMode.incremental) {
      return total > 0 ? (loaded / total).clamp(0.0, 1.0) : 0.0;
    }
    if (totalYears == 0) return 0.0;
    final yearsDone  = yearIndex.toDouble();
    final yearInner  = total > 0 ? (loaded / total) : 0.0;
    return ((yearsDone + yearInner) / totalYears).clamp(0.0, 1.0);
  }

  String get shortLabel {
    if (mode == SyncMode.incremental) {
      if (total > 0) return '$loaded / $total';
      return loaded > 0 ? '+$loaded' : '…';
    }
    if (currentYear != null) return '$currentYear';
    return '…';
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  AllScrobblesService
// ══════════════════════════════════════════════════════════════════════════

class AllScrobblesService {
  AllScrobblesService._();

  static const _delay = Duration(milliseconds: 200);

  // ── État ──────────────────────────────────────────────────────────────────

  static bool _running = false;
  static bool get isRunning => _running;

  static final Set<int> _yearsInLoading = {};

  static final progressNotifier =
      ValueNotifier<AllScrobblesProgress>(AllScrobblesProgress.idle());

  // ── Lectures publiques ────────────────────────────────────────────────────

  static bool get isFirstLoad => ScrobblesFileCache.getMeta() == null;

  static bool isYearCached(int year)   => ScrobblesFileCache.isYearCached(year);
  static bool isYearComplete(int year) => ScrobblesFileCache.isYearComplete(year);

  /// Records complets pour [year] (avec track + artist + album).
  static List<ScrobbleRecord>? getRecordsForYear(int year) =>
      ScrobblesFileCache.getRecords(year);

  /// Timestamps uniquement (rétrocompat).
  static List<int>? getTimestampsForYear(int year) =>
      ScrobblesFileCache.getTimestamps(year);

  static List<int> getCachedYears() => ScrobblesFileCache.getCachedYears();

  static int getTotalCachedScrobbles() =>
      ScrobblesFileCache.getTotalScrobbleCount();

  static int get lastCachedTimestamp {
    int latest = 0;
    for (final year in getCachedYears()) {
      final ts = getTimestampsForYear(year);
      if (ts != null && ts.isNotEmpty) {
        final yearMax = ts.last;
        if (yearMax > latest) latest = yearMax;
      }
    }
    return latest;
  }

  static int getRegistrationYear() {
    final info = DataCache.getSync(DataCache.keyUserInfo());
    if (info is Map) {
      final uts = int.tryParse(
          (info['registered']?['unixtime'] ?? '').toString());
      if (uts != null && uts > 0) {
        return DateTime.fromMillisecondsSinceEpoch(uts * 1000).year;
      }
      final text  = (info['registered']?['#text'] ?? '').toString();
      final parts = text.split(' ');
      if (parts.length >= 3) {
        final y = int.tryParse(parts[2].replaceAll(',', ''));
        if (y != null && y >= 2002 && y <= DateTime.now().year) return y;
      }
    }
    return DateTime.now().year - 3;
  }

  // ── Chargement d'une année ────────────────────────────────────────────────

  /// Charge (ou recharge) une année entière depuis l'API Last.fm.
  /// Stocke les records complets (ts + track + artist + album).
  static Future<List<ScrobbleRecord>> loadYear(
    int year,
    LastFmService service, {
    bool force = false,
    void Function(int loaded, int total)? onProgress,
  }) async {
    // Déjà en cache complet et non forcé → retourner le cache
    if (!force && isYearCached(year) && isYearComplete(year)) {
      return getRecordsForYear(year) ?? [];
    }

    // Verrou de concurrence
    if (_yearsInLoading.contains(year)) return [];
    _yearsInLoading.add(year);

    final now       = DateTime.now();
    final isCurrent = year == now.year;
    final from      = DateTime(year, 1, 1);
    final to        = isCurrent ? now : DateTime(year + 1, 1, 1);

    final records = <ScrobbleRecord>[];
    int page       = 1;
    int totalPages = 1;

    try {
      do {
        try {
          final data = await service.getRecentTracks(
            limit: 200,
            page:  page,
            from:  from.millisecondsSinceEpoch ~/ 1000,
            to:    to.millisecondsSinceEpoch   ~/ 1000,
          );

          final attr = data['@attr'] as Map?;
          if (attr != null) {
            totalPages = int.tryParse(
                attr['totalPages']?.toString() ?? '1') ?? 1;
            final ttl = int.tryParse(
                attr['total']?.toString() ?? '0') ?? 0;
            onProgress?.call(records.length, ttl);
          }

          final raw  = data['track'];
          final list = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);

          for (final t in list) {
            final m = t as Map?;
            if (m == null) continue;
            if (m['@attr']?['nowplaying'] == 'true') continue;
            final uts = m['date']?['uts']?.toString() ?? '';
            if (uts.isEmpty) continue;
            final sec = int.tryParse(uts);
            if (sec == null) continue;

            records.add(ScrobbleRecord(
              ts:     sec,
              track:  (m['name']           ?? '').toString(),
              artist: (m['artist']?['name'] ?? (m['artist'] ?? '')).toString(),
              album:  (m['album']?['#text'] ?? '').toString(),
            ));
          }

          page++;
          if (page <= totalPages) await Future.delayed(_delay);
        } catch (e) {
          debugPrint('[AllScrobbles] Erreur année=$year page=$page : $e');
          break;
        }
      } while (page <= totalPages);

      records.sort((a, b) => a.ts.compareTo(b.ts));
      await ScrobblesFileCache.setYear(year, records);
      await _updateMeta(year);
      return records;
    } finally {
      _yearsInLoading.remove(year);
    }
  }

  // ── Chargement complet (première connexion) ───────────────────────────────

  static Future<void> loadAll(
    LastFmService service, {
    bool force = false,
  }) async {
    if (_running) return;
    _running = true;

    final regYear     = getRegistrationYear();
    final currentYear = DateTime.now().year;
    final years       = List.generate(
        currentYear - regYear + 1, (i) => regYear + i);

    try {
      for (var i = 0; i < years.length; i++) {
        final year = years[i];

        // Skip si déjà en cache complet (sauf l'année en cours)
        if (!force && isYearCached(year) && isYearComplete(year) &&
            year != currentYear) continue;

        progressNotifier.value = AllScrobblesProgress(
          isLoading:   true,
          isIdle:      false,
          mode:        SyncMode.full,
          currentYear: year,
          yearIndex:   i,
          totalYears:  years.length,
        );

        await loadYear(year, service, force: force,
            onProgress: (loaded, total) {
          progressNotifier.value = AllScrobblesProgress(
            isLoading:   true,
            isIdle:      false,
            mode:        SyncMode.full,
            currentYear: year,
            yearIndex:   i,
            totalYears:  years.length,
            loaded:      loaded,
            total:       total,
          );
        });
      }
    } finally {
      _running = false;
      progressNotifier.value = AllScrobblesProgress.done(
          totalYears: years.length, mode: SyncMode.full);
    }
  }

  // ── Synchronisation incrémentale (lancements suivants) ───────────────────

  /// Récupère uniquement les scrobbles postérieurs au dernier timestamp connu.
  /// Fusionne avec les records existants.
  static Future<void> syncNew(LastFmService service) async {
    if (_running) return;

    final lastTs = lastCachedTimestamp;
    if (lastTs == 0) return loadAll(service);

    // Si des années en cache v1 (sans métadonnées), relancer un loadAll.
    // On ne bloque pas pour ça — on le fait silencieusement.
    final incompleteYears = getCachedYears()
        .where((y) => isYearCached(y) && !isYearComplete(y))
        .toList();
    if (incompleteYears.isNotEmpty) {
      debugPrint('[AllScrobbles] Années incomplètes (v1) → rechargement : '
          '$incompleteYears');
      return loadAll(service);
    }

    _running = true;
    final now   = DateTime.now();
    final nowTs = now.millisecondsSinceEpoch ~/ 1000;

    progressNotifier.value = const AllScrobblesProgress(
      isLoading:  true,
      isIdle:     false,
      mode:       SyncMode.incremental,
      totalYears: 1,
    );

    try {
      final newRecords = <ScrobbleRecord>[];
      int page       = 1;
      int totalPages = 1;

      do {
        try {
          final data = await service.getRecentTracks(
            limit: 200,
            page:  page,
            from:  lastTs + 1,
            to:    nowTs,
          );

          final attr = data['@attr'] as Map?;
          if (attr != null) {
            totalPages = int.tryParse(
                attr['totalPages']?.toString() ?? '1') ?? 1;
            final ttl = int.tryParse(
                attr['total']?.toString() ?? '0') ?? 0;
            progressNotifier.value = AllScrobblesProgress(
              isLoading:  true,
              isIdle:     false,
              mode:       SyncMode.incremental,
              loaded:     newRecords.length,
              total:      ttl,
              totalYears: 1,
            );
          }

          final raw  = data['track'];
          final list = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);

          for (final t in list) {
            final m = t as Map?;
            if (m == null) continue;
            if (m['@attr']?['nowplaying'] == 'true') continue;
            final uts = m['date']?['uts']?.toString() ?? '';
            if (uts.isEmpty) continue;
            final sec = int.tryParse(uts);
            if (sec == null) continue;

            newRecords.add(ScrobbleRecord(
              ts:     sec,
              track:  (m['name']            ?? '').toString(),
              artist: (m['artist']?['name']  ?? (m['artist'] ?? '')).toString(),
              album:  (m['album']?['#text']  ?? '').toString(),
            ));
          }

          page++;
          if (page <= totalPages) await Future.delayed(_delay);
        } catch (e) {
          debugPrint('[AllScrobbles] Erreur sync page=$page : $e');
          break;
        }
      } while (page <= totalPages);

      // Distribuer les nouveaux records par année et fusionner
      if (newRecords.isNotEmpty) {
        final byYear = <int, List<ScrobbleRecord>>{};
        for (final r in newRecords) {
          final year = DateTime.fromMillisecondsSinceEpoch(r.ts * 1000).year;
          (byYear[year] ??= []).add(r);
        }

        for (final entry in byYear.entries) {
          final year     = entry.key;
          final existing = getRecordsForYear(year) ?? [];

          // Merge + déduplique par timestamp + trie croissant
          final tsSet  = <int>{};
          final merged = <ScrobbleRecord>[];
          for (final r in [...existing, ...entry.value]) {
            if (tsSet.add(r.ts)) merged.add(r);
          }
          merged.sort((a, b) => a.ts.compareTo(b.ts));

          await ScrobblesFileCache.setYear(year, merged);
          await _updateMeta(year);
        }

        // Rafraîchir le TTL de l'année en cours même sans nouveaux scrobbles
        if (!byYear.containsKey(now.year)) {
          final cur = getRecordsForYear(now.year);
          if (cur != null) await ScrobblesFileCache.setYear(now.year, cur);
        }
      }

      _running = false;
      progressNotifier.value = AllScrobblesProgress.done(
          newCount: newRecords.length, mode: SyncMode.incremental);

    } catch (e) {
      debugPrint('[AllScrobbles] Erreur sync incrémentale : $e');
      _running = false;
      progressNotifier.value = AllScrobblesProgress.done(
          mode: SyncMode.incremental);
    }
  }

  // ── Rechargement forcé ────────────────────────────────────────────────────

  static Future<void> forceReload(LastFmService service) =>
      loadAll(service, force: true);

  // ── Calculs depuis les records ─────────────────────────────────────────────

  /// Répartition horaire {0..23 → compte}.
  static Map<int, int> computeHourly(List<ScrobbleRecord> records) {
    final h = <int, int>{for (var i = 0; i < 24; i++) i: 0};
    for (final r in records) {
      final dt = DateTime.fromMillisecondsSinceEpoch(r.ts * 1000);
      h[dt.hour] = (h[dt.hour] ?? 0) + 1;
    }
    return h;
  }

  /// Répartition par jour de la semaine {1(Lun)..7(Dim) → compte}.
  static Map<int, int> computeWeekday(List<ScrobbleRecord> records) {
    final d = <int, int>{for (var i = 1; i <= 7; i++) i: 0};
    for (final r in records) {
      final dt = DateTime.fromMillisecondsSinceEpoch(r.ts * 1000);
      d[dt.weekday] = (d[dt.weekday] ?? 0) + 1;
    }
    return d;
  }

  /// Calendrier quotidien {"YYYY-MM-DD" → compte}.
  static Map<String, int> computeCalendar(List<ScrobbleRecord> records) {
    final data = <String, int>{};
    for (final r in records) {
      final dt  = DateTime.fromMillisecondsSinceEpoch(r.ts * 1000);
      final key = '${dt.year}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
      data[key] = (data[key] ?? 0) + 1;
    }
    return data;
  }

  /// Scrobbles mensuels {"YYYY-MM" → compte}.
  static Map<String, int> computeMonthly(List<ScrobbleRecord> records) {
    final data = <String, int>{};
    for (final r in records) {
      final dt  = DateTime.fromMillisecondsSinceEpoch(r.ts * 1000);
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      data[key] = (data[key] ?? 0) + 1;
    }
    return data;
  }

  /// Total cumulé mois par mois pour [year].
  static Map<String, int> computeYearCumulative(
      List<ScrobbleRecord> records, int year) {
    final monthly = computeMonthly(records);
    int cum = 0;
    final result = <String, int>{};
    for (var m = 1; m <= 12; m++) {
      final key = '$year-${m.toString().padLeft(2, '0')}';
      cum += monthly[key] ?? 0;
      result[key] = cum;
    }
    return result;
  }

  // ── Helpers privés ────────────────────────────────────────────────────────

  static Future<void> _updateMeta(int year) async {
    final meta   = ScrobblesFileCache.getMeta();
    final loaded = <int>{};
    if (meta != null) {
      loaded.addAll(
          ((meta['loaded_years'] as List?)
                  ?.map((e) => (e as num).toInt())) ??
              []);
    }
    loaded.add(year);
    await ScrobblesFileCache.setMeta({
      'loaded_years': (loaded.toList()..sort()),
      'last_sync_ts': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
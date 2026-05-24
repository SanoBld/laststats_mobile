// lib/services/all_scrobbles_service.dart
// ══════════════════════════════════════════════════════════════════════════
//  AllScrobblesService — chargement et cache de l'historique complet
//
//  Stratégie :
//    • 1ère connexion  : loadAll()  — pagine toutes les années depuis
//      l'inscription (200 tracks/page, délai 200 ms entre pages).
//    • Lancements suiv.: syncNew()  — ne récupère que les scrobbles
//      postérieurs au dernier timestamp connu (beaucoup plus rapide).
//    • Stocke uniquement les timestamps Unix (int) — très compact.
//    • Clés cache :
//        allscrobbles_cur_YYYY  → année en cours (TTL 1 h)
//        allscrobbles_YYYY      → années passées  (TTL 90 j)
//        allscrobbles_meta      → années chargées (TTL 24 h)
//    • progressNotifier mis à jour en temps réel pour l'UI.
// ══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'data_cache.dart';
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
  final int      newCount;    // Nombre de nouveaux scrobbles (sync incrémentale)

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
    int newCount = 0,
    SyncMode mode = SyncMode.full,
  }) => AllScrobblesProgress(
    isDone: true, isIdle: false,
    totalYears: totalYears,
    newCount: newCount,
    mode: mode,
  );

  /// Progression globale [0.0 – 1.0].
  double get fraction {
    if (mode == SyncMode.incremental) {
      return total > 0 ? (loaded / total).clamp(0.0, 1.0) : 0.0;
    }
    if (totalYears == 0) return 0.0;
    final yearsDone = yearIndex.toDouble();
    final yearInner = (total > 0) ? (loaded / total) : 0.0;
    return ((yearsDone + yearInner) / totalYears).clamp(0.0, 1.0);
  }

  /// Texte court pour l'UI (ex: "1 234 / 5 000" ou "42 nouveaux").
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

  static final progressNotifier =
      ValueNotifier<AllScrobblesProgress>(AllScrobblesProgress.idle());

  // ── Clés cache ────────────────────────────────────────────────────────────

  static String _yearKey(int year) {
    final isCurrent = year == DateTime.now().year;
    return isCurrent ? 'allscrobbles_cur_$year' : 'allscrobbles_$year';
  }

  static const _metaKey = 'allscrobbles_meta';

  // ── Lectures publiques ────────────────────────────────────────────────────

  /// `true` si aucun chargement n'a jamais été fait (première connexion).
  static bool get isFirstLoad => DataCache.getSync(_metaKey) == null;

  /// `true` si les données de [year] sont en cache et non expirées.
  static bool isYearCached(int year) =>
      DataCache.getSync(_yearKey(year)) != null;

  /// Timestamps Unix (secondes) pour [year], ou null si absent du cache.
  static List<int>? getTimestampsForYear(int year) {
    final raw = DataCache.getSync(_yearKey(year));
    if (raw == null) return null;
    if (raw is List) {
      return raw.map((e) => (e as num).toInt()).toList();
    }
    return null;
  }

  /// Années dont les données sont en cache.
  static List<int> getCachedYears() {
    final meta = DataCache.getSync(_metaKey);
    if (meta is Map) {
      final years = (meta['loaded_years'] as List?)
          ?.map((e) => (e as num).toInt())
          .toList() ?? [];
      return years..sort();
    }
    return [];
  }

  /// Dernier timestamp Unix connu dans le cache (toutes années confondues).
  /// Retourne 0 si aucune donnée en cache.
  static int get lastCachedTimestamp {
    int latest = 0;
    for (final year in getCachedYears()) {
      final ts = getTimestampsForYear(year);
      if (ts != null && ts.isNotEmpty) {
        // Les timestamps sont triés croissant → le dernier est le plus récent
        final yearMax = ts.last;
        if (yearMax > latest) latest = yearMax;
      }
    }
    return latest;
  }

  /// Année d'inscription extraite du cache userInfo.
  /// Retourne (annéeActuelle − 3) si indisponible.
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

  static Future<List<int>> loadYear(
    int year,
    LastFmService service, {
    bool force = false,
    void Function(int loaded, int total)? onProgress,
  }) async {
    if (!force && isYearCached(year)) {
      return getTimestampsForYear(year) ?? [];
    }

    final now       = DateTime.now();
    final isCurrent = year == now.year;
    final from      = DateTime(year, 1, 1);
    final to        = isCurrent ? now : DateTime(year + 1, 1, 1);

    final timestamps = <int>[];
    int page       = 1;
    int totalPages = 1;

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
          onProgress?.call(timestamps.length, ttl);
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
          if (sec != null) timestamps.add(sec);
        }

        page++;
        if (page <= totalPages) await Future.delayed(_delay);
      } catch (e) {
        debugPrint('[AllScrobbles] Erreur année=$year page=$page : $e');
        break;
      }
    } while (page <= totalPages);

    await DataCache.set(_yearKey(year), timestamps);
    await _updateMeta(year);
    return timestamps;
  }

  // ── Chargement complet (première connexion) ───────────────────────────────

  /// Charge toutes les années de l'inscription à aujourd'hui.
  /// Met à jour [progressNotifier] en temps réel.
  /// Passe silencieusement les années déjà en cache (sauf l'année en cours).
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
        if (!force && isYearCached(year) && year != currentYear) continue;

        progressNotifier.value = AllScrobblesProgress(
          isLoading:   true,
          isIdle:      false,
          mode:        SyncMode.full,
          currentYear: year,
          yearIndex:   i,
          totalYears:  years.length,
          loaded:      0,
          total:       0,
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

  /// Ne récupère que les scrobbles postérieurs au dernier timestamp connu.
  /// Beaucoup plus rapide que loadAll() pour les lancements courants.
  /// Met à jour [progressNotifier] pendant la sync.
  static Future<void> syncNew(LastFmService service) async {
    if (_running) return;

    final lastTs = lastCachedTimestamp;
    if (lastTs == 0) {
      // Aucun cache → revenir au chargement complet
      return loadAll(service);
    }

    _running = true;
    final now = DateTime.now();
    final nowTs = now.millisecondsSinceEpoch ~/ 1000;

    progressNotifier.value = const AllScrobblesProgress(
      isLoading:  true,
      isIdle:     false,
      mode:       SyncMode.incremental,
      totalYears: 1,
    );

    try {
      final newTimestamps = <int>[];
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
              isLoading: true,
              isIdle:    false,
              mode:      SyncMode.incremental,
              loaded:    newTimestamps.length,
              total:     ttl,
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
            if (sec != null) newTimestamps.add(sec);
          }

          page++;
          if (page <= totalPages) await Future.delayed(_delay);
        } catch (e) {
          debugPrint('[AllScrobbles] Erreur sync page=$page : $e');
          break;
        }
      } while (page <= totalPages);

      // Distribuer les nouveaux timestamps dans les années appropriées
      if (newTimestamps.isNotEmpty) {
        final byYear = <int, List<int>>{};
        for (final ts in newTimestamps) {
          final year = DateTime.fromMillisecondsSinceEpoch(ts * 1000).year;
          (byYear[year] ??= []).add(ts);
        }

        for (final entry in byYear.entries) {
          final year     = entry.key;
          final existing = getTimestampsForYear(year) ?? [];
          // Merge + déduplique + trie croissant
          final merged   = ({...existing, ...entry.value}.toList()..sort());
          await DataCache.set(_yearKey(year), merged);
          await _updateMeta(year);
        }

        // Forcer le refresh de l'année en cours (TTL 1h)
        if (!byYear.containsKey(now.year)) {
          // Pas de nouveaux scrobbles cette année : rafraîchir le TTL quand même
          final cur = getTimestampsForYear(now.year);
          if (cur != null) {
            await DataCache.set(_yearKey(now.year), cur);
          }
        }
      }

      _running = false;
      progressNotifier.value = AllScrobblesProgress.done(
          newCount: newTimestamps.length,
          mode:     SyncMode.incremental);

    } catch (e) {
      debugPrint('[AllScrobbles] Erreur sync incrémentale : $e');
      _running = false;
      progressNotifier.value = AllScrobblesProgress.done(
          mode: SyncMode.incremental);
    }
  }

  // ── Forcer un rechargement complet ────────────────────────────────────────

  /// Recharge toutes les années depuis zéro (force=true).
  static Future<void> forceReload(LastFmService service) =>
      loadAll(service, force: true);

  // ── Calculs depuis les timestamps ─────────────────────────────────────────

  /// Répartition horaire {0..23 → compte}.
  static Map<int, int> computeHourly(List<int> timestamps) {
    final h = <int, int>{for (var i = 0; i < 24; i++) i: 0};
    for (final uts in timestamps) {
      final dt = DateTime.fromMillisecondsSinceEpoch(uts * 1000);
      h[dt.hour] = (h[dt.hour] ?? 0) + 1;
    }
    return h;
  }

  /// Répartition par jour de la semaine {1(Lun)..7(Dim) → compte}.
  static Map<int, int> computeWeekday(List<int> timestamps) {
    final d = <int, int>{for (var i = 1; i <= 7; i++) i: 0};
    for (final uts in timestamps) {
      final dt = DateTime.fromMillisecondsSinceEpoch(uts * 1000);
      d[dt.weekday] = (d[dt.weekday] ?? 0) + 1;
    }
    return d;
  }

  /// Calendrier quotidien {"YYYY-MM-DD" → compte}.
  static Map<String, int> computeCalendar(List<int> timestamps) {
    final data = <String, int>{};
    for (final uts in timestamps) {
      final dt  = DateTime.fromMillisecondsSinceEpoch(uts * 1000);
      final key = '${dt.year}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
      data[key] = (data[key] ?? 0) + 1;
    }
    return data;
  }

  /// Scrobbles mensuels {"YYYY-MM" → compte}.
  static Map<String, int> computeMonthly(List<int> timestamps) {
    final data = <String, int>{};
    for (final uts in timestamps) {
      final dt  = DateTime.fromMillisecondsSinceEpoch(uts * 1000);
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      data[key] = (data[key] ?? 0) + 1;
    }
    return data;
  }

  /// Total cumulé mois par mois pour [year].
  static Map<String, int> computeYearCumulative(
      List<int> timestamps, int year) {
    final monthly = computeMonthly(timestamps);
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
    final meta   = DataCache.getSync(_metaKey);
    final loaded = <int>{};
    if (meta is Map) {
      loaded.addAll(
          ((meta['loaded_years'] as List?)
                  ?.map((e) => (e as num).toInt())) ??
              []);
    }
    loaded.add(year);
    await DataCache.set(_metaKey, {
      'loaded_years':   (loaded.toList()..sort()),
      'last_sync_ts':   DateTime.now().millisecondsSinceEpoch,
    });
  }
}
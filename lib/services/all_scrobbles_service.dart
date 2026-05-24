// lib/services/all_scrobbles_service.dart
// ══════════════════════════════════════════════════════════════════════════
//  AllScrobblesService — chargement et cache de l'historique complet
//
//  Stratégie :
//    • Pagine user.getRecentTracks (200 tracks/page) pour chaque année.
//    • Stocke uniquement les timestamps Unix (int) — très compact.
//    • Clés cache :
//        allscrobbles_cur_YYYY  → année en cours (TTL 1 h)
//        allscrobbles_YYYY      → années passées  (TTL 90 j)
//        allscrobbles_meta      → années chargées (TTL 24 h)
//    • 200 ms de délai entre les pages pour respecter le rate-limit Last.fm.
//    • Méthodes compute*() pour dériver les données des graphiques
//      directement depuis les timestamps en cache.
// ══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'data_cache.dart';
import 'lastfm_service.dart';

// ══════════════════════════════════════════════════════════════════════════
//  Progress snapshot
// ══════════════════════════════════════════════════════════════════════════

class AllScrobblesProgress {
  final bool isLoading;
  final bool isDone;
  final bool isIdle;
  final int? currentYear;
  final int  yearIndex;
  final int  totalYears;
  final int  loaded;
  final int  total;

  const AllScrobblesProgress({
    this.isLoading   = false,
    this.isDone      = false,
    this.isIdle      = true,
    this.currentYear,
    this.yearIndex   = 0,
    this.totalYears  = 0,
    this.loaded      = 0,
    this.total       = 0,
  });

  factory AllScrobblesProgress.idle() => const AllScrobblesProgress();

  factory AllScrobblesProgress.done({int totalYears = 0}) =>
      AllScrobblesProgress(
        isDone: true, isIdle: false, totalYears: totalYears);

  /// Global progress [0.0 – 1.0].
  double get fraction {
    if (totalYears == 0) return 0.0;
    final yearsDone = yearIndex.toDouble();
    final yearInner = (total > 0) ? (loaded / total) : 0.0;
    return ((yearsDone + yearInner) / totalYears).clamp(0.0, 1.0);
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

  /// Année d'inscription extraite du cache userInfo.
  /// Retourne (annéeActuelle − 3) si indisponible.
  static int getRegistrationYear() {
    final info = DataCache.getSync(DataCache.keyUserInfo());
    if (info is Map) {
      // Priorité : champ unixtime (le plus fiable)
      final uts = int.tryParse(
          (info['registered']?['unixtime'] ?? '').toString());
      if (uts != null && uts > 0) {
        return DateTime.fromMillisecondsSinceEpoch(uts * 1000).year;
      }
      // Fallback : texte "DD Mon YYYY, HH:MM"
      final text = (info['registered']?['#text'] ?? '').toString();
      final parts = text.split(' ');
      if (parts.length >= 3) {
        final y = int.tryParse(parts[2].replaceAll(',', ''));
        if (y != null && y >= 2002 && y <= DateTime.now().year) return y;
      }
    }
    return DateTime.now().year - 3;
  }

  // ── Chargement d'une année ────────────────────────────────────────────────

  /// Charge toutes les pages de [year] et met les timestamps en cache.
  /// [onProgress] est appelé après chaque page avec (chargé, total).
  static Future<List<int>> loadYear(
    int year,
    LastFmService service, {
    bool force = false,
    void Function(int loaded, int total)? onProgress,
  }) async {
    if (!force && isYearCached(year)) {
      return getTimestampsForYear(year) ?? [];
    }

    final now         = DateTime.now();
    final isCurrent   = year == now.year;
    final from        = DateTime(year, 1, 1);
    final to          = isCurrent ? now : DateTime(year + 1, 1, 1);

    final timestamps  = <int>[];
    int page          = 1;
    int totalPages    = 1;

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
        if (page <= totalPages) {
          await Future.delayed(_delay);
        }
      } catch (e) {
        debugPrint('[AllScrobbles] Erreur année=$year page=$page : $e');
        break;
      }
    } while (page <= totalPages);

    // Persistance
    await DataCache.set(_yearKey(year), timestamps);
    await _updateMeta(year);

    return timestamps;
  }

  // ── Chargement de l'historique complet ───────────────────────────────────

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

        // Sauter les années déjà chargées (sauf l'année en cours)
        if (!force && isYearCached(year) && year != currentYear) continue;

        progressNotifier.value = AllScrobblesProgress(
          isLoading:   true,
          isIdle:      false,
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
      progressNotifier.value =
          AllScrobblesProgress.done(totalYears: years.length);
    }
  }

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

  /// Total cumulé mois par mois pour [year], départ à 0 le 1er janvier.
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
    final meta      = DataCache.getSync(_metaKey);
    final loaded    = <int>{};
    if (meta is Map) {
      loaded.addAll(
          ((meta['loaded_years'] as List?)
                  ?.map((e) => (e as num).toInt())) ??
              []);
    }
    loaded.add(year);
    await DataCache.set(_metaKey, {
      'loaded_years': (loaded.toList()..sort()),
    });
  }
}
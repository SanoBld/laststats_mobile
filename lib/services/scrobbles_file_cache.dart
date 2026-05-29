// lib/services/scrobbles_file_cache.dart
// ══════════════════════════════════════════════════════════════════════════
//  ScrobblesFileCache — stockage multi-plateforme de l'historique complet
//
//  Stratégie de stockage :
//    • Premier lancement  → AllScrobblesService.loadAll() charge TOUT.
//    • Lancements suivants → AllScrobblesService.syncNew() ne charge que
//      les scrobbles postérieurs au dernier timestamp connu.
//    • Les données ne sont JAMAIS supprimées automatiquement (pas de TTL).
//      Seul ScrobblesFileCache.clear() ou une déconnexion vide le cache.
//
//  Backends :
//    • Web                             → IndexedDB (illimité)
//    • Natif (Android / iOS / Desktop) → fichiers via path_provider
//
//  Structure stockage :
//    Clé "year_YYYY" → {"v":2,"ts":…,"data":[[ts,"Track","Artist","Album"],…]}
//    Clé "meta"      → {"ts":…,"data":{"loaded_years":[…],"last_sync_ts":…}}
//
//  Rétrocompat :
//    v1 (anciens fichiers, timestamps seulement) → chargés comme ScrobbleRecord
//    sans métadonnées (track/artist/album vides). Re-téléchargement déclenché
//    par AllScrobblesService si track vide.
//
//  API publique :
//    • init()                   — charge en mémoire au démarrage
//    • getRecords(year)         → List<ScrobbleRecord>?
//    • getTimestamps(year)      → List<int>?  (dérivé des records)
//    • isYearCached(year)       → bool
//    • isYearComplete(year)     → bool  (records avec track+artist)
//    • getMeta()                → Map<String,dynamic>?
//    • setYear(year, records)   — persiste + met à jour la mémoire
//    • setMeta(meta)            — persiste + met à jour la mémoire
//    • clear()                  — vide tout (déconnexion)
//    • getDiskUsageBytes()      → Future<int>
//    • getTotalScrobbleCount()  → int
//    • pruneExpired()           — no-op (données permanentes)
// ══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';

// Import conditionnel : le compilateur choisit le bon backend selon la cible.
import 'scrobbles_cache_backend_stub.dart'
    if (dart.library.io)   'scrobbles_cache_backend_native.dart'
    if (dart.library.html) 'scrobbles_cache_backend_web.dart';

// ══════════════════════════════════════════════════════════════════════════
//  Modèle
// ══════════════════════════════════════════════════════════════════════════

class ScrobbleRecord {
  final int    ts;      // Unix timestamp (secondes)
  final String track;
  final String artist;
  final String album;

  const ScrobbleRecord({
    required this.ts,
    required this.track,
    required this.artist,
    required this.album,
  });

  /// Sérialisation compacte : [ts, "track", "artist", "album"]
  List<dynamic> toList() => [ts, track, artist, album];

  /// Depuis le format compact v2 : [ts, track, artist, album]
  factory ScrobbleRecord.fromList(List<dynamic> l) => ScrobbleRecord(
        ts:     (l[0] as num).toInt(),
        track:  l.length > 1 ? (l[1] as String? ?? '') : '',
        artist: l.length > 2 ? (l[2] as String? ?? '') : '',
        album:  l.length > 3 ? (l[3] as String? ?? '') : '',
      );

  /// Depuis l'ancien format v1 (timestamp seul).
  factory ScrobbleRecord.fromTimestamp(int ts) =>
      ScrobbleRecord(ts: ts, track: '', artist: '', album: '');

  /// Vrai si les métadonnées (track, artist) sont présentes.
  bool get hasMetadata => track.isNotEmpty && artist.isNotEmpty;

  @override
  String toString() => '$ts · $artist — $track';
}

// ══════════════════════════════════════════════════════════════════════════
//  Cache
// ══════════════════════════════════════════════════════════════════════════

class ScrobblesFileCache {
  ScrobblesFileCache._();

  static const _fileVersion = 2;

  // ── Cache mémoire ─────────────────────────────────────────────────────────
  static final Map<int, List<ScrobbleRecord>> _years = {};
  static Map<String, dynamic>?                _meta;
  static bool                                 _initialized = false;

  // ── Clés de stockage ──────────────────────────────────────────────────────
  static String _yearKey(int year) => 'year_$year';
  static const  _metaKey = 'meta';

  // ──────────────────────────────────────────────────────────────────────────
  //  Init — charge toutes les données en mémoire au démarrage.
  //  Les données ne sont jamais expirées ; tout ce qui est stocké est chargé.
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // ── Méta ──────────────────────────────────────────────────────────────
      final metaRaw = await CacheBackend.read(_metaKey);
      if (metaRaw != null) {
        try {
          final decoded = jsonDecode(metaRaw) as Map<String, dynamic>;
          // 'data' contient loaded_years + last_sync_ts
          _meta = decoded['data'] as Map<String, dynamic>?;
        } catch (_) {}
      }

      // ── Années connues via la méta ─────────────────────────────────────────
      final years = _meta == null
          ? <int>[]
          : ((_meta!['loaded_years'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              []);

      for (final year in years) {
        final raw = await CacheBackend.read(_yearKey(year));
        if (raw == null) continue;
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final version = (decoded['v'] as num?)?.toInt() ?? 1;
          // Pas de vérification TTL — les données sont permanentes
          final records = _parseRecords(decoded['data'], version);
          if (records != null) _years[year] = records;
        } catch (_) {}
      }

      debugPrint('[ScrobblesCache] ${_years.length} année(s) chargée(s) '
          '(${getTotalScrobbleCount()} scrobbles).');
    } catch (e) {
      debugPrint('[ScrobblesCache] Erreur init : $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Lecture (synchrone — depuis le cache mémoire)
  // ──────────────────────────────────────────────────────────────────────────

  /// Records complets pour [year], ou null si absent.
  static List<ScrobbleRecord>? getRecords(int year) => _years[year];

  /// Timestamps extraits des records (rétrocompat).
  static List<int>? getTimestamps(int year) =>
      _years[year]?.map((r) => r.ts).toList();

  static bool isYearCached(int year) => _years.containsKey(year);

  /// Vrai si tous les records de [year] ont leurs métadonnées (track+artist).
  /// Une année sans aucun scrobble (liste vide) est considérée complète :
  /// elle a bien été chargée depuis l'API, il n'y avait simplement rien.
  /// Retourne false uniquement si la clé est absente (jamais chargée) ou si
  /// au moins un record manque ses métadonnées (ancien cache v1).
  static bool isYearComplete(int year) {
    final records = _years[year];
    if (records == null) return false;          // jamais chargée
    if (records.isEmpty) return true;           // année blanche = complète
    return records.every((r) => r.hasMetadata);
  }

  static Map<String, dynamic>? getMeta() => _meta;

  /// Nombre total de scrobbles en cache (toutes années confondues).
  static int getTotalScrobbleCount() {
    int total = 0;
    for (final list in _years.values) {
      total += list.length;
    }
    return total;
  }

  /// Années présentes en cache, triées.
  static List<int> getCachedYears() => (_years.keys.toList()..sort());

  // ──────────────────────────────────────────────────────────────────────────
  //  Écriture (async — persiste dans le backend)
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> setYear(int year, List<ScrobbleRecord> records) async {
    _years[year] = records;
    try {
      final ts      = DateTime.now().millisecondsSinceEpoch;
      final payload = jsonEncode({
        'v':    _fileVersion,
        'ts':   ts,   // date d'écriture (informatif)
        'data': records.map((r) => r.toList()).toList(),
      });
      await CacheBackend.write(_yearKey(year), payload);
    } catch (e) {
      debugPrint('[ScrobblesCache] Erreur écriture année=$year : $e');
    }
  }

  static Future<void> setMeta(Map<String, dynamic> meta) async {
    _meta = meta;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      await CacheBackend.write(
        _metaKey,
        jsonEncode({'ts': ts, 'data': meta}),
      );
    } catch (e) {
      debugPrint('[ScrobblesCache] Erreur écriture meta : $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Stats stockage
  // ──────────────────────────────────────────────────────────────────────────

  static Future<int> getDiskUsageBytes() => CacheBackend.totalBytes();

  // ──────────────────────────────────────────────────────────────────────────
  //  Nettoyage
  // ──────────────────────────────────────────────────────────────────────────

  /// No-op — les données scrobbles sont permanentes.
  /// Seul [clear()] supprime les données (déconnexion explicite).
  static Future<void> pruneExpired() async {
    // Intentionnellement vide : pas de TTL sur l'historique.
  }

  /// Vide complètement le cache (mémoire + stockage).
  /// À appeler uniquement lors d'une déconnexion du compte.
  static Future<void> clear() async {
    _years.clear();
    _meta = null;
    _initialized = false;
    await CacheBackend.clearAll();
    debugPrint('[ScrobblesCache] Cache vidé.');
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Helpers privés
  // ──────────────────────────────────────────────────────────────────────────

  static List<ScrobbleRecord>? _parseRecords(dynamic data, int version) {
    if (data == null) return null;
    try {
      if (version >= 2) {
        // v2 : liste de listes [ts, track, artist, album]
        final list = data as List;
        return list
            .map((e) => ScrobbleRecord.fromList(e as List<dynamic>))
            .toList();
      } else {
        // v1 : liste de timestamps (int) — rétrocompat
        final list = data as List;
        return list
            .map((e) => ScrobbleRecord.fromTimestamp((e as num).toInt()))
            .toList();
      }
    } catch (_) {
      return null;
    }
  }
}
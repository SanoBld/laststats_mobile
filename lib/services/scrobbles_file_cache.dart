// lib/services/scrobbles_file_cache.dart
// ══════════════════════════════════════════════════════════════════════════
//  ScrobblesFileCache — stockage multi-plateforme de l'historique complet
//
//  Chaque scrobble est stocké avec ses métadonnées complètes :
//    timestamp, titre, artiste, album
//  Format compact (tableau JSON) pour minimiser l'espace disque.
//
//  Backends :
//    • Natif (Android / iOS / Desktop) → fichiers via path_provider
//    • Web                             → SharedPreferences (localStorage)
//
//  Structure stockage :
//    Clé "year_YYYY" → {"v":2,"ts":…,"data":[[ts,"Track","Artist","Album"],…]}
//    Clé "meta"      → {"ts":…,"data":{…}}
//
//  Rétrocompat :
//    v1 (anciens fichiers, timestamps seulement) → chargés comme ScrobbleRecord
//    sans métadonnées (track/artist/album vides). Re-téléchargement automatique
//    déclenché par AllScrobblesService si track vide.
//
//  TTL :
//    Année en cours  → 1 h
//    Années passées  → 90 j (données immuables)
//    Méta            → 24 h
//
//  API publique :
//    • init()                   — charge en mémoire au démarrage
//    • pruneExpired()           — nettoyage non-bloquant
//    • getRecords(year)         → List<ScrobbleRecord>?
//    • getTimestamps(year)      → List<int>?  (dérivé des records)
//    • isYearCached(year)       → bool
//    • isYearComplete(year)     → bool  (records avec métadonnées)
//    • getMeta()                → Map<String,dynamic>?
//    • setYear(year, records)   — persiste + met à jour la mémoire
//    • setMeta(meta)            — persiste + met à jour la mémoire
//    • clear()                  — vide tout
//    • getDiskUsageBytes()      → Future<int>
//    • getTotalScrobbleCount()  → int
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

  // ── TTL (ms) ──────────────────────────────────────────────────────────────
  static const _ttlCurrentMs = 60 * 60 * 1000;           // 1 h
  static const _ttlPastMs    = 90 * 24 * 60 * 60 * 1000; // 90 j
  static const _ttlMetaMs    = 24 * 60 * 60 * 1000;      // 24 h
  static const _fileVersion  = 2;

  // ── Cache mémoire ─────────────────────────────────────────────────────────
  static final Map<int, List<ScrobbleRecord>> _years = {};
  static Map<String, dynamic>?                _meta;
  static bool                                 _initialized = false;

  // ── Clés de stockage ──────────────────────────────────────────────────────
  static String _yearKey(int year) => 'year_$year';
  static const  _metaKey = 'meta';

  // ──────────────────────────────────────────────────────────────────────────
  //  Init
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // ── Méta ────────────────────────────────────────────────────────────────
      final metaRaw = await CacheBackend.read(_metaKey);
      if (metaRaw != null) {
        try {
          final decoded = jsonDecode(metaRaw) as Map<String, dynamic>;
          final ts      = (decoded['ts'] as num?)?.toInt() ?? 0;
          if ((now - ts) <= _ttlMetaMs) {
            _meta = decoded['data'] as Map<String, dynamic>?;
          }
        } catch (_) {}
      }

      // ── Années listées dans la méta ─────────────────────────────────────────
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
          final ts      = (decoded['ts'] as num?)?.toInt() ?? 0;
          final version = (decoded['v']  as num?)?.toInt() ?? 1;
          if ((now - ts) > _ttlOf(year)) continue;

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
  //  Lecture (synchrone)
  // ──────────────────────────────────────────────────────────────────────────

  /// Records complets pour [year], ou null si absent.
  static List<ScrobbleRecord>? getRecords(int year) => _years[year];

  /// Timestamps extraits des records (rétrocompat).
  static List<int>? getTimestamps(int year) =>
      _years[year]?.map((r) => r.ts).toList();

  static bool isYearCached(int year) => _years.containsKey(year);

  /// Vrai si tous les records de [year] ont leurs métadonnées (track+artist).
  static bool isYearComplete(int year) {
    final records = _years[year];
    if (records == null || records.isEmpty) return false;
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
  //  Écriture (async)
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> setYear(int year, List<ScrobbleRecord> records) async {
    _years[year] = records;
    try {
      final ts      = DateTime.now().millisecondsSinceEpoch;
      final payload = jsonEncode({
        'v':    _fileVersion,
        'ts':   ts,
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

  /// Taille totale du cache en octets.
  static Future<int> getDiskUsageBytes() => CacheBackend.totalBytes();

  // ──────────────────────────────────────────────────────────────────────────
  //  Nettoyage
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> pruneExpired() async {
    try {
      final now  = DateTime.now().millisecondsSinceEpoch;
      final keys = await CacheBackend.listKeys();

      for (final key in keys) {
        if (key == _metaKey) continue;
        // Clés d'années : "year_YYYY"
        if (!key.startsWith('year_')) continue;
        final year = int.tryParse(key.replaceFirst('year_', ''));
        if (year == null) continue;

        final raw = await CacheBackend.read(key);
        if (raw == null) continue;
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final ts      = (decoded['ts'] as num?)?.toInt() ?? 0;
          if ((now - ts) > _ttlOf(year)) {
            await CacheBackend.delete(key);
            _years.remove(year);
            debugPrint('[ScrobblesCache] $year supprimé (expiré).');
          }
        } catch (_) {
          await CacheBackend.delete(key);
        }
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    _years.clear();
    _meta = null;
    _initialized = false;
    await CacheBackend.clearAll();
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Helpers privés
  // ──────────────────────────────────────────────────────────────────────────

  static int _ttlOf(int year) =>
      year == DateTime.now().year ? _ttlCurrentMs : _ttlPastMs;

  /// Parse les données selon la version du fichier.
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

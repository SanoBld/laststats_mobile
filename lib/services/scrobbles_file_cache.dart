// lib/services/scrobbles_file_cache.dart
// ══════════════════════════════════════════════════════════════════════════
//  ScrobblesFileCache — stockage fichier de l'historique complet
//
//  Chaque scrobble est stocké avec ses métadonnées complètes :
//    timestamp, titre, artiste, album
//  Format compact (tableau JSON) pour minimiser l'espace disque.
//
//  Structure fichiers :
//    {appSupportDir}/scrobbles/{year}.json  → {"v":2,"ts":…,"data":[[ts,"Track","Artist","Album"],…]}
//    {appSupportDir}/scrobbles/meta.json    → {"ts":…,"data":{…}}
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
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

  // ── Répertoire de travail ─────────────────────────────────────────────────
  static Directory? _dir;
  static bool       _initialized = false;

  // ──────────────────────────────────────────────────────────────────────────
  //  Init
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final dir = await _ensureDir();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Méta
      final mf = _metaFile(dir);
      if (mf.existsSync()) {
        try {
          final raw = jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
          final ts  = (raw['ts'] as num?)?.toInt() ?? 0;
          if ((now - ts) <= _ttlMetaMs) {
            _meta = raw['data'] as Map<String, dynamic>?;
          }
        } catch (_) {}
      }

      // Années listées dans la méta
      final years = _meta == null
          ? <int>[]
          : ((_meta!['loaded_years'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              []);

      for (final year in years) {
        final f = _yearFile(dir, year);
        if (!f.existsSync()) continue;
        try {
          final raw     = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          final ts      = (raw['ts'] as num?)?.toInt() ?? 0;
          final version = (raw['v']  as num?)?.toInt() ?? 1;
          if ((now - ts) > _ttlOf(year)) continue;

          final records = _parseRecords(raw['data'], version);
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
      final dir = await _ensureDir();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final payload = jsonEncode({
        'v':    _fileVersion,
        'ts':   ts,
        'data': records.map((r) => r.toList()).toList(),
      });
      await _yearFile(dir, year).writeAsString(payload);
    } catch (e) {
      debugPrint('[ScrobblesCache] Erreur écriture année=$year : $e');
    }
  }

  static Future<void> setMeta(Map<String, dynamic> meta) async {
    _meta = meta;
    try {
      final dir = await _ensureDir();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      await _metaFile(dir).writeAsString(jsonEncode({'ts': ts, 'data': meta}));
    } catch (e) {
      debugPrint('[ScrobblesCache] Erreur écriture meta : $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Stats disque
  // ──────────────────────────────────────────────────────────────────────────

  /// Taille totale du répertoire scrobbles en octets.
  static Future<int> getDiskUsageBytes() async {
    try {
      final dir = await _ensureDir();
      int total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          try { total += await entity.length(); } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Nettoyage
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> pruneExpired() async {
    try {
      final dir = await _ensureDir();
      final now = DateTime.now().millisecondsSinceEpoch;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name == 'meta.json') continue;
        final year = int.tryParse(name.replaceAll('.json', ''));
        if (year == null) continue;
        try {
          final raw = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          final ts  = (raw['ts'] as num?)?.toInt() ?? 0;
          if ((now - ts) > _ttlOf(year)) {
            await entity.delete();
            _years.remove(year);
            debugPrint('[ScrobblesCache] $year.json supprimé (expiré).');
          }
        } catch (_) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    _years.clear();
    _meta = null;
    try {
      final dir = await _ensureDir();
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Helpers privés
  // ──────────────────────────────────────────────────────────────────────────

  static int _ttlOf(int year) =>
      year == DateTime.now().year ? _ttlCurrentMs : _ttlPastMs;

  static Future<Directory> _ensureDir() async {
    if (_dir != null && _dir!.existsSync()) return _dir!;
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/scrobbles');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  static File _yearFile(Directory dir, int year) =>
      File('${dir.path}/$year.json');

  static File _metaFile(Directory dir) => File('${dir.path}/meta.json');

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
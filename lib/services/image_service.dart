// lib/services/image_service.dart
// ══════════════════════════════════════════════════════════════════════════
//  ImageService — résolution multi-sources avec cache bicouche
//
//  Nouveautés v2 :
//    • Cache persistant sur disque (SharedPreferences) avec TTL 7 jours
//    • Cache mémoire (session) — accès instantané, toujours prioritaire
//    • Deux couches transparentes : mémoire → disque → réseau → disque+mémoire
//
//  Chaîne de fallback (réseau) :
//    1. URL Last.fm (si non-placeholder)
//    2. iTunes Search API  (pas de clé, rate-limit généreux)
//    3. Deezer API         (pas de clé — artistes uniquement)
//    4. MusicBrainz + Cover Art Archive (albums)
//
//  Clés de cache disque :
//    Préfixe : "imgcache_"
//    Format  : "imgcache_artist|Radiohead"
//              "imgcache_album|Radiohead|The Bends"
//              "imgcache_track|Radiohead|Creep"
//    Valeur  : JSON {"url":"https://…","ts":1714000000000}
//    TTL     : 7 jours (604 800 000 ms) — les artworks changent rarement
// ══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ImageService {
  ImageService._();

  // ── Constantes ─────────────────────────────────────────────────────────────
  static const _placeholder   = '2a96cbd8b46e442fc41c2b86b821562f';
  static const _timeout       = Duration(seconds: 6);
  static const _diskPrefix    = 'imgcache_';
  static const _diskTtlMs     = 7 * 24 * 60 * 60 * 1000; // 7 jours

  // ── Cache mémoire (session) ────────────────────────────────────────────────
  static final Map<String, String> _mem = {};

  // ── Cache disque (SharedPreferences) ──────────────────────────────────────
  static SharedPreferences? _prefs;
  static bool               _diskLoaded = false;

  // ──────────────────────────────────────────────────────────────────────────
  //  Initialisation du cache disque
  // ──────────────────────────────────────────────────────────────────────────

  /// Charge toutes les entrées non-expirées du disque en mémoire.
  /// Appelé une seule fois, de manière paresseuse, à la première résolution.
  static Future<void> _ensureDiskCache() async {
    if (_diskLoaded) return;
    _diskLoaded = true;

    try {
      _prefs ??= await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final prefKey in _prefs!.getKeys()) {
        if (!prefKey.startsWith(_diskPrefix)) continue;
        final raw = _prefs!.getString(prefKey);
        if (raw == null) continue;

        try {
          final entry = jsonDecode(raw) as Map<String, dynamic>;
          final ts    = (entry['ts'] as num?)?.toInt() ?? 0;
          final url   = (entry['url'] as String?) ?? '';

          if (url.isEmpty || (now - ts) > _diskTtlMs) {
            // Expiré → supprimer du disque silencieusement
            unawaited(_prefs!.remove(prefKey));
            continue;
          }

          // Entrée valide → charger en mémoire
          final memKey = prefKey.substring(_diskPrefix.length);
          _mem[memKey] = url;
        } catch (_) {
          unawaited(_prefs!.remove(prefKey));
        }
      }

      debugLog('[ImageCache] ${_mem.length} URL(s) chargées depuis le disque.');
    } catch (e) {
      debugLog('[ImageCache] Erreur init disque : $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Lecture / écriture cache
  // ──────────────────────────────────────────────────────────────────────────

  /// Retourne l'URL depuis le cache mémoire, ou null si absent.
  static String? _getFromMem(String key) => _mem[key];

  /// Persiste [url] dans le cache mémoire ET sur le disque.
  static Future<String> _persist(String key, String url) async {
    _mem[key] = url;
    if (url.isEmpty) return url; // ne pas persister les vides

    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(
        '$_diskPrefix$key',
        jsonEncode({'url': url, 'ts': DateTime.now().millisecondsSinceEpoch}),
      );
    } catch (_) {}

    return url;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  API publique
  // ──────────────────────────────────────────────────────────────────────────

  /// Résout l'image d'un artiste.
  static Future<String> resolveArtist(
    String artist, {
    String? lastfmUrl,
  }) async {
    if (_ok(lastfmUrl)) return lastfmUrl!;
    await _ensureDiskCache();

    final key = 'artist|$artist';
    final mem = _getFromMem(key);
    if (mem != null) return mem;

    // 1 — iTunes
    final itunes = await _itunesSearch(artist, 'musicArtist', 'artistTerm');
    if (itunes.isNotEmpty) return _persist(key, itunes);

    // 2 — Deezer
    final deezer = await _deezerArtist(artist);
    if (deezer.isNotEmpty) return _persist(key, deezer);

    return _persist(key, '');
  }

  /// Résout l'image de couverture d'un album.
  static Future<String> resolveAlbum(
    String album,
    String artist, {
    String? lastfmUrl,
  }) async {
    if (_ok(lastfmUrl)) return lastfmUrl!;
    await _ensureDiskCache();

    final key = 'album|$artist|$album';
    final mem = _getFromMem(key);
    if (mem != null) return mem;

    // 1 — iTunes
    final itunes = await _itunesSearch('$artist $album', 'album');
    if (itunes.isNotEmpty) return _persist(key, itunes);

    // 2 — MusicBrainz + Cover Art Archive
    final mb = await _mbAlbum(album, artist);
    if (mb.isNotEmpty) return _persist(key, mb);

    return _persist(key, '');
  }

  /// Résout l'artwork associé à un titre (artwork de l'album sur iTunes).
  static Future<String> resolveTrack(
    String track,
    String artist, {
    String? lastfmUrl,
  }) async {
    if (_ok(lastfmUrl)) return lastfmUrl!;
    await _ensureDiskCache();

    final key = 'track|$artist|$track';
    final mem = _getFromMem(key);
    if (mem != null) return mem;

    // iTunes (artwork de l'album associé)
    final itunes = await _itunesSearch('$artist $track', 'song');
    if (itunes.isNotEmpty) return _persist(key, itunes);

    return _persist(key, '');
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Cache stats
  // ──────────────────────────────────────────────────────────────────────────

  /// Nombre d'entrées en cache mémoire (session).
  static int get memCacheSize => _mem.length;

  /// Vide uniquement le cache mémoire (le cache disque reste intact).
  static void clearMemCache() => _mem.clear();

  /// Vide le cache mémoire ET le cache disque.
  static Future<void> clearAllCache() async {
    _mem.clear();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final keys = _prefs!.getKeys()
          .where((k) => k.startsWith(_diskPrefix))
          .toList();
      for (final k in keys) await _prefs!.remove(k);
    } catch (_) {}
    debugLog('[ImageCache] Cache vidé.');
  }

  /// Supprime les entrées expirées du cache disque.
  static Future<int> pruneExpired() async {
    int removed = 0;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final now  = DateTime.now().millisecondsSinceEpoch;
      final keys = _prefs!.getKeys()
          .where((k) => k.startsWith(_diskPrefix))
          .toList();

      for (final prefKey in keys) {
        final raw = _prefs!.getString(prefKey);
        if (raw == null) { await _prefs!.remove(prefKey); removed++; continue; }
        try {
          final entry = jsonDecode(raw) as Map<String, dynamic>;
          final ts    = (entry['ts'] as num?)?.toInt() ?? 0;
          if ((now - ts) > _diskTtlMs) {
            await _prefs!.remove(prefKey);
            final memKey = prefKey.substring(_diskPrefix.length);
            _mem.remove(memKey);
            removed++;
          }
        } catch (_) {
          await _prefs!.remove(prefKey);
          removed++;
        }
      }
    } catch (_) {}
    debugLog('[ImageCache] $removed entrée(s) expirée(s) supprimées.');
    return removed;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Sources réseau
  // ──────────────────────────────────────────────────────────────────────────

  static bool _ok(String? url) =>
      url != null && url.isNotEmpty && !url.contains(_placeholder);

  // ── iTunes Search ──────────────────────────────────────────────────────────
  static Future<String> _itunesSearch(
    String term,
    String entity, [
    String? attribute,
  ]) async {
    try {
      final params = <String, String>{
        'term':   term,
        'entity': entity,
        'limit':  '1',
        'media':  'music',
      };
      if (attribute != null) params['attribute'] = attribute;

      final uri = Uri.https('itunes.apple.com', '/search', params);
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return '';

      final data    = jsonDecode(utf8.decode(res.bodyBytes));
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return '';

      // artworkUrl100 → upscale à 600×600
      final raw = (results.first['artworkUrl100'] ?? '').toString();
      return raw.isNotEmpty
          ? raw
              .replaceAll('100x100bb', '600x600bb')
              .replaceAll('100x100',   '600x600')
          : '';
    } catch (_) {
      return '';
    }
  }

  // ── Deezer (artistes) ──────────────────────────────────────────────────────
  static Future<String> _deezerArtist(String artist) async {
    try {
      final uri = Uri.https('api.deezer.com', '/search/artist', {
        'q':     artist,
        'limit': '1',
      });
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return '';

      final data  = jsonDecode(utf8.decode(res.bodyBytes));
      final items = data['data'] as List?;
      if (items == null || items.isEmpty) return '';

      return (items.first['picture_xl']  ??
              items.first['picture_big'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  // ── MusicBrainz + Cover Art Archive (albums) ───────────────────────────────
  static Future<String> _mbAlbum(String album, String artist) async {
    try {
      // Étape 1 : chercher le MBID de la release
      final searchUri = Uri.https('musicbrainz.org', '/ws/2/release/', {
        'query': 'release:"$album" AND artist:"$artist"',
        'limit': '1',
        'fmt':   'json',
      });
      final searchRes = await http.get(searchUri, headers: {
        'User-Agent': 'LastStatsMobile/2.0 (contact@laststats.app)',
      }).timeout(_timeout);

      if (searchRes.statusCode != 200) return '';
      final searchData = jsonDecode(utf8.decode(searchRes.bodyBytes));
      final releases   = searchData['releases'] as List?;
      if (releases == null || releases.isEmpty) return '';

      final mbid = (releases.first['id'] ?? '').toString();
      if (mbid.isEmpty) return '';

      // Étape 2 : Cover Art Archive
      final coverUri = Uri.https(
          'coverartarchive.org', '/release/$mbid/front');
      final coverRes = await http.get(coverUri).timeout(_timeout);

      if (coverRes.statusCode == 200 || coverRes.statusCode == 307) {
        if (coverRes.headers['content-type']?.startsWith('image') == true) {
          return coverUri.toString();
        }
        final location = coverRes.headers['location'];
        if (location != null && location.isNotEmpty) return location;
      }
      return 'https://coverartarchive.org/release/$mbid/front-500';
    } catch (_) {
      return '';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Debug log (no-op en release)
  // ──────────────────────────────────────────────────────────────────────────
  static void debugLog(String msg) {
    assert(() { print(msg); return true; }());
  }
}

// ── Helper pour les appels fire-and-forget (sans await) ──────────────────────
void unawaited(Future<void> future) {
  future.ignore();
}
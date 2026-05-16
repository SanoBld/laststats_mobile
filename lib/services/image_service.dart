import 'dart:convert';
import 'package:http/http.dart' as http;

// ══════════════════════════════════════════════════════════════════════════
//  ImageService — résolution multi-sources avec cache en mémoire
//  Chaîne de fallback :
//    1. URL Last.fm (si non-placeholder)
//    2. iTunes Search API  (pas de clé, rate-limit généreux)
//    3. Deezer API         (pas de clé — artistes uniquement)
//    4. MusicBrainz + Cover Art Archive (albums)
// ══════════════════════════════════════════════════════════════════════════

class ImageService {
  ImageService._();

  static const _placeholder = '2a96cbd8b46e442fc41c2b86b821562f';
  static const _timeout     = Duration(seconds: 6);

  /// Cache global partagé pour toute la session.
  static final Map<String, String> _cache = {};

  // ──────────────────────────────────────────────────────────────────────
  //  Public API
  // ──────────────────────────────────────────────────────────────────────

  static Future<String> resolveArtist(
    String artist, {
    String? lastfmUrl,
  }) async {
    if (_ok(lastfmUrl)) return lastfmUrl!;
    final key = 'artist|$artist';
    if (_cache.containsKey(key)) return _cache[key]!;

    // 1 — iTunes
    final itunes = await _itunesSearch('$artist', 'musicArtist', 'artistTerm');
    if (itunes.isNotEmpty) return _put(key, itunes);

    // 2 — Deezer
    final deezer = await _deezerArtist(artist);
    if (deezer.isNotEmpty) return _put(key, deezer);

    return _put(key, '');
  }

  static Future<String> resolveAlbum(
    String album,
    String artist, {
    String? lastfmUrl,
  }) async {
    if (_ok(lastfmUrl)) return lastfmUrl!;
    final key = 'album|$artist|$album';
    if (_cache.containsKey(key)) return _cache[key]!;

    // 1 — iTunes
    final itunes = await _itunesSearch('$artist $album', 'album');
    if (itunes.isNotEmpty) return _put(key, itunes);

    // 2 — MusicBrainz + Cover Art Archive
    final mb = await _mbAlbum(album, artist);
    if (mb.isNotEmpty) return _put(key, mb);

    return _put(key, '');
  }

  static Future<String> resolveTrack(
    String track,
    String artist, {
    String? lastfmUrl,
  }) async {
    if (_ok(lastfmUrl)) return lastfmUrl!;
    final key = 'track|$artist|$track';
    if (_cache.containsKey(key)) return _cache[key]!;

    // 1 — iTunes (artwork de l'album associé)
    final itunes = await _itunesSearch('$artist $track', 'song');
    if (itunes.isNotEmpty) return _put(key, itunes);

    return _put(key, '');
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Helpers privés
  // ──────────────────────────────────────────────────────────────────────

  static bool _ok(String? url) =>
      url != null &&
      url.isNotEmpty &&
      !url.contains(_placeholder);

  static String _put(String key, String url) {
    _cache[key] = url;
    return url;
  }

  // ── iTunes Search ──────────────────────────────────────────────────────
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

      // artworkUrl100 → remplace pour obtenir 600×600
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

  // ── Deezer (artistes) ──────────────────────────────────────────────────
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

  // ── MusicBrainz + Cover Art Archive (albums) ──────────────────────────
  static Future<String> _mbAlbum(String album, String artist) async {
    try {
      // Étape 1 : chercher le MBID de la release
      final searchUri = Uri.https('musicbrainz.org', '/ws/2/release/', {
        'query': 'release:"$album" AND artist:"$artist"',
        'limit': '1',
        'fmt':   'json',
      });
      final searchRes = await http.get(searchUri, headers: {
        'User-Agent': 'LastStatsMobile/1.2 (contact@laststats.app)',
      }).timeout(_timeout);

      if (searchRes.statusCode != 200) return '';
      final searchData = jsonDecode(utf8.decode(searchRes.bodyBytes));
      final releases   = searchData['releases'] as List?;
      if (releases == null || releases.isEmpty) return '';

      final mbid = (releases.first['id'] ?? '').toString();
      if (mbid.isEmpty) return '';

      // Étape 2 : Cover Art Archive
      final coverUri = Uri.https('coverartarchive.org', '/release/$mbid/front');
      // L'API redirige vers l'image ; on suit la redirection
      final coverRes = await http.get(coverUri).timeout(_timeout);

      if (coverRes.statusCode == 200 || coverRes.statusCode == 307) {
        // Certains clients suivent la redirection automatiquement
        if (coverRes.headers['content-type']?.startsWith('image') == true) {
          return coverUri.toString();
        }
        // Sinon l'URL finale après redirect est dans headers['location']
        final location = coverRes.headers['location'];
        if (location != null && location.isNotEmpty) return location;
      }
      // Fallback : URL directe (fonctionne souvent)
      return 'https://coverartarchive.org/release/$mbid/front-500';
    } catch (_) {
      return '';
    }
  }
}
